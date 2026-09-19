// lib/screens/card_edit_screen.dart
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/business_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../services/ocr_service.dart';
import '../db/database_helper.dart';
import '../services/industry_service.dart';
import '../services/settings_service.dart';
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
  late final FocusNode _nameFocusNode;     // 氏名フィールドのフォーカス監視用
  late final FocusNode _companyFocusNode;  // 会社名フィールドのフォーカス監視用
  List<BusinessCard> _duplicates = [];     // 重複候補リスト
  String? _scannedImagePath;               // スキャン済み画像パス
  String _industry = '';                   // 業種（28業種分類）

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
    _industry = widget.card?.industry ?? '';

    // 氏名フィールドのフォーカスアウト時によみがなを自動補完＆重複チェック
    _nameFocusNode = FocusNode();
    _nameFocusNode.addListener(() {
      if (!_nameFocusNode.hasFocus && _name.text.isNotEmpty) {
        if (_nameKana.text.isEmpty) _autoFillNameKana(_name.text);
        _checkDuplicate();
      }
    });

    // 会社名フィールドのフォーカスアウト時によみがなを自動補完＆重複チェック
    _companyFocusNode = FocusNode();
    _companyFocusNode.addListener(() {
      if (!_companyFocusNode.hasFocus && _company.text.isNotEmpty) {
        if (_companyKana.text.isEmpty) _autoFillCompanyKana(_company.text);
        _checkDuplicate();
        _autoDetectIndustry();
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_name,_nameKana,_company,_companyKana,_department,
      _title,_email,_phone,_mobilePhone,_fax,_zipCode,_address,_note,_projectCodes]) {
      c.dispose();
    }
    _nameFocusNode.dispose();
    _companyFocusNode.dispose();
    super.dispose();
  }

  // 業種自動判定（会社名・部署名から28業種を判定）
  void _autoDetectIndustry() {
    if (_industry.isNotEmpty) return; // 既に設定済みの場合はスキップ
    final detected = IndustryService.detect(_company.text, _department.text);
    setState(() => _industry = detected);
  }

  // 重複チェック（氏名・会社名でDBを検索）
  Future<void> _checkDuplicate() async {
    if (_name.text.isEmpty) return;
    final uid = context.read<AuthProvider>().uid;
    final results = await DatabaseHelper.instance.searchByNameAndCompany(
      userId: uid,
      name: _name.text.trim(),
      company: _company.text.trim(),
    );
    // 編集中のカード自身は除外
    final filtered = results.where((c) => c.id != widget.card?.id).toList();
    if (!mounted) return;
    setState(() => _duplicates = filtered);
  }

  // 氏名からよみがなをDBで自動補完
  Future<void> _autoFillNameKana(String name) async {
    final uid = context.read<AuthProvider>().uid;
    // DBから同じ氏名のよみがなを検索
    final cards = await DatabaseHelper.instance.searchByNameAndCompany(
      userId: uid, name: name);
    if (cards.isNotEmpty && cards.first.nameKana.isNotEmpty && mounted) {
      setState(() => _nameKana.text = cards.first.nameKana);
    }
  }

  // 会社名からよみがなをDBで自動補完
  Future<void> _autoFillCompanyKana(String company) async {
    final uid = context.read<AuthProvider>().uid;
    final kana = await DatabaseHelper.instance.getCompanyKana(uid, company);
    if (kana.isNotEmpty && mounted) {
      setState(() => _companyKana.text = kana);
    }
  }

  Future<void> _scanBusinessCard() async {
    // スキャン方法を選択
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('名刺を読み取る'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () { Navigator.of(context).pop(); _scanWithVisionKit(); },
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(CupertinoIcons.doc_text_viewfinder, size: 20),
              SizedBox(width: 8),
              Text('スキャン（斜め補正あり）'),
            ]),
          ),
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

  // VisionKitでスキャン（台形補正・斜め補正）
  Future<void> _scanWithVisionKit() async {
    const channel = MethodChannel('com.hirokino.namecardapp/document_picker');
    setState(() => _isOcrLoading = true);
    try {
      final String? filePath = await channel.invokeMethod('scanDocument');
      if (filePath == null || !mounted) {
        setState(() => _isOcrLoading = false);
        return;
      }
      // スキャン済み画像をOCRにかける
      final file = File(filePath);
      final result = await OcrService.recognizeBusinessCard(file);
      final lines = OcrService.lastLines;
      if (!mounted) return;

      // 設定で画像保存がオンの場合のみパスを保存
      final saveImage = await SettingsService.getSaveCardImage();
      setState(() {
        _isOcrLoading = false;
        _scannedImagePath = saveImage ? filePath : null;
      });
      final reviewed = await Navigator.of(context).push<Map<String, String>>(
        CupertinoPageRoute(
          builder: (_) => OcrReviewScreen(
            lines: lines,
            autoResult: result,
            userId: context.read<AuthProvider>().uid,
          ),
        ),
      );
      if (reviewed != null && mounted) {
        _applyOcrResult(reviewed);
      }
    } catch (e) {
      if (mounted) _showAlert('エラー', 'スキャンに失敗しました: \$e');
      if (mounted) setState(() => _isOcrLoading = false);
    }
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
    // OCR結果セット後にDBからよみがなを自動補完
    if (_nameKana.text.isEmpty && _name.text.isNotEmpty) {
      _autoFillNameKana(_name.text);
    }
    if (_companyKana.text.isEmpty && _company.text.isNotEmpty) {
      _autoFillCompanyKana(_company.text);
    }
    // 重複チェック
    _checkDuplicate();
    // 業種自動判定
    _autoDetectIndustry();
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
        note:_note.text.trim(), industry:_industry,
        projectCodes:codes, updatedAt:DateTime.now(),
      ));
    } else {
      await provider.addCard(BusinessCard.create(
        userId:uid, name:_name.text.trim(), nameKana:_nameKana.text.trim(),
        company:_company.text.trim(), companyKana:_companyKana.text.trim(),
        department:_department.text.trim(), title:_title.text.trim(),
        email:_email.text.trim(), phone:_phone.text.trim(),
        mobilePhone:_mobilePhone.text.trim(), fax:_fax.text.trim(),
        zipCode:_zipCode.text.trim(), address:_address.text.trim(),
        note:_note.text.trim(), industry:_industry,
        imagePath:_scannedImagePath, projectCodes:codes,
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  // 業種選択ピッカー
  // 画像フルスクリーン表示（ズーム可能）
  void _showImageFullScreen() {
    if (_scannedImagePath == null) return;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: CupertinoColors.black,
          child: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Image.file(File(_scannedImagePath!)),
            ),
          ),
        ),
      ),
    );
  }

  void _showIndustryPicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('業種を選択'),
        actions: IndustryService.industries.map((industry) =>
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _industry = industry);
            },
            child: Text(
              industry,
              style: TextStyle(
                color: _industry == industry
                    ? CupertinoColors.systemBlue
                    : CupertinoColors.label,
                fontWeight: _industry == industry
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
      ),
    );
  }

  void _showAlert(String title, String message) {
    showCupertinoDialog(context: context,
        builder: (_) => CupertinoAlertDialog(title: Text(title), content: Text(message),
            actions: [CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))]));
  }

  Widget _buildField({required String label, required TextEditingController controller,
      TextInputType keyboardType = TextInputType.text, String? placeholder,
      FocusNode? focusNode}) {
    return CupertinoTextFormFieldRow(
      controller: controller,
      focusNode: focusNode,
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
        // スキャン済み画像プレビュー
        if (_scannedImagePath != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: _showImageFullScreen,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_scannedImagePath!),
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
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
        // 重複警告表示
        if (_duplicates.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CupertinoColors.systemYellow.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: CupertinoColors.systemYellow),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(CupertinoIcons.exclamationmark_triangle, color: CupertinoColors.systemOrange, size: 16),
                  SizedBox(width: 6),
                  Text('同じ名前の方が登録されています', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: CupertinoColors.systemOrange)),
                ]),
                const SizedBox(height: 6),
                ..._duplicates.map((c) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('・${c.name}（${c.company}）', style: const TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
                )),
              ],
            ),
          ),
        CupertinoListSection.insetGrouped(header: const Text('基本情報'), children: [
          _buildField(label: '氏名', controller: _name, focusNode: _nameFocusNode),
          _buildField(label: 'よみがな', controller: _nameKana),
        ]),
        CupertinoListSection.insetGrouped(header: const Text('会社情報'), children: [
          _buildField(label: '会社名', controller: _company, focusNode: _companyFocusNode),
          _buildField(label: '会社名かな', controller: _companyKana),
          _buildField(label: '部署', controller: _department),
          _buildField(label: '役職', controller: _title),
          // 業種選択（28業種）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 100, child: Text('業種', style: const TextStyle(fontSize: 14))),
                Expanded(
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _showIndustryPicker,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _industry.isEmpty ? '業種を選択' : _industry,
                            style: TextStyle(
                              fontSize: 14,
                              color: _industry.isEmpty
                                  ? CupertinoColors.placeholderText
                                  : CupertinoColors.label,
                            ),
                          ),
                        ),
                        const Icon(CupertinoIcons.chevron_down, size: 14, color: CupertinoColors.systemGrey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
