// lib/screens/card_list_screen.dart
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show CircleAvatar, RefreshIndicator, Scrollbar, Theme, ThemeData, ScrollbarThemeData, WidgetStateProperty;
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/business_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import 'card_detail_screen.dart';
import 'card_edit_screen.dart';

class CardListScreen extends StatefulWidget {
  const CardListScreen({super.key});
  @override
  State<CardListScreen> createState() => _CardListScreenState();
}

class _CardListScreenState extends State<CardListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  Timer? _debounce;
  List<String> _departmentDict = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCards();
      await _initSpeech();
      await _buildDepartmentDict();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: (e) => setState(() => _isListening = false),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') setState(() => _isListening = false);
      },
    );
    setState(() => _speechAvailable = available);
  }

  Future<void> _buildDepartmentDict() async {
    final cards = context.read<CardProvider>().cards;
    final depts = cards
        .map((c) => c.department.trim())
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();
    depts.sort((a, b) => b.length.compareTo(a.length));
    setState(() => _departmentDict = depts);
  }

  // 編集距離（レーベンシュタイン距離）
  int _editDistance(String a, String b) {
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (i) => List.filled(n + 1, 0));
    for (int i = 0; i <= m; i++) dp[i][0] = i;
    for (int j = 0; j <= n; j++) dp[0][j] = j;
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = 1 + [dp[i-1][j], dp[i][j-1], dp[i-1][j-1]].reduce((a, b) => a < b ? a : b);
        }
      }
    }
    return dp[m][n];
  }

  // 類似部署名を候補として返す
  List<String> _findSimilarDepts(String token) {
    if (token.isEmpty || _departmentDict.isEmpty) return [];
    final threshold = (token.length * 0.5).ceil().clamp(1, 3);
    final candidates = _departmentDict.where((dept) {
      final dist = _editDistance(token, dept);
      return dist <= threshold && dist > 0;
    }).toList();
    candidates.sort((a, b) => _editDistance(token, a).compareTo(_editDistance(token, b)));
    return candidates.take(3).toList();
  }

  // 「もしかして？」候補提示
  void _showSuggestions(List<String> candidates, String original) {
    if (candidates.isEmpty || !mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('もしかして？'),
        content: Text('「$original」の候補:'),
        actions: [
          ...candidates.map((dept) => CupertinoDialogAction(
            onPressed: () {
              Navigator.of(context).pop();
              _searchController.text = dept;
              _onSearchChanged(dept);
            },
            child: Text(dept),
          )),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('そのまま検索'),
          ),
        ],
      ),
    );
  }

  String _normalizeVoiceInput(String text) {
    String result = text.trim();
    final tokens = result.split(RegExp(r'[\s\u3000]+'));
    final normalized = tokens.map((t) {
      return t.replaceAll(RegExp(r'さん$'), '').replaceAll(RegExp(r'様$'), '').trim();
    }).where((t) => t.isNotEmpty).toList();
    return normalized.join(' ');
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      _showAlert('音声認識が使えません', 'マイクのアクセスを許可してください。');
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: 'ja_JP'),
      onResult: (result) {
        if (result.finalResult) {
          final raw = result.recognizedWords;
          final normalized = _normalizeVoiceInput(raw);
          _searchController.text = normalized;
          _onSearchChanged(normalized);
          setState(() => _isListening = false);
          // 部署名候補提示
          final tokens = normalized.split(RegExp(r'[\s\u3000]+')).where((t) => t.isNotEmpty).toList();
          for (final tok in tokens) {
            final candidates = _findSimilarDepts(tok);
            if (candidates.isNotEmpty && !_departmentDict.contains(tok)) {
              _showSuggestions(candidates, tok);
              break;
            }
          }
        }
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _loadCards() async {
    final uid = context.read<AuthProvider>().uid;
    await context.read<CardProvider>().loadCards(uid);
  }

  Future<void> _importFromItunes() async {
    const channel = MethodChannel('com.hirokino.namecardapp/document_picker');
    final String? json = await channel.invokeMethod('pickDatabase');
    if (json == null || !mounted) return;
    final uid = context.read<AuthProvider>().uid;
    final count = await context.read<CardProvider>().importFromJson(json, uid);
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('インポート完了'),
        content: Text('$count件の名刺をインポートしました。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () { Navigator.of(context).pop(); _loadCards(); },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String keyword) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final uid = context.read<AuthProvider>().uid;
      context.read<CardProvider>().search(uid, keyword);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    context.read<CardProvider>().clearSearch();
  }

  Future<void> _importCsv() async {
    final uid = context.read<AuthProvider>().uid;
    final result = await context.read<CardProvider>().importFromCsv(uid);
    if (!mounted) return;
    if (result['cancelled'] == 1) return;
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
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
  }

  void _showAlert(String title, String message) {
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

  Widget _buildCardItem(BusinessCard card) {
    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: CircleAvatar(
        backgroundColor: CupertinoColors.systemBlue.withValues(alpha: 0.15),
        child: Text(
          card.name.isNotEmpty ? card.name[0] : '?',
          style: const TextStyle(color: CupertinoColors.systemBlue, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(card.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (card.company.isNotEmpty)
          Text(card.company,
              style: const TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 13)),
        if (card.department.isNotEmpty)
          Text(card.department,
              style: const TextStyle(color: CupertinoColors.tertiaryLabel, fontSize: 12),
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
      onTap: () => Navigator.of(context).push(
          CupertinoPageRoute(builder: (_) => CardDetailScreen(card: card))),
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
            onPressed: _importFromItunes,
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
          child: Row(children: [
            Expanded(
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: '氏名 会社名 部署（スペースでAND検索）',
                onChanged: _onSearchChanged,
                onSuffixTap: _clearSearch,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isListening ? _stopListening : _startListening,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isListening
                      ? CupertinoColors.systemRed.withValues(alpha: 0.15)
                      : CupertinoColors.systemBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  _isListening ? CupertinoIcons.stop_circle : CupertinoIcons.mic,
                  size: 24,
                  color: _isListening ? CupertinoColors.systemRed : CupertinoColors.systemBlue,
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            if (_isListening)
              const Row(children: [
                CupertinoActivityIndicator(radius: 8),
                SizedBox(width: 6),
                Text('聞いています...', style: TextStyle(color: CupertinoColors.systemRed, fontSize: 12)),
              ])
            else
              Text(
                isSearching ? '検索結果: ${cards.length}件' : '全$total件',
                style: const TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 12),
              ),
          ]),
        ),
        Expanded(child: isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : cards.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(CupertinoIcons.person_crop_rectangle,
                        size: 60, color: CupertinoColors.secondaryLabel),
                    const SizedBox(height: 16),
                    Text(
                      isSearching ? '該当する名刺が見つかりません'
                          : '名刺がまだありません\n右上の＋から追加してください',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: CupertinoColors.secondaryLabel),
                    ),
                  ]))
                : Theme(
                    data: ThemeData(
                      scrollbarTheme: ScrollbarThemeData(
                        thumbVisibility: WidgetStateProperty.all(true),
                        thickness: WidgetStateProperty.all(4),
                      ),
                    ),
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      thickness: 4,
                      child: RefreshIndicator.adaptive(
                        onRefresh: _loadCards,
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: cards.length,
                          itemBuilder: (context, index) => _buildCardItem(cards[index]),
                        ),
                      ),
                    ),
                  )),
      ])),
    );
  }
}
