import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

enum AuthStatus { checking, unauthenticated, authenticating, authenticated }

/// Owns the session state and drives the login screen.
class AuthState extends ChangeNotifier {
  final ApiService api;

  AuthState(this.api);

  AuthStatus status = AuthStatus.checking;
  String? error;

  Future<void> init() async {
    await api.loadToken();
    status = api.isAuthenticated
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      error = '请输入账号和密码';
      notifyListeners();
      return false;
    }
    status = AuthStatus.authenticating;
    error = null;
    notifyListeners();
    try {
      await api.login(username.trim(), password);
      status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    } catch (e) {
      error = '$e';
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await api.logout();
    status = AuthStatus.unauthenticated;
    error = null;
    notifyListeners();
  }

  /// Called by [ApiService] when the server rejects the stored token.
  void handleUnauthorized() {
    if (status == AuthStatus.authenticated) {
      status = AuthStatus.unauthenticated;
      error = '登录已失效，请重新登录';
      notifyListeners();
    }
  }
}
