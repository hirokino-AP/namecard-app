// ============================================================
// lib/services/settings_service.dart
//
// 【役割】
//   アプリの個人設定をUserDefaults（SharedPreferences）に保存・取得。
//
// 【設定項目】
//   - voiceSearchDelay: 音声検索待機時間（秒）デフォルト2秒
//
// 【使い方】
//   final delay = await SettingsService.getVoiceSearchDelay();
//   await SettingsService.setVoiceSearchDelay(3);
// ============================================================

import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  // キー定義
  static const String _keyVoiceSearchDelay = 'voice_search_delay';

  static const String _keyDisplayCount    = 'display_count';
  static const String _keyFontSize        = 'font_size';
  static const String _keyThemeColor      = 'theme_color';

  // デフォルト値
  static const int    defaultVoiceSearchDelay = 2;
  static const int    defaultDisplayCount     = 0;    // 0=制限なし
  static const double defaultFontSize         = 14.0;
  static const String defaultThemeColor       = '#185FA5'; // Navy Blue

  // 音声検索待機時間を取得（秒）
  static Future<int> getVoiceSearchDelay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyVoiceSearchDelay) ?? defaultVoiceSearchDelay;
  }

  // 音声検索待機時間を保存（秒）
  static Future<void> setVoiceSearchDelay(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyVoiceSearchDelay, seconds);
  }

  // 表示件数を取得（0=制限なし）
  static Future<int> getDisplayCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDisplayCount) ?? defaultDisplayCount;
  }

  // 表示件数を保存
  static Future<void> setDisplayCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDisplayCount, count);
  }

  // フォントサイズを取得
  static Future<double> getFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyFontSize) ?? defaultFontSize;
  }

  // フォントサイズを保存
  static Future<void> setFontSize(double size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, size);
  }

  // テーマカラーを取得（16進数文字列）
  static Future<String> getThemeColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyThemeColor) ?? defaultThemeColor;
  }

  // テーマカラーを保存
  static Future<void> setThemeColor(String colorHex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeColor, colorHex);
  }

  // テーマカラーをColorオブジェクトに変換
  static int colorFromHex(String hex) {
    final h = hex.replaceAll('#', '');
    return int.parse('FF$h', radix: 16);
  }

  // ── 画像保存設定 ──
  static const String _keySaveCardImage = 'save_card_image';
  static const bool defaultSaveCardImage = true;

  // 会社名マッチング最小文字数
  static const String _keyCompanyMatchLength = 'company_match_length';
  static const int defaultCompanyMatchLength = 3; // デフォルト3文字

  // 会社辞書登録件数
  static const String _keyCompanyDictSize = 'company_dict_size';
  static const int defaultCompanyDictSize = 0; // デフォルト制限なし（全件）

  // 画像保存設定を取得（trueなら画像を保存する）
  static Future<bool> getSaveCardImage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySaveCardImage) ?? defaultSaveCardImage;
  }

  // 会社辞書登録件数を取得
  static Future<int> getCompanyDictSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyCompanyDictSize) ?? defaultCompanyDictSize;
  }

  // 会社辞書登録件数を保存
  static Future<void> setCompanyDictSize(int size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCompanyDictSize, size);
  }

  // 会社名マッチング最小文字数を取得
  static Future<int> getCompanyMatchLength() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyCompanyMatchLength) ?? defaultCompanyMatchLength;
  }

  // 会社名マッチング最小文字数を保存
  static Future<void> setCompanyMatchLength(int length) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCompanyMatchLength, length);
  }

  // OCRプレフィックス除去キーワード
  static const String _keyOcrPrefixes = 'ocr_prefixes';
  static const String defaultOcrPrefixes =
      'E-mail,E-Mail,Email,Mail,email,メール,電子メール,TEL,Tel,tel,電話,FAX,Fax,fax,ファックス,ファクス,Mobile,mobile,携帯,Cell,Phone,phone,直通,内線';

  // OCRプレフィックスキーワードを取得
  static Future<String> getOcrPrefixes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOcrPrefixes) ?? defaultOcrPrefixes;
  }

  // OCRプレフィックスキーワードを保存
  static Future<void> setOcrPrefixes(String prefixes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOcrPrefixes, prefixes);
  }

  // OCRプレフィックスキーワードをリストで取得
  static Future<List<String>> getOcrPrefixList() async {
    final prefixes = await getOcrPrefixes();
    return prefixes.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  // 画像保存設定を保存
  static Future<void> setSaveCardImage(bool save) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySaveCardImage, save);
  }

  // ── OCRエンジン設定 ──
  // 'cloud'  = Google Cloud Vision（現行・画像をGoogleに送信）
  // 'device' = iPhone内蔵OCR（Apple Vision・端末内で完結）
  static const String _keyOcrEngine = 'ocr_engine';
  static const String ocrEngineCloud = 'cloud';
  static const String ocrEngineDevice = 'device';
  static const String defaultOcrEngine = ocrEngineCloud; // 既定は現行のまま

  // OCRエンジンを取得
  static Future<String> getOcrEngine() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyOcrEngine) ?? defaultOcrEngine;
    return v == ocrEngineDevice ? ocrEngineDevice : ocrEngineCloud;
  }

  // OCRエンジンを保存
  static Future<void> setOcrEngine(String engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyOcrEngine, engine == ocrEngineDevice ? ocrEngineDevice : ocrEngineCloud);
  }
}
