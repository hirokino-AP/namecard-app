import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
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


  Future<Map<String, int>> importFromCsv(String userId) async {
    int success = 0;
    int skip = 0;
    int error = 0;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (files.isEmpty) return {'success': 0, 'skip': 0, 'error': 0, 'cancelled': 1};
      final file = File(files.first.path!);
      final rawContent = await file.readAsString();
      final rows = Csv().decode(rawContent);
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

  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
// CSVインポート機能は別ファイルで追加
