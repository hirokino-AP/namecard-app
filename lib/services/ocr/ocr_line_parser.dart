// ============================================================
// lib/services/ocr/ocr_line_parser.dart
//
// 【役割】
//   OCRテキスト行リストを各フィールドに振り分ける。
//   電話・FAX・郵便番号・氏名・会社名等の判定ロジック。
//
// 【振り分け優先順位】（上から順に判定）
//   1. URL除外  2. メール  3. FAX単独行
//   4. TEL&FAX同一行  5. TEL単独行  6. 国際電話(+81)
//   7. 携帯プレフィックス  8. 固定電話プレフィックス
//   9. 携帯(090/080/070)  10. IP電話(050)
//   11. 固定電話  12. 郵便番号  13. 住所
//   14. 会社名  15. 部署名  16. 役職
//   17. ひらがな/カタカナ  18. ローマ字  19. 氏名
// ============================================================

import 'ocr_normalizer.dart';
import 'ocr_name_parser.dart';

class OcrLineParser {
  // 行ごとの判定結果を外部から参照できるように保持
  static Map<int, String> lastLineFields = {};

  static Map<String, String> parseLines(List<String> lines, {List<String> prefixes = const [], List<String> companyNames = const []}) {
    String name = '', nameKana = '', company = '', department = '', title = '';
    String email = '', phone = '', mobilePhone = '', fax = '', zipCode = '', address = '';
    final kanaCandidate = <String>[];
    final lineFields = <int, String>{};

    // プレフィックス除去処理
    String applyPrefixFilter(String line) {
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
      final line = applyPrefixFilter(raw);

      // URL除外
      if (RegExp(r'https?://|www\.').hasMatch(line)) { lineFields[i] = 'skip'; continue; }

      // メール（@マーク）
      final emailMatch = RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}').firstMatch(line);
      if (emailMatch != null) {
        if (email.isEmpty) { email = emailMatch.group(0)!; lineFields[i] = 'email'; }
        continue;
      }

      // ① FAX単独行
      if (RegExp(r'(?:FAX|Fax\.?|fax|ファックス|ファクス)[：:.\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:FAX|Fax\.?|fax|ファックス|ファクス)[：:.\s]*'), '').trim();
        final numMatch = RegExp(r'0\d[\d\-]{8,12}').firstMatch(cleaned);
        if (numMatch != null && fax.isEmpty) {
          fax = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'fax'; continue;
        }
      }

      // ② TEL&FAX同一行
      if (RegExp(r'(?:TEL|Tel\.?|tel|電話)').hasMatch(line) && RegExp(r'(?:FAX|Fax\.?|fax)').hasMatch(line)) {
        final telMatch = RegExp(r'(?:TEL|Tel\.?|tel|電話)[：:.\s]*([0-9０-９\-－()（）+]+)').firstMatch(line);
        final faxMatch = RegExp(r'(?:FAX|Fax\.?|fax)[：:.\s]*([0-9０-９\-－()（）+]+)').firstMatch(line);
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
        final numMatch = RegExp(r'0\d[\d\-－]{8,12}').firstMatch(cleaned);
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
        final numMatch = RegExp(r'0[678]0[\d\-]{8,9}').firstMatch(cleaned);
        if (numMatch != null && mobilePhone.isEmpty) {
          mobilePhone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'mobilePhone'; continue;
        }
      }

      // ⑥ 固定電話プレフィックス（Phone/Tel.）
      if (RegExp(r'(?:Phone|phone|Tel\.)[.：:\s]*').hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'(?:Phone|phone|Tel\.)[.：:\s]*'), '').trim();
        final numMatch = RegExp(r'0\d[\d\-]{8,12}').firstMatch(cleaned);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'phone'; continue;
        }
      }

      // ⑦ 携帯電話（プレフィックスなし・11桁）
      if (RegExp(r'0[678]0[-－]\d{4}[-－]\d{4}').hasMatch(line)) {
        final numMatch = RegExp(r'0[678]0[-－]\d{4}[-－]\d{4}').firstMatch(line);
        if (numMatch != null && mobilePhone.isEmpty) {
          mobilePhone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'mobilePhone'; continue;
        }
      }

      // ⑧ IP電話050（プレフィックスなし・11桁）
      if (RegExp(r'050[-－]\d{4}[-－]\d{4}').hasMatch(line)) {
        final numMatch = RegExp(r'050[-－]\d{4}[-－]\d{4}').firstMatch(line);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'phone'; continue;
        }
      }

      // ⑨ 固定電話（プレフィックスなし・10桁）
      if (RegExp(r'0\d{1,3}[-－]\d{2,4}[-－]\d{4}').hasMatch(line)) {
        final numMatch = RegExp(r'0\d{1,3}[-－]\d{2,4}[-－]\d{4}').firstMatch(line);
        if (numMatch != null && phone.isEmpty) {
          phone = numMatch.group(0)!.replaceAll(RegExp(r'[^\d\-]'), '');
          lineFields[i] = 'phone'; continue;
        }
      }

      // ⑩ 郵便番号（FAX・電話確定後に判定）
      final zipLineNorm = line.replaceAll('－', '-');
      final zipOnlyMatch = RegExp(r'(?<![\d])[〒ａ]?(\d{3})-(\d{4})(?![\d\-])').firstMatch(zipLineNorm);
      if (zipOnlyMatch != null) {
        zipCode = zipOnlyMatch.group(1)! + '-' + zipOnlyMatch.group(2)!;
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

      // 会社名（企業形態マーカーが前後に付いているもののみ）
      final companyMarker = RegExp(
        r'(?:株式会社|有限会社|合同会社|合資会社|合名会社|一般社団法人|公益社団法人|一般財団法人|公益財団法人|特定非営利活動法人|社会福祉法人|医療法人|学校法人|宗教法人|独立行政法人|国立大学法人|地方独立行政法人)'
        r'|(?:省|庁|機構|協会|組合|連合会|連盟|財団|大学院|大学|高等学校|中学校|小学校)'
        r'|(?:University|Corporation|Corp\.|Inc\.|Ltd\.|Co\.,? ?Ltd\.)'
      );
      final markerAtStart = RegExp(r'^(?:株式会社|有限会社|合同会社|合資会社|合名会社|一般社団法人|公益社団法人|一般財団法人|公益財団法人|特定非営利活動法人|社会福祉法人|医療法人|学校法人|宗教法人|独立行政法人|国立大学法人)');
      final markerAtEnd = RegExp(r'(?:株式会社|有限会社|合同会社|合資会社|合名会社|省|庁|機構|協会|組合|連合会|連盟|財団|大学院|大学|高等学校|中学校|小学校|Corporation|Corp\.|Inc\.|Ltd\.|Co\.,? ?Ltd\.)$');
      if (companyMarker.hasMatch(line) &&
          (markerAtStart.hasMatch(line) || markerAtEnd.hasMatch(line))) {
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
        kanaCandidate.add(OcrNormalizer.katakanaToHiragana(line.replaceAll(RegExp(r'[\s　]'), '')));
        lineFields[i] = 'nameKana'; continue;
      }
    }

    // ============================================================
    // 【2パス目】1パス目で未割り当ての行から氏名・よみがなを判定
    // ============================================================
    for (int i = 0; i < lines.length; i++) {
      if (lineFields.containsKey(i)) continue;
      final raw = lines[i].trim();
      if (raw.isEmpty) continue;
      final line = applyPrefixFilter(raw);
      final noSpace = line.replaceAll(RegExp(r'[\s　]'), '');

      // ローマ字2単語→よみがな候補
      if (RegExp(r'^[A-Za-z\s]+$').hasMatch(line) && line.length <= 25) {
        final words = line.trim().split(RegExp(r'\s+'));
        if (words.length == 2) {
          final kana = OcrNameParser.reverseRomajiName(line);
          if (kana.isNotEmpty) { kanaCandidate.add(kana); lineFields[i] = 'nameKana'; }
        }
        continue;
      }

      // 氏名（漢字2〜6文字）
      if (companyNames.contains(noSpace) || companyNames.contains(line)) {
        lineFields[i] = 'skip'; continue;
      }
      if (name.isEmpty) {
        if (RegExp(r'^[一-鿿々]{2,6}$').hasMatch(noSpace) && line.length <= 15) {
          name = noSpace; lineFields[i] = 'name'; continue;
        }
        if (RegExp(r'^[一-鿿々]{1,4}[\s　]+[一-鿿々]{1,4}$').hasMatch(line) ||
            RegExp(r'^[一-鿿々][\s　][一-鿿々][\s　][一-鿿々][\s　][一-鿿々]$').hasMatch(line)) {
          name = noSpace; lineFields[i] = 'name'; continue;
        }
        if (RegExp(r'^[一-鿿々]{1,4}[\s　]+[一-鿿々]{1,4}[\s　]+[A-Za-z]').hasMatch(line)) {
          final kanjiPart = line.split(RegExp(r'[A-Za-z]'))[0].trim();
          name = kanjiPart.replaceAll(RegExp(r'[\s　]'), '');
          lineFields[i] = 'name'; continue;
        }
      }
      lineFields[i] = 'skip';
    }

    // 行ごとの判定結果を保存
    lastLineFields = lineFields;

    // よみがな類推処理
    if (nameKana.isEmpty && kanaCandidate.isNotEmpty) {
      nameKana = kanaCandidate.first;
    }
    // メールアドレスから類推
    if (nameKana.isEmpty && email.isNotEmpty && name.isNotEmpty) {
      final emailLocal = email.split('@').first.toLowerCase();
      final parts = emailLocal.split(RegExp(r'[._\-]'))
          .where((p) => p.isNotEmpty && p.length >= 2)
          .toList();

      if (parts.isNotEmpty) {
        for (int take = parts.length; take >= 1; take--) {
          final romaji = parts.take(take).join('');
          final kana = OcrNameParser.romajiToHiragana(romaji);
          if (kana.isNotEmpty && kana.length >= 3) {
            nameKana = kana;
            break;
          }
        }

        if (nameKana.isEmpty && parts.length >= 2) {
          final reversedRomaji = parts.reversed.take(2).join('');
          final kana = OcrNameParser.romajiToHiragana(reversedRomaji);
          if (kana.isNotEmpty && kana.length >= 3) nameKana = kana;
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
