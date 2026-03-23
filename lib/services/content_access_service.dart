import 'package:cloud_firestore/cloud_firestore.dart';

import 'subscription_access_service.dart';

class ContentAccessService {
  const ContentAccessService._();

  static Query<Map<String, dynamic>> activeExamsQuery({
    FirebaseFirestore? firestore,
  }) {
    return (firestore ?? FirebaseFirestore.instance)
        .collection('exams')
        .where('isActive', isEqualTo: true);
  }

  static Query<Map<String, dynamic>> publishedTestsQuery(
    String examId, {
    FirebaseFirestore? firestore,
  }) {
    return (firestore ?? FirebaseFirestore.instance)
        .collection('exams')
        .doc(examId)
        .collection('tests')
        .where('status', isEqualTo: 'published');
  }

  static Query<Map<String, dynamic>> publishedPyqsQuery(
    String examId, {
    FirebaseFirestore? firestore,
  }) {
    return (firestore ?? FirebaseFirestore.instance)
        .collection('exams')
        .doc(examId)
        .collection('pyqs');
  }

  static Query<Map<String, dynamic>> publishedPyqChaptersQuery({
    required String examId,
    required String subjectId,
    FirebaseFirestore? firestore,
  }) {
    return (firestore ?? FirebaseFirestore.instance)
        .collection('exams')
        .doc(examId)
        .collection('pyqs')
        .doc(subjectId)
        .collection('chapters')
        .where('status', isEqualTo: 'published');
  }

  static bool isPublished(Map<String, dynamic>? data) {
    final status = (data?['status'] ?? 'published').toString().toLowerCase();
    return status == 'published';
  }

  static bool isVisibleNow(Map<String, dynamic>? data, {DateTime? now}) {
    if (!isPublished(data)) {
      return false;
    }

    final currentTime = now ?? DateTime.now();
    final visibilityStart = _readDateTime(data?['visibilityStart']);
    final visibilityEnd = _readDateTime(data?['visibilityEnd']);

    if (visibilityStart != null && currentTime.isBefore(visibilityStart)) {
      return false;
    }

    if (visibilityEnd != null && !currentTime.isBefore(visibilityEnd)) {
      return false;
    }

    return true;
  }

  static ContentAccessState resolveAccess({
    required Map<String, dynamic>? itemData,
    required Iterable<String> examPlanIds,
    required Iterable<String> activePlanIds,
    bool fallbackPremium = false,
  }) {
    final itemPlanIds = SubscriptionAccessService.readPlanIds(itemData);
    final requiredPlanIds = itemPlanIds.isNotEmpty
        ? itemPlanIds
        : examPlanIds.map((id) => id.toString()).toList();
    final isExplicitlyLocked = (itemData?['isLocked'] ?? false) == true;
    final isPremium = itemData != null && itemData.containsKey('isPremium')
        ? (itemData['isPremium'] ?? false) == true
        : fallbackPremium;
    final requiresSubscription = isPremium || requiredPlanIds.isNotEmpty;
    final hasPlanAccess =
        requiredPlanIds.isEmpty ||
        SubscriptionAccessService.hasRequiredPlanAccess(
          activePlanIds: activePlanIds,
          requiredPlanIds: requiredPlanIds,
        );

    return ContentAccessState(
      isLocked: isExplicitlyLocked || (requiresSubscription && !hasPlanAccess),
      requiredPlanIds: requiredPlanIds,
    );
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static int compareCreatedAtAsc(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final aTime =
        _readDateTime(a.data()['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final bTime =
        _readDateTime(b.data()['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return aTime.compareTo(bTime);
  }
}

class ContentAccessState {
  final bool isLocked;
  final List<String> requiredPlanIds;

  const ContentAccessState({
    required this.isLocked,
    required this.requiredPlanIds,
  });
}
