// ============================================================
// lib/services/company_merge_service.dart
//
// 【役割】
//   会社名の表記ゆれ（空白・全角半角の違い）の検出と、
//   会社名の統合・変更、およびその取り消しを担当する。
//   画面（company_merge_screen.dart など）からのみ呼び出す。
//
// 【処理の流れ】
//   1. 変更前の状態（名刺のIDと元の会社名、辞書の元の行）を履歴ファイルに書く
//   2. 1つのトランザクションで、名刺の会社名と会社辞書をまとめて更新する
//   3. 失敗した場合は、更新が取り消され、書いた履歴も削除する
//
// 【履歴】
//   保存先: DBと同じディレクトリの company_merge_history.json
//          （iTunesファイル共有には表示されない）
//   内容  : 変更した名刺のIDと元の会社名、辞書の元の行のみ
//          （電話・メールなどは含まない）
//   件数  : 直近10件。後の履歴が同じ会社名に触れていなければ、どれでも取り消せる。
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';

// 候補グループの中の1つの表記
class MergeVariant {
  final String company;
  final int cardCount;

  const MergeVariant(this.company, this.cardCount);
}

// 同じ会社と思われる表記のグループ
class MergeCandidate {
  final String key;
  // 名刺の件数が多い順（同数なら短い表記が先）
  final List<MergeVariant> variants;
  const MergeCandidate(this.key, this.variants);
  int get totalCards => variants.fold(0, (s, v) => s + v.cardCount);
}

// 取り消し結果
class UndoResult {
  final int restored;
  final int skipped;
  const UndoResult(this.restored, this.skipped);
}

// 履歴1件分
class MergeHistoryEntry {
  final int id;
  final String type; // 'merge'（統合）または 'rename'（社名変更）
  final String userId;
  final DateTime at;
  final String toName;
  final List<String> fromNames;
  final List<List<dynamic>> cards; // [[名刺ID, 元の会社名], ...]
  final List<Map<String, dynamic>> dictRows;

  const MergeHistoryEntry({
    required this.id,

    required this.type,
    required this.userId,
    required this.at,
    required this.toName,
    required this.fromNames,
    required this.cards,
    required this.dictRows,
  });

  int get changedCount => cards.length;
  String get typeLabel => type == 'rename' ? '社名変更' : '統合';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'userId': userId,
        'at': at.toIso8601String(),
        'toName': toName,
        'fromNames': fromNames,
        'cards': cards,
        'dictRows': dictRows,
      };

  factory MergeHistoryEntry.fromJson(Map<String, dynamic> j) {
    return MergeHistoryEntry(
      id: j['id'] as int,
      type: j['type'] as String? ?? 'merge',
      userId: j['userId'] as String? ?? '',
      at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      toName: j['toName'] as String? ?? '',
      fromNames: List<String>.from(j['fromNames'] as List),
      cards: (j['cards'] as List)

          .map((e) => List<dynamic>.from(e as List))
          .toList(),
      dictRows: (j['dictRows'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}

class CompanyMergeService {
  static const int _maxHistory = 10;

  // ---------- 候補の検出 ----------

  // 空白（半角・全角・タブ）を除き、全角の英数字・記号を半角にそろえたキー。
  // 大文字小文字、ひらがなカタカナの違いは区別する。
  static String normalizeKey(String s) {
    final buf = StringBuffer();
    for (final rune in s.runes) {
      var c = rune;
      if (c == 0x20 || c == 0x3000 || c == 0x09 || c == 0xA0) continue;
      if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角ASCII→半角
      buf.writeCharCode(c);
    }
    return buf.toString();
  }

  // 同じキーになる会社名が2つ以上ある組を返す
  static Future<List<MergeCandidate>> findCandidates(String uid) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
        "SELECT company, COUNT(*) AS cnt FROM business_cards "
        "WHERE user_id = ? AND company != '' GROUP BY company",
        [uid]);
    final Map<String, List<MergeVariant>> groups = {};
    for (final r in rows) {
      final company = r['company'] as String;
      final cnt = (r['cnt'] as int?) ?? 0;
      groups
          .putIfAbsent(normalizeKey(company), () => [])
          .add(MergeVariant(company, cnt));
    }
    final result = <MergeCandidate>[];
    groups.forEach((key, list) {
      if (list.length < 2) return;
      list.sort((a, b) {
        final c = b.cardCount.compareTo(a.cardCount);
        if (c != 0) return c;
        final l = a.company.length.compareTo(b.company.length);
        if (l != 0) return l;
        return a.company.compareTo(b.company);
      });
      result.add(MergeCandidate(key, list));
    });
    result.sort((a, b) => b.totalCards.compareTo(a.totalCards));
    return result;
  }

  // 実際に書き換わる会社名（統合先と同じ名前は除く）
  static List<String> _changedNames(List<String> fromNames, String toName) =>
      fromNames.toSet().where((n) => n != toName).toList();

  static String _placeholders(int n) => List.filled(n, '?').join(',');

  // 書き換わる名刺の件数（実行前の表示用）
  static Future<int> countCardsToChange(
      String uid, List<String> fromNames, String toName) async {
    final names = _changedNames(fromNames, toName.trim());
    if (names.isEmpty) return 0;
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM business_cards '
        'WHERE user_id = ? AND company IN (${_placeholders(names.length)})',
        [uid, ...names]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // ---------- 履歴ファイル ----------

  static Future<File> _historyFile() async {
    final dir = await getDatabasesPath();
    return File(join(dir, 'company_merge_history.json'));
  }

  // 古い順に全件読む
  static Future<List<MergeHistoryEntry>> _readAll() async {
    try {
      final f = await _historyFile();
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return (data['entries'] as List)
          .map((e) =>
              MergeHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> _writeAll(List<MergeHistoryEntry> entries) async {
    final f = await _historyFile();
    await f.writeAsString(
        jsonEncode({'entries': entries.map((e) => e.toJson()).toList()}),
        flush: true);
  }

  static Future<void> _removeEntry(int id) async {
    final all = await _readAll();
    all.removeWhere((e) => e.id == id);
    await _writeAll(all);
  }

  // 直近10件だけ残す
  static Future<void> _trim() async {
    final all = await _readAll();
    if (all.length <= _maxHistory) return;
    await _writeAll(all.sublist(all.length - _maxHistory));
  }

  // 自分の履歴を新しい順に返す
  static Future<List<MergeHistoryEntry>> loadHistory(String uid) async {
    final all = await _readAll();
    return all.where((e) => e.userId == uid).toList().reversed.toList();
  }

  // ---------- 統合・社名変更 ----------

  // fromNames の会社名を toName にそろえる（統合・社名変更の共通処理）
  // 戻り値：書き換えた名刺の件数
  static Future<int> applyRename(
    String uid,
    List<String> fromNames,
    String toName, {
    required String type,
  }) async {
    final target = toName.trim();
    if (target.isEmpty) throw Exception('会社名が空です');
    final changed = _changedNames(fromNames, target);
    if (changed.isEmpty) return 0;
    final dictNames = <String>{...changed, target}.toList();
    final phC = _placeholders(changed.length);
    final phD = _placeholders(dictNames.length);
    final db = await DatabaseHelper.instance.database;

    final cardRows = await db.rawQuery(
        'SELECT id, company FROM business_cards '
        'WHERE user_id = ? AND company IN ($phC)',
        [uid, ...changed]);
    final dictRows = await db.rawQuery(
        'SELECT * FROM company_dict '
        'WHERE user_id = ? AND company IN ($phD) ORDER BY count DESC',
        [uid, ...dictNames]);
    if (cardRows.isEmpty && dictRows.isEmpty) return 0;

    final entry = MergeHistoryEntry(
      id: DateTime.now().millisecondsSinceEpoch,
      type: type,
      userId: uid,
      at: DateTime.now(),
      toName: target,
      fromNames: changed,
      cards: cardRows.map((r) => <dynamic>[r['id'], r['company']]).toList(),
      dictRows: dictRows.map((r) => Map<String, dynamic>.from(r)).toList(),
    );

    // ① 変更前の状態を履歴に書く
    final all = await _readAll();
    all.add(entry);
    await _writeAll(all);

    try {
      final now = DateTime.now().toIso8601String();
      await db.transaction((txn) async {
        // ② 名刺の会社名をそろえる
        await txn.rawUpdate(
            'UPDATE business_cards SET company = ?, updated_at = ? '
            'WHERE user_id = ? AND company IN ($phC)',
            [target, now, uid, ...changed]);

        // ③ 会社辞書を1行にまとめる
        if (dictRows.isNotEmpty) {
          // 統合先の値を優先し、空なら他の行（人数の多い順）から補う
          String pick(String field) {
            for (final r in dictRows) {
              if (r['company'] == target) {
                final v = (r[field] as String?) ?? '';
                if (v.isNotEmpty) return v;
              }
            }
            for (final r in dictRows) {
              final v = (r[field] as String?) ?? '';
              if (v.isNotEmpty) return v;
            }
            return '';
          }

          final allConfirmed =
              dictRows.every((r) => ((r['confirmed'] as int?) ?? 0) == 1);
          await txn.delete('company_dict',
              where: 'user_id = ? AND company IN ($phD)',
              whereArgs: [uid, ...dictNames]);
          final cnt = Sqflite.firstIntValue(await txn.rawQuery(
                  'SELECT COUNT(*) FROM business_cards '
                  'WHERE user_id = ? AND company = ?',
                  [uid, target])) ??
              0;
          await txn.insert('company_dict', {
            'user_id': uid,
            'company': target,
            'company_kana': pick('company_kana'),
            'abbreviation': pick('abbreviation'),
            'count': cnt,
            'industry': pick('industry'),
            'confirmed': allConfirmed ? 1 : 0,
            'updated_at': now,
          });
        }
      });
    } catch (e) {
      // 更新が失敗したら、書いた履歴も消す
      await _removeEntry(entry.id);
      rethrow;
    }
    await _trim();
    return cardRows.length;
  }

  // ---------- 取り消し ----------

  // 指定した履歴より新しい履歴のうち、同じ会社名に触れているもの
  // （空なら取り消せる。古い順の一覧を渡す）
  static List<MergeHistoryEntry> blockersOf(
      MergeHistoryEntry target, List<MergeHistoryEntry> oldestFirst) {
    final idx = oldestFirst.indexWhere((e) => e.id == target.id);
    if (idx < 0) return [];
    final names = <String>{...target.fromNames, target.toName};
    final result = <MergeHistoryEntry>[];

    for (final e in oldestFirst.sublist(idx + 1)) {
      final other = <String>{...e.fromNames, e.toName};
      if (other.intersection(names).isNotEmpty) result.add(e);
    }
    return result;
  }

  // 取り消すと書き戻る名刺の件数（今も統合後の会社名のままのもの）
  static Future<int> countRestorable(
      String uid, MergeHistoryEntry entry) async {
    final db = await DatabaseHelper.instance.database;
    final ids = entry.cards.map((c) => c[0]).toList();
    int n = 0;
    for (var i = 0; i < ids.length; i += 500) {
      final end = i + 500 > ids.length ? ids.length : i + 500;
      final chunk = ids.sublist(i, end);
      final r = await db.rawQuery(
          'SELECT COUNT(*) FROM business_cards '
          'WHERE user_id = ? AND company = ? '
          'AND id IN (${_placeholders(chunk.length)})',
          [uid, entry.toName, ...chunk]);
      n += Sqflite.firstIntValue(r) ?? 0;
    }
    return n;
  }

  // 指定した履歴を取り消す（後の履歴が同じ会社名に触れている場合は取り消せない）
  static Future<UndoResult> undoEntry(String uid, int entryId) async {
    final all = await _readAll();
    final mine = all.where((e) => e.userId == uid).toList();
    final found = mine.where((e) => e.id == entryId).toList();
    if (found.isEmpty) throw Exception('履歴が見つかりません');

    final entry = found.first;
    final blockers = blockersOf(entry, mine);
    if (blockers.isNotEmpty) {
      throw Exception('先に「${blockers.last.toName}」の履歴を取り消してください');
    }
    final names = <String>{...entry.fromNames, entry.toName}.toList();
    final phD = _placeholders(names.length);
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    int restored = 0;

    await db.transaction((txn) async {
      // 名刺：統合後の会社名のままのものだけ、元に戻す
      for (final c in entry.cards) {
        final n = await txn.rawUpdate(
            'UPDATE business_cards SET company = ?, updated_at = ? '
            'WHERE id = ? AND user_id = ? AND company = ?',
            [c[1], now, c[0], uid, entry.toName]);
        restored += n;
      }
      // 辞書：統合前の行を戻し、人数は名刺から数え直す
      await txn.delete('company_dict',
          where: 'user_id = ? AND company IN ($phD)',
          whereArgs: [uid, ...names]);
      for (final r in entry.dictRows) {
        final row = Map<String, dynamic>.from(r)..remove('id');
        final company = (row['company'] as String?) ?? '';
        final cnt = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COUNT(*) FROM business_cards '
                'WHERE user_id = ? AND company = ?',
                [uid, company])) ??
            0;
        row['count'] = cnt;
        await txn.insert('company_dict', row);
      }
    });
    await _removeEntry(entry.id);
    return UndoResult(restored, entry.cards.length - restored);
  }
}
