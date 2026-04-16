import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_identity_service.dart';
import 'subscription_access_service.dart';

class SingleDeviceSessionService {
  static const String _sessionIdField = 'activeSessionId';
  static const String _sessionUpdatedAtField = 'activeSessionUpdatedAt';
  static const String _lastLoginNoticeField = 'lastLoginNotice';
  static const String _localSessionKeyPrefix = 'active_session_id_';

  static String? _pendingLogoutMessage;

  static String? consumePendingLogoutMessage() {
    final message = _pendingLogoutMessage;
    _pendingLogoutMessage = null;
    return message;
  }

  static Future<void> registerLoginSession(User user) async {
    final sessionId = _buildSessionId(user.uid);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localSessionKey(user.uid), sessionId);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      _sessionIdField: sessionId,
      _sessionUpdatedAtField: Timestamp.now(),
      _lastLoginNoticeField:
          'You are signed in on this device. Any earlier session on another device has been signed out.',
      'normalizedEmail': AuthIdentityService.normalizeEmail(user.email),
      'normalizedPhone': AuthIdentityService.normalizePhone(user.phoneNumber),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<bool> isSessionCurrent(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final localSessionId = prefs.getString(_localSessionKey(user.uid));
    if (localSessionId == null || localSessionId.isEmpty) {
      return true;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = snapshot.data();
    if (data == null) return true;

    final remoteSessionId = (data[_sessionIdField] ?? '').toString().trim();
    if (remoteSessionId.isEmpty) return true;
    return remoteSessionId == localSessionId;
  }

  static Future<SessionStatus> ensureSessionRegistered(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final localSessionId = prefs.getString(_localSessionKey(user.uid)) ?? '';

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = snapshot.data();
    final remoteSessionId =
        (data?[_sessionIdField] ?? '').toString().trim();

    if (localSessionId.isEmpty || remoteSessionId.isEmpty) {
      await registerLoginSession(user);
      return SessionStatus.registeredBehindTheScenes;
    }

    if (localSessionId == remoteSessionId) {
      return SessionStatus.current;
    }

    return SessionStatus.signedInElsewhere;
  }

  static Future<void> forceLogoutBecauseAnotherDeviceSignedIn() async {
    _pendingLogoutMessage =
        'You were signed out because your account was used to log in on another device.';
    await _clearProviderSessions();
    await FirebaseAuth.instance.signOut();
    await clearLocalSession();
  }

  static Future<void> clearLocalSession([String? uid]) async {
    final prefs = await SharedPreferences.getInstance();
    if (uid != null && uid.isNotEmpty) {
      await prefs.remove(_localSessionKey(uid));
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await prefs.remove(_localSessionKey(currentUser.uid));
    }
  }

  static Future<void> signOutToLogin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _clearRemoteSession(user);
    }
    await _clearProviderSessions();
    await FirebaseAuth.instance.signOut();
    await clearLocalSession();
  }

  static Future<void> _clearProviderSessions() async {
    if (!kIsWeb) {
      try {
        await GoogleSignIn().signOut().timeout(const Duration(seconds: 3));
        await GoogleSignIn().disconnect().timeout(const Duration(seconds: 3));
      } catch (_) {
        // Ignore Google session cleanup errors on devices without stable GMS.
      }
    }
    SubscriptionAccessService.clearCache();
  }

  static String _localSessionKey(String uid) => '$_localSessionKeyPrefix$uid';

  static String _buildSessionId(String uid) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    return '$uid-$micros';
  }

  static Future<void> _clearRemoteSession(User user) async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      _sessionIdField: FieldValue.delete(),
      _sessionUpdatedAtField: FieldValue.delete(),
      _lastLoginNoticeField: FieldValue.delete(),
      'normalizedEmail': AuthIdentityService.normalizeEmail(user.email),
      'normalizedPhone': AuthIdentityService.normalizePhone(user.phoneNumber),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

enum SessionStatus { current, registeredBehindTheScenes, signedInElsewhere }
