// lib/screens/card_edit_screen.dart
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/business_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../services/ocr_service.dart';
import 'ocr_review_screen.dart';

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
  bool _isOcrLoading = false;

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

  Future<void> _scanBusinessCard() async {
    // カメラかギャラリーか選択
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('名刺を読み取る'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () { Navigator.of(context).pop(); _pickImage(ImageSource.camera); },
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(CupertinoIcons.camera, size: 20),
              SizedBox(width: 8),
              Text('カメラで撮影'),
            ]),
          ),
          CupertinoActionSheetAction(
            onPressed: () { Navigator.of(context).pop(); _pickImage(ImageSource.gallery); },
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(CupertinoIcons.photo, size: 20),
              SizedBox(width: 8),
              Text('写真ライブラリから選択'),
            ]),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    setState(() => _isOcrLoading = true);
    try {
      final file = File(picked.path);
      final result = await OcrService.recognizeBusinessCard(file);
      final lines = OcrService.lastLines;
      if (!mounted) return;
      setState(() => _isOcrLoading = false);
      // OcrReviewScreenに遷移
      final reviewed = await Navigator.of(context).push<Map<String, String>>(
        CupertinoPageRoute(
          builder: (_) => OcrReviewScreen(lines: lines, autoResult: result, userId: context.read<AuthProvider>().uid),
        ),
      );
      if (reviewed != null && mounted) {
        _applyOcrResult(reviewed);
      }
    } catch (e) {
      if (mounted) _showAlert('エラー', 'OCR読み取りに失敗しました: $e');
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  void _applyOcrResult(Map<String, String> result) {
    setState(() {
      if (result['name']!.isNotEmpty) _name.text = result['name']!;
      if (result['company']!.isNotEmpty) _company.text = result['company']!;
      if (result['department']!.isNotEmpty) _department.text = result['department']!;
      if (result['title']!.isNotEmpty) _title.text = result['title']!;
      if (result['email']!.isNotEmpty) _email.text = result['email']!;
      if (result['phone']!.isNotEmpty) _phone.text = result['phone']!;
      if (result['mobilePhone']!.isNotEmpty) _mobilePhone.text = result['mobilePhone']!;
      if (result['fax']!.isNotEmpty) _fax.text = result['fax']!;
      if (result['zipCode']!.isNotEmpty) _zipCode.text = result['zipCode']!;
      if (result['address']!.isNotEmpty) _address.text = result['address']!;
    });
    final raw = result.values.where((v) => v.isNotEmpty).join('\n');
    _showAlert('読み取り結果', raw.isEmpty ? '何も読み取れませんでした。\n(APIは正常に応答しました)' : raw);
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
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _isOcrLoading ? null : _scanBusinessCard,
            child: _isOcrLoading
                ? const CupertinoActivityIndicator()
                : const Icon(CupertinoIcons.camera, size: 24),
          ),
          CupertinoButton(padding: EdgeInsets.zero,
              onPressed: isLoading ? null : _save,
              child: isLoading ? const CupertinoActivityIndicator()
                  : const Text('保存', style: TextStyle(fontWeight: FontWeight.bold))),
        ]),
      ),
      child: SafeArea(child: ListView(children: [
        // OCR読み取り中インジケーター
        if (_isOcrLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              CupertinoActivityIndicator(),
              SizedBox(width: 8),
              Text('名刺を読み取っています...', style: TextStyle(color: CupertinoColors.secondaryLabel)),
            ]),
          ),
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
