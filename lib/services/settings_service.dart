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

  // 画像保存設定を取得（trueなら画像を保存する）
  static Future<bool> getSaveCardImage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySaveCardImage) ?? defaultSaveCardImage;
  }

  // 画像保存設定を保存
  static Future<void> setSaveCardImage(bool save) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySaveCardImage, save);
  }
}
