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
      version: 3,
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

      // 既存の辞書を削除
      await db.delete('company_dict', where: 'user_id = ?', whereArgs: [userId]);

      // business_cardsから会社名・よみがなを集計
      final rows = await db.rawQuery('''
        SELECT company, company_kana, COUNT(*) as cnt
        FROM business_cards
        WHERE user_id = ? AND company != ''
        GROUP BY company, company_kana
        ORDER BY cnt DESC
      ''', [userId]);

      // company_dictに登録
      await db.transaction((txn) async {
        for (final row in rows) {
          final company = row['company'] as String;
          final kana = row['company_kana'] as String? ?? '';
          final count = row['cnt'] as int;
          // 省庁略称を自動設定
          final abbr = _getAbbreviation(company);
          await txn.insert('company_dict', {
            'user_id': userId,
            'company': company,
            'company_kana': kana,
            'abbreviation': abbr,
            'count': count,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // 省庁略称マッピング
  static const Map<String, String> _abbreviationMap = {
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
    '内閣府': '内閣府',
    '復興庁': '復興庁',
    'デジタル庁': 'デジ庁',
    '消費者庁': '消費者庁',
    '金融庁': '金融庁',
    '警察庁': '警察庁',
    '文化庁': '文化庁',
    '気象庁': '気象庁',
    '国税庁': '国税庁',
  };

  String _getAbbreviation(String company) {
    for (final entry in _abbreviationMap.entries) {
      if (company.contains(entry.key)) return entry.value;
    }
    return '';
  }

  // company_dictから会社名を検索（部分一致）
  Future<List<Map<String, dynamic>>> searchCompanyDict(
      String userId, String keyword, {int minLength = 3}) async {
    final db = await database;
    if (keyword.isEmpty) {
      // キーワードなし→件数順で上位20件
      return await db.query('company_dict',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'count DESC',
          limit: 20);
    }
    // 略称・正式名称・よみがなで部分一致検索
    return await db.rawQuery('''
      SELECT * FROM company_dict
      WHERE user_id = ?
        AND (company LIKE ? OR company_kana LIKE ? OR abbreviation LIKE ?)
      ORDER BY count DESC
      LIMIT 10
    ''', [userId, '%$keyword%', '%$keyword%', '%$keyword%']);
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
