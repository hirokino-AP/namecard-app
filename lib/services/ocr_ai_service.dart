// ============================================================
// lib/services/ocr_ai_service.dart
//
// 【役割】
//   OCR振り分けAIの抽象インターフェース。
//   将来的により高精度なAIに差し替える場合は：
//   1. OcrAiServiceを継承した新クラスを作成
//   2. OcrAiService.instance = 新クラス() に変更するだけでOK
//
// 【現在の実装】
//   RuleBasedOcrAiService：ルールベース＋Wikipedia API
// ============================================================

import 'industry_service.dart';
import 'wikipedia_industry_service.dart';

abstract class OcrAiService {
  // 現在使用するAIサービスのインスタンス（差し替えポイント）
  static OcrAiService instance = RuleBasedOcrAiService();

  // 会社名から業種を判定する
  Future<String> detectIndustry(String company, String department);

  // よみがなを類推する
  Future<String> inferNameKana(String name, String company, String email);
}

// ルールベース＋Wikipedia実装（現在の実装）
class RuleBasedOcrAiService extends OcrAiService {

  @override
  Future<String> detectIndustry(String company, String department) async {
    final detected = IndustryService.detect(company, department);
    if (detected != 'その他') return detected;
    return await WikipediaIndustryService.detectFromWikipedia(company);
  }

  @override
  Future<String> inferNameKana(String name, String company, String email) async {
    if (email.isNotEmpty && name.isNotEmpty) {
      final emailLocal = email.split('@').first.toLowerCase();
      final parts = emailLocal.split(RegExp(r'[._\-]'));
      if (parts.length >= 2) {
        final romaji = parts.take(2).join('');
        final kana = _romajiToHiragana(romaji);
        if (kana.isNotEmpty) return kana;
      }
    }
    return '';
  }

  String _romajiToHiragana(String romaji) {
    final map = {
      'sha':'しゃ','shi':'し','shu':'しゅ','sho':'しょ',
      'chi':'ち','tsu':'つ','cha':'ちゃ','chu':'ちゅ','cho':'ちょ',
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
      'wa':'わ','wo':'を',
      'ga':'が','gi':'ぎ','gu':'ぐ','ge':'げ','go':'ご',
      'za':'ざ','zi':'じ','zu':'ず','ze':'ぜ','zo':'ぞ',
      'da':'だ','di':'ぢ','du':'づ','de':'で','do':'ど',
      'ba':'ば','bi':'び','bu':'ぶ','be':'べ','bo':'ぼ',
      'pa':'ぱ','pi':'ぴ','pu':'ぷ','pe':'ぺ','po':'ぽ',
      'fa':'ふぁ','fu':'ふ',
      'a':'あ','i':'い','u':'う','e':'え','o':'お','n':'ん',
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
