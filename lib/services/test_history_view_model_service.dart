import 'package:cloud_firestore/cloud_firestore.dart';

import 'result_data_service.dart';
import 'result_schema_contract.dart';

class TestHistoryPage {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts;
  final Map<String, Map<String, dynamic>> results;
  final QueryDocumentSnapshot<Map<String, dynamic>>? lastAttemptDoc;
  final bool hasMore;

  const TestHistoryPage({
    required this.attempts,
    required this.results,
    required this.lastAttemptDoc,
    required this.hasMore,
  });
}

class TestHistoryViewData {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredAttempts;
  final int totalTests;
  final double avgScore;
  final double bestScore;
  final int totalMinutes;

  const TestHistoryViewData({
    required this.filteredAttempts,
    required this.totalTests,
    required this.avgScore,
    required this.bestScore,
    required this.totalMinutes,
  });
}

class TestHistoryViewModelService {
  TestHistoryViewModelService._();

  static final Map<String, Future<TestHistoryPage>> _pageFutures =
      <String, Future<TestHistoryPage>>{};
  static final Map<String, TestHistoryViewData> _viewCache =
      <String, TestHistoryViewData>{};

  static Future<TestHistoryPage> loadPage({
    required String userId,
    required String? examId,
    required int pageSize,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
    bool forceRefresh = false,
  }) {
    final key =
        '$userId|${examId ?? ''}|$pageSize|${startAfter?.id ?? 'first'}';
    if (forceRefresh) {
      _pageFutures.remove(key);
    }
    return _pageFutures.putIfAbsent(
      key,
      () => _fetchPage(
        userId: userId,
        examId: examId,
        pageSize: pageSize,
        startAfter: startAfter,
      ),
    );
  }

  static Future<TestHistoryPage> _fetchPage({
    required String userId,
    required String? examId,
    required int pageSize,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    try {
      return await _fetchPageWithIndexedQuery(
        userId: userId,
        examId: examId,
        pageSize: pageSize,
        startAfter: startAfter,
      );
    } on FirebaseException {
      return _fetchPageWithFallbackQuery(
        userId: userId,
        examId: examId,
        pageSize: pageSize,
        startAfter: startAfter,
      );
    }
  }

  static Future<TestHistoryPage> _fetchPageWithIndexedQuery({
    required String userId,
    required String? examId,
    required int pageSize,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection(ResultSchemaContract.attemptCollection)
        .where('userId', isEqualTo: userId);

    if ((examId ?? '').isNotEmpty) {
      query = query.where('examId', isEqualTo: examId);
    }

    query = query.orderBy('startedAt', descending: true).limit(pageSize);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    return _buildPageFromAttempts(
      attempts: snap.docs,
      userId: userId,
      examId: examId,
      pageSize: pageSize,
      startAfter: startAfter,
    );
  }

  static Future<TestHistoryPage> _fetchPageWithFallbackQuery({
    required String userId,
    required String? examId,
    required int pageSize,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection(ResultSchemaContract.attemptCollection)
        .where('userId', isEqualTo: userId);

    if ((examId ?? '').isNotEmpty) {
      query = query.where('examId', isEqualTo: examId);
    }

    final snap = await query.get();
    final allAttempts = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
      snap.docs,
    )..sort((a, b) {
        final aTs =
            (a.data()['startedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final bTs =
            (b.data()['startedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return bTs.compareTo(aTs);
      });

    var startIndex = 0;
    if (startAfter != null) {
      final lastIndex = allAttempts.indexWhere((doc) => doc.id == startAfter.id);
      if (lastIndex >= 0) {
        startIndex = lastIndex + 1;
      }
    }

    final pageAttempts = allAttempts.skip(startIndex).take(pageSize).toList();
    return _buildPageFromAttempts(
      attempts: pageAttempts,
      userId: userId,
      examId: examId,
      pageSize: pageSize,
      startAfter: startAfter,
    );
  }

  static Future<TestHistoryPage> _buildPageFromAttempts({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    required String userId,
    required String? examId,
    required int pageSize,
    required QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final results = attempts.isEmpty
        ? const <String, Map<String, dynamic>>{}
        : await ResultDataService.loadResultsMap(
            attempts: attempts,
            userId: userId,
            examId: examId,
          );

    return TestHistoryPage(
      attempts: attempts,
      results: results,
      lastAttemptDoc: attempts.isEmpty ? startAfter : attempts.last,
      hasMore: attempts.length == pageSize,
    );
  }

  static TestHistoryViewData buildViewData({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    required Map<String, Map<String, dynamic>> results,
    required String searchText,
    required String typeFilter,
    required String scoreFilter,
    required String sortBy,
    required String Function(Map<String, dynamic>) titleText,
    required String Function(String examId) examNameFor,
    required String Function(String examId, String testId) testNameFor,
    required String Function(Map<String, dynamic>) testTypeForAttempt,
    required double Function(Map<String, dynamic>, Map<String, dynamic>)
        scorePercent,
    required int Function(QueryDocumentSnapshot<Map<String, dynamic>>)
        attemptMinutes,
  }) {
    final key = [
      attempts.map((doc) => doc.id).join('|'),
      searchText,
      typeFilter,
      scoreFilter,
      sortBy,
      results.keys.join('|'),
    ].join('::');
    final cached = _viewCache[key];
    if (cached != null) return cached;

    final searched = attempts.where((doc) {
      if (searchText.isEmpty) return true;

      final data = doc.data();
      final testId = (data['testId'] ?? '').toString().toLowerCase();
      final examId = (data['examId'] ?? '').toString().toLowerCase();
      final title = titleText(data).toLowerCase();
      final examName = examNameFor((data['examId'] ?? '').toString()).toLowerCase();
      final testName = testNameFor(
        (data['examId'] ?? '').toString(),
        (data['testId'] ?? '').toString(),
      ).toLowerCase();

      return testId.contains(searchText) ||
          examId.contains(searchText) ||
          title.contains(searchText) ||
          examName.contains(searchText) ||
          testName.contains(searchText);
    }).toList(growable: false);

    final filtered = searched.where((doc) {
      final data = doc.data();
      if (typeFilter != 'all') {
        final isPractice = testTypeForAttempt(data) == 'Practice Test';
        if (typeFilter == 'mock' && isPractice) return false;
        if (typeFilter == 'practice' && !isPractice) return false;
      }

      if (scoreFilter != 'all') {
        final score = scorePercent(
          data,
          results[doc.id] ?? const <String, dynamic>{},
        );
        if (scoreFilter == 'high' && score < 80) return false;
        if (scoreFilter == 'revision' && score >= 50) return false;
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      final aData = a.data();
      final bData = b.data();
      final aScore = scorePercent(
        aData,
        results[a.id] ?? const <String, dynamic>{},
      );
      final bScore = scorePercent(
        bData,
        results[b.id] ?? const <String, dynamic>{},
      );
      final aTs =
          (aData['startedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final bTs =
          (bData['startedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

      switch (sortBy) {
        case 'oldest':
          return aTs.compareTo(bTs);
        case 'score_high':
          return bScore.compareTo(aScore);
        case 'score_low':
          return aScore.compareTo(bScore);
        case 'newest':
        default:
          return bTs.compareTo(aTs);
      }
    });

    double sum = 0;
    double best = 0;
    var totalMinutes = 0;
    for (final attempt in filtered) {
      final result = results[attempt.id] ?? const <String, dynamic>{};
      final score = scorePercent(attempt.data(), result);
      sum += score;
      if (score > best) best = score;
      totalMinutes += attemptMinutes(attempt);
    }

    final viewData = TestHistoryViewData(
      filteredAttempts: filtered,
      totalTests: filtered.length,
      avgScore: filtered.isEmpty ? 0 : sum / filtered.length,
      bestScore: best,
      totalMinutes: totalMinutes,
    );
    _viewCache[key] = viewData;
    return viewData;
  }

  static void invalidateScope(String userId, String? examId) {
    final prefix = '$userId|${examId ?? ''}|';
    _pageFutures.removeWhere((key, _) => key.startsWith(prefix));
    _viewCache.clear();
  }
}
