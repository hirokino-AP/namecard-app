// ============================================================
// lib/services/ocr/ocr_api_client.dart
//
// 【役割】
//   Google Cloud Vision APIとの通信のみを担当する。
//   URLやAPIキーはocr_config.dartから参照する。
//   テキスト抽出のみ行い、フィールド振り分けは行わない。
// ============================================================

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'ocr_config.dart';

class OcrApiClient {
  // 名刺画像をVision APIに送信し、テキスト行リストを返す
  static Future<List<String>> extractText(File imageFile) async {
    final xfile = XFile(imageFile.path);
    final bytes = await xfile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse('${OcrConfig.endpoint}?key=${OcrConfig.apiKey}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'requests': [{
          'image': {'content': base64Image},
          'features': [{'type': 'TEXT_DETECTION', 'maxResults': 1}],
          'imageContext': {'languageHints': ['ja', 'en']},
        }]
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("Vision API Status: ${response.statusCode}");
    }

    final data = jsonDecode(response.body);
    final annotations = data['responses']?[0]?['textAnnotations'] as List?;
    if (annotations == null || annotations.isEmpty) {
      throw Exception("OCR結果が取得できませんでした");
    }

    final fullText = annotations[0]['description'] as String? ?? '';
    return fullText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }
}
