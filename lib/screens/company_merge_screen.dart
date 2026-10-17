// ============================================================
// lib/screens/company_merge_screen.dart
//
// 【役割】
//   重複企業名チェック画面。空白・全角半角の違いだけで別の会社に
//   なっている会社名を一覧し、正しい表記を選んで統合する。
//   右上の「履歴」から、直近の統合・社名変更を取り消せる。
// ============================================================

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../services/company_merge_service.dart';

class CompanyMergeScreen extends StatefulWidget {
  const CompanyMergeScreen({super.key});

  @override
  State<CompanyMergeScreen> createState() => _CompanyMergeScreenState();
}

class _CompanyMergeScreenState extends State<CompanyMergeScreen> {
  List<MergeCandidate> _candidates = [];
  // グループごとに選んだ正しい表記（キー：グループのキー）
  final Map<String, String> _selected = {};
  bool _isLoading = true;
  bool _isWorking = false;
  int _historyCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final uid = context.read<AuthProvider>().uid;
    final result = await CompanyMergeService.findCandidates(uid);
    final history = await CompanyMergeService.loadHistory(uid);
    if (!mounted) return;
    setState(() {
      _candidates = result;
      _historyCount = history.length;
      // 件数が多い表記を、初めから選んでおく
      for (final c in result) {
        _selected.putIfAbsent(c.key, () => c.variants.first.company);
      }
      _isLoading = false;
    });
  }

  void _showMessage(String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // 統合の確認 → 実行
  Future<void> _merge(MergeCandidate c) async {
    final toName = _selected[c.key] ?? c.variants.first.company;
    final fromNames = c.variants.map((v) => v.company).toList();
    final uid = context.read<AuthProvider>().uid;
    final count =
        await CompanyMergeService.countCardsToChange(uid, fromNames, toName);
    if (!mounted) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('統合の確認'),
        content: Text(
            '「$toName」にそろえます。\n名刺 $count 件の会社名が書き換わります。\n\n'
            '念のため、事前に設定画面から「データをバックアップ（AirDrop）」を取っておくと安心です。\n'
            '実行後も、右上の「履歴」から取り消せます。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('統合する'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _isWorking = true);
    try {
      final changed = await CompanyMergeService.applyRename(
          uid, fromNames, toName,
          type: 'merge');
      if (!mounted) return;
      await context.read<CardProvider>().loadCards(uid);
      if (!mounted) return;
      setState(() => _isWorking = false);
      await _load();
      if (!mounted) return;
      _showMessage('統合しました', '名刺 $changed 件の会社名を「$toName」にそろえました。');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isWorking = false);
      _showMessage('エラー', '統合に失敗しました。名刺データは変更されていません。\n$e');
    }
  }

  // 空白の違いが見えるように、表示用に置き換える（· = 半角空白、□ = 全角空白）
  String _visible(String s) => s.replaceAll(' ', '·').replaceAll('\u3000', '□');

  Widget _buildCandidate(MergeCandidate c) {
    final selected = _selected[c.key] ?? c.variants.first.company;
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
          const Text('正しい表記を選んでください',
              style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
          const SizedBox(height: 4),
          for (final v in c.variants)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _selected[c.key] = v.company),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      selected == v.company
                          ? CupertinoIcons.largecircle_fill_circle
                          : CupertinoIcons.circle,
                      size: 22,
                      color: selected == v.company
                          ? CupertinoColors.systemBlue
                          : CupertinoColors.systemGrey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_visible(v.company),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: selected == v.company
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                    ),
                    Text('${v.cardCount}件',
                        style: const TextStyle(
                            fontSize: 12, color: CupertinoColors.secondaryLabel)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: CupertinoColors.systemBlue,
              borderRadius: BorderRadius.circular(8),
              onPressed: () => _merge(c),
              child: const Text('この表記に統合する',
                  style: TextStyle(fontSize: 14, color: CupertinoColors.white)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('重複企業名チェック'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isWorking ? null : _showHistory,
          child: Text(_historyCount > 0 ? '履歴($_historyCount)' : '履歴'),
        ),
      ),
      child: SafeArea(
        child: (_isLoading || _isWorking)
            ? const Center(child: CupertinoActivityIndicator())
            : _candidates.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.checkmark_circle,
                            size: 60, color: CupertinoColors.systemGreen),
                        SizedBox(height: 16),
                        Text('表記ゆれの会社名はありません',
                            style: TextStyle(color: CupertinoColors.secondaryLabel)),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          '${_candidates.length}グループの候補が見つかりました\n'
                          '（· = 半角空白、□ = 全角空白）',
                          style: const TextStyle(
                              color: CupertinoColors.systemOrange,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      ..._candidates.map(_buildCandidate),
                      const SizedBox(height: 32),
                    ],
                  ),
      ),
    );
  }

  // 履歴の一覧を表示し、最も新しい1件だけ取り消せるようにする
  Future<void> _showHistory() async {
    final uid = context.read<AuthProvider>().uid;
    final history = await CompanyMergeService.loadHistory(uid);
    if (!mounted) return;
    if (history.isEmpty) {
      _showMessage('履歴', '取り消せる履歴はありません。');
      return;
    }
    final latest = history.first;
    final lines = history.take(10).map((h) {
      final t = h.at;
      final d = '${t.month}/${t.day} '
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      return '$d ${h.typeLabel}：→「${h.toName}」（${h.changedCount}件）';
    }).join('\n');
    final undo = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('履歴（新しい順）'),
        content: Text(
            '$lines\n\n取り消せるのは、いちばん新しい1件（「${latest.toName}」）のみです。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('閉じる'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('最新の1件を取り消す'),
          ),
        ],
      ),
    );
    if (undo != true || !mounted) return;

    setState(() => _isWorking = true);
    try {
      final r = await CompanyMergeService.undoLatest(uid);
      if (!mounted) return;
      await context.read<CardProvider>().loadCards(uid);
      if (!mounted) return;
      setState(() => _isWorking = false);
      await _load();
      if (!mounted) return;
      final skipped = r.skipped > 0
          ? '\n${r.skipped}件は、その後に会社名が変更または削除されていたため、そのままにしました。'
          : '';
      _showMessage('取り消しました', '名刺 ${r.restored} 件の会社名を元に戻しました。$skipped');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isWorking = false);
      _showMessage('エラー', '取り消しに失敗しました。\n$e');
    }
  }
}
