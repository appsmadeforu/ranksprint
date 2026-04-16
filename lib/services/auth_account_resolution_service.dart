import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_identity_service.dart';

class AuthAccountResolutionService {
  const AuthAccountResolutionService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const List<String> _migratableSubcollections = <String>[
    'examAnalytics',
    'examRecommendations',
    'notifications',
  ];

  static Future<ResolvedAccount> resolveForUser(
    User user, {
    String? fallbackPhoneNumber,
  }) async {
    final normalizedEmail = AuthIdentityService.normalizeEmail(user.email);
    final normalizedPhone = AuthIdentityService.normalizePhone(
      user.phoneNumber ?? fallbackPhoneNumber,
    );

    final currentRef = _firestore.collection('users').doc(user.uid);
    final currentSnapshot = await currentRef.get();
    final currentData = currentSnapshot.data() ?? <String, dynamic>{};

    final candidates = await _loadCandidates(
      userId: user.uid,
      normalizedEmail: normalizedEmail,
      normalizedPhone: normalizedPhone,
    );

    final duplicates = _rankCandidates(
      candidates,
      normalizedEmail: normalizedEmail,
      normalizedPhone: normalizedPhone,
    );

    final mergedData = <String, dynamic>{};
    final mergedFrom = <String>[];

    for (final duplicate in duplicates) {
      mergedFrom.add(duplicate.id);
      _mergeMaps(mergedData, duplicate.data());
    }
    _mergeMaps(mergedData, currentData);

    final hasExistingData = mergedFrom.isNotEmpty;
    final payload = _buildResolvedUserData(
      mergedData,
      user: user,
      normalizedEmail: normalizedEmail,
      normalizedPhone: normalizedPhone,
    );

    await currentRef.set(payload, SetOptions(merge: true));

    for (final duplicate in duplicates) {
      await _migrateSubcollections(
        sourceUserId: duplicate.id,
        targetUserId: user.uid,
      );
      await duplicate.reference.delete();
    }

    return ResolvedAccount(
      normalizedEmail: normalizedEmail,
      normalizedPhone: normalizedPhone,
      mergedFromUserIds: mergedFrom,
      hadExistingAccount: hasExistingData || currentSnapshot.exists,
    );
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadCandidates({
    required String userId,
    required String normalizedEmail,
    required String normalizedPhone,
  }) async {
    final snapshot = await _firestore.collection('users').get();
    return snapshot.docs.where((doc) {
      if (doc.id == userId) return false;
      final data = doc.data();
      final email = AuthIdentityService.normalizeEmail(data['email']?.toString());
      final phone = AuthIdentityService.normalizePhone(data['phone']?.toString());
      final emailMatches = normalizedEmail.isNotEmpty && email == normalizedEmail;
      final phoneMatches = normalizedPhone.isNotEmpty && phone == normalizedPhone;
      return emailMatches || phoneMatches;
    }).toList();
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _rankCandidates(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> candidates, {
    required String normalizedEmail,
    required String normalizedPhone,
  }) {
    final ranked = <_CandidateScore>[];
    for (final candidate in candidates) {
      final data = candidate.data();
      final email = AuthIdentityService.normalizeEmail(data['email']?.toString());
      final phone = AuthIdentityService.normalizePhone(data['phone']?.toString());
      final emailMatches = normalizedEmail.isNotEmpty && email == normalizedEmail;
      final phoneMatches = normalizedPhone.isNotEmpty && phone == normalizedPhone;
      final score =
          (emailMatches ? 100 : 0) +
          (phoneMatches ? 100 : 0) +
          ((data['selectedExams'] is List) ? (data['selectedExams'] as List).length : 0);
      ranked.add(_CandidateScore(candidate, score));
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked.map((entry) => entry.doc).toList();
  }

  static Map<String, dynamic> _buildResolvedUserData(
    Map<String, dynamic> mergedData, {
    required User user,
    required String normalizedEmail,
    required String normalizedPhone,
  }) {
    final payload = <String, dynamic>{
      'name': _preferNonEmpty(user.displayName, mergedData['name']),
      'email': _preferNonEmpty(user.email, mergedData['email']),
      'phone': _preferNonEmpty(
        normalizedPhone,
        AuthIdentityService.normalizePhone(mergedData['phone']?.toString()),
      ),
      'normalizedEmail': normalizedEmail,
      'normalizedPhone': normalizedPhone,
      'updatedAt': FieldValue.serverTimestamp(),
      'selectedExams': _uniqueStringList(mergedData['selectedExams']),
      'activePlanIds': _uniqueStringList(mergedData['activePlanIds']),
      'subscriptionIds': _uniqueStringList(mergedData['subscriptionIds']),
    };

    final fieldsToCarry = <String>[
      'firstName',
      'middleName',
      'lastName',
      'photoURL',
      'pincode',
      'city',
      'state',
      'gender',
      'dob',
      'lastSelectedExamId',
      'currentGoal',
      'examGoals',
      'favoritePyqLessons',
      'groupId',
      'groupJoinedAt',
      'pendingEmailVerificationEmail',
      'pendingEmailVerificationUpdatedAt',
      'themeMode',
      'createdAt',
    ];

    for (final field in fieldsToCarry) {
      if (mergedData.containsKey(field)) {
        payload[field] = mergedData[field];
      }
    }

    payload['createdAt'] ??= FieldValue.serverTimestamp();

    return payload;
  }

  static Future<void> _migrateSubcollections({
    required String sourceUserId,
    required String targetUserId,
  }) async {
    if (sourceUserId == targetUserId) return;

    for (final subcollection in _migratableSubcollections) {
      final sourceCollection = _firestore
          .collection('users')
          .doc(sourceUserId)
          .collection(subcollection);
      final targetCollection = _firestore
          .collection('users')
          .doc(targetUserId)
          .collection(subcollection);

      final snapshot = await sourceCollection.get();
      for (final doc in snapshot.docs) {
        final targetRef = targetCollection.doc(doc.id);
        final targetSnapshot = await targetRef.get();
        final merged = <String, dynamic>{};
        if (targetSnapshot.exists) {
          _mergeMaps(merged, targetSnapshot.data() ?? <String, dynamic>{});
        }
        _mergeMaps(merged, doc.data());
        await targetRef.set(merged, SetOptions(merge: true));
        await doc.reference.delete();
      }
    }
  }

  static void _mergeMaps(
    Map<String, dynamic> target,
    Map<String, dynamic> source,
  ) {
    source.forEach((key, value) {
      if (value == null) return;
      final existing = target[key];
      if (existing is Map && value is Map) {
        final merged = Map<String, dynamic>.from(
          existing.map((key, value) => MapEntry(key.toString(), value)),
        );
        _mergeMaps(
          merged,
          value.map((key, value) => MapEntry(key.toString(), value)),
        );
        target[key] = merged;
        return;
      }
      if (existing is List || value is List) {
        target[key] = _mergeListValues(existing, value);
        return;
      }
      if (existing == null ||
          (existing is String && existing.trim().isEmpty) ||
          (existing is Map && existing.isEmpty)) {
        target[key] = value;
      }
    });
  }

  static dynamic _mergeListValues(dynamic existing, dynamic incoming) {
    final left = existing is List ? existing : const <dynamic>[];
    final right = incoming is List ? incoming : const <dynamic>[];
    final seen = <String>{};
    final merged = <dynamic>[];
    for (final item in <dynamic>[...left, ...right]) {
      final key = item.toString();
      if (seen.add(key)) {
        merged.add(item);
      }
    }
    return merged;
  }

  static List<String> _uniqueStringList(dynamic value) {
    if (value is! List) return <String>[];
    final seen = <String>{};
    final items = <String>[];
    for (final item in value) {
      final text = item.toString().trim();
      if (text.isEmpty || !seen.add(text)) continue;
      items.add(text);
    }
    return items;
  }

  static String _preferNonEmpty(Object? preferred, Object? fallback) {
    final preferredText = (preferred ?? '').toString().trim();
    if (preferredText.isNotEmpty) return preferredText;
    return (fallback ?? '').toString().trim();
  }
}

class ResolvedAccount {
  final String normalizedEmail;
  final String normalizedPhone;
  final List<String> mergedFromUserIds;
  final bool hadExistingAccount;

  const ResolvedAccount({
    required this.normalizedEmail,
    required this.normalizedPhone,
    required this.mergedFromUserIds,
    required this.hadExistingAccount,
  });
}

class _CandidateScore {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int score;

  const _CandidateScore(this.doc, this.score);
}
