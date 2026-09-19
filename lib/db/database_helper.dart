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
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/business_card.dart';


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
      version: 2,
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
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'name_kana ASC');
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
      if (!await File(srcPath).exists()) return 0;
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = join(tmpDir.path, 'import_tmp.db');
      await File(srcPath).copy(tmpPath);
      final srcDb = await openDatabase(tmpPath, readOnly: true);
      final rows = await srcDb.query('business_cards');
      await srcDb.close();
      await File(tmpPath).delete();
      if (rows.isEmpty) return 0;
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

  Future<void> close() async {
    final db = await database;
    await db.close();
    _db = null;
  }
}
