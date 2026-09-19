// ============================================================
// lib/screens/settings_screen.dart
//
// 【役割】
//   個人設定画面。SharedPreferencesに設定を保存。
//
// 【設定項目】
//   - 音声検索待機時間（-10秒〜+10秒）
//   - 表示件数（制限なし/50/100/200/500件）
//   - フォントサイズ（12/14/16/18pt）
//   - テーマカラー（6色から選択）
// ============================================================

import 'package:flutter/cupertino.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _voiceSearchDelay = SettingsService.defaultVoiceSearchDelay;
  int _displayCount = SettingsService.defaultDisplayCount;
  double _fontSize = SettingsService.defaultFontSize;
  String _themeColor = SettingsService.defaultThemeColor;
  bool _isLoading = true;
  bool _saveCardImage = SettingsService.defaultSaveCardImage;

  // テーマカラー選択肢
  static const List<Map<String, String>> _themeColors = [
    {'name': 'ネイビーブルー', 'hex': '#185FA5'},
    {'name': 'ダークグリーン', 'hex': '#1A7A4A'},
    {'name': 'ダークレッド',   'hex': '#A51818'},
    {'name': 'パープル',       'hex': '#6B18A5'},
    {'name': 'ダークオレンジ', 'hex': '#A55C18'},
    {'name': 'ダークグレー',   'hex': '#444444'},
  ];

  // 表示件数選択肢
  static const List<int> _displayCountOptions = [0, 50, 100, 200, 500];

  // フォントサイズ選択肢
  static const List<double> _fontSizeOptions = [12, 14, 16, 18];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final delay     = await SettingsService.getVoiceSearchDelay();
    final count     = await SettingsService.getDisplayCount();
    final size      = await SettingsService.getFontSize();
    final color     = await SettingsService.getThemeColor();
    final saveImage = await SettingsService.getSaveCardImage();
    setState(() {
      _voiceSearchDelay = delay;
      _displayCount     = count;
      _fontSize         = size;
      _themeColor       = color;
      _saveCardImage    = saveImage;
      _isLoading        = false;
    });
  }

  Future<void> _saveSettings() async {
    await SettingsService.setVoiceSearchDelay(_voiceSearchDelay);
    await SettingsService.setDisplayCount(_displayCount);
    await SettingsService.setFontSize(_fontSize);
    await SettingsService.setThemeColor(_themeColor);
    await SettingsService.setSaveCardImage(_saveCardImage);
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('保存しました'),
        content: const Text('設定を保存しました。\n一部の設定はアプリ再起動後に反映されます。'),
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

  // 待機時間の選択肢（-10〜+10秒）
  List<int> get _delayOptions => List.generate(21, (i) => i - 10);

  String _delayLabel(int seconds) {
    if (seconds == 0) return '0秒（即時）';
    if (seconds > 0) return '+$seconds秒';
    return '$seconds秒';
  }

  String _displayCountLabel(int count) =>
      count == 0 ? '制限なし' : '$count件';

  String _fontSizeLabel(double size) => '${size.toInt()}pt';

  void _showPicker<T>({
    required String title,
    required String message,
    required List<T> options,
    required T current,
    required String Function(T) label,
    required void Function(T) onSelect,
  }) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(title),
        message: Text(message),
        actions: options.map((opt) =>
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => onSelect(opt));
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (current == opt)
                  const Icon(CupertinoIcons.checkmark, size: 16,
                      color: CupertinoColors.systemBlue),
                if (current == opt) const SizedBox(width: 8),
                Text(
                  label(opt),
                  style: TextStyle(
                    color: current == opt
                        ? CupertinoColors.systemBlue
                        : CupertinoColors.label,
                    fontWeight: current == opt
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
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

  void _showColorPicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('テーマカラーを選択'),
        actions: _themeColors.map((c) =>
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _themeColor = c['hex']!);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: Color(SettingsService.colorFromHex(c['hex']!)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  c['name']!,
                  style: TextStyle(
                    color: _themeColor == c['hex']
                        ? CupertinoColors.systemBlue
                        : CupertinoColors.label,
                    fontWeight: _themeColor == c['hex']
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                if (_themeColor == c['hex']) ...[
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.checkmark, size: 16,
                      color: CupertinoColors.systemBlue),
                ],
              ],
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

  String get _currentColorName =>
      _themeColors.firstWhere(
        (c) => c['hex'] == _themeColor,
        orElse: () => {'name': 'カスタム'},
      )['name']!;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('設定'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saveSettings,
          child: const Text('保存',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
      child: _isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : SafeArea(
              child: ListView(
                children: [
                  // ── 音声検索 ──
                  CupertinoListSection.insetGrouped(
                    header: const Text('音声検索'),
                    footer: const Text('音声が止まってから検索するまでの待機時間を設定します。'),
                    children: [
                      CupertinoListTile(
                        title: const Text('待機時間'),
                        additionalInfo: Text(
                          _delayLabel(_voiceSearchDelay),
                          style: const TextStyle(
                              color: CupertinoColors.systemBlue),
                        ),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () => _showPicker(
                          title: '音声検索待機時間',
                          message: '音声終了後の待機時間（秒）',
                          options: _delayOptions,
                          current: _voiceSearchDelay,
                          label: _delayLabel,
                          onSelect: (v) => _voiceSearchDelay = v,
                        ),
                      ),
                    ],
                  ),

                  // ── 表示 ──
                  CupertinoListSection.insetGrouped(
                    header: const Text('データ'),
                    footer: const Text('名刺画像を保存するとストレージを使用します（1枚約200〜300KB）。'),
                    children: [
                      CupertinoListTile(
                        title: const Text('名刺画像を保存する'),
                        additionalInfo: Text(
                          _saveCardImage ? 'オン' : 'オフ',
                          style: TextStyle(
                            color: _saveCardImage
                                ? CupertinoColors.systemBlue
                                : CupertinoColors.systemGrey,
                          ),
                        ),
                        trailing: CupertinoSwitch(
                          value: _saveCardImage,
                          onChanged: (val) => setState(() => _saveCardImage = val),
                        ),
                      ),
                    ],
                  ),

                  CupertinoListSection.insetGrouped(
                    header: const Text('表示'),
                    footer: const Text('名刺一覧の表示件数とフォントサイズを設定します。'),
                    children: [
                      CupertinoListTile(
                        title: const Text('表示件数'),
                        additionalInfo: Text(
                          _displayCountLabel(_displayCount),
                          style: const TextStyle(
                              color: CupertinoColors.systemBlue),
                        ),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () => _showPicker(
                          title: '表示件数',
                          message: '名刺一覧に表示する件数',
                          options: _displayCountOptions,
                          current: _displayCount,
                          label: _displayCountLabel,
                          onSelect: (v) => _displayCount = v,
                        ),
                      ),
                      CupertinoListTile(
                        title: const Text('フォントサイズ'),
                        additionalInfo: Text(
                          _fontSizeLabel(_fontSize),
                          style: const TextStyle(
                              color: CupertinoColors.systemBlue),
                        ),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () => _showPicker(
                          title: 'フォントサイズ',
                          message: '名刺一覧のフォントサイズ',
                          options: _fontSizeOptions,
                          current: _fontSize,
                          label: _fontSizeLabel,
                          onSelect: (v) => _fontSize = v,
                        ),
                      ),
                    ],
                  ),

                  // ── テーマ ──
                  CupertinoListSection.insetGrouped(
                    header: const Text('テーマ'),
                    footer: const Text('アプリのテーマカラーを変更します。再起動後に反映されます。'),
                    children: [
                      CupertinoListTile(
                        title: const Text('テーマカラー'),
                        additionalInfo: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 16, height: 16,
                              decoration: BoxDecoration(
                                color: Color(SettingsService
                                    .colorFromHex(_themeColor)),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(_currentColorName,
                                style: const TextStyle(
                                    color: CupertinoColors.systemBlue)),
                          ],
                        ),
                        trailing: const CupertinoListTileChevron(),
                        onTap: _showColorPicker,
                      ),
                    ],
                  ),

                  // ── アプリ情報 ──
                  CupertinoListSection.insetGrouped(
                    header: const Text('アプリ情報'),
                    children: [
                      const CupertinoListTile(
                        title: Text('アプリ名'),
                        additionalInfo: Text('Business card hirokino',
                            style: TextStyle(
                                color: CupertinoColors.systemGrey)),
                      ),
                      const CupertinoListTile(
                        title: Text('バージョン'),
                        additionalInfo: Text('0.9.0',
                            style: TextStyle(
                                color: CupertinoColors.systemGrey)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
