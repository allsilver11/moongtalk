import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => ApiService.isLoggedIn;
  String? get error => _error;

  Future<void> init() async {
    await ApiService.init();
    if (ApiService.isLoggedIn) {
      await loadProfile();
      WebSocketService.instance.connect();
    }
  }

  Future<bool> sendCode(String phone) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await ApiService.sendCode(phone);
      _isLoading = false;
      if (result['error'] != null) {
        _error = result['error'];
        notifyListeners();
        return false;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyCode(String phone, String code) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await ApiService.verifyCode(phone, code);
      _isLoading = false;
      if (result['error'] != null) {
        _error = result['error'];
        notifyListeners();
        return false;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String phone,
    required String password,
    required String name,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await ApiService.register(
        username: username,
        phone: phone,
        password: password,
        name: name,
      );
      _isLoading = false;
      if (result['error'] != null) {
        _error = result['error'];
        notifyListeners();
        return false;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await ApiService.login(username, password);
      if (result['error'] != null) {
        _error = result['error'];
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await loadProfile();
      WebSocketService.instance.connect();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> loadProfile() async {
    try {
      _user = await ApiService.getProfile();
      notifyListeners();
    } catch (e) {
      // Token might be expired
      await logout();
    }
  }

  Future<void> logout() async {
    WebSocketService.instance.disconnect();
    await ApiService.clearToken();
    _user = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
