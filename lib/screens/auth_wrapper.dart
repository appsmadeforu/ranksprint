import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_session_coordinator.dart';
import '../services/auth_account_cleanup_service.dart';
import '../services/single_device_session_service.dart';
import 'auth/login_screen.dart';
import 'home/edit_profile_screen.dart';
import 'home/main_navigation.dart';
import 'onboarding/select_exam_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _sessionFutureUserId;
  Future<SessionStatus>? _sessionStatusFuture;
  bool _loggingOutForRemoteSession = false;

  void _log(String message) {
    debugPrint('AuthWrapper: $message');
  }

  Future<SessionStatus> _sessionFutureFor(User user) {
    if (_sessionFutureUserId == user.uid && _sessionStatusFuture != null) {
      return _sessionStatusFuture!;
    }
    _sessionFutureUserId = user.uid;
    _sessionStatusFuture = AuthSessionCoordinator.ensureCurrentSession(user);
    return _sessionStatusFuture!;
  }

  Future<void> _handleRemoteSessionConflict(User user) async {
    if (_loggingOutForRemoteSession) return;
    _loggingOutForRemoteSession = true;
    _log('remote session conflict uid=${user.uid}');
    await AuthSessionCoordinator.forceLogoutForRemoteSession();
    if (!mounted) return;
    setState(() {
      _loggingOutForRemoteSession = false;
      _sessionFutureUserId = null;
      _sessionStatusFuture = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoadingScreen();
        }

        final user = authSnapshot.data;
        if (user == null) {
          _log('auth state signed out');
          _sessionFutureUserId = null;
          _sessionStatusFuture = null;
          return const LoginScreen();
        }

        if (_loggingOutForRemoteSession) {
          return const _AuthLoadingScreen();
        }

        return FutureBuilder<SessionStatus>(
          future: _sessionFutureFor(user),
          builder: (context, sessionSnapshot) {
            if (sessionSnapshot.connectionState != ConnectionState.done) {
              return const _AuthLoadingScreen();
            }

            if (sessionSnapshot.hasError) {
              _log('session check error=${sessionSnapshot.error}');
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await SingleDeviceSessionService.signOutToLogin();
              });
              return const _AuthLoadingScreen();
            }

            if (sessionSnapshot.data == SessionStatus.signedInElsewhere) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleRemoteSessionConflict(user);
              });
              return const _AuthLoadingScreen();
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const _AuthLoadingScreen();
                }

                if (userSnapshot.hasError) {
                  _log('user snapshot error=${userSnapshot.error}');
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    await SingleDeviceSessionService.signOutToLogin();
                  });
                  return const _AuthLoadingScreen();
                }

                final data = userSnapshot.data?.data();
                return _buildAuthenticatedDestination(data);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAuthenticatedDestination(Map<String, dynamic>? data) {
    if (AuthAccountCleanupService.isAccountDeletionInProgress) {
      return const _AuthLoadingScreen();
    }

    final firstName = (data?['firstName'] ?? '').toString().trim();
    final lastName = (data?['lastName'] ?? '').toString().trim();
    final legacyName = (data?['name'] ?? '').toString().trim();
    final hasProfileName =
        firstName.isNotEmpty || lastName.isNotEmpty || legacyName.isNotEmpty;
    final hasEmail = (data?['email'] ?? '').toString().trim().isNotEmpty;
    final hasPhone = (data?['phone'] ?? '').toString().trim().isNotEmpty;

    if (data == null || ((!hasEmail && !hasPhone) || !hasProfileName)) {
      return const EditProfileScreen();
    }

    final selectedExams = data['selectedExams'];
    if (selectedExams == null ||
        selectedExams is! List ||
        selectedExams.isEmpty) {
      return const SelectExamScreen();
    }

    return const MainNavigation(initialIndex: 0);
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
