// ============================================================
// lib/services/ocr/ocr_vision_client.dart
//
// 【役割】
//   iPhone内蔵OCR（Apple Vision）の呼び出しのみを担当する。
//   画像は端末外に送信されない。
//   ocr_api_client.dart と同じ形（画像 → 行リスト）で返す。
//   フィールド振り分けは行わない。
// ============================================================

import 'dart:io';
import 'package:flutter/services.dart';

class OcrVisionClient {
  static const MethodChannel _channel =
      MethodChannel('com.hirokino.namecardapp/document_picker');

  // 名刺画像を端末内でOCRし、テキスト行リストを返す
  static Future<List<String>> extractText(File imageFile) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
          'recognizeText', imageFile.path);
      final lines = (result ?? [])
          .map((e) => e.toString().trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        throw Exception('OCR結果が取得できませんでした');
      }
      return lines;
    } on PlatformException catch (e) {
      throw Exception('端末内OCRエラー: ${e.message ?? e.code}');
    }
  }
}
