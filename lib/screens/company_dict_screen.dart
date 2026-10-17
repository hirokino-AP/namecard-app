// ============================================================
// lib/screens/company_dict_screen.dart
//
// 【役割】
//   会社辞書を一覧表示し、よみがな・略称・業種を確認・編集して保存する画面。
//   既定は未確認の会社のみ表示。チェックを入れると確認済みの会社も
//   表示・検索でき、修正して保存し直せる。
//
// 【検索】
//   会社名・よみがな・略称・業種を対象に、空白・全角半角・
//   ひらがなカタカナ・大文字小文字の違いを無視して絞り込む。
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
  // 表示対象の会社（既定は未確認のみ。チェックONで確認済みも含む）
  List<Map<String, dynamic>> _rows = [];
  bool _isLoading = true;
  // 確認済みの会社も表示・検索対象に含めるか
  bool _includeConfirmed = false;

  // 検索
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  // 編集中のデータを保持
  final Map<String, TextEditingController> _kanaControllers = {};
  final Map<String, TextEditingController> _abbrevControllers = {};
  final Map<String, TextEditingController> _industryControllers = {};

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  @override
  void dispose() {
    for (final c in _kanaControllers.values) {
      c.dispose();
    }
    for (final c in _abbrevControllers.values) {
      c.dispose();
    }
    for (final c in _industryControllers.values) {
      c.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  bool _isConfirmed(Map<String, dynamic> row) =>
      (row['confirmed'] as int? ?? 0) == 1;


  Future<void> _loadRows() async {
    final uid = context.read<AuthProvider>().uid;
    List<Map<String, dynamic>> rows;
    if (_includeConfirmed) {
      final db = await DatabaseHelper.instance.database;
      rows = await db.query(
        'company_dict',
        where: 'user_id = ?',
        whereArgs: [uid],
        orderBy: 'confirmed ASC, "count" DESC, company ASC',
      );
    } else {
      rows = await DatabaseHelper.instance.getUnconfirmedCompanyDict(uid);
    }
    if (!mounted) return;
    setState(() {
      _rows = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      _isLoading = false;
      // コントローラーを初期化（入力途中の内容は残す）
      for (final row in _rows) {
        final company = row['company'] as String;
        _kanaControllers.putIfAbsent(company,
            () => TextEditingController(text: row['company_kana'] as String? ?? ''));
        _abbrevControllers.putIfAbsent(company,
            () => TextEditingController(text: row['abbreviation'] as String? ?? ''));
        _industryControllers.putIfAbsent(company,
            () => TextEditingController(text: row['industry'] as String? ?? ''));
      }
    });
  }

  Future<void> _setIncludeConfirmed(bool value) async {

    if (_includeConfirmed == value) return;
    setState(() => _includeConfirmed = value);
    await _loadRows();
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
    if (!mounted) return;
    setState(() {
      if (_includeConfirmed) {
        // 確認済みも表示中：一覧に残して「確認済み」表示に切り替える
        for (final r in _rows) {
          if (r['company'] == company) {
            r['confirmed'] = 1;
          }
        }
      } else {
        _rows.removeWhere((r) => r['company'] == company);
      }
    });
  }

  // 検索用の正規化：空白除去・全角英数→半角・カタカナ→ひらがな・小文字化
  String _normalize(String s) {
    final buf = StringBuffer();
    for (final rune in s.runes) {
      var c = rune;
      if (c == 0x20 || c == 0x3000 || c == 0x09) continue;
      if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角ASCII→半角
      if (c >= 0x30A1 && c <= 0x30F6) c -= 0x60;   // カタカナ→ひらがな
      buf.writeCharCode(c);
    }
    return buf.toString().toLowerCase();
  }

  // 検索条件に合う会社（会社名・よみがな・略称・業種が対象）
  List<Map<String, dynamic>> get _filtered {
    final q = _normalize(_query);
    if (q.isEmpty) return _rows;
    return _rows.where((row) {
      final company = row['company'] as String;
      final fields = [
        company,
        _kanaControllers[company]?.text ?? '',
        _abbrevControllers[company]?.text ?? '',
        _industryControllers[company]?.text ?? '',
      ];
      return fields.any((t) => _normalize(t).contains(q));
    }).toList();
  }

  // 一括確認：画面に表示中の「未確認」の会社だけが対象
  Future<void> _confirmAll() async {
    final targets = _filtered.where((r) => !_isConfirmed(r)).toList();
    if (targets.isEmpty) return;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('一括確認'),
        content: Text('${_query.isEmpty ? "未確認" : "検索で表示中の未確認"}${targets.length}社を全て確認済みにしますか？\nよみがな・略称・業種は現在の入力値で保存されます。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              Navigator.of(context).pop();
              for (final row in targets) {
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
    final filtered = _filtered;
    final filteredUnconfirmed = filtered.where((r) => !_isConfirmed(r)).toList();
    final unconfirmedTotal = _rows.where((r) => !_isConfirmed(r)).length;
    final summary = _includeConfirmed
        ? '全${_rows.length}社（未確認$unconfirmedTotal社）'
        : '未確認: ${_rows.length}社';
    final summaryText =
        _query.isEmpty ? summary : '$summary ／ 表示 ${filtered.length}社';

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('会社辞書確認'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
        trailing: filteredUnconfirmed.isNotEmpty
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _confirmAll,
                child: const Text('一括確認'),
              )
            : null,
      ),
      child: _isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : Column(
              children: [

                Container(
                  padding: const EdgeInsets.all(12),
                  color: CupertinoColors.systemBlue.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.info_circle, size: 16, color: CupertinoColors.systemBlue),
                      const SizedBox(width: 8),
                      Text(summaryText,
                          style: const TextStyle(color: CupertinoColors.systemBlue, fontSize: 14)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: CupertinoSearchTextField(
                    controller: _searchController,
                    placeholder: '会社名・よみがな・略称で検索',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                _buildIncludeConfirmedToggle(),
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmpty()
                      : ListView.builder(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) => _buildCard(filtered[index]),
                        ),
                ),
              ],
            ),

    );
  }

  // 「確認済みの会社も表示・検索する」レ点
  Widget _buildIncludeConfirmedToggle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setIncludeConfirmed(!_includeConfirmed),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            Icon(
              _includeConfirmed
                  ? CupertinoIcons.checkmark_square_fill
                  : CupertinoIcons.square,
              size: 22,
              color: _includeConfirmed
                  ? CupertinoColors.systemBlue
                  : CupertinoColors.systemGrey,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('確認済みの会社も表示・検索する',
                  style: TextStyle(fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildEmpty() {
    final noRows = _rows.isEmpty && _query.isEmpty;
    final message = noRows
        ? (_includeConfirmed ? '会社辞書は空です' : '未確認の会社はありません')
        : '該当する会社はありません';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            noRows ? CupertinoIcons.checkmark_circle : CupertinoIcons.search,
            size: 60,
            color: noRows ? CupertinoColors.systemGreen : CupertinoColors.systemGrey,
          ),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(fontSize: 16, color: CupertinoColors.secondaryLabel)),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> row) {
    final company = row['company'] as String;
    final count = row['count'] as int? ?? 0;
    final confirmed = _isConfirmed(row);
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
          // 会社名・確認済み表示・登録人数
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(company,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (confirmed)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),

                  child: const Text('確認済み',
                      style: TextStyle(fontSize: 11, color: CupertinoColors.systemGreen)),
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
                  child: Text(confirmed ? '保存' : '確認済み',
                      style: const TextStyle(fontSize: 14, color: CupertinoColors.white)),
                ),
              ),
              if (!confirmed) ...[

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
            ],
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
