import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class ThemeModeService extends ChangeNotifier {
  ThemeModeService._();

  static const String _field = 'themeMode';
  static final ThemeModeService instance = ThemeModeService._();
  static const ThemeMode _defaultThemeMode = ThemeMode.light;

  ThemeMode _themeMode = _defaultThemeMode;
  bool _isInitialized = false;
  StreamSubscription<User?>? _authSubscription;
  int _syncGeneration = 0;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> load() async {
    if (!_isInitialized) {
      _isInitialized = true;
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        _handleAuthStateChanged(user);
      });
    }

    await _syncFromRemote();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    final previousMode = _themeMode;
    _themeMode = mode;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        _field: _encodeThemeMode(mode),
      }, SetOptions(merge: true));
    } catch (_) {
      _updateThemeMode(previousMode);
    }
  }

  Future<void> setDarkMode(bool enabled) {
    return setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }

  void _handleAuthStateChanged(User? user) {
    if (user == null) {
      _syncGeneration++;
      _updateThemeMode(_defaultThemeMode);
      return;
    }

    unawaited(_syncFromRemote());
  }

  Future<void> _syncFromRemote() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _updateThemeMode(_defaultThemeMode);
      return;
    }

    final syncGeneration = ++_syncGeneration;
    final userId = user.uid;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!_shouldApplySync(syncGeneration, userId)) {
        return;
      }

      _updateThemeMode(_decodeThemeMode(snap.data()?[_field]));
    } catch (_) {
      if (!_shouldApplySync(syncGeneration, userId)) {
        return;
      }

      _updateThemeMode(_defaultThemeMode);
    }
  }

  bool _shouldApplySync(int syncGeneration, String userId) {
    final currentUser = FirebaseAuth.instance.currentUser;
    return syncGeneration == _syncGeneration &&
        currentUser != null &&
        currentUser.uid == userId;
  }

  ThemeMode _decodeThemeMode(Object? rawValue) {
    final normalized = rawValue?.toString().trim().toLowerCase();
    if (normalized == 'dark') return ThemeMode.dark;
    return _defaultThemeMode;
  }

  String _encodeThemeMode(ThemeMode mode) {
    return mode == ThemeMode.dark ? 'dark' : 'light';
  }

  void _updateThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }
}
