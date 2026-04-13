import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'single_device_session_service.dart';

class AuthSessionCoordinator {
  const AuthSessionCoordinator._();

  static void _log(String message) {
    debugPrint('AuthSessionCoordinator: $message');
  }

  static Future<void> completePostLogin(
    User user, {
    String? fallbackPhoneNumber,
  }) async {
    _log('completePostLogin start uid=${user.uid}');
    try {
      await SingleDeviceSessionService.registerLoginSessionSafe(user);
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snapshot = await userDoc.get().timeout(const Duration(seconds: 15));
      if (!snapshot.exists) {
        _log('creating user doc uid=${user.uid}');
        await userDoc.set({
          'name': user.displayName ?? '',
          'email': user.email ?? '',
          'phone': user.phoneNumber ?? fallbackPhoneNumber ?? '',
          'selectedExams': [],
          'activePlanIds': [],
          'subscriptionIds': [],
          'createdAt': Timestamp.now(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));
        return;
      }

      _log('updating user doc uid=${user.uid}');
      await userDoc.set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
        'phone': user.phoneNumber ?? fallbackPhoneNumber ?? '',
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));
    } catch (error, stackTrace) {
      _log('completePostLogin failed uid=${user.uid} error=$error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<SessionStatus> ensureCurrentSession(User user) async {
    _log('ensureCurrentSession start uid=${user.uid}');
    try {
      final status = await SingleDeviceSessionService.ensureSessionRegistered(
        user,
      ).timeout(const Duration(seconds: 15));
      _log('ensureCurrentSession result uid=${user.uid} status=$status');
      return status;
    } catch (error, stackTrace) {
      _log('ensureCurrentSession failed uid=${user.uid} error=$error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<void> forceLogoutForRemoteSession() async {
    _log('forceLogoutForRemoteSession start');
    try {
      await SingleDeviceSessionService.forceLogoutBecauseAnotherDeviceSignedIn()
          .timeout(const Duration(seconds: 10));
      _log('forceLogoutForRemoteSession complete');
    } catch (error, stackTrace) {
      _log('forceLogoutForRemoteSession failed error=$error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}
