import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_identity_service.dart';

class AuthAccountCleanupService {
  const AuthAccountCleanupService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static bool _accountDeletionInProgress = false;

  static bool get isAccountDeletionInProgress => _accountDeletionInProgress;

  static void beginAccountDeletion() {
    _accountDeletionInProgress = true;
  }

  static const List<String> _subcollections = <String>[
    'examAnalytics',
    'examRecommendations',
    'notifications',
  ];

  static Future<void> deleteAccountData(User user) async {
    _accountDeletionInProgress = true;
    final currentRef = _firestore.collection('users').doc(user.uid);
    final currentSnapshot = await currentRef.get();
    final currentData = currentSnapshot.data() ?? <String, dynamic>{};

    final normalizedEmail = AuthIdentityService.normalizeEmail(
      _firstNonEmpty(user.email, currentData['email']?.toString()),
    );
    final normalizedPhone = AuthIdentityService.normalizePhone(
      _firstNonEmpty(user.phoneNumber, currentData['phone']?.toString()),
    );

    final users = await _firestore.collection('users').get();
    final docsToDelete = users.docs.where((doc) {
      final data = doc.data();
      final docEmail = AuthIdentityService.normalizeEmail(data['email']?.toString());
      final docPhone = AuthIdentityService.normalizePhone(data['phone']?.toString());
      final emailMatches = normalizedEmail.isNotEmpty && docEmail == normalizedEmail;
      final phoneMatches = normalizedPhone.isNotEmpty && docPhone == normalizedPhone;
      return doc.id == user.uid || emailMatches || phoneMatches;
    }).toList();

    for (final doc in docsToDelete) {
      await _deleteUserDocument(doc.reference);
    }
  }

  static void clearAccountDeletionFlag() {
    _accountDeletionInProgress = false;
  }

  static Future<void> _deleteUserDocument(
    DocumentReference<Map<String, dynamic>> userRef,
  ) async {
    for (final subcollection in _subcollections) {
      final snapshot = await userRef.collection(subcollection).get();
      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
    }
    await userRef.delete();
  }

  static String _firstNonEmpty(String? primary, String? fallback) {
    final primaryText = (primary ?? '').trim();
    if (primaryText.isNotEmpty) return primaryText;
    return (fallback ?? '').trim();
  }
}
