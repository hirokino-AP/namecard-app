// lib/screens/card_list_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircleAvatar, RefreshIndicator;
import 'package:provider/provider.dart';
import '../models/business_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../db/database_helper.dart';
import 'card_detail_screen.dart';
import 'card_edit_screen.dart';

class CardListScreen extends StatefulWidget {
  const CardListScreen({super.key});
  @override
  State<CardListScreen> createState() => _CardListScreenState();
}

class _CardListScreenState extends State<CardListScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCards());
  }

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  Future<void> _loadCards() async {
  final uid = context.read<AuthProvider>().uid;
  final imported = await context.read<CardProvider>().importFromItunes(uid);
  if (mounted) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('デバッグ'),
        content: Text('importFromItunes結果: $imported'),
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
  await context.read<CardProvider>().loadCards(uid);
}

  void _onSearchChanged(String keyword) {
    final uid = context.read<AuthProvider>().uid;
    context.read<CardProvider>().search(uid, keyword);
  }

  void _clearSearch() {
    _searchController.clear();
    context.read<CardProvider>().clearSearch();
  }


  Future<void> _importDb() async {
    final result = await FilePicker.instance.pickFiles(
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final uid = context.read<AuthProvider>().uid;
    final count = await DatabaseHelper.instance.importFromPath(path, uid);
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('インポート完了'),
        content: Text('$count件の名刺をインポートしました。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.of(context).pop();
              _loadCards();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _importCsv() async {
    final uid = context.read<AuthProvider>().uid;
    final result = await context.read<CardProvider>().importFromCsv(uid);
    if (!mounted) return;
    final cancelled = result['cancelled'] == 1;
    if (cancelled) return;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('インポート完了'),
        content: Text("成功: ${result['success']}件\nスキップ: ${result['skip']}件\nエラー: ${result['error']}件"),
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

  void _confirmLogout() {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(context).pop();
              await context.read<AuthProvider>().signOut(context.read<CardProvider>());
            },
            child: const Text('ログアウト'),
          ),
          CupertinoDialogAction(isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル')),
        ],
      ),
    );
  }

  Widget _buildCardItem(BusinessCard card) {
    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: CircleAvatar(
        backgroundColor: CupertinoColors.systemBlue.withValues(alpha: 0.15),
        child: Text(card.name.isNotEmpty ? card.name[0] : '?',
            style: const TextStyle(color: CupertinoColors.systemBlue, fontWeight: FontWeight.bold)),
      ),
      title: Text(card.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (card.company.isNotEmpty)
          Text(card.company, style: const TextStyle(
              color: CupertinoColors.secondaryLabel, fontSize: 13)),
        if (card.department.isNotEmpty)
          Text(card.department, style: const TextStyle(
              color: CupertinoColors.tertiaryLabel, fontSize: 12),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        if (card.mobilePhone.isNotEmpty || card.phone.isNotEmpty)
          Row(children: [
            const Icon(CupertinoIcons.phone, size: 11, color: CupertinoColors.tertiaryLabel),
            const SizedBox(width: 4),
            Text(card.mobilePhone.isNotEmpty ? card.mobilePhone : card.phone,
                style: const TextStyle(color: CupertinoColors.tertiaryLabel, fontSize: 12)),
          ]),
      ]),
      trailing: const CupertinoListTileChevron(),
      onTap: () => Navigator.of(context).push(CupertinoPageRoute(
          builder: (_) => CardDetailScreen(card: card))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = context.watch<CardProvider>().displayCards;
    final isLoading = context.watch<CardProvider>().isLoading;
    final isSearching = context.watch<CardProvider>().isSearching;
    final total = context.watch<CardProvider>().cards.length;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('名刺管理'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _confirmLogout,
          child: const Icon(CupertinoIcons.square_arrow_right, size: 22),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _importDb,
            child: const Icon(CupertinoIcons.square_arrow_down, size: 22),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _importCsv,
            child: const Icon(CupertinoIcons.arrow_down_doc, size: 22),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => const CardEditScreen())),
            child: const Icon(CupertinoIcons.add, size: 26),
          ),
        ]),
      ),
      child: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: CupertinoSearchTextField(
            controller: _searchController,
            placeholder: '氏名・会社名・よみがなで検索',
            onChanged: _onSearchChanged,
            onSuffixTap: _clearSearch,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Text(isSearching ? '検索結果: ${cards.length}件' : '全$total件',
                style: const TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 12)),
          ]),
        ),
        Expanded(child: isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : cards.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(CupertinoIcons.person_crop_rectangle,
                        size: 60, color: CupertinoColors.secondaryLabel),
                    const SizedBox(height: 16),
                    Text(isSearching ? '該当する名刺が見つかりません'
                        : '名刺がまだありません\n右上の＋から追加してください',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: CupertinoColors.secondaryLabel)),
                  ]))
                : RefreshIndicator.adaptive(
                    onRefresh: _loadCards,
                    child: CupertinoListSection.insetGrouped(
                        children: cards.map(_buildCardItem).toList()),
                  )),
      ])),
    );
  }
}
