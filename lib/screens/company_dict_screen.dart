// ============================================================
// lib/screens/company_dict_screen.dart
//
// 【役割】
//   会社辞書の未確認データを一覧表示し、
//   よみがな・略称・業種を確認・編集して保存する画面。
// ============================================================

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../db/database_helper.dart';
import '../providers/auth_provider.dart';

class CompanyDictScreen extends StatefulWidget {
  const CompanyDictScreen({super.key});

  @override
  State<CompanyDictScreen> createState() => _CompanyDictScreenState();
}

class _CompanyDictScreenState extends State<CompanyDictScreen> {
  List<Map<String, dynamic>> _unconfirmed = [];
  bool _isLoading = true;
  // 編集中のデータを保持
  final Map<String, TextEditingController> _kanaControllers = {};
  final Map<String, TextEditingController> _abbrevControllers = {};
  final Map<String, TextEditingController> _industryControllers = {};

  @override
  void initState() {
    super.initState();
    _loadUnconfirmed();
  }

  @override
  void dispose() {
    _kanaControllers.values.forEach((c) => c.dispose());
    _abbrevControllers.values.forEach((c) => c.dispose());
    _industryControllers.values.forEach((c) => c.dispose());
    super.dispose();
  }

  Future<void> _loadUnconfirmed() async {
    setState(() => _isLoading = true);
    final uid = context.read<AuthProvider>().uid;
    final rows = await DatabaseHelper.instance.getUnconfirmedCompanyDict(uid);
    setState(() {
      _unconfirmed = rows;
      _isLoading = false;
      // コントローラーを初期化
      for (final row in rows) {
        final company = row['company'] as String;
        _kanaControllers[company] = TextEditingController(text: row['company_kana'] as String? ?? '');
        _abbrevControllers[company] = TextEditingController(text: row['abbreviation'] as String? ?? '');
        _industryControllers[company] = TextEditingController(text: row['industry'] as String? ?? '');
      }
    });
  }

  Future<void> _confirm(String company) async {
    final uid = context.read<AuthProvider>().uid;
    // よみがな・略称・業種を保存
    await DatabaseHelper.instance.updateCompanyDictKana(uid, company, _kanaControllers[company]!.text.trim());
    await DatabaseHelper.instance.updateCompanyDictIndustry(uid, company, _industryControllers[company]!.text.trim());
    // 略称を更新
    final db = await DatabaseHelper.instance.database;
    await db.update('company_dict',
      {'abbreviation': _abbrevControllers[company]!.text.trim(), 'updated_at': DateTime.now().toIso8601String()},
      where: 'user_id = ? AND company = ?',
      whereArgs: [uid, company],
    );
    // confirmed=1に更新
    await DatabaseHelper.instance.updateCompanyDictConfirmed(uid, company, true);
    setState(() => _unconfirmed.removeWhere((r) => r['company'] == company));
  }

  Future<void> _confirmAll() async {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('一括確認'),
        content: Text('未確認${_unconfirmed.length}社を全て確認済みにしますか？\nよみがな・略称・業種は現在の入力値で保存されます。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              Navigator.of(context).pop();
              for (final row in List.from(_unconfirmed)) {
                await _confirm(row['company'] as String);
              }
            },
            child: const Text('確認済みにする'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('会社辞書確認'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
        trailing: _unconfirmed.isNotEmpty
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _confirmAll,
                child: const Text('一括確認'),
              )
            : null,
      ),
      child: _isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : _unconfirmed.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.checkmark_circle, size: 60, color: CupertinoColors.systemGreen),
                      SizedBox(height: 16),
                      Text('未確認の会社はありません', style: TextStyle(fontSize: 16, color: CupertinoColors.secondaryLabel)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: CupertinoColors.systemBlue.withValues(alpha: 0.1),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.info_circle, size: 16, color: CupertinoColors.systemBlue),
                          const SizedBox(width: 8),
                          Text('未確認: ${_unconfirmed.length}社',
                              style: const TextStyle(color: CupertinoColors.systemBlue, fontSize: 14)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _unconfirmed.length,
                        itemBuilder: (context, index) {
                          final row = _unconfirmed[index];
                          final company = row['company'] as String;
                          final count = row['count'] as int? ?? 0;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: CupertinoColors.systemGrey4),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 会社名・登録人数
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(company,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ),
                                    Text('$count名',
                                        style: const TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // よみがな
                                _buildField('よみがな', _kanaControllers[company]!, 'ふじふいるむかぶしきがいしゃ'),
                                const SizedBox(height: 6),
                                // 略称（任意）
                                _buildField('略称（任意）', _abbrevControllers[company]!, '例：富士フイルム、経産省'),
                                const SizedBox(height: 6),
                                // 業種
                                _buildField('業種', _industryControllers[company]!, '例：電機・電子'),
                                const SizedBox(height: 10),
                                // ボタン
                                Row(
                                  children: [
                                    Expanded(
                                      child: CupertinoButton(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        color: CupertinoColors.systemBlue,
                                        borderRadius: BorderRadius.circular(8),
                                        minSize: 0,
                                        onPressed: () => _confirm(company),
                                        child: const Text('確認済み',
                                            style: TextStyle(fontSize: 14, color: CupertinoColors.white)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: CupertinoButton(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        color: CupertinoColors.systemGrey5,
                                        borderRadius: BorderRadius.circular(8),
                                        minSize: 0,
                                        onPressed: () {
                                          // 後で確認→そのままリストに残す
                                          showCupertinoDialog(
                                            context: context,
                                            builder: (_) => CupertinoAlertDialog(
                                              title: const Text('後で確認'),
                                              content: const Text('この会社は後で確認リストに残ります。'),
                                              actions: [
                                                CupertinoDialogAction(
                                                  isDefaultAction: true,
                                                  onPressed: () => Navigator.of(context).pop(),
                                                  child: const Text('OK'),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                        child: const Text('後で確認',
                                            style: TextStyle(fontSize: 14, color: CupertinoColors.label)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String placeholder) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
        ),
        Expanded(
          child: CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            style: const TextStyle(fontSize: 14),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ],
    );
  }
}
