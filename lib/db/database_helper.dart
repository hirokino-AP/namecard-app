// ============================================================
// lib/db/database_helper.dart
//
// 【役割】
//   SQLiteデータベース（app_namecard.db）の全CRUD操作を管理。
//   シングルトンパターンで実装。
//
// 【DBファイル】
//   - app_namecard.db: アプリ内部ストレージ（iTunes File Sharing非公開）
//   - namecard.db: iTunes経由で転送するインポート用ファイル
//
// 【主要メソッド一覧】
//   insert/update/delete     : 単件CRUD
//   insertAll                : 一括挿入（トランザクション）
//   getAllByUser             : 全件取得（よみがな順）
//   search                  : キーワード検索（複数フィールド対象）
//   getAllCompanyNames       : 会社名一覧取得（OCR候補表示用）
//   getCompanyKana          : 会社名からよみがな取得（OCR自動補完用）
//   findDuplicates          : 重複チェック
//   importFromItunes        : iTunes転送DBをインポート
//   importFromPath          : パス指定DBをインポート
//   importFromJson          : JSON文字列からインポート
//
// 【注意事項】
//   - sqfliteのsandbox制約のため、外部DBはtmpディレクトリ経由でopen
//   - project_codesはカンマ区切り文字列で保存
// ============================================================
// lib/db/database_helper.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/business_card.dart';


// 端末内バックアップ1件分
class LocalBackupInfo {
  final String path;
  final String name;
  final String label;
  final DateTime modified;
  final int bytes;
  const LocalBackupInfo(
      this.path, this.name, this.label, this.modified, this.bytes);
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _db;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'app_namecard.db');
    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // DBバージョンアップ時のマイグレーション
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1→v2: industryフィールド追加
      await db.execute("ALTER TABLE business_cards ADD COLUMN industry TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 3) {
      // v2→v3: company_dictテーブル追加
      await db.execute('''
        CREATE TABLE IF NOT EXISTS company_dict (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id       TEXT NOT NULL DEFAULT '',
          company       TEXT NOT NULL DEFAULT '',
          company_kana  TEXT NOT NULL DEFAULT '',
          abbreviation  TEXT NOT NULL DEFAULT '',
          count         INTEGER NOT NULL DEFAULT 1,
          updated_at    TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_dict_user_id ON company_dict(user_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_dict_company ON company_dict(company)');
    }
    if (oldVersion < 4) {
      // v3→v4: company_dictにindustryフィールド追加
      await db.execute("ALTER TABLE company_dict ADD COLUMN industry TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 5) {
      // v4→v5: company_dictにconfirmedフィールド追加
      await db.execute("ALTER TABLE company_dict ADD COLUMN confirmed INTEGER NOT NULL DEFAULT 0");
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE business_cards (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id         TEXT NOT NULL DEFAULT '',
        name            TEXT NOT NULL DEFAULT '',
        name_kana       TEXT NOT NULL DEFAULT '',
        company         TEXT NOT NULL DEFAULT '',
        company_kana    TEXT NOT NULL DEFAULT '',
        department      TEXT NOT NULL DEFAULT '',
        title           TEXT NOT NULL DEFAULT '',
        email           TEXT NOT NULL DEFAULT '',
        phone           TEXT NOT NULL DEFAULT '',
        mobile_phone    TEXT NOT NULL DEFAULT '',
        fax             TEXT NOT NULL DEFAULT '',
        zip_code        TEXT NOT NULL DEFAULT '',
        address         TEXT NOT NULL DEFAULT '',
        note            TEXT NOT NULL DEFAULT '',
        industry        TEXT NOT NULL DEFAULT '',
        image_path      TEXT,
        voice_memo_path TEXT,
        project_codes   TEXT NOT NULL DEFAULT '',
        created_at      TEXT NOT NULL,
        updated_at      TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_user_id      ON business_cards(user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_name_kana    ON business_cards(name_kana)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_company_kana ON business_cards(company_kana)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_name         ON business_cards(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_company      ON business_cards(company)');

    // company_dictテーブル
    await db.execute('''
      CREATE TABLE IF NOT EXISTS company_dict (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id       TEXT NOT NULL DEFAULT '',
        company       TEXT NOT NULL DEFAULT '',
        company_kana  TEXT NOT NULL DEFAULT '',
        abbreviation  TEXT NOT NULL DEFAULT '',
        count         INTEGER NOT NULL DEFAULT 1,
        industry      TEXT NOT NULL DEFAULT '',
        confirmed     INTEGER NOT NULL DEFAULT 0,
        updated_at    TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dict_user_id ON company_dict(user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dict_company ON company_dict(company)');
  }

  Future<BusinessCard> insert(BusinessCard card) async {
    final db = await database;
    final id = await db.insert('business_cards', card.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return card.copyWith(id: id);
  }

  Future<int> insertAll(List<BusinessCard> cards) async {
    final db = await database;
    int count = 0;
    await db.transaction((txn) async {
      for (final card in cards) {
        await txn.insert('business_cards', card.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        count++;
      }
    });
    return count;
  }

  Future<List<BusinessCard>> getAllByUser(String userId) async {
    final db = await database;
    final maps = await db.query('business_cards',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'updated_at DESC');
    return maps.map((m) => BusinessCard.fromMap(m)).toList();
  }

  Future<BusinessCard?> getById(int id) async {
    final db = await database;
    final maps = await db.query('business_cards',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return BusinessCard.fromMap(maps.first);
  }

  Future<List<BusinessCard>> search({required String userId, required String keyword}) async {
    final db = await database;
    final keywords = keyword.trim().split(RegExp(r'[\s\u3000]+')).where((k) => k.isNotEmpty).toList();
    if (keywords.isEmpty) return [];
    final cond = keywords.map((_) => '(name_kana LIKE ? OR name LIKE ? OR company_kana LIKE ? OR company LIKE ? OR department LIKE ? OR title LIKE ? OR email LIKE ? OR phone LIKE ? OR mobile_phone LIKE ? OR note LIKE ?)').join(' AND ');
    final args = <dynamic>[userId];
    for (final k in keywords) { final q = '%' + k + '%'; args.addAll([q,q,q,q,q,q,q,q,q,q]); }
    final maps = await db.rawQuery('SELECT * FROM business_cards WHERE user_id = ? AND ' + cond + ' ORDER BY name_kana ASC', args);
    return maps.map((m) => BusinessCard.fromMap(m)).toList();
  }



  Future<List<String>> getAllCompanyNames(String userId) async {
    final db = await database;
    final maps = await db.rawQuery(
      "SELECT DISTINCT company FROM business_cards WHERE user_id = ? AND company != '' ORDER BY company ASC",
      [userId],
    );
    return maps.map((m) => m['company'] as String).toList();
  }

  // 会社名からよみがなを取得
  Future<String> getCompanyKana(String userId, String companyName) async {
    final db = await database;
    final maps = await db.rawQuery(
      "SELECT company_kana FROM business_cards WHERE user_id = ? AND company = ? AND company_kana != '' LIMIT 1",
      [userId, companyName],
    );
    if (maps.isEmpty) return '';
    return maps[0]['company_kana'] as String? ?? '';

  }

  Future<Map<String, List<BusinessCard>>> findDuplicates(String userId) async {
    final db = await database;
    final maps = await db.query('business_cards',
        where: "user_id = ? AND name != '' AND company != ''",
        whereArgs: [userId],
        orderBy: 'name ASC, company ASC');
    final cards = maps.map((m) => BusinessCard.fromMap(m)).toList();
    final Map<String, List<BusinessCard>> groups = {};
    for (final card in cards) {
      final key = card.name.trim() + '___' + card.company.trim();
      groups.putIfAbsent(key, () => []).add(card);
    }
    groups.removeWhere((key, list) => list.length < 2);
    return groups;
  }

  Future<List<BusinessCard>> searchBlankKana(String userId) async {
    final db = await database;
    final maps = await db.query('business_cards',
        where: 'user_id = ? AND (name_kana = ? OR name_kana IS NULL)',
        whereArgs: [userId, ''],
        orderBy: 'name ASC');
    return maps.map((m) => BusinessCard.fromMap(m)).toList();
  }

  Future<List<BusinessCard>> searchByNameAndCompany({
    required String userId, required String name, String? company}) async {
    final db = await database;
    if (company == null || company.isEmpty) {
      final maps = await db.query('business_cards',
          where: 'user_id = ? AND (name LIKE ? OR name_kana LIKE ?)',
          whereArgs: [userId, '%$name%', '%$name%'], orderBy: 'name_kana ASC');
      return maps.map((m) => BusinessCard.fromMap(m)).toList();
    }
    final maps = await db.query('business_cards',
        where: '''user_id = ? AND (name LIKE ? OR name_kana LIKE ?)
          AND (company LIKE ? OR company_kana LIKE ?)''',
        whereArgs: [userId, '%$name%', '%$name%', '%$company%', '%$company%'],
        orderBy: 'name_kana ASC');
    return maps.map((m) => BusinessCard.fromMap(m)).toList();
  }

  Future<List<BusinessCard>> searchByProjectCode({
    required String userId, required String projectCode}) async {
    final db = await database;
    final maps = await db.query('business_cards',
        where: 'user_id = ? AND project_codes LIKE ?',
        whereArgs: [userId, '%$projectCode%'], orderBy: 'name_kana ASC');
    return maps.map((m) => BusinessCard.fromMap(m)).toList();
  }

  Future<int> update(BusinessCard card) async {
    final db = await database;
    final updated = card.copyWith(updatedAt: DateTime.now());
    return await db.update('business_cards', updated.toMap(),
        where: 'id = ?', whereArgs: [card.id]);
  }

  Future<int> delete(int id) async {
    final db = await database;
    return await db.delete('business_cards', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllByUser(String userId) async {
    final db = await database;
    return await db.delete('business_cards', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<int> countByUser(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM business_cards WHERE user_id = ?', [userId]);
    return result.first['cnt'] as int;
  }


  // iTunesで転送されたnamecard.dbを自動インポート
  // ============================================================
  // company_dict操作
  // ============================================================

  // business_cardsからcompany_dictを再構築
  Future<bool> rebuildCompanyDict(String userId) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();

      // 既存の辞書の手入力内容（よみがな・略称・業種・確認済み）を控える
      final oldRows = await db.query('company_dict',
          where: 'user_id = ?', whereArgs: [userId]);
      final Map<String, Map<String, dynamic>> oldDict = {};
      for (final r in oldRows) {
        final name = r['company'] as String;
        final prev = oldDict[name];
        if (prev == null) {
          oldDict[name] = Map<String, dynamic>.from(r);
        } else {
          // 同じ会社名の行が複数ある場合は、空でない値を引き継ぐ
          for (final f in ['company_kana', 'abbreviation', 'industry']) {
            if (((prev[f] as String?) ?? '').isEmpty) prev[f] = r[f];
          }
          if (((r['confirmed'] as int?) ?? 0) == 0) prev['confirmed'] = 0;
        }
      }

      // business_cardsから会社名・よみがなを集計（会社名ごとに1行）
      final rows = await db.rawQuery('''
        SELECT company, MAX(company_kana) AS company_kana, COUNT(*) as cnt
        FROM business_cards
        WHERE user_id = ? AND company != ''
        GROUP BY company
        ORDER BY cnt DESC
      ''', [userId]);

      // NLFrameworkで会社名リストのよみがなを一括変換
      final companyNames = rows.map((r) => r['company'] as String).toList();
      Map<String, String> yomiganaMap = {};
      try {
        const channel = MethodChannel('com.hirokino.namecardapp/document_picker');
        final result = await channel.invokeMapMethod<String, String>(
            'convertListToYomigana', companyNames);
        yomiganaMap = result ?? {};
      } catch (e) {
        // NLFramework失敗時は空のまま
      }

      // company_dictに登録（削除と再登録は同じトランザクション内で行う）
      await db.transaction((txn) async {
        await txn.delete('company_dict',
            where: 'user_id = ?', whereArgs: [userId]);
        for (final row in rows) {
          final company = row['company'] as String;
          final old = oldDict[company];
          // よみがな：辞書の手入力→名刺の値→NLFramework→空文字
          String kana = (old?['company_kana'] as String?) ?? '';
          if (kana.isEmpty) kana = row['company_kana'] as String? ?? '';
          if (kana.isEmpty) kana = yomiganaMap[company] ?? '';
          final count = row['cnt'] as int;
          // 略称：手入力を優先し、なければ省庁略称を自動設定
          String abbr = (old?['abbreviation'] as String?) ?? '';
          if (abbr.isEmpty) abbr = _getAbbreviation(company);
          await txn.insert('company_dict', {
            'user_id': userId,
            'company': company,
            'company_kana': kana,
            'abbreviation': abbr,
            'count': count,
            'industry': (old?['industry'] as String?) ?? '',
            'confirmed': (old?['confirmed'] as int?) ?? 0,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // 省庁略称マッピング（正式名称→略称）
  // 略称からも検索できるようabbreviationフィールドに登録される
  static const Map<String, String> _abbreviationMap = {
    // 省（2〜3文字略称）
    '経済産業省': '経産省',
    '文部科学省': '文科省',
    '厚生労働省': '厚労省',
    '国土交通省': '国交省',
    '農林水産省': '農水省',
    '環境省': '環境省',
    '防衛省': '防衛省',
    '総務省': '総務省',
    '財務省': '財務省',
    '外務省': '外務省',
    '法務省': '法務省',
    '文部省': '文科省',   // 旧省庁名
    // 庁
    '内閣府': '内閣府',
    '復興庁': '復興庁',
    'デジタル庁': 'デジ庁',
    '消費者庁': '消費者庁',
    '金融庁': '金融庁',
    '警察庁': '警察庁',
    '文化庁': '文化庁',
    '気象庁': '気象庁',
    '国税庁': '国税庁',
    '防衛装備庁': '防装庁',
    '資源エネルギー庁': 'エネ庁',
    '中小企業庁': '中企庁',
    '特許庁': '特許庁',
    '林野庁': '林野庁',
    '水産庁': '水産庁',
    '海上保安庁': '海保庁',
    '消防庁': '消防庁',
    // よく使われる2文字略称（逆引き用）
    '経産': '経産省',
    '文科': '文科省',
    '厚労': '厚労省',
    '国交': '国交省',
    '農水': '農水省',
    '内閣': '内閣府',
  };

  String _getAbbreviation(String company) {
    for (final entry in _abbreviationMap.entries) {
      if (company.contains(entry.key)) return entry.value;
    }
    return '';
  }

  // company_dictから会社名を検索（部分一致）
  Future<List<Map<String, dynamic>>> searchCompanyDict(
      String userId, String keyword, {int limit = 500}) async {
    final db = await database;
    if (keyword.isEmpty) {
      // キーワードなし→件数順で上位limit件
      return await db.query('company_dict',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'count DESC',
          limit: limit);
    }
    // 略称・正式名称・よみがなで部分一致検索
    return await db.rawQuery('''
      SELECT * FROM company_dict
      WHERE user_id = ?
        AND (company LIKE ? OR company_kana LIKE ? OR abbreviation LIKE ?)
      ORDER BY count DESC
      LIMIT $limit
    ''', [userId, '%$keyword%', '%$keyword%', '%$keyword%']);
  }

  // company_dictのconfirmedフラグを更新
  Future<void> updateCompanyDictConfirmed(String userId, String company, bool confirmed) async {
    try {
      final db = await database;
      await db.update(
        'company_dict',
        {'confirmed': confirmed ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'user_id = ? AND company = ?',
        whereArgs: [userId, company],
      );
    } catch (e) {
      // 更新失敗は無視
    }
  }

  // company_dictの未確認リストを取得
  Future<List<Map<String, dynamic>>> getUnconfirmedCompanyDict(String userId) async {
    final db = await database;
    return await db.query(
      'company_dict',
      where: 'user_id = ? AND confirmed = 0',
      whereArgs: [userId],
      orderBy: 'count DESC',
    );
  }

  // company_dictのよみがなを更新
  Future<void> updateCompanyDictKana(String userId, String company, String kana) async {
    try {
      final db = await database;
      await db.update(
        'company_dict',
        {'company_kana': kana, 'updated_at': DateTime.now().toIso8601String()},
        where: 'user_id = ? AND company = ?',
        whereArgs: [userId, company],
      );
    } catch (e) {
      // 更新失敗は無視
    }
  }

  // company_dictのindustryを更新
  Future<void> updateCompanyDictIndustry(String userId, String company, String industry) async {
    try {
      final db = await database;
      await db.update(
        'company_dict',
        {'industry': industry, 'updated_at': DateTime.now().toIso8601String()},
        where: 'user_id = ? AND company = ?',
        whereArgs: [userId, company],
      );
    } catch (e) {
      // 更新失敗は無視
    }
  }

  // company_dictの総件数を取得
  Future<int> countCompanyDict(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM company_dict WHERE user_id = ?', [userId]);
    return result.first['cnt'] as int;
  }

  Future<int> importFromItunes(String userId) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final srcPath = join(docsDir.path, 'namecard.db');
      if (!await File(srcPath).exists()) return 0;

      // sqflite sandbox回避: tmpディレクトリ経由でopen
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = join(tmpDir.path, 'itunes_tmp.db');
      await File(srcPath).copy(tmpPath);
      final srcDb = await openDatabase(tmpPath, readOnly: true);
      final rows = await srcDb.query('business_cards');
      await srcDb.close();
      await File(tmpPath).delete();

      if (rows.isEmpty) return -99;

      final db = await database;
      int count = 0;
      await db.transaction((txn) async {
        for (final row in rows) {
          final map = Map<String, dynamic>.from(row);
          map['user_id'] = userId;
          map.remove('id');
          await txn.insert('business_cards', map,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      });

      // インポート済みファイルを削除
      await File(srcPath).delete();
      return count;
    } catch (e) {
      return 0;
    }
  }

  Future<int> importFromPath(String srcPath, String userId) async {
    try {
      if (!await File(srcPath).exists()) return -1; // ファイルが存在しない
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = join(tmpDir.path, 'import_tmp.db');
      await File(srcPath).copy(tmpPath);
      final srcDb = await openDatabase(tmpPath, readOnly: true);
      // テーブル一覧を取得してデバッグ
      final tables = await srcDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      if (tables.isEmpty) { await srcDb.close(); return -2; } // テーブルなし
      // business_cardsテーブルが存在するか確認
      final hasTable = tables.any((t) => t['name'] == 'business_cards');
      if (!hasTable) { await srcDb.close(); return -3; } // business_cardsテーブルなし
      final rows = await srcDb.query('business_cards');
      await srcDb.close();
      await File(tmpPath).delete();
      if (rows.isEmpty) return -4; // データが0件
      final db = await database;
      int count = 0;
      await db.transaction((txn) async {
        for (final row in rows) {
          final map = Map<String, dynamic>.from(row);
          map['user_id'] = userId;
          map.remove('id');
          await txn.insert('business_cards', map,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      });
      return count;
    } catch (e) {
      return -999;
    }
  }

  Future<int> importFromJson(String jsonStr, String userId) async {
    try {
      final List<dynamic> rows = json.decode(jsonStr);
      if (rows.isEmpty) return 0;
      final db = await database;
      int count = 0;
      await db.transaction((txn) async {
        for (final row in rows) {
          final map = Map<String, dynamic>.from(row as Map);
          map['user_id'] = userId;
          map.remove('id');
          await txn.insert('business_cards', map,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      });
      return count;
    } catch (e) {
      return -999;
    }
  }

  // ============================================================
  // バックアップの入れ替え（刷新）
  // ============================================================

  // JSONを検査して、名刺リストを返す。失敗・空・不正な場合は例外
  List<Map<String, dynamic>> _parseBackupRows(String jsonStr) {
    final dynamic decoded;
    try {
      decoded = json.decode(jsonStr);
    } catch (e) {
      throw Exception('バックアップファイルを読み込めませんでした');
    }
    if (decoded is! List) {
      throw Exception('バックアップファイルの形式が正しくありません');
    }
    if (decoded.isEmpty) {

      throw Exception('バックアップファイルに名刺が入っていません');
    }
    final rows = <Map<String, dynamic>>[];
    for (final row in decoded) {
      if (row is! Map) {
        throw Exception('バックアップファイルの形式が正しくありません');
      }
      rows.add(Map<String, dynamic>.from(row));
    }
    // 氏名か会社名が入った名刺が、1件もない場合は、不正なファイルとみなす
    final hasContent = rows.any((r) =>
        ((r['name'] as String?) ?? '').trim().isNotEmpty ||
        ((r['company'] as String?) ?? '').trim().isNotEmpty);
    if (!hasContent) {
      throw Exception('バックアップファイルの内容が正しくありません');
    }
    return rows;
  }

  // 入れ替え前の確認用：ファイルの名刺件数（検査に失敗したら例外）
  int countBackupRows(String jsonStr) => _parseBackupRows(jsonStr).length;

  // 名刺を、バックアップの内容に入れ替える（削除と登録は1つのトランザクション）
  // 戻り値：登録した件数。検査に失敗した場合は、何も削除せず例外
  Future<int> replaceAllFromJson(String jsonStr, String userId) async {
    final rows = _parseBackupRows(jsonStr);
    // 入れ替え前の状態を、端末内バックアップとして自動保存（保存できなければ中止）
    final safety = await saveLocalBackup(prefix: 'before_replace', keep: 3);
    if (safety == null) {
      throw Exception('入れ替え前のバックアップを作れなかったため、中止しました');
    }
    final db = await database;
    int count = 0;
    await db.transaction((txn) async {
      await txn.delete('business_cards',
          where: 'user_id = ?', whereArgs: [userId]);
      for (final row in rows) {

        final map = Map<String, dynamic>.from(row);
        map['user_id'] = userId;
        map.remove('id');
        await txn.insert('business_cards', map,
            conflictAlgorithm: ConflictAlgorithm.replace);
        count++;
      }
    });
    // 会社辞書は、入れ替えた名刺から作り直す（同じ会社名の略称・業種・確認済みは引き継がれる）
    await rebuildCompanyDict(userId);
    // 会社名の統合履歴は、名刺IDが変わるので消す
    try {
      final dir = await getDatabasesPath();
      final f = File(join(dir, 'company_merge_history.json'));
      if (await f.exists()) await f.delete();
    } catch (e) {
      // 履歴の削除に失敗しても、入れ替えは成功とする
    }
    return count;
  }

  // ============================================================
  // バックアップ・リストア
  // ============================================================

  // ---------- 端末内バックアップ ----------
  // 保存先: Library/Application Support/backups
  // iTunesファイル共有には表示されない。iOSの端末バックアップには通常含まれる。
  // アプリを削除すると消える。

  Future<Directory> _localBackupDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(join(base.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static const Map<String, String> _backupKinds = {
    'manual': '手動',
    'before_replace': '入れ替え前（自動）',
    'before_restore': '復元前（自動）',
  };

  // 端末内にバックアップを保存する。失敗したら null
  Future<String?> saveLocalBackup(
      {String prefix = 'manual', int keep = 10}) async {
    try {
      await database; // DBファイルが無ければ作られる
      final dbPath = await getDatabasesPath();
      final srcPath = join(dbPath, 'app_namecard.db');
      if (!await File(srcPath).exists()) return null;
      final dir = await _localBackupDir();
      final n = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp =
          '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
      final destPath = join(dir.path, 'namecard_${prefix}_$stamp.db');
      await close();
      await File(srcPath).copy(destPath);
      await _pruneLocalBackups(dir, prefix, keep);
      return destPath;
    } catch (e) {
      return null;
    }
  }

  Future<void> _pruneLocalBackups(
      Directory dir, String prefix, int keep) async {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = basename(f.path);
          return name.startsWith('namecard_${prefix}_') && name.endsWith('.db');
        })
        .toList()
      ..sort((a, b) => basename(b.path).compareTo(basename(a.path)));
    for (final f in files.skip(keep)) {
      try {
        await f.delete();
      } catch (e) {
        // 削除に失敗しても続行
      }
    }
  }

  // 端末内バックアップの一覧（新しい順）
  Future<List<LocalBackupInfo>> listLocalBackups() async {
    final dir = await _localBackupDir();
    final result = <LocalBackupInfo>[];
    for (final f in dir.listSync().whereType<File>()) {
      final name = basename(f.path);
      if (!name.startsWith('namecard_') || !name.endsWith('.db')) continue;
      String label = 'その他';
      _backupKinds.forEach((k, v) {
        if (name.startsWith('namecard_${k}_')) label = v;
      });
      final stat = f.statSync();
      result.add(LocalBackupInfo(f.path, name, label, stat.modified, stat.size));
    }
    result.sort((a, b) => b.modified.compareTo(a.modified));
    return result;
  }

  // バックアップの名刺件数（読み込めないバックアップなら例外）
  Future<int> backupCardCount(String path) async {
    Database? b;
    try {
      b = await openDatabase(path, readOnly: true);
      final r = await b.rawQuery('SELECT COUNT(*) AS c FROM business_cards');
      return Sqflite.firstIntValue(r) ?? 0;
    } finally {
      await b?.close();
    }
  }

  // 端末内バックアップから復元する（名刺・会社辞書がバックアップの内容になる）
  Future<void> restoreLocalBackup(String path) async {
    await backupCardCount(path); // 読めなければここで例外（何も変更しない）
    final dbPath = await getDatabasesPath();
    final target = join(dbPath, 'app_namecard.db');
    final tmp = '$target.restore_tmp';
    // 先に、選んだバックアップを作業用にコピーしておく
    await File(path).copy(tmp);
    try {
      final safety = await saveLocalBackup(prefix: 'before_restore', keep: 3);
      if (safety == null) {
        throw Exception('復元前のバックアップを作れなかったため、復元を中止しました');
      }
      await close();
      for (final suffix in ['-journal', '-wal', '-shm']) {
        final j = File('$target$suffix');
        if (await j.exists()) await j.delete();
      }
      await File(tmp).rename(target);
    } catch (e) {
      try {
        if (await File(tmp).exists()) await File(tmp).delete();
      } catch (_) {}
      rethrow;
    }
    _db = null;
    // 会社名の統合履歴は、名刺IDが変わるので消す
    try {
      final f = File(join(dbPath, 'company_merge_history.json'));
      if (await f.exists()) await f.delete();
    } catch (e) {
      // 履歴の削除に失敗しても、復元は成功とする
    }
  }

  // app_namecard.dbをコピーしてバックアップファイルのパスを返す
  Future<String?> createBackup() async {
    try {
      final dbPath = await getDatabasesPath();
      final srcPath = join(dbPath, 'app_namecard.db');
      if (!await File(srcPath).exists()) return null;

      // 一時ディレクトリにコピー
      final tmpDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final fileName = 'namecard_backup_'
          '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}'
          '_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}'
          '.db';
      final destPath = join(tmpDir.path, fileName);

      // DBを一旦クローズしてからコピー
      await close();
      await File(srcPath).copy(destPath);
      return destPath;
    } catch (e) {
      return null;
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _db = null;
  }
}
