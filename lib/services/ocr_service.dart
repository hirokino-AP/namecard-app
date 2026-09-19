// ============================================================
// lib/services/ocr_service.dart
//
// 【役割】
//   名刺画像をGoogle Cloud Vision APIでOCRし、
//   各フィールド（氏名・会社名・電話等）に振り分けるサービス。
//
// 【処理フロー】
//   1. 画像をBase64エンコードしてVision APIに送信
//   2. 返ってきたテキストを改行で分割して行リストを作成
//   3. _parseLines()で各行をフィールドに振り分け
//   4. 振り分け結果をOcrReviewScreenに渡してユーザーが確認・修正
//
// 【重要な制約】
//   - APIキーは--dart-defineで注入（ハードコード禁止）
//   - よみがなはOCRでは取得不可 → ユーザー手入力 or DB参照
//   - 氏名の振り分け精度は限定的 → OcrReviewScreenで補完
//
// 【今後の改善予定】
//   - bounding box（位置情報）を使った精度向上
//   - フォントサイズで氏名を特定する方式
// ============================================================

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class OcrService {
  // OCR後の生テキスト行リスト（OcrReviewScreenで参照）
  static List<String> lastLines = [];

  // Google Cloud Vision API設定（--dart-defineで注入）
  static const _apiKey = String.fromEnvironment('GOOGLE_VISION_API_KEY');
  static const _endpoint = 'https://vision.googleapis.com/v1/images:annotate';

  // ============================================================
  // 名刺画像をOCRして各フィールドのMapを返す（メインエントリ）
  // 戻り値: {'name': '', 'company': '', 'phone': '', ...}
  // ============================================================
  static Future<Map<String, String>> recognizeBusinessCard(File imageFile) async {
    try {
      // 画像をBase64エンコード
      final xfile = XFile(imageFile.path);
      final bytes = await xfile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Vision API呼び出し
      final response = await http.post(
        Uri.parse('${_endpoint}?key=${_apiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requests': [{
            'image': {'content': base64Image},
            'features': [{'type': 'TEXT_DETECTION', 'maxResults': 1}],
            'imageContext': {'languageHints': ['ja', 'en']}, // 日本語・英語優先
          }]
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Status: \${response.statusCode}\nBody: \${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}");
      }

      // レスポンスからテキスト取得
      final data = jsonDecode(response.body);
      final annotations = data['responses']?[0]?['textAnnotations'] as List?;
      if (annotations == null || annotations.isEmpty) throw Exception("annotations empty");

      // textAnnotations[0]が全テキスト結合結果
      final fullText = annotations[0]['description'] as String? ?? '';
      final lines = fullText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      // 生テキスト行を保存（OcrReviewScreenで使用）
      lastLines = lines;

      return _parseLines(lines);
    } catch (e) {
      throw Exception('Vision API error: \$e');
    }
  }

  // ============================================================
  // OCRテキスト行リストを各フィールドに振り分ける
  //
  // 【振り分け優先順位】（上から順に判定・continueで次の行へ）
  //   1. URL除外
  //   2. メールアドレス
  //   3. 郵便番号（住所が同行の場合も処理）
  //   4. TEL&FAX同一行
  //   5. FAX単独行
  //   6. TEL単独行
  //   7. 国際電話（+81）
  //   8. 携帯プレフィックス（Mobile/携帯）
  //   9. 固定電話プレフィックス（Phone/Tel.）
  //  10. 携帯電話（090/080/070パターン）
  //  11. 固定電話（0XX-XXXX-XXXXパターン）
  //  12. 住所（都道府県市区町村を含む）
  //  13. 会社名（株式会社・大学等を含む）
  //  14. 部署名（部・課・室・本部等を含む）
  //  15. 役職（長・マネージャー等を含む）
  //  16. 氏名（漢字2〜5文字、スペース区切り）
  //
  // 【既知の限界】
  //   - ロゴ・印章のテキストが混入することがある
  //   - 字間スペースがある氏名は認識しにくい
  //   - よみがな（ふりがな）は取得不可
  //   → OcrReviewScreenでユーザーが手動修正
  // ============================================================
  static Map<String, String> _parseLines(List<String> lines) {
    String name = '', company = '', department = '', title = '';
    String email = '', phone = '', mobilePhone = '', fax = '', zipCode = '', address = '';

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // ① URL除外（会社名・住所への誤判定防止）
      if (RegExp(r'https?://|www\.').hasMatch(line)) continue;

      // ② メールアドレス（E-mail:/Mail.等のプレフィックスを除去して抽出）
      final emailMatch = RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}').firstMatch(line);
      if (emailMatch != null) {
        if (email.isEmpty) email = emailMatch.group(0)!;
        continue;
      }

      // ③ 郵便番号（〒XXX-XXXX形式、電話番号との混在対策あり）
      if (RegExp(r'[〒ａ]?\d{3}[-－]\d{4}(?!\d)').hasMatch(line) && !line.contains('TEL') && !line.contains('FAX') && !RegExp(r'0\d{9,10}').hasMatch(line)) {
        final zipMatch = RegExp(r'\d{3}[-－]\d{4}').firstMatch(line);
        if (zipMatch != null) { zipCode = zipMatch.group(0)!; }
        // 郵便番号の後に住所が続く場合（例：〒104-0033 東京都中央区...）
        final afterZip = line.replaceAll(RegExp(r'[〒ａ]?\d{3}[-－]\d{4}'), '').trim();
        if (afterZip.isNotEmpty && RegExp(r'[都道府県市区町村]').hasMatch(afterZip) && address.isEmpty) {
          address = afterZip;
        }
        continue;
      }

      // ④ TEL&FAX同一行（例：TEL: 03-1234-5678  FAX: 03-1234-5679）
      if (RegExp(r'(?:TEL|Tel|tel|電話)').hasMatch(line) && RegExp(r'(?:FAX|Fax|fax)').hasMatch(line)) {
        final telMatch = RegExp(r'(?:TEL|Tel|tel|電話)[：:\s]*([0-9０-９\-－()（）+]+)').firstMatch(line);
        final faxMatch = RegExp(r'(?:FAX|Fax|fax)[：:\s]*([0-9０-９\-－()（）+]+)').firstMatch(line);
        if (telMatch != null && phone.isEmpty) phone = telMatch.group(1)!.replaceAll(RegExp(r'[^\d\-]'), '');
        if (faxMatch != null && fax.isEmpty) fax = faxMatch.group(1)!.replaceAll(RegExp(r'[^\d\-]'), '');
        continue;
      }

      // ⑤ FAX単独行
      if (RegExp(r'(?:FAX|Fax|fax|ファックス|ファクス)[：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:FAX|Fax|fax|ファックス|ファクス)[：:\s]*'), '').trim();
        final numMatch = RegExp(r'[\d\-－()（）]+').firstMatch(cleaned);
        if (numMatch != null && fax.isEmpty) { fax = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), ''); continue; }
      }

      // ⑥ TEL単独行（携帯(070/080/090)と固定電話を判別）
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

      // ⑦ 国際電話番号（+81形式 → 先頭を0に変換）
      if (RegExp(r'\+81[\s\-]?[\(\d]').hasMatch(line)) {
        final intlMatch = RegExp(r'\+81[\s\-]?\(?(\d[\s\-()\d]{6,14})').firstMatch(line);
        if (intlMatch != null) {
          var num = intlMatch.group(0)!.replaceAll(RegExp(r'[^\d]'), '').replaceFirst('81', '0');
          if (phone.isEmpty) phone = num;
          continue;
        }
      }

      // ⑧ 携帯プレフィックス（Mobile./携帯:）
      if (RegExp(r'(?:Mobile|mobile|携帯)[.：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:Mobile|mobile|携帯)[.：:\s]*'), '').trim();
        final numMatch = RegExp(r'0[789]0[\d\-]{8,9}').firstMatch(cleaned);
        if (numMatch != null && mobilePhone.isEmpty) {
          mobilePhone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), ''); continue;
        }
      }

      // ⑨ 固定電話プレフィックス（Phone./Tel.）
      if (RegExp(r'(?:Phone|phone|Tel\.)[.：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:Phone|phone|Tel\.)[.：:\s]*'), '').trim();
        final numMatch = RegExp(r'0\d[\d\-]{8,12}').firstMatch(cleaned);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), ''); continue;
        }
      }

      // ⑩ 携帯電話（プレフィックスなし、090/080/070パターン）
      if (RegExp(r'0[789]0[-－\s]?\d{4}[-－\s]?\d{4}').hasMatch(line)) {
        final numMatch = RegExp(r'0[789]0[-－\s]?\d{4}[-－\s]?\d{4}').firstMatch(line);
        if (numMatch != null && mobilePhone.isEmpty) {
          mobilePhone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          continue;
        }
      }

      // ⑪ 固定電話（プレフィックスなし）
      if (RegExp(r'0\d{1,4}[-－\s]?\d{2,4}[-－\s]?\d{4}').hasMatch(line) &&
          !line.contains('〒') && !RegExp(r'\d{3}[-－]\d{4}(?!\d)').hasMatch(line)) {
        final numMatch = RegExp(r'0\d{1,4}[-－\s]?\d{2,4}[-－\s]?\d{4}').firstMatch(line);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          continue;
        }
      }

      // ⑫ 住所（都道府県市区町村を含む行、会社名との誤判定対策あり）
      if (RegExp(r'[都道府県市区町村]').hasMatch(line) && !RegExp(r'株式会社|有限会社|合同会社').hasMatch(line)) {
        if (address.isEmpty) {
          // 住所に郵便番号が混入している場合は除去（例：〒104-0033 東京都→東京都）
          final cleanAddress = line.replaceAll(RegExp(r'[〒ａ]?\d{3}[-－]\d{4}\s*'), '').trim();
          // 郵便番号が未取得の場合は住所行から抽出
          if (zipCode.isEmpty) {
            final zipMatch = RegExp(r'\d{3}[-－]\d{4}').firstMatch(line);
            if (zipMatch != null) zipCode = zipMatch.group(0)!;
          }
          address = cleanAddress;
        }
        continue;
      }

      // ⑬ 会社名（株式会社・大学・University等を含む）
      // ※センターは部署と重複するため会社名判定から除外
      if (RegExp(r'株式会社|有限会社|合同会社|一般社団|公益財団|省$|庁$|機構|協会|組合|大学|University').hasMatch(line)) {
        if (company.isEmpty) company = line;
        continue;
      }

      // ⑭ 部署名（部・課・室・本部・センター等を含む）
      if (RegExp(r'(?:部|課|室|グループ|チーム|センター|局|本部|Division|Dept)').hasMatch(line) && line.length <= 40) {
        if (department.isEmpty) department = line;
        continue;
      }

      // ⑮ 役職（長・マネージャー・教授等を含む）
      if (RegExp(r'長$|主任|マネージャー|ディレクター|代表|社長|取締役|執行役|理事|助教|教授|Chairman|Director|Manager|President|professor').hasMatch(line) && line.length <= 30) {
        if (title.isEmpty) title = line;
        continue;
      }

      // ⑯ 氏名（字間スペース対応、漢字2〜5文字）
      // 【注意】ロゴ・印章テキストが混入する場合あり → OcrReviewScreenで修正
      if (name.isEmpty) {
        final noSpace = line.replaceAll(RegExp(r'[\s　]'), '');

        // パターンA: 漢字のみ2〜5文字（字間スペース除去後）
        if (RegExp(r'^[一-鿿]{2,5}\$').hasMatch(noSpace) && line.length <= 12) {
          name = noSpace; continue;
        }
        // パターンB: 姓名スペース区切り（例：山田 太郎）
        if (RegExp(r'^[一-鿿]{1,4}[\s　]+[一-鿿]{1,4}\$').hasMatch(line)) {
          name = noSpace; continue;
        }
        // パターンC: 漢字＋ローマ字（例：西田 進一 Shinichi Nishida）
        if (RegExp(r'^[一-鿿]{1,4}[\s　]+[一-鿿]{1,4}[\s　]+[A-Za-z]').hasMatch(line)) {
          final kanjiPart = line.split(RegExp(r'[A-Za-z]'))[0].trim();
          name = kanjiPart.replaceAll(RegExp(r'[\s　]'), ''); continue;
        }
      }
    }

    // よみがな（nameKana）はOCRで取得不可 → 空文字で返す
    return {
      'name': name, 'nameKana': '', 'company': company,
      'department': department, 'title': title,
      'email': email, 'phone': phone, 'mobilePhone': mobilePhone,
      'fax': fax, 'zipCode': zipCode, 'address': address,
    };
  }
}
