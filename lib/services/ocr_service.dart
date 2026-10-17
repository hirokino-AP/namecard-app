// ============================================================
// lib/services/ocr_service.dart
//
// 【役割】
//   OCRモジュールの統合エントリ。
//   各画面からはこのクラスのみをimportする。
//   実際のロジックは lib/services/ocr/ 配下に分割。
//
// 【モジュール構成】
//   ocr_config.dart       - APIキー・エンドポイント
//   ocr_api_client.dart   - Vision API通信（Google Cloud Vision）
//   ocr_vision_client.dart - 端末内OCR（Apple Vision・画像を外部送信しない）
//   ocr_normalizer.dart   - 前処理・正規化
//   ocr_name_parser.dart  - 氏名・よみがな判定
//   ocr_line_parser.dart  - 行振り分けロジック
// ============================================================

import 'dart:io';
import 'ocr/ocr_api_client.dart';
import 'ocr/ocr_vision_client.dart';
import 'ocr/ocr_normalizer.dart';
import 'ocr/ocr_name_parser.dart';
import 'ocr/ocr_line_parser.dart';
import 'settings_service.dart';

class OcrService {
  // OCR後の生テキスト行リスト（OcrReviewScreenで参照）
  static List<String> lastLines = [];
  // 会社辞書（氏名誤判定防止用）→OCR前にセットする
  static List<String> companyNames = [];
  // 行ごとの判定結果（OcrReviewScreenで参照）
  static Map<int, String> get lastLineFields => OcrLineParser.lastLineFields;

  // ============================================================
  // 名刺画像をOCRして各フィールドのMapを返す（メインエントリ）
  // ============================================================
  static Future<Map<String, String>> recognizeBusinessCard(File imageFile) async {
    try {
      // ① OCRエンジンを設定で切り替えてテキスト抽出
      final engine = await SettingsService.getOcrEngine();
      final lines = engine == SettingsService.ocrEngineDevice
          ? await OcrVisionClient.extractText(imageFile)
          : await OcrApiClient.extractText(imageFile);

      // ② 前処理（郵便番号+住所の分離）
      final splitLines = OcrNormalizer.splitZipAndAddress(lines);

      // ③ 確認画面表示用にプレフィックスを除去
      final prefixes = await SettingsService.getOcrPrefixList();
      lastLines = splitLines.map((line) =>
          OcrNormalizer.cleanLineForDisplay(line, prefixes: prefixes)).toList();

      // ④ 各行をフィールドに振り分け
      final parsed = OcrLineParser.parseLines(
          splitLines, prefixes: prefixes, companyNames: companyNames);

      // ⑤ よみがなが取得できなかった場合はApple NLFrameworkで補完
      if (parsed['nameKana']!.isEmpty && parsed['name']!.isNotEmpty) {
        final yomigana = await OcrNameParser.convertToYomigana(parsed['name']!);
        if (yomigana.isNotEmpty) {
          parsed['nameKana'] = yomigana;
        }
      }

      return parsed;
    } catch (e) {
      throw Exception("Vision API error: $e");
    }
  }
}
