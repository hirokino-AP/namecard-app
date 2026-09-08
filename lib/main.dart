// lib/main.dart
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/auth_provider.dart';
import 'providers/card_provider.dart';
import 'services/url_scheme_service.dart';
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

  @override
  void initState() {
    super.initState();
    _initUrlScheme();
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
      theme: const CupertinoThemeData(
          primaryColor: CupertinoColors.systemBlue, brightness: Brightness.light),
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
