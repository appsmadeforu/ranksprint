import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final inlineActivePlanIds = List<String>.from(
      userDoc.data()?['activePlanIds'] ?? const [],
    ).where((id) => id.isNotEmpty);
    if (inlineActivePlanIds.isNotEmpty) {
      _cachedUserId = user.uid;
      _cachedActivePlanIds = inlineActivePlanIds.toSet();
      return _cachedActivePlanIds!;
    }

    final subscriptionIds = List<String>.from(
      userDoc.data()?['subscriptionIds'] ?? const [],
    );

    if (subscriptionIds.isEmpty) {
      _cachedUserId = user.uid;
      _cachedActivePlanIds = <String>{};
      return _cachedActivePlanIds!;
    }

    final activePlanIds = <String>{};

    final subscriptionDocs = await Future.wait(
      subscriptionIds.map(
        (subscriptionId) => FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(subscriptionId)
            .get(),
      ),
    );

    for (final subscriptionDoc in subscriptionDocs) {

      if (!subscriptionDoc.exists) continue;

      final data = subscriptionDoc.data() ?? const <String, dynamic>{};
      if ((data['status'] ?? '').toString() != 'active') continue;

      final planId = (data['planId'] ?? '').toString();
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
