import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenshotProtectionService {
  static const MethodChannel _channel = MethodChannel(
    'ranksprint/screenshot_protection',
  );
  static const String _field = 'screenshotEnabled';
  static StreamSubscription<User?>? _authSubscription;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _userDocSubscription;
  static bool _isInitialized = false;
  static bool _lastAppliedEnabled = false;

  static Future<void> syncWithConfig() async {
    if (_isInitialized) {
      await _syncForCurrentUser();
      return;
    }

    _isInitialized = true;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(_handleAuthStateChanged(user));
    });

    await _syncForCurrentUser();
  }

  static Future<void> _handleAuthStateChanged(User? user) async {
    await _userDocSubscription?.cancel();
    _userDocSubscription = null;

    if (user == null) {
      await setEnabled(false);
      return;
    }

    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          final isEnabled = data?[_field] == true;
          unawaited(setEnabled(isEnabled));
        });

    await _syncForCurrentUser();
  }

  static Future<void> _syncForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await setEnabled(false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snapshot.data();
      await setEnabled(data?[_field] == true);
    } catch (_) {
      await setEnabled(false);
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    if (kIsWeb) return;
    if (_lastAppliedEnabled == enabled) return;

    try {
      await _channel.invokeMethod<void>('setEnabled', <String, dynamic>{
        'enabled': enabled,
      });
      _lastAppliedEnabled = enabled;
    } on PlatformException {
      // Keep startup resilient on platforms where screenshot protection
      // isn't wired yet.
    } on MissingPluginException {
      // Some desktop/mobile targets may not register the native bridge.
    }
  }
}
