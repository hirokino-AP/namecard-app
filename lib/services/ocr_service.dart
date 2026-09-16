// lib/services/ocr_service.dart
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  static final _recognizer = TextRecognizer(script: TextRecognitionScript.japanese);

  static Future<Map<String, String>> recognizeBusinessCard(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognized = await _recognizer.processImage(inputImage);
    final lines = recognized.blocks
        .expand((b) => b.lines)
        .map((l) => l.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return _parseLines(lines);
  }

  static Map<String, String> _parseLines(List<String> lines) {
    String name = '';
    String company = '';
    String department = '';
    String title = '';
    String email = '';
    String phone = '';
    String mobilePhone = '';
    String fax = '';
    String zipCode = '';
    String address = '';

    for (final line in lines) {
      // メール
      if (RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}').hasMatch(line)) {
        email = line.trim();
        continue;
      }
      // 郵便番号
      if (RegExp(r'[〒]?\d{3}-\d{4}').hasMatch(line)) {
        zipCode = line.replaceAll('〒', '').trim();
        continue;
      }
      // FAX
      if (line.contains('FAX') || line.contains('Fax') || line.contains('fax') || line.contains('ファックス')) {
        fax = line.replaceAll(RegExp(r'[FAXfaxファックス：: ]'), '').trim();
        continue;
      }
      // 携帯電話
      if (RegExp(r'0[789]0[-\s]?\d{4}[-\s]?\d{4}').hasMatch(line)) {
        mobilePhone = line.replaceAll(RegExp(r'[^\d\-]'), '').trim();
        continue;
      }
      // 電話番号
      if (RegExp(r'0\d{1,4}[-\s]?\d{2,4}[-\s]?\d{4}').hasMatch(line)) {
        phone = line.replaceAll(RegExp(r'[^\d\-]'), '').trim();
        continue;
      }
      // 住所
      if (line.contains('都') || line.contains('道') || line.contains('府') || line.contains('県') ||
          line.contains('市') || line.contains('区') || line.contains('町') || line.contains('村')) {
        address = line.trim();
        continue;
      }
      // 会社名
      if (line.contains('株式会社') || line.contains('有限会社') || line.contains('合同会社') ||
          line.contains('一般社団') || line.contains('公益財団') || line.contains('省') ||
          line.contains('庁') || line.contains('局') && line.length > 3) {
        if (company.isEmpty) company = line.trim();
        else if (department.isEmpty) department = line.trim();
        continue;
      }
      // 部署
      if (line.contains('部') || line.contains('課') || line.contains('室') || line.contains('グループ') ||
          line.contains('チーム') || line.contains('センター')) {
        if (department.isEmpty) department = line.trim();
        continue;
      }
      // 役職
      if (line.contains('長') || line.contains('部長') || line.contains('課長') || line.contains('係長') ||
          line.contains('主任') || line.contains('マネージャー') || line.contains('ディレクター') ||
          line.contains('代表') || line.contains('社長') || line.contains('取締役')) {
        if (title.isEmpty) title = line.trim();
        continue;
      }
      // 氏名候補（漢字2〜4文字、ひらがな・カタカナのみの短い行）
      if (name.isEmpty &&
          RegExp(r'^[\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff]{2,6}$').hasMatch(line) &&
          line.length <= 6) {
        name = line.trim();
        continue;
      }
    }

    return {
      'name': name,
      'company': company,
      'department': department,
      'title': title,
      'email': email,
      'phone': phone,
      'mobilePhone': mobilePhone,
      'fax': fax,
      'zipCode': zipCode,
      'address': address,
    };
  }

  static Future<void> close() async {
    await _recognizer.close();
  }
}
