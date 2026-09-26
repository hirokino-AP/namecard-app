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
import 'package:flutter/services.dart';
import 'settings_service.dart';

class OcrService {
  // OCR後の生テキスト行リスト（OcrReviewScreenで参照）
  static List<String> lastLines = [];
  // 会社辞書（氏名誤判定防止用）→OCR前にセットする
  static List<String> companyNames = [];
  // ローマ字単語のY座標（bounding boxから取得）→名姓判定用
  static Map<String, double> _romajiPositions = {};
  // 市外局番パターン（郵便番号との誤認識防止）
  static final _areaCodePattern = RegExp(
    r'^0(?:'
    r'3|6|'                           // 東京・大阪（2桁）
    r'11|19|22|23|24|25|26|27|28|29|' // 北海道・東北
    r'42|43|44|45|46|47|48|49|'       // 関東
    r'52|53|54|55|56|57|58|59|'       // 中部
    r'72|73|74|75|76|77|78|79|'       // 近畿
    r'82|83|84|85|86|87|88|89|'       // 中国・四国
    r'92|93|94|95|96|97|98|99'        // 九州・沖縄
    r')'
  );

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

      // Vision API呼び出し（DOCUMENT_TEXT_DETECTION：bounding box付き）
      final response = await http.post(
        Uri.parse('\${_endpoint}?key=\${_apiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requests': [{
            'image': {'content': base64Image},
            'features': [{'type': 'DOCUMENT_TEXT_DETECTION', 'maxResults': 1}],
            'imageContext': {'languageHints': ['ja', 'en']}, // 日本語・英語優先
          }]
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Status: \${response.statusCode}\nBody: \${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}");
      }

      // レスポンスからテキストとbounding box取得
      final data = jsonDecode(response.body);
      
      // DOCUMENT_TEXT_DETECTIONはfullTextAnnotationを使用
      final fullTextAnnotation = data['responses']?[0]?['fullTextAnnotation'];
      if (fullTextAnnotation == null) throw Exception("fullTextAnnotation empty");
      
      final fullText = fullTextAnnotation['text'] as String? ?? '';
      final lines = fullText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      
      // bounding boxからローマ字行の位置を取得（名姓判定用）
      // pages→blocks→paragraphs→words の順で解析
      final romajiPositions = <String, double>{}; // テキスト→Y座標
      try {
        final pages = fullTextAnnotation['pages'] as List? ?? [];
        for (final page in pages) {
          final blocks = page['blocks'] as List? ?? [];
          for (final block in blocks) {
            final paragraphs = block['paragraphs'] as List? ?? [];
            for (final para in paragraphs) {
              final words = para['words'] as List? ?? [];
              for (final word in words) {
                // 各単語のY座標（上端）を取得
                final vertices = word['boundingBox']?['vertices'] as List?;
                if (vertices != null && vertices.isNotEmpty) {
                  final y = (vertices[0]['y'] as num?)?.toDouble() ?? 0;
                  final symbols = word['symbols'] as List? ?? [];
                  final wordText = symbols.map((s) => s['text'] as String? ?? '').join();
                  if (RegExp(r'^[A-Za-z]+\$').hasMatch(wordText)) {
                    romajiPositions[wordText] = y;
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        // bounding box取得失敗→テキストのみで継続（影響なし）
        OcrService._romajiPositions = {};
      }
      
      // ローマ字の位置情報をOcrServiceに保存（_parseLinesで参照）
      OcrService._romajiPositions = romajiPositions;

      // 生テキスト行を保存（OcrReviewScreenで使用）
      // 郵便番号+住所を分離した行リストを確認画面・パース両方に使用
      final splitLines = _splitZipAndAddress(lines);
      // 確認画面表示用にプレフィックスを除去（設定値を使用）
      final prefixes = await SettingsService.getOcrPrefixList();
      lastLines = splitLines.map((line) => _cleanLineForDisplay(line, prefixes: prefixes)).toList();

      // company_dictから会社名リストを取得（氏名誤判定防止）
      // ※DBアクセスは非同期なので静的メソッドでは難しいため
      // OcrService.companyNamesを事前にセットする方式を使用
      final parsed = _parseLines(splitLines, prefixes: prefixes, companyNames: OcrService.companyNames);

      // よみがなが取得できなかった場合はApple NLFrameworkで補完
      if (parsed['nameKana']!.isEmpty && parsed['name']!.isNotEmpty) {
        final yomigana = await _convertToYomigana(parsed['name']!);
        if (yomigana.isNotEmpty) {
          parsed['nameKana'] = yomigana;
        }
      }

      return parsed;
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
      // ハイフン1個・頭3桁・後4桁・計7桁のみ郵便番号として認識
      final lineNorm = line.replaceAll('－', '-');
      final zipMatch = RegExp(r'(?<![\d])[〒ａ]?(\d{3})-(\d{4})(?![\d\-])').firstMatch(lineNorm);
      if (zipMatch != null && RegExp(r'[都道府県市区町村]').hasMatch(line)) {
        final zip = zipMatch.group(1)! + '-' + zipMatch.group(2)!;
        final address = line.replaceAll(RegExp(r'[〒ａ]?\d{3}[-－]\d{4}\s*'), '').trim();
        result.add(zip);
        if (address.isNotEmpty) result.add(address);
      } else {
        result.add(line);
      }
    }
    return result;
  }


  // Apple NLFrameworkで漢字→よみがな変換
  static const _channel = MethodChannel('com.hirokino.namecardapp/document_picker');
  
  static Future<String> _convertToYomigana(String text) async {
    if (text.isEmpty) return '';
    try {
      final result = await _channel.invokeMethod<String>('convertToYomigana', text);
      return result ?? '';
    } catch (e) {
      return '';
    }
  }

  // 全角数字・記号→半角変換（電話番号・郵便番号の前処理）
  static String _normalizeNumbers(String text) {
    return text
      .replaceAllMapped(RegExp(r'[０-９]'), (m) =>
        String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFF10 + 0x30))
      .replaceAll('－', '-')
      .replaceAll('ー', '-')
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('　', ' '); // 全角スペース→半角
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
  // bounding boxのY座標を使って名前行を特定し、名姓順を判定
  // 例：Ryuichi Yorimoto → よりもとりゅういち（英語式：名 姓 → 日本式：姓 名）
  // 例：Kinoshita, Hiroshi → きのしたひろし（カンマ区切りは姓名順）
  static String _reverseRomajiName(String romaji) {
    String normalized = romaji.trim();
    
    // カンマ区切り対応（Kinoshita, Hiroshi）→ 既に姓→名の順
    if (normalized.contains(',')) {
      final parts = normalized.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      return _romajiToHiragana(parts.join('').toLowerCase());
    }

    // スペース区切り
    final parts = normalized.split(RegExp(r'[\s　]+')).where((s) => s.isNotEmpty).toList();
    if (parts.length < 2) return '';

    // イニシャルのみの部分を除外（例：H. Kinoshita → スキップ）
    if (parts.any((p) => RegExp(r'^[A-Za-z]\.$').hasMatch(p))) return '';

    // bounding boxのY座標で名姓順を判定
    // 名刺上部にある単語が姓の可能性が高い（日本語名刺の場合）
    // ただし英語表記（名 姓）が多いため、基本は反転する
    // 全大文字の場合（YORIMOTO RYUICHI）も反転
    
    // 2単語：英語式（名 姓）→ 日本式（姓 名）に反転してひらがな化
    if (parts.length == 2) {
      // Y座標が取得できている場合、位置で姓名を判定
      final y0 = _romajiPositions[parts[0]];
      final y1 = _romajiPositions[parts[1]];
      if (y0 != null && y1 != null) {
        // 同じY座標（同一行）→ 英語式（名 姓）なので反転
        // 異なるY座標（別行）→ 別々の情報の可能性があるためスキップ
        if ((y0 - y1).abs() > 20) return '';
      }
      final reversed = [...parts.reversed].join('');
      return _romajiToHiragana(reversed.toLowerCase());
    }
    
    // 3単語以上：最後の単語が姓（英語式）として反転
    final lastName = parts.last;
    final firstName = parts.sublist(0, parts.length - 1).join('');
    return _romajiToHiragana((lastName + firstName).toLowerCase());
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
      final raw = _normalizeNumbers(lines[i].trim());
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

      // ① FAX単独行（最初に特定→番号を確定してから電話・〒と区別）
      if (RegExp(r'(?:FAX|Fax\.?|fax|ファックス|ファクス)[：:.\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:FAX|Fax\.?|fax|ファックス|ファクス)[：:.\s]*'), '').trim();
        final numMatch = RegExp(r'0\d[\d\s\-－]{8,14}').firstMatch(cleaned);
        if (numMatch != null && fax.isEmpty) {
          fax = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'fax'; continue;
        }
      }

      // ② TEL&FAX同一行（FAXと電話を同時に特定）
      if (RegExp(r'(?:TEL|Tel\.?|tel|電話)').hasMatch(line) && RegExp(r'(?:FAX|Fax\.?|fax)').hasMatch(line)) {
        final telMatch = RegExp(r'(?:TEL|Tel\.?|tel|電話)[：:.\s]*(0\d[\d\s\-－]{8,14})').firstMatch(line);
        final faxMatch = RegExp(r'(?:FAX|Fax\.?|fax)[：:.\s]*(0\d[\d\s\-－]{8,14})').firstMatch(line);
        if (telMatch != null) {
          final num = telMatch.group(1)!.replaceAll(RegExp(r'[^\d\-]'), '');
          if (RegExp(r'^0[678]0').hasMatch(num)) { if (mobilePhone.isEmpty) { mobilePhone = num; lineFields[i] = 'mobilePhone'; } }
          else if (RegExp(r'^050').hasMatch(num)) { if (phone.isEmpty) { phone = num; lineFields[i] = 'phone'; } }
          else { if (phone.isEmpty) { phone = num; lineFields[i] = 'phone'; } }
        }
        if (faxMatch != null && fax.isEmpty) { fax = faxMatch.group(1)!.replaceAll(RegExp(r'[^\d\-]'), ''); lineFields[i] = 'fax'; }
        continue;
      }

      // ③ TEL単独行（携帯・固定・IPを判別）
      if (RegExp(r'(?:TEL|Tel\.?|tel|電話)[：:.\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:TEL|Tel\.?|tel|電話)[：:.\s]*'), '').trim();
        final numMatch = RegExp(r'0\d[\d\s\-－]{8,14}').firstMatch(cleaned);
        if (numMatch != null) {
          final num = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          if (RegExp(r'^0[678]0').hasMatch(num)) { if (mobilePhone.isEmpty) { mobilePhone = num; lineFields[i] = 'mobilePhone'; } }
          else if (RegExp(r'^050').hasMatch(num)) { if (phone.isEmpty) { phone = num; lineFields[i] = 'phone'; } }
          else { if (phone.isEmpty) { phone = num; lineFields[i] = 'phone'; } }
          continue;
        }
      }

      // ④ 国際電話（+81）
      if (RegExp(r'\+81[\s\-]?[\(\d]').hasMatch(line)) {
        final intlMatch = RegExp(r'\+81[\s\-]?\(?([\d][\s\-()[\d]{6,14})').firstMatch(line);
        if (intlMatch != null) {
          final num = intlMatch.group(0)!.replaceAll(RegExp(r'[^\d]'), '').replaceFirst('81', '0');
          if (phone.isEmpty) { phone = num; lineFields[i] = 'phone'; }
          continue;
        }
      }

      // ⑤ 携帯プレフィックス（Mobile/携帯）
      if (RegExp(r'(?:Mobile|mobile|携帯)[.：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:Mobile|mobile|携帯)[.：:\s]*'), '').trim();
        final numMatch = RegExp(r'0[678]0[\s\-－]?\d{3,4}[\s\-－]?\d{4}').firstMatch(cleaned);
        if (numMatch != null && mobilePhone.isEmpty) {
          mobilePhone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'mobilePhone'; continue;
        }
      }

      // ⑥ 固定電話プレフィックス（Phone/Tel.）
      if (RegExp(r'(?:Phone|phone|Tel\.)[.：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:Phone|phone|Tel\.)[.：:\s]*'), '').trim();
        final numMatch = RegExp(r'0\d[\d\s\-－]{8,14}').firstMatch(cleaned);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'phone'; continue;
        }
      }

      // ⑦ 携帯電話（プレフィックスなし・ハイフン2個・11桁）
      if (RegExp(r'0[678]0[\s\-－]?\d{4}[\s\-－]?\d{4}').hasMatch(line)) {
        final numMatch = RegExp(r'0[678]0[\s\-－]?\d{4}[\s\-－]?\d{4}').firstMatch(line);
        if (numMatch != null && mobilePhone.isEmpty) {
          mobilePhone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'mobilePhone'; continue;
        }
      }

      // ⑧ IP電話050（プレフィックスなし・ハイフン2個・11桁）
      if (RegExp(r'050[-－]\d{4}[-－]\d{4}').hasMatch(line)) {
        final numMatch = RegExp(r'050[-－]\d{4}[-－]\d{4}').firstMatch(line);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'phone'; continue;
        }
      }

      // ⑨ 固定電話（プレフィックスなし・10桁・ハイフンあり/なし両対応）
      // 同一行に2つ番号がある場合：1つ目→TEL、2つ目→FAX
      if (RegExp(r'0\d{1,3}[\s\-－]?\d{2,4}[\s\-－]?\d{4}').hasMatch(line)) {
        final allMatches = RegExp(r'0\d{1,3}[\s\-－]?\d{2,4}[\s\-－]?\d{4}')
            .allMatches(line).toList();
        if (allMatches.isNotEmpty) {
          final num1 = allMatches[0].group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          // 市外局番チェック（郵便番号との誤認識防止）
          final digits1 = num1.replaceAll('-', '');
          if (_areaCodePattern.hasMatch(digits1.substring(0, digits1.length > 4 ? 4 : digits1.length))) {
            if (phone.isEmpty) { phone = num1; lineFields[i] = 'phone'; }
          } else if (phone.isEmpty) {
            phone = num1; lineFields[i] = 'phone';
          }
          // 2つ目の番号→FAX
          if (allMatches.length >= 2) {
            final num2 = allMatches[1].group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
            if (fax.isEmpty) { fax = num2; lineFields[i] = 'fax'; }
          }
          continue;
        }
      }

      // ⑩ 郵便番号（FAX・電話確定後に判定・ハイフン1個・頭3桁・後4桁・計7桁のみ）
      final zipLineNorm = line.replaceAll('－', '-');
      final zipOnlyMatch = RegExp(r'(?<![\d])[〒ａ]?(\d{3})-(\d{4})(?![\d\-])').firstMatch(zipLineNorm);
      if (zipOnlyMatch != null) {
        final zipCandidate = zipOnlyMatch.group(1)! + '-' + zipOnlyMatch.group(2)!;
        // 市外局番パターンに一致する場合は郵便番号ではなく電話番号として扱う
        final fullNum = zipOnlyMatch.group(1)! + zipOnlyMatch.group(2)!;
        if (_areaCodePattern.hasMatch('0' + fullNum)) {
          // 電話番号として処理（プレフィックスなし固定電話）
          if (phone.isEmpty) { phone = zipCandidate; lineFields[i] = 'phone'; }
          continue;
        }
        zipCode = zipCandidate;
        lineFields[i] = 'zipCode';
        final afterZip = line.replaceAll(RegExp(r'[〒ａ]?\d{3}[-－]\d{4}'), '').trim();
        if (afterZip.isNotEmpty && RegExp(r'[都道府県市区町村]').hasMatch(afterZip) && address.isEmpty) {
          address = afterZip;
        }
        continue;
      }

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

      // 会社名（企業形態マーカーが前後に付いているもののみ会社名として認識）
      // 例：「富士フイルム株式会社」→✅ 「東芝」→❌（マーカーなし）
      final _companyMarker = RegExp(
        r'(?:株式会社|有限会社|合同会社|合資会社|合名会社|一般社団法人|公益社団法人|一般財団法人|公益財団法人|特定非営利活動法人|社会福祉法人|医療法人|学校法人|宗教法人|独立行政法人|国立大学法人|地方独立行政法人)'
        r'|(?:省|庁|機構|協会|組合|連合会|連盟|財団|大学院|大学|高等学校|中学校|小学校)'
        r'|(?:University|Corporation|Corp\.|Inc\.|Ltd\.|Co\.,? ?Ltd\.)'
      );
      // 前後どちらかにマーカーがある場合のみ会社名として認識
      final _markerAtStart = RegExp(r'^(?:株式会社|有限会社|合同会社|合資会社|合名会社|一般社団法人|公益社団法人|一般財団法人|公益財団法人|特定非営利活動法人|社会福祉法人|医療法人|学校法人|宗教法人|独立行政法人|国立大学法人)');
      final _markerAtEnd = RegExp(r'(?:株式会社|有限会社|合同会社|合資会社|合名会社|省|庁|機構|協会|組合|連合会|連盟|財団|大学院|大学|高等学校|中学校|小学校|Corporation|Corp\.|Inc\.|Ltd\.|Co\.,? ?Ltd\.)$');
      if (_companyMarker.hasMatch(line) && 
          (_markerAtStart.hasMatch(line) || _markerAtEnd.hasMatch(line))) {
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
      final raw = _normalizeNumbers(lines[i].trim());
      if (raw.isEmpty) continue;
      final line = _applyPrefixFilter(raw);
      final noSpace = line.replaceAll(RegExp(r'[\s　]'), '');

      // ローマ字→よみがな候補（名刺に英語名が記載されている場合）
      if (RegExp(r'^[A-Za-z\s]+\$').hasMatch(line) && line.length <= 25) {
        final words = line.trim().split(RegExp(r'\s+'));
        if (words.length == 2) {
          // 同一行に2単語（例：Ryuichi Yorimoto）
          final kana = _reverseRomajiName(line);
          if (kana.isNotEmpty) { kanaCandidate.add(kana); lineFields[i] = 'nameKana'; }
        } else if (words.length == 1) {
          // 1単語のみ（例：FUJIOKA）→次の行と連結を試みる
          if (i + 1 < lines.length) {
            final nextRaw = _normalizeNumbers(lines[i + 1].trim());
            final nextLine = _applyPrefixFilter(nextRaw);
            if (RegExp(r'^[A-Za-z\s]+\$').hasMatch(nextLine) && nextLine.length <= 15) {
              // 次行もローマ字→連結してよみがな変換（姓→名の順として処理）
              final combined = line.trim() + ' ' + nextLine.trim();
              final kana = _reverseRomajiName(combined);
              if (kana.isNotEmpty) {
                kanaCandidate.add(kana);
                lineFields[i] = 'nameKana';
                lineFields[i + 1] = 'nameKana'; // 次行もマーク
              }
            }
          }
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
    // ① まずkanaCandidateから候補を取得
    if (nameKana.isEmpty && kanaCandidate.isNotEmpty) {
      nameKana = kanaCandidate.first;
    }

    // ② メールアドレスから類推（姓名逆転対応）
    if (email.isNotEmpty) {
      final emailLocal = email.split('@').first.toLowerCase();
      final parts = emailLocal.split(RegExp(r'[._\-]'))
          .where((p) => p.isNotEmpty && p.length >= 2)
          .toList();

      if (parts.length >= 2) {
        // 姓名順（fujioka.masayoshi）→ ふじおかまさよし
        final kanaForward = _romajiToHiragana(parts.join(''));
        // 名姓順（masayoshi.fujioka）→ ふじおかまさよし（逆転）
        final kanaReversed = _romajiToHiragana(parts.reversed.join(''));

        // 既存のkanaCandidate と照合して一致度が高い方を採用
        if (nameKana.isEmpty) {
          // 候補なし→逆順（日本語名刺は名姓順が多い）を優先
          if (kanaReversed.isNotEmpty && kanaReversed.length >= 3) {
            nameKana = kanaReversed;
          } else if (kanaForward.isNotEmpty && kanaForward.length >= 3) {
            nameKana = kanaForward;
          }
        } else {
          // 既存候補あり→メール逆引き結果と比較して長い方（より完全な読み）を採用
          if (kanaReversed.length > nameKana.length && kanaReversed.isNotEmpty) {
            nameKana = kanaReversed;
          } else if (kanaForward.length > nameKana.length && kanaForward.isNotEmpty) {
            nameKana = kanaForward;
          }
        }
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