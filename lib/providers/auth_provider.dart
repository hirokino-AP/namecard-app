// lib/providers/auth_provider.dart
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'card_provider.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;
  AuthStatus _status = AuthStatus.unknown;
  bool _isLoading = false;
  String _errorMessage = '';

  User? get user => _user;
  AuthStatus get status => _status;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get hasError => _errorMessage.isNotEmpty;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  String get uid => _user?.uid ?? '';
  String get email => _user?.email ?? '';

  AuthProvider() {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      _status = user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      notifyListeners();
    });
  }

  Future<bool> signIn({required String email, required String password}) async {
    _setLoading(true);
    _clearError();
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _convertErrorMessage(e.code);
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'ログインに失敗しました: $e';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> signUp({required String email, required String password}) async {
    _setLoading(true);
    _clearError();
    try {
      await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _convertErrorMessage(e.code);
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'アカウント登録に失敗しました: $e';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut(CardProvider cardProvider) async {
    _setLoading(true);
    try {
      cardProvider.clearAll();
      await _auth.signOut();
    } catch (e) {
      _errorMessage = 'ログアウトに失敗しました: $e';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> sendPasswordResetEmail(String email) async {
    _setLoading(true);
    _clearError();
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _convertErrorMessage(e.code);
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void clearError() { _clearError(); notifyListeners(); }

  String _convertErrorMessage(String code) {
    switch (code) {
      case 'user-not-found': return 'メールアドレスが登録されていません';
      case 'wrong-password': return 'パスワードが正しくありません';
      case 'invalid-email': return 'メールアドレスの形式が正しくありません';
      case 'user-disabled': return 'このアカウントは無効化されています';
      case 'email-already-in-use': return 'このメールアドレスはすでに使用されています';
      case 'weak-password': return 'パスワードは6文字以上で設定してください';
      case 'too-many-requests': return 'しばらく待ってから再試行してください';
      case 'network-request-failed': return 'ネットワークエラーが発生しました';
      case 'invalid-credential': return 'メールアドレスまたはパスワードが正しくありません';
      default: return '認証エラーが発生しました（$code）';
    }
  }

  void _setLoading(bool value) { _isLoading = value; notifyListeners(); }
  void _clearError() { _errorMessage = ''; }
}
