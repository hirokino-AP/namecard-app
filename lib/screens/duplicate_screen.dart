// lib/screens/duplicate_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircleAvatar;
import 'package:provider/provider.dart';
import '../models/business_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../db/database_helper.dart';
import 'card_detail_screen.dart';

class DuplicateScreen extends StatefulWidget {
  const DuplicateScreen({super.key});
  @override
  State<DuplicateScreen> createState() => _DuplicateScreenState();
}

class _DuplicateScreenState extends State<DuplicateScreen> {
  Map<String, List<BusinessCard>> _duplicates = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDuplicates());
  }

  Future<void> _loadDuplicates() async {
    setState(() => _isLoading = true);
    final uid = context.read<AuthProvider>().uid;
    final result = await DatabaseHelper.instance.findDuplicates(uid);
    setState(() {
      _duplicates = result;
      _isLoading = false;
    });
  }

  Future<void> _deleteCard(BusinessCard card, String key) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('削除確認'),
        content: Text('${card.name}（${card.company}）を削除しますか？'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<CardProvider>().deleteCard(card.id!);
    await _loadDuplicates();
  }

  Widget _buildCardItem(BusinessCard card, String key) {
    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: CupertinoColors.systemOrange.withValues(alpha: 0.15),
        child: Text(
          card.name.isNotEmpty ? card.name[0] : '?',
          style: const TextStyle(color: CupertinoColors.systemOrange, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(card.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (card.department.isNotEmpty)
          Text(card.department,
              style: const TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 12)),
        if (card.title.isNotEmpty)
          Text(card.title,
              style: const TextStyle(color: CupertinoColors.tertiaryLabel, fontSize: 12)),
        if (card.mobilePhone.isNotEmpty || card.phone.isNotEmpty)
          Text(card.mobilePhone.isNotEmpty ? card.mobilePhone : card.phone,
              style: const TextStyle(color: CupertinoColors.tertiaryLabel, fontSize: 12)),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).push(
              CupertinoPageRoute(builder: (_) => CardDetailScreen(card: card))),
          child: const Icon(CupertinoIcons.eye, size: 20, color: CupertinoColors.systemBlue),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _deleteCard(card, key),
          child: const Icon(CupertinoIcons.trash, size: 20, color: CupertinoColors.systemRed),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('重複名刺チェック'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _loadDuplicates,
          child: const Icon(CupertinoIcons.refresh, size: 20),
        ),
      ),
      child: SafeArea(
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : _duplicates.isEmpty
                ? const Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(CupertinoIcons.checkmark_circle,
                          size: 60, color: CupertinoColors.systemGreen),
                      SizedBox(height: 16),
                      Text('重複する名刺はありません',
                          style: TextStyle(color: CupertinoColors.secondaryLabel)),
                    ]),
                  )
                : ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          '${_duplicates.length}グループの重複が見つかりました',
                          style: const TextStyle(
                              color: CupertinoColors.systemOrange,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      ..._duplicates.entries.map((entry) {
                        final parts = entry.key.split('___');
                        final name = parts[0];
                        final company = parts.length > 1 ? parts[1] : '';
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Row(children: [
                              const Icon(CupertinoIcons.exclamationmark_circle,
                                  size: 14, color: CupertinoColors.systemOrange),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '$name　$company　（${entry.value.length}件）',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: CupertinoColors.systemOrange),
                                ),
                              ),
                            ]),
                          ),
                          CupertinoListSection.insetGrouped(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            children: entry.value
                                .map((card) => _buildCardItem(card, entry.key))
                                .toList(),
                          ),
                        ]);
                      }),
                      const SizedBox(height: 32),
                    ],
                  ),
      ),
    );
  }
}
