// lib/screens/card_edit_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../models/business_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';

class CardEditScreen extends StatefulWidget {
  final BusinessCard? card;
  const CardEditScreen({super.key, this.card});
  @override
  State<CardEditScreen> createState() => _CardEditScreenState();
}

class _CardEditScreenState extends State<CardEditScreen> {
  late final TextEditingController _name, _nameKana, _company, _companyKana,
      _department, _title, _email, _phone, _mobilePhone, _fax,
      _zipCode, _address, _note, _projectCodes;

  bool get _isEditing => widget.card != null;

  @override
  void initState() {
    super.initState();
    final c = widget.card;
    _name         = TextEditingController(text: c?.name         ?? '');
    _nameKana     = TextEditingController(text: c?.nameKana     ?? '');
    _company      = TextEditingController(text: c?.company      ?? '');
    _companyKana  = TextEditingController(text: c?.companyKana  ?? '');
    _department   = TextEditingController(text: c?.department   ?? '');
    _title        = TextEditingController(text: c?.title        ?? '');
    _email        = TextEditingController(text: c?.email        ?? '');
    _phone        = TextEditingController(text: c?.phone        ?? '');
    _mobilePhone  = TextEditingController(text: c?.mobilePhone  ?? '');
    _fax          = TextEditingController(text: c?.fax          ?? '');
    _zipCode      = TextEditingController(text: c?.zipCode      ?? '');
    _address      = TextEditingController(text: c?.address      ?? '');
    _note         = TextEditingController(text: c?.note         ?? '');
    _projectCodes = TextEditingController(text: c?.projectCodes.join(',') ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name,_nameKana,_company,_companyKana,_department,
      _title,_email,_phone,_mobilePhone,_fax,_zipCode,_address,_note,_projectCodes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) { _showAlert('入力エラー', '氏名は必須です'); return; }
    final uid = context.read<AuthProvider>().uid;
    final provider = context.read<CardProvider>();
    final codes = _projectCodes.text.split(',')
        .map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (_isEditing) {
      await provider.updateCard(widget.card!.copyWith(
        name:_name.text.trim(), nameKana:_nameKana.text.trim(),
        company:_company.text.trim(), companyKana:_companyKana.text.trim(),
        department:_department.text.trim(), title:_title.text.trim(),
        email:_email.text.trim(), phone:_phone.text.trim(),
        mobilePhone:_mobilePhone.text.trim(), fax:_fax.text.trim(),
        zipCode:_zipCode.text.trim(), address:_address.text.trim(),
        note:_note.text.trim(), projectCodes:codes, updatedAt:DateTime.now(),
      ));
    } else {
      await provider.addCard(BusinessCard.create(
        userId:uid, name:_name.text.trim(), nameKana:_nameKana.text.trim(),
        company:_company.text.trim(), companyKana:_companyKana.text.trim(),
        department:_department.text.trim(), title:_title.text.trim(),
        email:_email.text.trim(), phone:_phone.text.trim(),
        mobilePhone:_mobilePhone.text.trim(), fax:_fax.text.trim(),
        zipCode:_zipCode.text.trim(), address:_address.text.trim(),
        note:_note.text.trim(), projectCodes:codes,
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _showAlert(String title, String message) {
    showCupertinoDialog(context: context,
        builder: (_) => CupertinoAlertDialog(title: Text(title), content: Text(message),
            actions: [CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))]));
  }

  Widget _buildField({required String label, required TextEditingController controller,
      TextInputType keyboardType = TextInputType.text, String? placeholder}) {
    return CupertinoTextFormFieldRow(
      controller: controller,
      prefix: SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 14))),
      placeholder: placeholder ?? label,
      keyboardType: keyboardType,
      autocorrect: false,
      style: const TextStyle(fontSize: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<CardProvider>().isLoading;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_isEditing ? '名刺を編集' : '名刺を追加'),
        leading: CupertinoButton(padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
        trailing: CupertinoButton(padding: EdgeInsets.zero,
            onPressed: isLoading ? null : _save,
            child: isLoading ? const CupertinoActivityIndicator()
                : const Text('保存', style: TextStyle(fontWeight: FontWeight.bold))),
      ),
      child: SafeArea(child: ListView(children: [
        CupertinoListSection.insetGrouped(header: const Text('基本情報'), children: [
          _buildField(label: '氏名', controller: _name),
          _buildField(label: 'よみがな', controller: _nameKana),
        ]),
        CupertinoListSection.insetGrouped(header: const Text('会社情報'), children: [
          _buildField(label: '会社名', controller: _company),
          _buildField(label: '会社名かな', controller: _companyKana),
          _buildField(label: '部署', controller: _department),
          _buildField(label: '役職', controller: _title),
        ]),
        CupertinoListSection.insetGrouped(header: const Text('連絡先'), children: [
          _buildField(label: '携帯電話', controller: _mobilePhone, keyboardType: TextInputType.phone),
          _buildField(label: '会社電話', controller: _phone, keyboardType: TextInputType.phone),
          _buildField(label: 'FAX', controller: _fax, keyboardType: TextInputType.phone),
          _buildField(label: 'メール', controller: _email, keyboardType: TextInputType.emailAddress),
        ]),
        CupertinoListSection.insetGrouped(header: const Text('住所'), children: [
          _buildField(label: '郵便番号', controller: _zipCode, keyboardType: TextInputType.number),
          _buildField(label: '住所', controller: _address),
        ]),
        CupertinoListSection.insetGrouped(
          header: const Text('関連プロジェクト'),
          footer: const Text('プロジェクトコードをカンマ区切りで入力\n例: PHR-CYCLE,CHASE'),
          children: [_buildField(label: 'PJコード', controller: _projectCodes,
              placeholder: 'PHR-CYCLE,CHASE')],
        ),
        CupertinoListSection.insetGrouped(header: const Text('備考'), children: [
          Padding(padding: const EdgeInsets.all(12),
              child: CupertinoTextField(controller: _note, placeholder: '備考・メモを入力',
                  maxLines: 5, minLines: 3, decoration: null)),
        ]),
        const SizedBox(height: 32),
      ])),
    );
  }
}
