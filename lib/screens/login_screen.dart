// lib/screens/login_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final email    = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showAlert('入力エラー', 'メールアドレスとパスワードを入力してください');
      return;
    }
    bool success = _isSignUp
        ? await auth.signUp(email: email, password: password)
        : await auth.signIn(email: email, password: password);
    if (!success && mounted) _showAlert('エラー', auth.errorMessage);
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showAlert('確認', 'メールアドレスを入力してからタップしてください');
      return;
    }
    final auth = context.read<AuthProvider>();
    final success = await auth.sendPasswordResetEmail(email);
    if (mounted) { _showAlert(
      success ? '送信完了' : 'エラー',
      success ? 'パスワードリセットメールを送信しました' : auth.errorMessage,
    ); }
  }

  void _showAlert(String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(title), content: Text(message),
        actions: [CupertinoDialogAction(
          child: const Text('OK'),
          onPressed: () => Navigator.of(context).pop(),
        )],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(CupertinoIcons.person_crop_rectangle,
                  size: 72, color: CupertinoColors.systemBlue),
              const SizedBox(height: 16),
              Text('名刺管理', textAlign: TextAlign.center,
                  style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle),
              const SizedBox(height: 8),
              Text(_isSignUp ? 'アカウントを作成' : 'ログイン',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 16)),
              const SizedBox(height: 40),
              CupertinoTextField(
                controller: _emailController,
                placeholder: 'メールアドレス',
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                prefix: const Padding(padding: EdgeInsets.only(left: 12),
                    child: Icon(CupertinoIcons.mail,
                        color: CupertinoColors.secondaryLabel, size: 20)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(color: CupertinoColors.systemBackground,
                    borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _passwordController,
                placeholder: 'パスワード（6文字以上）',
                obscureText: _obscurePassword,
                prefix: const Padding(padding: EdgeInsets.only(left: 12),
                    child: Icon(CupertinoIcons.lock,
                        color: CupertinoColors.secondaryLabel, size: 20)),
                suffix: CupertinoButton(
                  padding: const EdgeInsets.only(right: 8),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  child: Icon(_obscurePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                      color: CupertinoColors.secondaryLabel, size: 20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(color: CupertinoColors.systemBackground,
                    borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(height: 24),
              CupertinoButton.filled(
                onPressed: auth.isLoading ? null : _submit,
                child: auth.isLoading
                    ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                    : Text(_isSignUp ? 'アカウントを作成' : 'ログイン'),
              ),
              const SizedBox(height: 16),
              CupertinoButton(
                onPressed: () {
                  setState(() => _isSignUp = !_isSignUp);
                  context.read<AuthProvider>().clearError();
                },
                child: Text(_isSignUp ? 'すでにアカウントをお持ちの方はこちら' : 'アカウントを新規作成',
                    style: const TextStyle(fontSize: 14)),
              ),
              if (!_isSignUp)
                CupertinoButton(
                  onPressed: auth.isLoading ? null : _resetPassword,
                  child: const Text('パスワードをお忘れの方',
                      style: TextStyle(fontSize: 13, color: CupertinoColors.secondaryLabel)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
