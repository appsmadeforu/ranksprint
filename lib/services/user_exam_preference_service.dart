import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class UserExamPreferenceService {
  const UserExamPreferenceService._();

  static const String _field = 'lastSelectedExamId';
  static final ValueNotifier<String?> preferredExamNotifier =
      ValueNotifier<String?>(null);

  static void syncPreferredExamId(String? examId) {
    if (preferredExamNotifier.value == examId) return;
    preferredExamNotifier.value = examId;
  }

  static Future<String?> loadPreferredExamId({
    required List<String> availableExamIds,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || availableExamIds.isEmpty) {
      return availableExamIds.isEmpty ? null : availableExamIds.first;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final preferred = (snap.data()?[_field] ?? '').toString();
      if (preferred.isNotEmpty && availableExamIds.contains(preferred)) {
        syncPreferredExamId(preferred);
        return preferred;
      }
    } catch (_) {
      // Fall through to a safe default when the preference cannot be read.
    }

    final fallbackExamId = availableExamIds.first;
    syncPreferredExamId(fallbackExamId);
    return fallbackExamId;
  }

  static Future<void> savePreferredExamId(String examId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || examId.isEmpty) return;

    syncPreferredExamId(examId);

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        _field: examId,
      }, SetOptions(merge: true));
    } catch (_) {
      // Preference persistence should never block the main UI flow.
    }
  }
}
