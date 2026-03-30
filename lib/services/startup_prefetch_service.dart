import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'result_data_service.dart';
import 'user_exam_preference_service.dart';

class StartupPrefetchService {
  StartupPrefetchService._();

  static final Set<String> _startedForUsers = <String>{};
  static final Map<String, String> _dashboardAttemptSignatures =
      <String, String>{};
  static final Map<String, Future<void>> _dashboardPrefetchInFlight =
      <String, Future<void>>{};

  static Future<void> prefetchForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_startedForUsers.contains(user.uid)) return;
    _startedForUsers.add(user.uid);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? const <String, dynamic>{};
      final selectedExams = List<String>.from(
        userData['selectedExams'] ?? const <String>[],
      );
      if (selectedExams.isEmpty) return;

      final preferredExamId =
          await UserExamPreferenceService.loadPreferredExamId(
            availableExamIds: selectedExams,
          );
      final activeExamId =
          preferredExamId != null && selectedExams.contains(preferredExamId)
          ? preferredExamId
          : selectedExams.first;

      final futures = <Future<dynamic>>[
        for (final examId in selectedExams)
          FirebaseFirestore.instance.collection('exams').doc(examId).get(),
        FirebaseFirestore.instance
            .collection('testAttempts')
            .where('userId', isEqualTo: user.uid)
            .get(),
        FirebaseFirestore.instance
            .collection('results')
            .where('userId', isEqualTo: user.uid)
            .get(),
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('notifications')
            .limit(20)
            .get(),
        FirebaseFirestore.instance.collection('notification').limit(40).get(),
        FirebaseFirestore.instance
            .collection('results')
            .where('examId', isEqualTo: activeExamId)
            .limit(120)
            .get(),
        FirebaseFirestore.instance
            .collection('exams')
            .doc(activeExamId)
            .collection('home_config')
            .doc('featured')
            .get(),
      ];

      unawaited(Future.wait(futures));
      unawaited(prefetchDashboardData(userId: user.uid, examId: activeExamId));

      final featuredConfig = await FirebaseFirestore.instance
          .collection('exams')
          .doc(activeExamId)
          .collection('home_config')
          .doc('featured')
          .get();
      final featuredData = featuredConfig.data() ?? const <String, dynamic>{};
      final featuredMockTestIds = List<String>.from(
        featuredData['featuredMockTestIds'] ?? const <String>[],
      );
      final featuredPyqIds = List<String>.from(
        featuredData['featuredPyqIds'] ?? const <String>[],
      );

      final followUps = <Future<dynamic>>[];
      if (featuredMockTestIds.isNotEmpty) {
        followUps.add(
          FirebaseFirestore.instance
              .collection('exams')
              .doc(activeExamId)
              .collection('tests')
              .where(
                FieldPath.documentId,
                whereIn: featuredMockTestIds.take(10).toList(),
              )
              .get(),
        );
      }
      if (featuredPyqIds.isNotEmpty) {
        followUps.add(
          FirebaseFirestore.instance
              .collection('exams')
              .doc(activeExamId)
              .collection('pyqs')
              .where(
                FieldPath.documentId,
                whereIn: featuredPyqIds.take(10).toList(),
              )
              .get(),
        );
      }
      if (followUps.isNotEmpty) {
        unawaited(Future.wait(followUps));
      }
    } catch (_) {
      // Prefetch should never block app startup.
    }
  }

  static Future<void> prefetchDashboardData({
    required String userId,
    required String examId,
    bool forceRefresh = false,
  }) async {
    if (userId.isEmpty || examId.isEmpty) return;

    final key = '$userId|$examId';
    if (!forceRefresh) {
      final pending = _dashboardPrefetchInFlight[key];
      if (pending != null) {
        await pending;
        return;
      }
    }

    Future<void> task() async {
      final attemptsSnap = await FirebaseFirestore.instance
          .collection('testAttempts')
          .where('examId', isEqualTo: examId)
          .where('userId', isEqualTo: userId)
          .get();

      final attempts =
          attemptsSnap.docs.where((doc) {
            final status = (doc.data()['status'] ?? 'completed')
                .toString()
                .toLowerCase();
            return status == 'completed';
          }).toList()..sort((a, b) {
            final aTs =
                _toDate(a.data()['submittedAt']) ??
                _toDate(a.data()['startedAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bTs =
                _toDate(b.data()['submittedAt']) ??
                _toDate(b.data()['startedAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return aTs.compareTo(bTs);
          });

      final signature = _attemptSignature(attempts);
      if (!forceRefresh && _dashboardAttemptSignatures[key] == signature) {
        return;
      }

      final resultMap = await ResultDataService.loadResultsMap(
        attempts: attempts,
        userId: userId,
        examId: examId,
      );
      final futures = <Future<dynamic>>[
        FirebaseFirestore.instance.collection('exams').doc(examId).get(),
        FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('examRecommendations')
            .doc(examId)
            .get(),
        FirebaseFirestore.instance
            .collection('results')
            .where('examId', isEqualTo: examId)
            .orderBy('createdAt', descending: true)
            .limit(120)
            .get(),
      ];

      final uniqueTestKeys = <String>{};
      for (final attemptDoc in attempts) {
        final attempt = attemptDoc.data();
        final attemptExamId = (attempt['examId'] ?? '').toString();
        final testId = (attempt['testId'] ?? '').toString();
        if (attemptExamId.isEmpty || testId.isEmpty) continue;

        final cacheKey = '$attemptExamId|$testId';
        if (!uniqueTestKeys.add(cacheKey)) continue;

        futures.add(
          FirebaseFirestore.instance
              .collection('exams')
              .doc(attemptExamId)
              .collection('tests')
              .doc(testId)
              .get(),
        );
        futures.add(
          FirebaseFirestore.instance
              .collection('exams')
              .doc(attemptExamId)
              .collection('tests')
              .doc(testId)
              .collection('sections')
              .get(),
        );

        final embeddedQuestions = _readEmbeddedQuestions(
          resultMap[attemptDoc.id]?['question'] ?? attempt['question'],
        );
        if (embeddedQuestions.isEmpty) {
          futures.add(
            FirebaseFirestore.instance
                .collection('exams')
                .doc(attemptExamId)
                .collection('tests')
                .doc(testId)
                .collection('questions')
                .get(),
          );
        }
      }

      await Future.wait(futures);
      _dashboardAttemptSignatures[key] = signature;
    }

    final future = task();
    _dashboardPrefetchInFlight[key] = future;
    try {
      await future;
    } catch (_) {
      // Prefetch should never block the main app flow.
    } finally {
      if (identical(_dashboardPrefetchInFlight[key], future)) {
        _dashboardPrefetchInFlight.remove(key);
      }
    }
  }

  static void invalidateDashboardData({
    required String userId,
    required String examId,
  }) {
    if (userId.isEmpty || examId.isEmpty) return;
    final key = '$userId|$examId';
    _dashboardAttemptSignatures.remove(key);
  }

  static String _attemptSignature(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) {
    return attempts
        .map((doc) {
          final data = doc.data();
          final stamp =
              (_toDate(data['submittedAt']) ?? _toDate(data['startedAt']))
                  ?.millisecondsSinceEpoch ??
              0;
          return '${doc.id}:$stamp:${(data['status'] ?? '').toString()}';
        })
        .join('|');
  }

  static List<Map<String, dynamic>> _readEmbeddedQuestions(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
