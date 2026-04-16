import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_identity_service.dart';

class AuthDeletedIdentityService {
  const AuthDeletedIdentityService._();

  static Future<bool> isIdentityDeleted({
    String? email,
    String? phone,
  }) async {
    final normalizedEmail = AuthIdentityService.normalizeEmail(email);
    final normalizedPhone = AuthIdentityService.normalizePhone(phone);

    final refs = <DocumentReference<Map<String, dynamic>>>[];
    if (normalizedEmail.isNotEmpty) {
      refs.add(
        FirebaseFirestore.instance
            .collection('deletedAccountIdentities')
            .doc('email:$normalizedEmail'),
      );
    }
    if (normalizedPhone.isNotEmpty) {
      refs.add(
        FirebaseFirestore.instance
            .collection('deletedAccountIdentities')
            .doc('phone:$normalizedPhone'),
      );
    }

    for (final ref in refs) {
      final snapshot = await ref.get();
      if (snapshot.exists) return true;
    }
    return false;
  }
}
