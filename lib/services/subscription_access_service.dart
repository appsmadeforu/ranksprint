import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SubscriptionAccessService {
  const SubscriptionAccessService._();

  static Future<Set<String>> getCurrentUserActivePlanIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return <String>{};

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final subscriptionIds = List<String>.from(
      userDoc.data()?['subscriptionIds'] ?? const [],
    );

    if (subscriptionIds.isEmpty) return <String>{};

    final activePlanIds = <String>{};

    for (final subscriptionId in subscriptionIds) {
      final subscriptionDoc = await FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(subscriptionId)
          .get();

      if (!subscriptionDoc.exists) continue;

      final data = subscriptionDoc.data() ?? const <String, dynamic>{};
      if ((data['status'] ?? '').toString() != 'active') continue;

      final planId = (data['planId'] ?? '').toString();
      if (planId.isNotEmpty) {
        activePlanIds.add(planId);
      }
    }

    return activePlanIds;
  }

  static List<String> readPlanIds(Map<String, dynamic>? data) {
    if (data == null) return const <String>[];

    final raw = data['subscriptionPlanIds'];
    if (raw is! Iterable) return const <String>[];

    return raw
        .map((value) => value.toString())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  static bool hasRequiredPlanAccess({
    required Iterable<String> activePlanIds,
    required Iterable<String> requiredPlanIds,
  }) {
    final active = activePlanIds.toSet();
    for (final planId in requiredPlanIds) {
      if (active.contains(planId)) {
        return true;
      }
    }
    return false;
  }

  static bool planIncludesExam(dynamic examsIncluded, String examId) {
    if (examsIncluded is Iterable) {
      return examsIncluded.map((value) => value.toString()).contains(examId);
    }

    if (examsIncluded is Map) {
      return examsIncluded.keys.map((key) => key.toString()).contains(examId);
    }

    return false;
  }
}
