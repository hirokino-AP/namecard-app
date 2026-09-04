// lib/screens/call_result_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircleAvatar;
import 'package:provider/provider.dart';
import '../models/business_card.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';

class CallResultScreen extends StatefulWidget {
  final BusinessCard card;
  final String? todoId;
  const CallResultScreen({super.key, required this.card, this.todoId});
  @override
  State<CallResultScreen> createState() => _CallResultScreenState();
}

class _CallResultScreenState extends State<CallResultScreen> {
  CallResult? _selectedResult;
  final _memoController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() { _memoController.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_selectedResult == null) { _showAlert('選択してください', '通話結果を選択してください'); return; }
    if (widget.todoId == null || widget.todoId!.isEmpty) { Navigator.of(context).pop(); return; }
    setState(() => _isSaving = true);
    try {
      final uid = context.read<AuthProvider>().uid;
      final success = await FirestoreService.instance.addCallLog(
          todoId: widget.todoId!, result: _selectedResult!,
          callerUid: uid, memo: _memoController.text.trim());
      if (mounted) {
        if (success) {
          showCupertinoDialog(context: context,
              builder: (_) => CupertinoAlertDialog(
                title: const Text('記録完了'),
                content: const Text('通話結果をTodoに記録しました'),
                actions: [CupertinoDialogAction(isDefaultAction: true,
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                    }, child: const Text('OK'))],
              ));
        } else { _showAlert('エラー', 'Todoへの記録に失敗しました'); }
      }
    } finally { if (mounted) setState(() => _isSaving = false); }
  }

  void _showAlert(String title, String message) {
    showCupertinoDialog(context: context,
        builder: (_) => CupertinoAlertDialog(title: Text(title), content: Text(message),
            actions: [CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))]));
  }

  Widget _buildResultButton(CallResult result) {
    final isSelected = _selectedResult == result;
    return GestureDetector(
      onTap: () => setState(() => _selectedResult = result),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? CupertinoColors.systemBlue : CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? CupertinoColors.systemBlue : CupertinoColors.systemGrey4),
        ),
        child: Row(children: [
          Text(result.label, style: TextStyle(fontSize: 16,
              color: isSelected ? CupertinoColors.white : CupertinoColors.label,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          if (isSelected) const Icon(CupertinoIcons.checkmark_circle_fill,
              color: CupertinoColors.white, size: 20),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('通話結果を記録'),
        leading: CupertinoButton(padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
        trailing: CupertinoButton(padding: EdgeInsets.zero,
            onPressed: _isSaving ? null : _save,
            child: _isSaving ? const CupertinoActivityIndicator()
                : const Text('記録', style: TextStyle(fontWeight: FontWeight.bold))),
      ),
      child: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: CupertinoColors.systemBackground,
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            CircleAvatar(
                backgroundColor: CupertinoColors.systemBlue.withValues(alpha: 0.15),
                child: Text(widget.card.name.isNotEmpty ? widget.card.name[0] : '?',
                    style: const TextStyle(color: CupertinoColors.systemBlue, fontWeight: FontWeight.bold))),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.card.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(widget.card.company, style: const TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 13)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('通話結果', style: TextStyle(fontSize: 13,
            color: CupertinoColors.secondaryLabel, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...CallResult.values.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 10), child: _buildResultButton(r))),
        const SizedBox(height: 16),
        const Text('メモ（任意）', style: TextStyle(fontSize: 13,
            color: CupertinoColors.secondaryLabel, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: CupertinoColors.systemBackground,
              borderRadius: BorderRadius.circular(12)),
          child: CupertinoTextField(controller: _memoController,
              placeholder: '例：来週再度連絡、資料を送付済み...',
              maxLines: 4, minLines: 3, padding: const EdgeInsets.all(12), decoration: null),
        ),
        const SizedBox(height: 32),
      ])),
    );
  }
}
