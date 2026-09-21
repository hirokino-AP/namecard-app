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
import 'settings_service.dart';

class OcrService {
  // OCR後の生テキスト行リスト（OcrReviewScreenで参照）
  static List<String> lastLines = [];
  // 会社辞書（氏名誤判定防止用）→OCR前にセットする
  static List<String> companyNames = [];

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
      // 郵便番号+住所を分離した行リストを確認画面・パース両方に使用
      final splitLines = _splitZipAndAddress(lines);
      // 確認画面表示用にプレフィックスを除去（設定値を使用）
      final prefixes = await SettingsService.getOcrPrefixList();
      lastLines = splitLines.map((line) => _cleanLineForDisplay(line, prefixes: prefixes)).toList();

      // company_dictから会社名リストを取得（氏名誤判定防止）
      // ※DBアクセスは非同期なので静的メソッドでは難しいため
      // OcrService.companyNamesを事前にセットする方式を使用
      return _parseLines(splitLines, prefixes: prefixes, companyNames: OcrService.companyNames);
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
  // 確認画面表示用：プレフィックスを除去してクリーンな表示にする
  // 設定で追加されたキーワードも除去する
  static String _cleanLineForDisplay(String line, {List<String> prefixes = const []}) {
    String cleaned = line;
    // 設定値のプレフィックスを除去
    for (final prefix in prefixes) {
      if (prefix.isEmpty) continue;
      // プレフィックス+区切り文字（:、：、.、スペース）を除去
      cleaned = cleaned.replaceAll(
        RegExp('${RegExp.escape(prefix)}[：:.\s]*', caseSensitive: false),
        '',
      );
    }
    return cleaned.trim().isEmpty ? line : cleaned.trim();
  }

  // OCR行リストの前処理：郵便番号+住所を分離して2行に分割
  static List<String> _splitZipAndAddress(List<String> lines) {
    final result = <String>[];
    for (final line in lines) {
      // 〒XXX-XXXX + 住所が同一行の場合に分離
      final zipMatch = RegExp(r'[〒ａ]?\d{3}[-－]\d{4}').firstMatch(line);
      if (zipMatch != null && RegExp(r'[都道府県市区町村]').hasMatch(line)) {
        final zip = zipMatch.group(0)!;
        final address = line.replaceAll(RegExp(r'[〒ａ]?\d{3}[-－]\d{4}\s*'), '').trim();
        result.add(zip);         // 郵便番号を独立した行として追加
        if (address.isNotEmpty) result.add(address); // 住所を独立した行として追加
      } else {
        result.add(line);
      }
    }
    return result;
  }

  // カタカナ→ひらがな変換
  static String _katakanaToHiragana(String katakana) {
    return katakana.split('').map((c) {
      final code = c.codeUnitAt(0);
      // カタカナ範囲（0x30A0〜0x30FF）をひらがな（0x3040〜0x309F）に変換
      if (code >= 0x30A1 && code <= 0x30F6) {
        return String.fromCharCode(code - 0x60);
      }
      return c;
    }).join('');
  }

  // ローマ字の姓名を反転（英語式→日本式）
  // 例：Hiroshi Kinoshita → Kinoshita Hiroshi → きのしたひろし
  static String _reverseRomajiName(String romaji) {
    final parts = romaji.trim().split(RegExp(r'[\s　]+'));
    if (parts.length < 2) return romaji;
    // 英語式（名 姓）→ 日本式（姓 名）に反転
    final reversed = [...parts.reversed].join('');
    return _romajiToHiragana(reversed.toLowerCase());
  }

  // ローマ字→ひらがな変換（ヘボン式・訓令式対応）
  static String _romajiToHiragana(String romaji) {
    final map = {
      'sha':'しゃ','shi':'し','shu':'しゅ','sho':'しょ',
      'chi':'ち','tsu':'つ','tchi':'っち',
      'cha':'ちゃ','chu':'ちゅ','cho':'ちょ',
      'kya':'きゃ','kyu':'きゅ','kyo':'きょ',
      'nya':'にゃ','nyu':'にゅ','nyo':'にょ',
      'hya':'ひゃ','hyu':'ひゅ','hyo':'ひょ',
      'mya':'みゃ','myu':'みゅ','myo':'みょ',
      'rya':'りゃ','ryu':'りゅ','ryo':'りょ',
      'ka':'か','ki':'き','ku':'く','ke':'け','ko':'こ',
      'sa':'さ','si':'し','su':'す','se':'せ','so':'そ',
      'ta':'た','ti':'ち','tu':'つ','te':'て','to':'と',
      'na':'な','ni':'に','nu':'ぬ','ne':'ね','no':'の',
      'ha':'は','hi':'ひ','hu':'ふ','he':'へ','ho':'ほ',
      'ma':'ま','mi':'み','mu':'む','me':'め','mo':'も',
      'ya':'や','yu':'ゆ','yo':'よ',
      'ra':'ら','ri':'り','ru':'る','re':'れ','ro':'ろ',
      'wa':'わ','wi':'ゐ','we':'ゑ','wo':'を',
      'ga':'が','gi':'ぎ','gu':'ぐ','ge':'げ','go':'ご',
      'za':'ざ','zi':'じ','zu':'ず','ze':'ぜ','zo':'ぞ',
      'da':'だ','di':'ぢ','du':'づ','de':'で','do':'ど',
      'ba':'ば','bi':'び','bu':'ぶ','be':'べ','bo':'ぼ',
      'pa':'ぱ','pi':'ぴ','pu':'ぷ','pe':'ぺ','po':'ぽ',
      'fa':'ふぁ','fu':'ふ',
      'a':'あ','i':'い','u':'う','e':'え','o':'お',
      'n':'ん',
    };

    String result = romaji.toLowerCase();
    // 長い音から順に置換
    final keys = map.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      result = result.replaceAll(key, map[key]!);
    }
    // 変換できなかった文字が残っている場合は空文字を返す
    if (RegExp(r'[a-z]').hasMatch(result)) return '';
    return result;
  }

  // 行ごとの判定結果を外部から参照できるように保持
  static Map<int, String> lastLineFields = {};

  static Map<String, String> _parseLines(List<String> lines, {List<String> prefixes = const [], List<String> companyNames = const []}) {
    String name = '', nameKana = '', company = '', department = '', title = '';
    String email = '', phone = '', mobilePhone = '', fax = '', zipCode = '', address = '';
    final kanaCandidate = <String>[];
    final lineFields = <int, String>{};

    // プレフィックス除去処理
    String _applyPrefixFilter(String line) {
      String filtered = line;
      for (final prefix in prefixes) {
        if (prefix.isEmpty) continue;
        filtered = filtered.replaceAll(
          RegExp('${RegExp.escape(prefix)}[：:．.\s]*', caseSensitive: false), '').trim();
      }
      return filtered.isEmpty ? line : filtered;
    }

    // ============================================================
    // 【1パス目】確実なマーカーで確定できるものを全行スキャン
    // ============================================================
    for (int i = 0; i < lines.length; i++) {
      final raw = lines[i].trim();
      if (raw.isEmpty) continue;
      final line = _applyPrefixFilter(raw);

      // URL除外
      if (RegExp(r'https?://|www\.').hasMatch(line)) { lineFields[i] = 'skip'; continue; }

      // メール（@マーク）
      final emailMatch = RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}').firstMatch(line);
      if (emailMatch != null) {
        if (email.isEmpty) { email = emailMatch.group(0)!; lineFields[i] = 'email'; }
        continue;
      }

      // 郵便番号（〒XXX-XXXX）
      if (RegExp(r'[〒ａ]?\d{3}[-－]\d{4}(?!\d)').hasMatch(line) &&
          !RegExp(r'0\d{9,10}').hasMatch(line)) {
        final zipMatch = RegExp(r'\d{3}[-－]\d{4}').firstMatch(line);
        if (zipMatch != null) { zipCode = zipMatch.group(0)!; lineFields[i] = 'zipCode'; }
        final afterZip = line.replaceAll(RegExp(r'[〒ａ]?\d{3}[-－]\d{4}'), '').trim();
        if (afterZip.isNotEmpty && RegExp(r'[都道府県市区町村]').hasMatch(afterZip) && address.isEmpty) {
          address = afterZip;
        }
        continue;
      }

      // TEL&FAX同一行
      if (RegExp(r'(?:TEL|Tel\.?|tel|電話)').hasMatch(line) && RegExp(r'(?:FAX|Fax\.?|fax)').hasMatch(line)) {
        final telMatch = RegExp(r'(?:TEL|Tel\.?|tel|電話)[：:.\s]*([0-9０-９\-－()（）+]+)').firstMatch(line);
        final faxMatch = RegExp(r'(?:FAX|Fax\.?|fax)[：:.\s]*([0-9０-９\-－()（）+]+)').firstMatch(line);
        if (telMatch != null) {
          final num = telMatch.group(1)!.replaceAll(RegExp(r'[^\d\-]'), '');
          if (RegExp(r'^0[789]0').hasMatch(num)) { if (mobilePhone.isEmpty) { mobilePhone = num; lineFields[i] = 'mobilePhone'; } }
          else { if (phone.isEmpty) { phone = num; lineFields[i] = 'phone'; } }
        }
        if (faxMatch != null && fax.isEmpty) { fax = faxMatch.group(1)!.replaceAll(RegExp(r'[^\d\-]'), ''); lineFields[i] = 'fax'; }
        continue;
      }

      // FAX単独行
      if (RegExp(r'(?:FAX|Fax\.?|fax|ファックス|ファクス)[：:.\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:FAX|Fax\.?|fax|ファックス|ファクス)[：:.\s]*'), '').trim();
        final numMatch = RegExp(r'[\d\-－()（）]+').firstMatch(cleaned);
        if (numMatch != null && fax.isEmpty) { fax = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), ''); lineFields[i] = 'fax'; continue; }
      }

      // TEL単独行
      if (RegExp(r'(?:TEL|Tel\.?|tel|電話)[：:.\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:TEL|Tel\.?|tel|電話)[：:.\s]*'), '').trim();
        final numMatch = RegExp(r'0\d[\d\-－]{8,12}').firstMatch(cleaned);
        if (numMatch != null) {
          final num = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          if (RegExp(r'^0[789]0').hasMatch(num)) { if (mobilePhone.isEmpty) { mobilePhone = num; lineFields[i] = 'mobilePhone'; } }
          else { if (phone.isEmpty) { phone = num; lineFields[i] = 'phone'; } }
          continue;
        }
      }

      // 国際電話（+81）
      if (RegExp(r'\+81[\s\-]?[\(\d]').hasMatch(line)) {
        final intlMatch = RegExp(r'\+81[\s\-]?\(?(\ d[\s\-()\ d]{6,14})').firstMatch(line);
        if (intlMatch != null) {
          final num = intlMatch.group(0)!.replaceAll(RegExp(r'[^\d]'), '').replaceFirst('81', '0');
          if (phone.isEmpty) { phone = num; lineFields[i] = 'phone'; }
          continue;
        }
      }

      // 携帯プレフィックス
      if (RegExp(r'(?:Mobile|mobile|携帯)[.：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:Mobile|mobile|携帯)[.：:\s]*'), '').trim();
        final numMatch = RegExp(r'0[789]0[\d\-]{8,9}').firstMatch(cleaned);
        if (numMatch != null && mobilePhone.isEmpty) {
          mobilePhone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'mobilePhone'; continue;
        }
      }

      // 固定電話プレフィックス
      if (RegExp(r'(?:Phone|phone|Tel\.)[.：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:Phone|phone|Tel\.)[.：:\s]*'), '').trim();
        final numMatch = RegExp(r'0\d[\d\-]{8,12}').firstMatch(cleaned);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'phone'; continue;
        }
      }

      // 携帯電話（プレフィックスなし）
      if (RegExp(r'0[789]0[-－\s]?\d{4}[-－\s]?\d{4}').hasMatch(line)) {
        final numMatch = RegExp(r'0[789]0[-－\s]?\d{4}[-－\s]?\d{4}').firstMatch(line);
        if (numMatch != null && mobilePhone.isEmpty) {
          mobilePhone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'mobilePhone'; continue;
        }
      }

      // 固定電話（プレフィックスなし）
      if (RegExp(r'0\d{1,4}[-－\s]?\d{2,4}[-－\s]?\d{4}').hasMatch(line) &&
          !line.contains('〒') && !RegExp(r'\d{3}[-－]\d{4}(?!\d)').hasMatch(line)) {
        final numMatch = RegExp(r'0\d{1,4}[-－\s]?\d{2,4}[-－\s]?\d{4}').firstMatch(line);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'phone'; continue;
        }
      }

      // 住所（都道府県市区町村）
      if (RegExp(r'[都道府県市区町村]').hasMatch(line) && !RegExp(r'株式会社|有限会社|合同会社').hasMatch(line)) {
        if (address.isEmpty) {
          final cleanAddress = line.replaceAll(RegExp(r'[〒ａ]?\d{3}[-－]\d{4}\s*'), '').trim();
          if (zipCode.isEmpty) {
            final zipMatch = RegExp(r'\d{3}[-－]\d{4}').firstMatch(line);
            if (zipMatch != null) zipCode = zipMatch.group(0)!;
          }
          address = cleanAddress; lineFields[i] = 'address';
        }
        continue;
      }

      // 会社名（企業形態マーカーで確定）
      if (RegExp(r'株式会社|有限会社|合同会社|合資会社|合名会社|一般社団|公益社団|一般財団|公益財団|特定非営利|社会福祉|医療法人|学校法人|宗教法人|省$|庁$|機構|協会|組合|大学|大学院|University|Corporation|Corp\.|Inc\.|Ltd\.').hasMatch(line)) {
        if (company.isEmpty) { company = line; lineFields[i] = 'company'; }
        continue;
      }

      // 部署名（部・課・室・本部等）
      if (RegExp(r'(?:事業部|営業部|開発部|管理部|総務部|人事部|経理部|財務部|法務部|広報部|企画部|技術部|製造部|品質部|購買部|物流部|情報部|システム部|デジタル部|課|室|グループ|チーム|センター|局|本部|事務局|Division|Dept\.|Department)').hasMatch(line) && line.length <= 40) {
        if (department.isEmpty) { department = line; lineFields[i] = 'department1'; }
        else if (department.isNotEmpty) { lineFields[i] = 'department2'; }
        continue;
      }

      // 役職（長・マネージャー等）
      if (RegExp(r'(?:代表取締役|取締役|執行役員|常務|専務|部長|課長|係長|主任|リーダー|マネージャー|ディレクター|エグゼクティブ|社長|会長|副社長|副会長|理事長|理事|監事|幹事|教授|准教授|助教|講師|研究員|Chairman|Director|Manager|Executive|President|Officer|Fellow|Engineer|Architect)').hasMatch(line) && line.length <= 30) {
        if (title.isEmpty) { title = line; lineFields[i] = 'title1'; }
        continue;
      }

      // ひらがな行→よみがな候補
      if (RegExp(r'^[ぁ-ん\s　ー]+$').hasMatch(line) && line.length <= 20) {
        kanaCandidate.add(line.replaceAll(RegExp(r'[\s　]'), ''));
        lineFields[i] = 'nameKana'; continue;
      }

      // カタカナ行→よみがな候補
      if (RegExp(r'^[ァ-ヶー\s　]+$').hasMatch(line) && line.length <= 20) {
        kanaCandidate.add(_katakanaToHiragana(line.replaceAll(RegExp(r'[\s　]'), '')));
        lineFields[i] = 'nameKana'; continue;
      }
    }

    // ============================================================
    // 【2パス目】1パス目で未割り当ての行から氏名・よみがなを判定
    // ============================================================
    for (int i = 0; i < lines.length; i++) {
      if (lineFields.containsKey(i)) continue; // 1パス目で判定済み
      final raw = lines[i].trim();
      if (raw.isEmpty) continue;
      final line = _applyPrefixFilter(raw);
      final noSpace = line.replaceAll(RegExp(r'[\s　]'), '');

      // ローマ字2単語→よみがな候補（名刺に英語名が記載されている場合）
      if (RegExp(r'^[A-Za-z\s]+$').hasMatch(line) && line.length <= 25) {
        final words = line.trim().split(RegExp(r'\s+'));
        if (words.length == 2) {
          final kana = _reverseRomajiName(line);
          if (kana.isNotEmpty) { kanaCandidate.add(kana); lineFields[i] = 'nameKana'; }
        }
        continue;
      }

      // 氏名（漢字2〜6文字）
      // company_dictに含まれる会社名は氏名候補から除外
      if (companyNames.contains(noSpace) || companyNames.contains(line)) {
        lineFields[i] = 'skip'; continue;
      }
      if (name.isEmpty) {
        // パターンA: 漢字のみ2〜6文字（字間スペース除去後）
        if (RegExp(r'^[一-鿿々]{2,6}$').hasMatch(noSpace) && line.length <= 15) {
          name = noSpace; lineFields[i] = 'name'; continue;
        }
        // パターンB: 姓名スペース区切り（例：山田 太郎、熊 井 秀 樹）
        if (RegExp(r'^[一-鿿々]{1,4}[\s　]+[一-鿿々]{1,4}$').hasMatch(line) ||
            RegExp(r'^[一-鿿々][\s　][一-鿿々][\s　][一-鿿々][\s　][一-鿿々]$').hasMatch(line)) {
          name = noSpace; lineFields[i] = 'name'; continue;
        }
        // パターンC: 漢字＋ローマ字（例：熊井秀樹 Hideki Kumai）
        if (RegExp(r'^[一-鿿々]{1,4}[\s　]+[一-鿿々]{1,4}[\s　]+[A-Za-z]').hasMatch(line)) {
          final kanjiPart = line.split(RegExp(r'[A-Za-z]'))[0].trim();
          name = kanjiPart.replaceAll(RegExp(r'[\s　]'), '');
          lineFields[i] = 'name'; continue;
        }
      }
      // 未判定行はスキップ
      lineFields[i] = 'skip';
    }

    // 行ごとの判定結果を保存
    lastLineFields = lineFields;

    // よみがな類推処理
    if (nameKana.isEmpty && kanaCandidate.isNotEmpty) {
      nameKana = kanaCandidate.first;
    }
    if (nameKana.isEmpty && email.isNotEmpty && name.isNotEmpty) {
      final emailLocal = email.split('@').first.toLowerCase();
      final parts = emailLocal.split(RegExp(r'[._\-]'));
      if (parts.length >= 2) {
        final kana = _romajiToHiragana(parts.take(2).join(''));
        if (kana.isNotEmpty) nameKana = kana;
      }
    }

    return {
      'name': name, 'nameKana': nameKana, 'company': company,
      'department': department, 'title': title,
      'email': email, 'phone': phone, 'mobilePhone': mobilePhone,
      'fax': fax, 'zipCode': zipCode, 'address': address,
    };
  }
}