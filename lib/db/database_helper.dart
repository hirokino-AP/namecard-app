// lib/db/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
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
    final path = join(dbPath, 'namecard.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
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
    final q = '%$keyword%';
    final maps = await db.query('business_cards',
        where: '''user_id = ? AND (
          name_kana LIKE ? OR name LIKE ? OR company_kana LIKE ? OR
          company LIKE ? OR department LIKE ? OR email LIKE ? OR
          phone LIKE ? OR mobile_phone LIKE ? OR note LIKE ?)''',
        whereArgs: [userId, q, q, q, q, q, q, q, q, q],
        orderBy: 'name_kana ASC');
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

  Future<void> close() async {
    final db = await database;
    await db.close();
    _db = null;
  }
}
