import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'subscription_backend_service.dart';

class SubscriptionAccessService {
  const SubscriptionAccessService._();
  static String? _cachedUserId;
  static Set<String>? _cachedActivePlanIds;

  static Future<Set<String>> getCurrentUserActivePlanIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return <String>{};

    if (_cachedUserId == user.uid && _cachedActivePlanIds != null) {
      return _cachedActivePlanIds!;
    }

    try {
      await SubscriptionBackendService.refreshAccess();
    } catch (_) {
      // Fall back to direct reads so existing users are not blocked by a
      // temporary functions outage.
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('subscriptions')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'active')
        .get();

    final now = DateTime.now();
    final activePlanIds = <String>{};

    for (final subscriptionDoc in snapshot.docs) {
      final data = subscriptionDoc.data();
      final expiry = data['expiresAt'];
      if (expiry is Timestamp && !expiry.toDate().isAfter(now)) {
        continue;
      }

      final planId = (data['planId'] ?? '').toString().trim();
      if (planId.isNotEmpty) {
        activePlanIds.add(planId);
      }
    }

    _cachedUserId = user.uid;
    _cachedActivePlanIds = activePlanIds;
    return activePlanIds;
  }

  static void clearCache() {
    _cachedUserId = null;
    _cachedActivePlanIds = null;
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
