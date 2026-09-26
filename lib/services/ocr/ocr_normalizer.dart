// ============================================================
// lib/services/ocr/ocr_normalizer.dart
//
// 【役割】
//   OCRテキストの前処理・正規化を行う。
//   - プレフィックス除去（確認画面表示用）
//   - 郵便番号＋住所の分離
//   - カタカナ→ひらがな変換
// ============================================================

class OcrNormalizer {
  // 確認画面表示用：プレフィックスを除去してクリーンな表示にする
  static String cleanLineForDisplay(String line, {List<String> prefixes = const []}) {
    String cleaned = line;
    for (final prefix in prefixes) {
      if (prefix.isEmpty) continue;
      cleaned = cleaned.replaceAll(
        RegExp('${RegExp.escape(prefix)}[：:.\s]*', caseSensitive: false),
        '',
      );
    }
    return cleaned.trim().isEmpty ? line : cleaned.trim();
  }

  // OCR行リストの前処理：郵便番号+住所を分離して2行に分割
  static List<String> splitZipAndAddress(List<String> lines) {
    final result = <String>[];
    for (final line in lines) {
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

  // カタカナ→ひらがな変換
  static String katakanaToHiragana(String katakana) {
    return katakana.split('').map((c) {
      final code = c.codeUnitAt(0);
      if (code >= 0x30A1 && code <= 0x30F6) {
        return String.fromCharCode(code - 0x60);
      }
      return c;
    }).join('');
  }
}
