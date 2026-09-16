// lib/services/ocr_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class OcrService {
  static const _apiKey = String.fromEnvironment('GOOGLE_VISION_API_KEY');
  static const _endpoint = 'https://vision.googleapis.com/v1/images:annotate';

  static Future<Map<String, String>> recognizeBusinessCard(File imageFile) async {
    try {
      // 画像を圧縮（最大1MB）
      final picker = ImagePicker();
      final xfile = XFile(imageFile.path);
      final bytes = await xfile.readAsBytes();
      // 1MB超えの場合はそのまま（image_pickerで既に圧縮済み）
      final base64Image = base64Encode(bytes);
      print('Image size: \${bytes.length} bytes');
      print('Base64 length: \${base64Image.length}');
      final response = await http.post(
        Uri.parse('$_endpoint?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requests': [{
            'image': {'content': base64Image},
            'features': [{'type': 'TEXT_DETECTION', 'maxResults': 1}],
            'imageContext': {'languageHints': ['ja', 'en']},
          }]
        }),
      );
      final statusCode = response.statusCode;
      final responseBody = response.body.length > 1000 ? response.body.substring(0, 1000) : response.body;
      if (statusCode != 200) {
        throw Exception("Status: ${response.statusCode}\nBody: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}");
      }
      final data = jsonDecode(response.body);
      final annotations = data['responses']?[0]?['textAnnotations'] as List?;
      if (annotations == null || annotations.isEmpty) throw Exception("annotations empty\nResponse: $responseBody");
      final fullText = annotations[0]['description'] as String? ?? '';
      final lines = fullText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      return _parseLines(lines);
    } catch (e) {
      throw Exception('Vision API error: $e');
    }
  }

  static Map<String, String> _emptyResult() => {
    'name': '', 'company': '', 'department': '', 'title': '',
    'email': '', 'phone': '', 'mobilePhone': '', 'fax': '', 'zipCode': '', 'address': '',
  };

  static Map<String, String> _parseLines(List<String> lines) {
    String name = '', company = '', department = '', title = '';
    String email = '', phone = '', mobilePhone = '', fax = '', zipCode = '', address = '';

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // メール（ヘッダー除去: e-mail:, Email:, メール: 等）
      final emailMatch = RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}').firstMatch(line);
      if (emailMatch != null) {
        email = emailMatch.group(0)!;
        continue;
      }

      // 郵便番号（〒マーク除去、電話番号との混在対策）
      if (RegExp(r'[〒ａ]?\d{3}[-－]\d{4}(?!\d)').hasMatch(line) && !line.contains('TEL') && !line.contains('FAX') && !RegExp(r'0\d{9,10}').hasMatch(line)) {
        final zipMatch = RegExp(r'\d{3}[-－]\d{4}').firstMatch(line);
        if (zipMatch != null) { zipCode = zipMatch.group(0)!; continue; }
      }

      // FAX（ヘッダー除去）
      if (RegExp(r'(?:FAX|Fax|fax|ファックス|ファクス)[：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:FAX|Fax|fax|ファックス|ファクス)[：:\s]*'), '').trim();
        final numMatch = RegExp(r'[\d\-－()（）]+').firstMatch(cleaned);
        if (numMatch != null && fax.isEmpty) { fax = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), ''); continue; }
      }

      // TEL（ヘッダー除去）
      if (RegExp(r'(?:TEL|Tel|tel|電話)[：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:TEL|Tel|tel|電話)[：:\s]*'), '').trim();
        final numMatch = RegExp(r'0\d[\d\-－]{8,12}').firstMatch(cleaned);
        if (numMatch != null) {
          final num = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          if (RegExp(r'^0[789]0').hasMatch(num)) { if (mobilePhone.isEmpty) mobilePhone = num; }
          else { if (phone.isEmpty) phone = num; }
          continue;
        }
      }

      // 携帯電話（090/080/070）
      if (RegExp(r'0[789]0[-－\s]?\d{4}[-－\s]?\d{4}').hasMatch(line)) {
        final numMatch = RegExp(r'0[789]0[-－\s]?\d{4}[-－\s]?\d{4}').firstMatch(line);
        if (numMatch != null && mobilePhone.isEmpty) {
          mobilePhone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          continue;
        }
      }

      // 固定電話
      if (RegExp(r'0\d{1,4}[-－\s]?\d{2,4}[-－\s]?\d{4}').hasMatch(line) && !line.contains('〒') && !RegExp(r'\d{3}[-－]\d{4}(?!\d)').hasMatch(line)) {
        final numMatch = RegExp(r'0\d{1,4}[-－\s]?\d{2,4}[-－\s]?\d{4}').firstMatch(line);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          continue;
        }
      }

      // 住所
      if (RegExp(r'[都道府県市区町村]').hasMatch(line)) { if (address.isEmpty) address = line; continue; }

      // 会社名
      if (RegExp(r'株式会社|有限会社|合同会社|一般社団|公益財団|省$|庁$|機構|センター|協会|組合').hasMatch(line)) {
        if (company.isEmpty) company = line;
        else if (department.isEmpty) department = line;
        continue;
      }

      // 部署
      if (RegExp(r'(?:部|課|室|グループ|チーム|センター|局|Division|Dept)').hasMatch(line) && line.length <= 30) {
        if (department.isEmpty) department = line;
        continue;
      }

      // 役職
      if (RegExp(r'長|主任|マネージャー|ディレクター|代表|社長|取締役|執行役|理事|Chairman|Director|Manager|President').hasMatch(line) && line.length <= 20) {
        if (title.isEmpty) title = line;
        continue;
      }

      // 氏名（漢字2〜4文字 or 姓名スペース区切り）
      if (name.isEmpty) {
        // 漢字のみ2〜5文字
        if (RegExp(r'^[一-鿿]{2,5}$').hasMatch(line)) { name = line; continue; }
        // 姓名スペース区切り（漢字）
        if (RegExp(r'^[一-鿿]{1,3}[\s　][一-鿿]{1,3}$').hasMatch(line)) { name = line.replaceAll(RegExp(r'[\s　]'), ''); continue; }
      }
    }

    return {
      'name': name, 'company': company, 'department': department, 'title': title,
      'email': email, 'phone': phone, 'mobilePhone': mobilePhone,
      'fax': fax, 'zipCode': zipCode, 'address': address,
    };
  }
}
