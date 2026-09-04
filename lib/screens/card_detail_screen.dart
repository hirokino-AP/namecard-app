// lib/screens/card_detail_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircleAvatar;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/business_card.dart';
import '../providers/card_provider.dart';
import 'card_edit_screen.dart';

class CardDetailScreen extends StatelessWidget {
  final BusinessCard card;
  const CardDetailScreen({super.key, required this.card});

  Future<void> _callPhone(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _sendEmail(BuildContext context, String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _showProjects(BuildContext context) async {
    if (card.projectCodes.isEmpty) {
      _showAlert(context, 'プロジェクト', '紐づいているプロジェクトはありません');
      return;
    }
    showCupertinoDialog(context: context,
        builder: (_) => const CupertinoAlertDialog(
            title: Text('プロジェクト'),
            content: Padding(padding: EdgeInsets.only(top: 8),
                child: CupertinoActivityIndicator())));
    try {
      final firestore = FirebaseFirestore.instance;
      final List<String> names = [];
      for (final code in card.projectCodes) {
        final doc = await firestore.collection('projects').doc(code).get();
        names.add(doc.exists ? '📁 ${doc.data()?['name'] ?? code}' : '📁 $code（未登録）');
      }
      if (context.mounted) {
        Navigator.of(context).pop();
        showCupertinoDialog(context: context,
            builder: (_) => CupertinoAlertDialog(
              title: const Text('関連プロジェクト'),
              content: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: names.map((n) => Padding(
                      padding: const EdgeInsets.only(top: 8), child: Text(n))).toList()),
              actions: [CupertinoDialogAction(isDefaultAction: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('閉じる'))],
            ));
      }
    } catch (e) {
      if (context.mounted) { Navigator.of(context).pop(); _showAlert(context, 'エラー', '取得失敗'); }
    }
  }

  void _confirmDelete(BuildContext context) {
    showCupertinoDialog(context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('名刺を削除'),
          content: Text('${card.name}さんの名刺を削除しますか？'),
          actions: [
            CupertinoDialogAction(isDestructiveAction: true,
                onPressed: () async {
                  Navigator.of(context).pop();
                  await context.read<CardProvider>().deleteCard(card.id!);
                  if (context.mounted) Navigator.of(context).pop();
                }, child: const Text('削除')),
            CupertinoDialogAction(isDefaultAction: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('キャンセル')),
          ],
        ));
  }

  void _showAlert(BuildContext context, String title, String message) {
    showCupertinoDialog(context: context,
        builder: (_) => CupertinoAlertDialog(title: Text(title), content: Text(message),
            actions: [CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))]));
  }

  Widget _buildInfoTile({required IconData icon, required String label,
      required String value, VoidCallback? onTap}) {
    if (value.isEmpty) return const SizedBox.shrink();
    return CupertinoListTile(
      leading: Icon(icon, color: CupertinoColors.systemBlue, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
      subtitle: Text(value, style: const TextStyle(fontSize: 15)),
      trailing: onTap != null ? const Icon(CupertinoIcons.chevron_right,
          size: 14, color: CupertinoColors.tertiaryLabel) : null,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(card.name),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          CupertinoButton(padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute(builder: (_) => CardEditScreen(card: card))),
              child: const Icon(CupertinoIcons.pencil, size: 22)),
          CupertinoButton(padding: EdgeInsets.zero,
              onPressed: () => _confirmDelete(context),
              child: const Icon(CupertinoIcons.trash, size: 22,
                  color: CupertinoColors.destructiveRed)),
        ]),
      ),
      child: SafeArea(child: ListView(children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          color: CupertinoColors.systemBackground,
          child: Column(children: [
            CircleAvatar(radius: 36,
                backgroundColor: CupertinoColors.systemBlue.withValues(alpha: 0.15),
                child: Text(card.name.isNotEmpty ? card.name[0] : '?',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                        color: CupertinoColors.systemBlue))),
            const SizedBox(height: 12),
            Text(card.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            if (card.nameKana.isNotEmpty)
              Text(card.nameKana, style: const TextStyle(fontSize: 13, color: CupertinoColors.secondaryLabel)),
            if (card.company.isNotEmpty)
              Text(card.company, style: const TextStyle(fontSize: 15, color: CupertinoColors.secondaryLabel)),
            if (card.title.isNotEmpty)
              Text(card.title, style: const TextStyle(fontSize: 13, color: CupertinoColors.tertiaryLabel)),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            if (card.mobilePhone.isNotEmpty || card.phone.isNotEmpty)
              Expanded(child: CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(vertical: 10),
                onPressed: () => _callPhone(context,
                    card.mobilePhone.isNotEmpty ? card.mobilePhone : card.phone),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(CupertinoIcons.phone_fill, size: 18), SizedBox(width: 6), Text('電話'),
                ]),
              )),
            if ((card.mobilePhone.isNotEmpty || card.phone.isNotEmpty) && card.email.isNotEmpty)
              const SizedBox(width: 12),
            if (card.email.isNotEmpty)
              Expanded(child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: CupertinoColors.systemGrey5,
                onPressed: () => _sendEmail(context, card.email),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(CupertinoIcons.mail_solid, size: 18, color: CupertinoColors.label),
                  SizedBox(width: 6), Text('メール', style: TextStyle(color: CupertinoColors.label)),
                ]),
              )),
          ]),
        ),
        const SizedBox(height: 16),
        CupertinoListSection.insetGrouped(header: const Text('連絡先'), children: [
          _buildInfoTile(icon: CupertinoIcons.phone, label: '携帯電話', value: card.mobilePhone,
              onTap: card.mobilePhone.isNotEmpty ? () => _callPhone(context, card.mobilePhone) : null),
          _buildInfoTile(icon: CupertinoIcons.phone, label: '会社電話', value: card.phone,
              onTap: card.phone.isNotEmpty ? () => _callPhone(context, card.phone) : null),
          _buildInfoTile(icon: CupertinoIcons.printer, label: 'FAX', value: card.fax),
          _buildInfoTile(icon: CupertinoIcons.mail, label: 'メール', value: card.email,
              onTap: card.email.isNotEmpty ? () => _sendEmail(context, card.email) : null),
        ].where((w) => w is! SizedBox).toList()),
        CupertinoListSection.insetGrouped(header: const Text('会社情報'), children: [
          _buildInfoTile(icon: CupertinoIcons.building_2_fill, label: '会社名', value: card.company),
          _buildInfoTile(icon: CupertinoIcons.person_2, label: '部署', value: card.department),
          _buildInfoTile(icon: CupertinoIcons.briefcase, label: '役職', value: card.title),
          _buildInfoTile(icon: CupertinoIcons.location, label: '住所',
              value: card.zipCode.isNotEmpty ? '〒${card.zipCode} ${card.address}' : card.address),
        ].where((w) => w is! SizedBox).toList()),
        if (card.projectCodes.isNotEmpty)
          CupertinoListSection.insetGrouped(header: const Text('関連プロジェクト'), children: [
            CupertinoListTile(
              leading: const Icon(CupertinoIcons.folder, color: CupertinoColors.systemBlue, size: 20),
              title: Text('${card.projectCodes.length}件のプロジェクト'),
              subtitle: Text(card.projectCodes.join('  /  '),
                  style: const TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
              trailing: const CupertinoListTileChevron(),
              onTap: () => _showProjects(context),
            ),
          ]),
        if (card.note.isNotEmpty)
          CupertinoListSection.insetGrouped(header: const Text('備考'), children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(card.note)),
          ]),
        const SizedBox(height: 32),
      ])),
    );
  }
}
