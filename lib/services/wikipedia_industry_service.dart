// ============================================================
// lib/services/wikipedia_industry_service.dart
//
// 【役割】
//   会社名でWikipedia APIを検索して業種を自動判定する。
//   OCR確認画面表示中にバックグラウンドで実行。
//
// 【処理フロー】
//   1. 会社名でWikipedia検索APIを呼び出す
//   2. 取得したページの概要テキストから業種キーワードを検索
//   3. マッチした業種を返す
//   4. マッチしない場合は既存のキーワードマッチで補完
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;

class WikipediaIndustryService {
  static const _endpoint = 'https://ja.wikipedia.org/api/rest_v1/page/summary/';
  static const _searchEndpoint = 'https://ja.wikipedia.org/w/api.php';

  // 業種キーワードマップ（Wikipedia本文から業種を判定）
  static const Map<String, List<String>> _industryKeywords = {
    'IT・情報通信': ['情報技術','ソフトウェア','システム','IT企業','情報通信','クラウド','半導体','インターネット'],
    '製造・メーカー': ['製造業','メーカー','工業','製造','生産'],
    '金融・銀行・証券': ['銀行','証券','金融','投資','信託','ファンド'],
    '保険': ['保険','生命保険','損害保険','共済'],
    '不動産・建設': ['不動産','建設','住宅','マンション','建築'],
    '商社・卸売': ['商社','卸売','貿易','物産'],
    '小売・流通': ['小売','スーパー','コンビニ','百貨店','流通'],
    '医療・製薬': ['医療','製薬','病院','薬品','医薬'],
    '教育・学術・研究': ['大学','学校','教育','研究','学術'],
    '官公庁・自治体': ['省','庁','市','区','町','村','政府','自治体'],
    '法律・会計・コンサル': ['法律','弁護士','会計','コンサル','監査'],
    '広告・マーケティング': ['広告','マーケティング','PR','プロモーション'],
    'メディア・出版・放送': ['出版','放送','テレビ','新聞','メディア'],
    '運輸・物流': ['運輸','物流','輸送','航空','鉄道','海運'],
    'エネルギー・電力・ガス': ['電力','エネルギー','ガス','石油','電気'],
    '食品・飲料': ['食品','飲料','食料','農産','水産'],
    '化学・素材': ['化学','素材','樹脂','ガラス','繊維'],
    '電機・電子': ['電機','電子','電器','エレクトロニクス'],
    '自動車・輸送機器': ['自動車','自動車メーカー','輸送機器'],
    '機械・重工業': ['機械','重工業','鉄鋼','造船'],
    '観光・ホテル・旅行': ['ホテル','旅館','観光','旅行'],
    '外食・フードサービス': ['飲食','レストラン','外食'],
    '医療機器・ヘルスケア': ['医療機器','ヘルスケア','医工'],
    '人材・採用': ['人材','派遣','採用','人材サービス'],
    'NPO・団体・協会': ['NPO','NGO','協会','財団','社団'],
  };

  // Wikipedia APIで業種を検索（バックグラウンド実行用）
  static Future<String> detectFromWikipedia(String companyName) async {
    if (companyName.isEmpty) return '';

    try {
      // 会社名を検索
      final searchUrl = Uri.parse(_searchEndpoint).replace(queryParameters: {
        'action': 'query',
        'list': 'search',
        'srsearch': companyName,
        'srlimit': '1',
        'format': 'json',
        'utf8': '1',
      });

      final searchResponse = await http.get(searchUrl)
          .timeout(const Duration(seconds: 5));

      if (searchResponse.statusCode != 200) return '';

      final searchData = jsonDecode(searchResponse.body);
      final searchResults = searchData['query']?['search'] as List?;
      if (searchResults == null || searchResults.isEmpty) return '';

      // 最初のヒットのページタイトルを取得
      final pageTitle = searchResults[0]['title'] as String;

      // ページの概要を取得
      final summaryUrl = Uri.parse('$_endpoint${Uri.encodeComponent(pageTitle)}');
      final summaryResponse = await http.get(summaryUrl)
          .timeout(const Duration(seconds: 5));

      if (summaryResponse.statusCode != 200) return '';

      final summaryData = jsonDecode(summaryResponse.body);
      final extract = summaryData['extract'] as String? ?? '';

      if (extract.isEmpty) return '';

      // 業種キーワードマッチング
      for (final entry in _industryKeywords.entries) {
        for (final keyword in entry.value) {
          if (extract.contains(keyword)) {
            return entry.key;
          }
        }
      }

      return '';
    } catch (e) {
      return '';
    }
  }
}
