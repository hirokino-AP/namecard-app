// ============================================================
// lib/main.dart
//
// 【役割】
//   アプリのエントリポイント。以下を担当：
//   1. Firebase初期化
//   2. Provider設定（AuthProvider・CardProvider）
//   3. URLスキーム処理（namecard://call?name=&company=&todoId=）
//   4. 認証状態に応じた画面ルーティング
//
// 【画面ルーティング】
//   AuthStatus.unknown        → ローディング画面
//   AuthStatus.authenticated  → CardListScreen（名刺一覧）
//   AuthStatus.unauthenticated→ LoginScreen（ログイン）
//
// 【URLスキーム】
//   外部アプリ（Todoアプリ）からの呼び出しを処理
//   namecard://call?name=山田太郎&company=株式会社XX&todoId=123
//   → 名刺検索 → CallResultScreenに遷移
// ============================================================
// lib/main.dart
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/auth_provider.dart';
import 'providers/card_provider.dart';
import 'services/url_scheme_service.dart';
import 'services/settings_service.dart';
import 'screens/login_screen.dart';
import 'screens/card_list_screen.dart';
import 'screens/call_result_screen.dart';
import 'firebase_options.dart'; // FlutterFire CLI実行後にコメント解除

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // FlutterFire CLI実行後にコメント解除
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CardProvider()),
      ],
      child: const NamecardApp(),
    ),
  );
}

class NamecardApp extends StatefulWidget {
  const NamecardApp({super.key});
  @override
  State<NamecardApp> createState() => _NamecardAppState();
}

class _NamecardAppState extends State<NamecardApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  Color _themeColor = const Color(0xFF185FA5); // デフォルト：Navy Blue

  @override
  void initState() {
    super.initState();
    _initUrlScheme();
    _loadThemeColor();
  }

  // 設定からテーマカラーを読み込む
  Future<void> _loadThemeColor() async {
    final colorHex = await SettingsService.getThemeColor();
    final colorValue = SettingsService.colorFromHex(colorHex);
    setState(() => _themeColor = Color(colorValue));
  }

  // テーマカラーの明度から文字色を決定（暗色→白、明色→黒）
  Color get _contrastColor {
    final r = _themeColor.red;
    final g = _themeColor.green;
    final b = _themeColor.blue;
    final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance > 0.5 ? CupertinoColors.black : CupertinoColors.white;
  }

  void _initUrlScheme() {
    final urlService = UrlSchemeService.instance;
    urlService.onCallRequest = _handleCallRequest;
    urlService.initialize();
  }

  Future<void> _handleCallRequest(CallRequest request) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) return;
    final cardProvider = context.read<CardProvider>();
    final results = await cardProvider.searchForCall(
        userId: authProvider.uid, name: request.name, company: request.company);
    if (!mounted) return;
    if (results.isEmpty) {
      showCupertinoDialog(
        context: _navigatorKey.currentContext!,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('名刺が見つかりません'),
          content: Text('「${request.name}」（${request.company}）に一致する名刺が見つかりませんでした'),
          actions: [CupertinoDialogAction(
              onPressed: () => Navigator.of(_navigatorKey.currentContext!).pop(),
              child: const Text('OK'))],
        ),
      );
      return;
    }
    if (results.length == 1) {
      _navigatorKey.currentState?.push(CupertinoPageRoute(
          builder: (_) => CallResultScreen(card: results.first, todoId: request.todoId)));
    } else {
      showCupertinoModalPopup(
        context: _navigatorKey.currentContext!,
        builder: (_) => CupertinoActionSheet(
          title: const Text('名刺を選択'),
          message: Text('「${request.name}」で${results.length}件見つかりました'),
          actions: results.map((card) => CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(_navigatorKey.currentContext!).pop();
              _navigatorKey.currentState?.push(CupertinoPageRoute(
                  builder: (_) => CallResultScreen(card: card, todoId: request.todoId)));
            },
            child: Column(children: [
              Text(card.name),
              Text(card.company, style: const TextStyle(
                  fontSize: 12, color: CupertinoColors.secondaryLabel)),
            ]),
          )).toList(),
          cancelButton: CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(_navigatorKey.currentContext!).pop(),
              child: const Text('キャンセル')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      navigatorKey: _navigatorKey,
      title: '名刺管理',
      theme: CupertinoThemeData(
          primaryColor: _themeColor,
          barBackgroundColor: _themeColor,
          primaryContrastingColor: _contrastColor,
          brightness: Brightness.light),
      home: const _RootScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _RootScreen extends StatelessWidget {
  const _RootScreen();
  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthProvider>().status;
    switch (status) {
      case AuthStatus.unknown:
        return const CupertinoPageScaffold(
            child: Center(child: CupertinoActivityIndicator()));
      case AuthStatus.authenticated:
        return const CardListScreen();
      case AuthStatus.unauthenticated:
        return const LoginScreen();
    }
  }
}
