// lib/services/ocr_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class OcrService {
  static const _apiKey = String.fromEnvironment('GOOGLE_VISION_API_KEY');
  static const _endpoint = 'https://vision.googleapis.com/v1/images:annotate';

  static Future<Map<String, String>> recognizeBusinessCard(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
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
      if (response.statusCode != 200) return _emptyResult();
      final data = jsonDecode(response.body);
      final annotations = data['responses']?[0]?['textAnnotations'] as List?;
      if (annotations == null || annotations.isEmpty) return _emptyResult();
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
    for (final line in lines) {
      if (RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}').hasMatch(line)) { email = line.trim(); continue; }
      if (RegExp(r'[〒]?\d{3}-\d{4}').hasMatch(line)) { zipCode = line.replaceAll('〒', '').trim(); continue; }
      if (line.contains('FAX') || line.contains('Fax') || line.contains('ファックス')) { fax = line.replaceAll(RegExp(r'[FAXfaxファックス：: ]'), '').trim(); continue; }
      if (RegExp(r'0[789]0[-\s]?\d{4}[-\s]?\d{4}').hasMatch(line)) { mobilePhone = line.replaceAll(RegExp(r'[^\d\-]'), '').trim(); continue; }
      if (RegExp(r'0\d{1,4}[-\s]?\d{2,4}[-\s]?\d{4}').hasMatch(line)) { phone = line.replaceAll(RegExp(r'[^\d\-]'), '').trim(); continue; }
      if (line.contains('都') || line.contains('道') || line.contains('府') || line.contains('県') || line.contains('市') || line.contains('区')) { address = line.trim(); continue; }
      if (line.contains('株式会社') || line.contains('有限会社') || line.contains('合同会社') || line.contains('省') || line.contains('庁')) { if (company.isEmpty) company = line.trim(); else if (department.isEmpty) department = line.trim(); continue; }
      if (line.contains('部') || line.contains('課') || line.contains('室') || line.contains('グループ') || line.contains('センター')) { if (department.isEmpty) department = line.trim(); continue; }
      if (line.contains('長') || line.contains('主任') || line.contains('マネージャー') || line.contains('代表') || line.contains('社長') || line.contains('取締役')) { if (title.isEmpty) title = line.trim(); continue; }
      if (name.isEmpty && RegExp(r'^[\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff]{2,6}$').hasMatch(line) && line.length <= 6) { name = line.trim(); continue; }
    }
    return {'name': name, 'company': company, 'department': department, 'title': title, 'email': email, 'phone': phone, 'mobilePhone': mobilePhone, 'fax': fax, 'zipCode': zipCode, 'address': address};
  }
}
