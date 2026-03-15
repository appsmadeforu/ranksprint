import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ThemeModeService extends ChangeNotifier {
  ThemeModeService._();

  static const String _field = 'themeMode';
  static final ThemeModeService instance = ThemeModeService._();

  ThemeMode _themeMode = ThemeMode.light;
  bool _isInitialized = false;
  Stream<User?>? _authChanges;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> load() async {
    if (!_isInitialized) {
      _isInitialized = true;
      _authChanges = FirebaseAuth.instance.authStateChanges();
      _authChanges!.listen((_) {
        _syncFromRemote();
      });
    }

    await _syncFromRemote();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      _field: mode == ThemeMode.dark ? 'dark' : 'light',
    }, SetOptions(merge: true));
  }

  Future<void> setDarkMode(bool enabled) {
    return setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> _syncFromRemote() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _updateThemeMode(ThemeMode.light);
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final savedMode = (snap.data()?[_field] ?? 'light').toString();
      _updateThemeMode(savedMode == 'dark' ? ThemeMode.dark : ThemeMode.light);
    } catch (_) {
      _updateThemeMode(ThemeMode.light);
    }
  }

  void _updateThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }
}
