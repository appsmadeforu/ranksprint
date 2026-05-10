import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'subscription_backend_service.dart';

class SubscriptionAccessService {
  const SubscriptionAccessService._();
  static String? _cachedUserId;
  static Set<String>? _cachedActivePlanIds;
  static final Map<String, ExamSubscriptionScope> _examScopeCache =
      <String, ExamSubscriptionScope>{};

  static Future<Set<String>> getCurrentUserActivePlanIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return <String>{};

    if (_cachedUserId == user.uid && _cachedActivePlanIds != null) {
      return _cachedActivePlanIds!;
    }

    SubscriptionRefreshResult? refreshedAccess;
    try {
      refreshedAccess = await SubscriptionBackendService.refreshAccess();
    } catch (_) {
      // Fall back to direct reads so existing users are not blocked by a
      // temporary functions outage.
    }

    if (refreshedAccess != null) {
      final refreshedPlanIds = refreshedAccess.activePlanIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      _cachedUserId = user.uid;
      _cachedActivePlanIds = refreshedPlanIds;
      return refreshedPlanIds;
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
    _examScopeCache.clear();
  }

  static Future<ExamSubscriptionScope> getExamSubscriptionScope(
    String examId,
  ) async {
    final normalizedExamId = examId.trim();
    if (normalizedExamId.isEmpty) {
      return const ExamSubscriptionScope();
    }

    final cached = _examScopeCache[normalizedExamId];
    if (cached != null) {
      return cached;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('subscriptionPlans')
        .get();

    final examPlanIds = <String>{};
    final testPlanIdsById = <String, Set<String>>{};
    final pyqPlanIdsById = <String, Set<String>>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final features = _asStringMap(data['features']);
      final isActive = features['isActive'] is bool
          ? features['isActive'] == true
          : data['isActive'] is bool
          ? data['isActive'] == true
          : true;
      if (!isActive) {
        continue;
      }

      final examsIncluded = data['examsIncluded'];
      if (examsIncluded is Iterable) {
        if (examsIncluded.map((value) => value.toString()).contains(normalizedExamId)) {
          examPlanIds.add(doc.id);
        }
        continue;
      }

      if (examsIncluded is! Map) {
        continue;
      }

      final normalizedMap = _asStringMap(examsIncluded);
      if (!normalizedMap.containsKey(normalizedExamId)) {
        continue;
      }

      final examEntry = normalizedMap[normalizedExamId];
      if (examEntry is Map) {
        final entryMap = _asStringMap(examEntry);
        final tests = _readStringList(entryMap['tests']);
        final pyqs = _readStringList(entryMap['pyqs']);

        for (final testId in tests) {
          testPlanIdsById.putIfAbsent(testId, () => <String>{}).add(doc.id);
        }
        for (final pyqId in pyqs) {
          pyqPlanIdsById.putIfAbsent(pyqId, () => <String>{}).add(doc.id);
        }

        final appliesToWholeExam =
            tests.isEmpty &&
            pyqs.isEmpty &&
            (entryMap.isEmpty ||
                entryMap['all'] == true ||
                entryMap['fullExam'] == true ||
                entryMap['exam'] == true);
        if (appliesToWholeExam) {
          examPlanIds.add(doc.id);
        }
        continue;
      }

      if (examEntry == true || examEntry != null) {
        examPlanIds.add(doc.id);
      }
    }

    final scope = ExamSubscriptionScope(
      examPlanIds: examPlanIds,
      testPlanIdsById: testPlanIdsById.map(
        (key, value) => MapEntry(key, value.toList(growable: false)),
      ),
      pyqPlanIdsById: pyqPlanIdsById.map(
        (key, value) => MapEntry(key, value.toList(growable: false)),
      ),
    );
    _examScopeCache[normalizedExamId] = scope;
    return scope;
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

  static Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, mapValue) => MapEntry(key.toString(), mapValue),
      );
    }
    return const <String, dynamic>{};
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! Iterable) {
      return const <String>[];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class ExamSubscriptionScope {
  final Set<String> examPlanIds;
  final Map<String, List<String>> testPlanIdsById;
  final Map<String, List<String>> pyqPlanIdsById;

  const ExamSubscriptionScope({
    this.examPlanIds = const <String>{},
    this.testPlanIdsById = const <String, List<String>>{},
    this.pyqPlanIdsById = const <String, List<String>>{},
  });
}
