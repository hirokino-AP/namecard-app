// lib/services/ocr_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class OcrService {
  static List<String> lastLines = [];
  static const _apiKey = String.fromEnvironment('GOOGLE_VISION_API_KEY');
  static const _endpoint = 'https://vision.googleapis.com/v1/images:annotate';

  static Future<Map<String, String>> recognizeBusinessCard(File imageFile) async {
    try {
      final xfile = XFile(imageFile.path);
      final bytes = await xfile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final response = await http.post(
        Uri.parse('${_endpoint}?key=${_apiKey}'),
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
        throw Exception("Status: \${response.statusCode}\nBody: \${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}");
      }
      final data = jsonDecode(response.body);
      final annotations = data['responses']?[0]?['textAnnotations'] as List?;
      if (annotations == null || annotations.isEmpty) throw Exception("annotations empty");
      final fullText = annotations[0]['description'] as String? ?? '';
      final lines = fullText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      lastLines = lines;
      return _parseLines(lines);
    } catch (e) {
      throw Exception('Vision API error: \$e');
    }
  }


  static Map<String, String> _parseLines(List<String> lines) {
    String name = '', company = '', department = '', title = '';
    String email = '', phone = '', mobilePhone = '', fax = '', zipCode = '', address = '';

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // URL除外
      if (RegExp(r'https?://|www\.').hasMatch(line)) continue;

      // メール（@を含む行からアドレスのみ抽出）
      final emailMatch = RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}').firstMatch(line);
      if (emailMatch != null) {
        if (email.isEmpty) email = emailMatch.group(0)!;

        continue;
      }

      // 郵便番号
      if (RegExp(r'[〒ａ]?\d{3}[-－]\d{4}(?!\d)').hasMatch(line) && !line.contains('TEL') && !line.contains('FAX') && !RegExp(r'0\d{9,10}').hasMatch(line)) {
        final zipMatch = RegExp(r'\d{3}[-－]\d{4}').firstMatch(line);
        if (zipMatch != null) { zipCode = zipMatch.group(0)!; }
        // 郵便番号の後に住所が続く場合
        final afterZip = line.replaceAll(RegExp(r'[〒ａ]?\d{3}[-－]\d{4}'), '').trim();
        if (afterZip.isNotEmpty && RegExp(r'[都道府県市区町村]').hasMatch(afterZip) && address.isEmpty) {
          address = afterZip;
        }
        continue;
      }

      // TEL & FAX が同一行の場合（例：TEL: 03-1234-5678  FAX: 03-1234-5679）
      if (RegExp(r'(?:TEL|Tel|tel|電話)').hasMatch(line) && RegExp(r'(?:FAX|Fax|fax)').hasMatch(line)) {
        final telMatch = RegExp(r'(?:TEL|Tel|tel|電話)[：:\s]*([0-9０-９\-－()（）+]+)').firstMatch(line);
        final faxMatch = RegExp(r'(?:FAX|Fax|fax)[：:\s]*([0-9０-９\-－()（）+]+)').firstMatch(line);
        if (telMatch != null && phone.isEmpty) {
          phone = telMatch.group(1)!.replaceAll(RegExp(r'[^\d\-]'), '');
        }
        if (faxMatch != null && fax.isEmpty) {
          fax = faxMatch.group(1)!.replaceAll(RegExp(r'[^\d\-]'), '');
        }
        continue;
      }

      // FAX（単独行）
      if (RegExp(r'(?:FAX|Fax|fax|ファックス|ファクス)[：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:FAX|Fax|fax|ファックス|ファクス)[：:\s]*'), '').trim();
        final numMatch = RegExp(r'[\d\-－()（）]+').firstMatch(cleaned);

        if (numMatch != null && fax.isEmpty) { fax = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), ''); continue; }
      }

      // TEL（単独行）
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

      // 国際電話番号（+81形式）
      if (RegExp(r'\+81[\s\-]?[\(\d]').hasMatch(line)) {
        final intlMatch = RegExp(r'\+81[\s\-]?\(?([\d\s\-()]{7,15})').firstMatch(line);
        if (intlMatch != null) {
          // +81 (3) 4222 4342 → 0342224342
          var num = intlMatch.group(0)!
              .replaceAll(RegExp(r'[^\d]'), '')
              .replaceFirst('81', '0');
          if (phone.isEmpty) phone = num;
          continue;
        }
      }

      // Mobile/Phone プレフィックス付き携帯
      if (RegExp(r'(?:Mobile|mobile|携帯)[.：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:Mobile|mobile|携帯)[.：:\s]*'), '').trim();
        final numMatch = RegExp(r'0[789]0[\d\-]{8,9}').firstMatch(cleaned);

        if (numMatch != null && mobilePhone.isEmpty) {
          mobilePhone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), ''); continue;
        }
      }

      // Phone プレフィックス付き固定電話
      if (RegExp(r'(?:Phone|phone|Tel\.)[.：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:Phone|phone|Tel\.)[.：:\s]*'), '').trim();
        final numMatch = RegExp(r'0\d[\d\-]{8,12}').firstMatch(cleaned);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), ''); continue;
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
      if (RegExp(r'[都道府県市区町村]').hasMatch(line) && !RegExp(r'株式会社|有限会社|合同会社').hasMatch(line)) {
        if (address.isEmpty) address = line; continue;
      }

      // 会社名（センターは部署と重複するので会社名には含めない）
      if (RegExp(r'株式会社|有限会社|合同会社|一般社団|公益財団|省$|庁$|機構|協会|組合|大学|University').hasMatch(line)) {
        if (company.isEmpty) company = line;
        continue;
      }

      // 部署
      if (RegExp(r'(?:部|課|室|グループ|チーム|センター|局|本部|Division|Dept)').hasMatch(line) && line.length <= 40) {
        if (department.isEmpty) department = line;
        continue;
      }

      // 役職
      if (RegExp(r'長$|主任|マネージャー|ディレクター|代表|社長|取締役|執行役|理事|助教|教授|Chairman|Director|Manager|President|professor').hasMatch(line) && line.length <= 30) {
        if (title.isEmpty) title = line;
        continue;
      }

      // 氏名（字間スペース対応）
      if (name.isEmpty) {
        final noSpace = line.replaceAll(RegExp(r'[\s　]'), '');
        // 漢字のみ2〜5文字（字間スペース除去後、行全体が短い場合）
        if (RegExp(r'^[一-鿿]{2,5}$').hasMatch(noSpace) && line.length <= 12) {
          name = noSpace; continue;
        }
        // 姓名スペース区切り（漢字）
        if (RegExp(r'^[一-鿿]{1,4}[\s　]+[一-鿿]{1,4}$').hasMatch(line)) {

          name = noSpace; continue;
        }
        // 漢字+英字ローマ字（例：西田 進一 Shinichi Nishida）
        if (RegExp(r'^[一-鿿]{1,4}[\s　]+[一-鿿]{1,4}[\s　]+[A-Za-z]').hasMatch(line)) {
          final kanjiPart = line.split(RegExp(r'[A-Za-z]'))[0].trim();
          name = kanjiPart.replaceAll(RegExp(r'[\s　]'), ''); continue;
        }
      }
    }

    return {
      'name': name, 'nameKana': '', 'company': company, 'department': department, 'title': title,
      'email': email, 'phone': phone, 'mobilePhone': mobilePhone,
      'fax': fax, 'zipCode': zipCode, 'address': address,
    };
  }
}
