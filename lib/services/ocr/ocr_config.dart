// ============================================================
// lib/services/ocr/ocr_config.dart
//
// 【役割】
//   Google Cloud Vision APIの設定値を一元管理する。
//   URLやAPIキーはこのファイルのみに記載。他ファイルでは触らない。
// ============================================================

class OcrConfig {
  // Google Cloud Vision API設定（--dart-defineで注入）
  static const apiKey = String.fromEnvironment('GOOGLE_VISION_API_KEY');
  static const endpoint = 'https://vision.googleapis.com/v1/images:annotate';
}
