// lib/screens/ocr_review_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DropdownButton, DropdownMenuItem;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../db/database_helper.dart';

enum OcrField {
  name('氏名'),
  nameKana('氏名よみがな'),
  company('会社名'),
  companyKana('会社名よみがな'),
  department('部署名'),
  phone('電話'),
  mobilePhone('携帯'),
  fax('FAX'),
  zipCode('郵便番号'),
  address('住所'),
  projectCodes('関連'),
  note('備考'),
  skip('スキップ');

  final String label;
  const OcrField(this.label);
}

class OcrReviewScreen extends StatefulWidget {
  final List<String> lines;
  final Map<String, String> autoResult;
  final String userId;

  const OcrReviewScreen({
    super.key,
    required this.lines,
    required this.autoResult,
    required this.userId,
  });

  @override
  State<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends State<OcrReviewScreen> {
  late List<OcrField> _assignments;
  List<String> _companyNames = [];
  // 会社名候補（行ごと）
  Map<int, List<String>> _companyCandidates = {};

  @override
  void initState() {
    super.initState();
    _assignments = widget.lines.map((line) => _guessField(line)).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCompanyNames());
  }

  Future<void> _loadCompanyNames() async {
    final uid = context.read<AuthProvider>().uid;
    final names = await context.read<CardProvider>().getAllCompanyNames(uid);
    setState(() {
      _companyNames = names;
      // 各行に対して類似会社名を検索
      for (int i = 0; i < widget.lines.length; i++) {
        final candidates = _findSimilarCompanies(widget.lines[i]);
        if (candidates.isNotEmpty) {
          _companyCandidates[i] = candidates;
        }
      }
    });
  }

  // 編集距離で類似会社名を検索
  int _editDistance(String a, String b) {
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (i) => List.filled(n + 1, 0));
    for (int i = 0; i <= m; i++) dp[i][0] = i;
    for (int j = 0; j <= n; j++) dp[0][j] = j;
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i-1] == b[j-1]) dp[i][j] = dp[i-1][j-1];
        else dp[i][j] = 1 + [dp[i-1][j], dp[i][j-1], dp[i-1][j-1]].reduce((a, b) => a < b ? a : b);
      }
    }
    return dp[m][n];
  }

  List<String> _findSimilarCompanies(String token) {
    if (token.isEmpty || _companyNames.isEmpty) return [];

    // ① 完全一致または部分一致を優先
    final exact = _companyNames.where((c) => c.contains(token) || token.contains(c)).toList();
    if (exact.isNotEmpty) return exact.take(3).toList();

    // ② 部分文字列マッチング強化（3文字以上の共通部分があればヒット）
    final partialMatch = <String>[];
    for (final c in _companyNames) {
      // tokenの3文字以上の部分文字列がcに含まれるか確認
      for (int len = token.length - 1; len >= 3; len--) {
        for (int start = 0; start <= token.length - len; start++) {
          final sub = token.substring(start, start + len);
          if (c.contains(sub)) {
            partialMatch.add(c);
            break;
          }
        }
        if (partialMatch.contains(c)) break;
      }
    }
    if (partialMatch.isNotEmpty) {
      // 共通部分が長いものを優先
      partialMatch.sort((a, b) => b.length.compareTo(a.length));
      return partialMatch.take(3).toList();
    }

    // ③ 編集距離で類似検索（閾値を少し緩める）
    final threshold = (token.length * 0.5).ceil().clamp(1, 5);
    final similar = _companyNames.where((c) => _editDistance(token, c) <= threshold).toList();
    similar.sort((a, b) => _editDistance(token, a).compareTo(_editDistance(token, b)));
    return similar.take(3).toList();
  }

  OcrField _guessField(String line) {
    final result = widget.autoResult;
    if (result['name'] == line) return OcrField.name;
    if (result['nameKana'] == line) return OcrField.nameKana;
    if (result['company'] == line) return OcrField.company;
    if (result['companyKana'] == line) return OcrField.companyKana;
    if (result['department'] == line) return OcrField.department;
    if (result['phone'] == line) return OcrField.phone;
    if (result['mobilePhone'] == line) return OcrField.mobilePhone;
    if (result['fax'] == line) return OcrField.fax;
    if (result['zipCode'] == line) return OcrField.zipCode;
    if (result['address'] == line) return OcrField.address;
    if (result['projectCodes'] == line) return OcrField.projectCodes;
    if (result['note'] == line) return OcrField.note;
    return OcrField.skip;
  }

  Map<String, String> _buildResult() {
    final result = <String, String>{
      'name': '', 'nameKana': '', 'company': '', 'companyKana': _autoCompanyKana,
      'department': '', 'phone': '', 'mobilePhone': '', 'fax': '',
      'zipCode': '', 'address': '', 'projectCodes': '', 'note': '',
    };
    for (int i = 0; i < widget.lines.length; i++) {
      final field = _assignments[i];
      if (field == OcrField.skip) continue;
      final key = field.name;
      final value = _selectedCompany[i] ?? widget.lines[i];
      if (result[key]!.isEmpty) {
        result[key] = value;
      } else {
        result[key] = '${result[key]} $value';
      }
    }
    return result;
  }

  // 選択された会社名候補（行ごと）
  final Map<int, String> _selectedCompany = {};
  String _autoCompanyKana = ''; // 会社名候補選択時に自動取得したよみがな

  void _showCompanyCandidates(int index) {
    final candidates = _companyCandidates[index] ?? [];
    if (candidates.isEmpty) return;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('会社名の候補'),
        message: Text('「${widget.lines[index]}」に近い会社名:'),
        actions: candidates.map((company) => CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.of(context).pop();
            // 会社よみがなをDBから自動取得
            final kana = await DatabaseHelper.instance.getCompanyKana(widget.userId, company);
            setState(() {
              _selectedCompany[index] = company;
              _assignments[index] = OcrField.company;
              // よみがなが取得できた場合は自動セット
              if (kana.isNotEmpty) {
                _autoCompanyKana = kana;
              }
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(company),
              FutureBuilder<String>(
                future: DatabaseHelper.instance.getCompanyKana(widget.userId, company),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    return Text(snapshot.data!, style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey));
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('OCR確認・振り分け'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(_buildResult()),
          child: const Text('確定', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: const Text(
                '各行の項目をドロップダウンで変更できます\n会社名は候補ボタンから既存データを選択できます',
                textAlign: TextAlign.center,
                style: TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 12),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: widget.lines.length,
                itemBuilder: (context, index) {
                  final line = widget.lines[index];
                  final selectedCompany = _selectedCompany[index];
                  final hasCandidates = _companyCandidates.containsKey(index);

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: CupertinoColors.systemGrey5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                selectedCompany ?? line,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: selectedCompany != null
                                      ? CupertinoColors.systemGreen
                                      : CupertinoColors.label,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: _assignments[index] == OcrField.skip
                                      ? CupertinoColors.systemGrey6
                                      : CupertinoColors.systemBlue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _assignments[index] == OcrField.skip
                                        ? CupertinoColors.systemGrey4
                                        : CupertinoColors.systemBlue,
                                  ),
                                ),
                                child: DropdownButton<OcrField>(
                                  value: _assignments[index],
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  isDense: true,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _assignments[index] == OcrField.skip
                                        ? CupertinoColors.secondaryLabel
                                        : CupertinoColors.systemBlue,
                                  ),
                                  items: OcrField.values.map((field) {
                                    return DropdownMenuItem(
                                      value: field,
                                      child: Text(
                                        field.label,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _assignments[index] = value);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        // 会社名候補ボタン
                        if (hasCandidates)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              color: CupertinoColors.systemOrange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              minSize: 0,
                              onPressed: () => _showCompanyCandidates(index),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(CupertinoIcons.building_2_fill, size: 12, color: CupertinoColors.systemOrange),
                                  SizedBox(width: 4),
                                  Text('会社名候補を見る', style: TextStyle(fontSize: 12, color: CupertinoColors.systemOrange)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
