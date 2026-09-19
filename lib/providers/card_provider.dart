// ============================================================
// lib/providers/card_provider.dart
//
// 【役割】
//   名刺データのビジネスロジックを管理するProvider。
//   UIとDBの橋渡し役。ChangeNotifierでUI変更を通知。
//
// 【状態管理】
//   _cards        : 全名刺リスト
//   _searchResults: 検索結果リスト
//   _isLoading    : ローディング状態
//   _errorMessage : エラーメッセージ
//   _searchKeyword: 現在の検索キーワード
//
// 【主要メソッド一覧】
//   loadCards       : 全件読み込み
//   addCard         : 新規追加
//   updateCard      : 更新
//   deleteCard      : 削除
//   search          : キーワード検索
//   searchForCall   : Todo連携用名前・会社検索
//   importFromCsv   : CSVインポート（UIDocumentPicker経由）
//   importFromPath  : DBインポート（パス指定）
//   importFromJson  : DBインポート（JSON文字列）
//   deleteAllCards  : 全件削除
//
// 【注意事項】
//   - file_pickerパッケージは使用禁止（セキュリティ問題）
//   - CSVインポートはUIDocumentPicker経由でパスを受け取る
//   - displayCardsプロパティで検索中/非検索中を自動切替
// ============================================================
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/business_card.dart';
import '../db/database_helper.dart';

class CardProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<BusinessCard> _cards = [];
  List<BusinessCard> _searchResults = [];
  bool _isLoading = false;
  String _errorMessage = '';
  String _searchKeyword = '';

  List<BusinessCard> get cards => _cards;
  List<BusinessCard> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  String get searchKeyword => _searchKeyword;
  bool get hasError => _errorMessage.isNotEmpty;
  bool get isSearching => _searchKeyword.isNotEmpty;
  List<BusinessCard> get displayCards => isSearching ? _searchResults : _cards;

  Future<void> loadCards(String userId) async {
    _setLoading(true);
    try {
      _cards = await _db.getAllByUser(userId);
      _errorMessage = '';
    } catch (e) {
      _errorMessage = '名刺データの読み込みに失敗しました: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<BusinessCard?> addCard(BusinessCard card) async {
    _setLoading(true);
    try {
      final saved = await _db.insert(card);
      _cards.insert(0, saved);
      _errorMessage = '';
      notifyListeners();
      return saved;
    } catch (e) {
      _errorMessage = '名刺の保存に失敗しました: $e';
      notifyListeners();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateCard(BusinessCard card) async {
    _setLoading(true);
    try {
      await _db.update(card);
      final index = _cards.indexWhere((c) => c.id == card.id);
      if (index != -1) _cards[index] = card.copyWith(updatedAt: DateTime.now());
      _errorMessage = '';
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '名刺の更新に失敗しました: $e';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteCard(int id) async {
    _setLoading(true);
    try {
      await _db.delete(id);
      _cards.removeWhere((c) => c.id == id);
      _searchResults.removeWhere((c) => c.id == id);
      _errorMessage = '';
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '名刺の削除に失敗しました: $e';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> search(String userId, String keyword) async {
    _searchKeyword = keyword;
    if (keyword.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    try {
      _searchResults = await _db.search(userId: userId, keyword: keyword);
      _errorMessage = '';
    } catch (e) {
      _errorMessage = '検索に失敗しました: $e';
    }
    notifyListeners();
  }

  Future<List<BusinessCard>> searchForCall({
    required String userId, required String name, String? company}) async {
    try {
      return await _db.searchByNameAndCompany(
          userId: userId, name: name, company: company);
    } catch (e) {
      _errorMessage = '検索に失敗しました: $e';
      notifyListeners();
      return [];
    }
  }

  Future<List<String>> getAllCompanyNames(String userId) async {
    return await _db.getAllCompanyNames(userId);
  }

  Future<void> searchBlankKana(String userId) async {
    _searchKeyword = 'よみがな未入力';
    try {
      _searchResults = await _db.searchBlankKana(userId);
      _errorMessage = '';
    } catch (e) {
      _errorMessage = '検索に失敗しました: $e';
    }
    notifyListeners();
  }

  void clearSearch() {
    _searchKeyword = '';
    _searchResults = [];
    notifyListeners();
  }

  void clearAll() {
    _cards = [];
    _searchResults = [];
    _searchKeyword = '';
    _errorMessage = '';
    notifyListeners();
  }


  Future<int> importFromItunes(String userId) async {
    final count = await _db.importFromItunes(userId);
    if (count > 0) await loadCards(userId);
    return count;
  }

  Future<int> importFromJson(String json, String userId) async {
    final count = await _db.importFromJson(json, userId);
    if (count > 0) await loadCards(userId);
    return count;
  }

  Future<int> importFromPath(String path, String userId) async {
    final count = await _db.importFromPath(path, userId);
    if (count > 0) await loadCards(userId);
    return count;
  }

  // CSVファイルパスを受け取ってインポート（UIDocumentPicker経由で呼ぶ）
  Future<Map<String, int>> importFromCsv(String userId, {String? filePath}) async {
    int success = 0;
    int skip = 0;
    int error = 0;
    try {
      if (filePath == null || filePath.isEmpty) {
        return {'success': 0, 'skip': 0, 'error': 0, 'cancelled': 1};
      }
      final file = File(filePath);
      if (!await file.exists()) {
        return {'success': 0, 'skip': 0, 'error': 0, 'cancelled': 1};
      }
      final rawContent = await file.readAsString();
      // 簡易CSVパース（カンマ区切り、ダブルクォート対応）
      final rows = _parseCsv(rawContent);
      if (rows.isEmpty) return {'success': 0, 'skip': 0, 'error': 0};
      final dataRows = rows.skip(1).toList();
      for (final row in dataRows) {
        try {
          String v(int i) => i < row.length ? row[i].toString().trim() : '';
          if (v(0).isEmpty) { skip++; continue; }
          final card = BusinessCard(
            userId: userId,
            name: v(0),
            nameKana: v(1),
            company: v(2),
            companyKana: v(3),
            department: v(4),
            title: v(5),
            email: v(6),
            phone: v(7),
            mobilePhone: v(8),
            fax: v(9),
            note: v(10),
            industry: '',
            zipCode: v(11),
            address: v(12),
            projectCodes: [],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await _db.insert(card);
          success++;
        } catch (e) {
          error++;
        }
      }
      await loadCards(userId);
      return {'success': success, 'skip': skip, 'error': error};
    } catch (e) {
      _errorMessage = 'CSVインポートに失敗しました: $e';
      notifyListeners();
      return {'success': 0, 'skip': 0, 'error': 0};
    }
  }

  Future<int> deleteAllCards(String userId) async {
    _setLoading(true);
    try {
      final count = await _db.deleteAllByUser(userId);
      _cards = [];
      _searchResults = [];
      _searchKeyword = '';
      _errorMessage = '';
      notifyListeners();
      return count;
    } catch (e) {
      _errorMessage = '全削除に失敗しました: $e';
      notifyListeners();
      return 0;
    } finally {
      _setLoading(false);
    }
  }

  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }

  // 簡易CSVパーサー（外部パッケージ不要）
  List<List<String>> _parseCsv(String content) {
    final lines = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final result = <List<String>>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final fields = <String>[];
      bool inQuotes = false;
      final current = StringBuffer();
      for (int i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          inQuotes = !inQuotes;
        } else if (ch == ',' && !inQuotes) {
          fields.add(current.toString().trim());
          current.clear();
        } else {
          current.write(ch);
        }
      }
      fields.add(current.toString().trim());
      result.add(fields);
    }
    return result;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
// CSVインポート機能は別ファイルで追加
