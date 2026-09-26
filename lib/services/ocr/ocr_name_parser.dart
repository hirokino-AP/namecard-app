// ============================================================
// lib/services/ocr/ocr_name_parser.dart
//
// 【役割】
//   氏名・よみがなの判定・変換を行う。
//   - Apple NLFrameworkでの漢字→よみがな変換
//   - ローマ字→ひらがな変換（ヘボン式・訓令式対応）
//   - ローマ字の姓名反転（英語式→日本式）
// ============================================================

import 'package:flutter/services.dart';
import 'ocr_normalizer.dart';

class OcrNameParser {
  // Apple NLFrameworkで漢字→よみがな変換
  static const _channel = MethodChannel('com.hirokino.namecardapp/document_picker');

  static Future<String> convertToYomigana(String text) async {
    if (text.isEmpty) return '';
    try {
      final result = await _channel.invokeMethod<String>('convertToYomigana', text);
      return result ?? '';
    } catch (e) {
      return '';
    }
  }

  // ローマ字の姓名を反転（英語式→日本式）
  // 例：Ryuichi Yorimoto → よりもとりゅういち
  // 例：KINOSHITA HIROSHI → きのしたひろし
  // 例：Kinoshita, Hiroshi → きのしたひろし
  static String reverseRomajiName(String romaji) {
    String normalized = romaji.trim();
    if (normalized.contains(',')) {
      final parts = normalized.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      return romajiToHiragana(parts.join('').toLowerCase());
    }

    final parts = normalized.split(RegExp(r'[\s　]+')).where((s) => s.isNotEmpty).toList();
    if (parts.length < 2) return '';

    if (parts.any((p) => RegExp(r'^[A-Za-z]\.$').hasMatch(p))) return '';

    final reversed = [...parts.reversed].join('');
    return romajiToHiragana(reversed.toLowerCase());
  }

  // ローマ字→ひらがな変換（ヘボン式・訓令式対応）
  static String romajiToHiragana(String romaji) {
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
    final keys = map.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      result = result.replaceAll(key, map[key]!);
    }
    if (RegExp(r'[a-z]').hasMatch(result)) return '';
    return result;
  }
}
