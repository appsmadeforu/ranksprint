import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../examSummary/exam_summary_screen.dart';
import '../../sections/section_bean.dart';
import '../../services/exam_metadata_cache_service.dart';
import '../../services/result_data_service.dart';
import '../../services/test_history_view_model_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/offline_state.dart';
import '../../widgets/top_header.dart';
import 'performance_trends_screen.dart';
import 'test_runner_screen.dart';

class TestHistoryScreen extends StatefulWidget {
  final String? initialExamId;

  const TestHistoryScreen({super.key, this.initialExamId});

  @override
  State<TestHistoryScreen> createState() => _TestHistoryScreenState();
}

class _TestHistoryScreenState extends State<TestHistoryScreen> {
  static const int _historyPageSize = 20;

  String? selectedExamId;
  List<String> userExamIds = [];

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchText = '';
  String _typeFilter = 'all';
  String _scoreFilter = 'all';
  String _sortBy = 'newest';
  bool _isInitialLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreAttempts = true;
  String? _loadErrorMessage;
  QueryDocumentSnapshot<Map<String, dynamic>>? _lastAttemptDoc;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _attempts =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  Map<String, Map<String, dynamic>> _results =
      <String, Map<String, dynamic>>{};
  TestHistoryViewData _viewData = const TestHistoryViewData(
    filteredAttempts: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
    totalTests: 0,
    avgScore: 0,
    bestScore: 0,
    totalMinutes: 0,
  );
  final Map<String, String> _examNameCache = <String, String>{};
  final Map<String, String> _testNameCache = <String, String>{};
  final Set<String> _examNameRequestsInFlight = <String>{};
  final Set<String> _testNameRequestsInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    UserExamPreferenceService.preferredExamNotifier.addListener(
      _handlePreferredExamChanged,
    );
    _loadUserExams();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
        _rebuildViewData();
      });
    });
    _scrollController.addListener(_handleHistoryScroll);
  }

  @override
  void dispose() {
    UserExamPreferenceService.preferredExamNotifier.removeListener(
      _handlePreferredExamChanged,
    );
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserExams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data() ?? <String, dynamic>{};
    final exams = List<String>.from(data['selectedExams'] ?? []);
    final preferredExamId =
        widget.initialExamId != null && exams.contains(widget.initialExamId)
        ? widget.initialExamId
        : await UserExamPreferenceService.loadPreferredExamId(
            availableExamIds: exams,
          );

    if (!mounted) return;
    setState(() {
      userExamIds = exams;
      selectedExamId = preferredExamId;
    });
    await _loadInitialHistory();
  }

  void _handlePreferredExamChanged() {
    final preferredExamId =
        UserExamPreferenceService.preferredExamNotifier.value;
    if (!mounted ||
        preferredExamId == null ||
        preferredExamId == selectedExamId ||
        !userExamIds.contains(preferredExamId)) {
      return;
    }

    setState(() {
      selectedExamId = preferredExamId;
      _resetLoadedData();
    });
    _loadInitialHistory();
  }

  void _resetLoadedData() {
    _isInitialLoading = false;
    _isLoadingMore = false;
    _hasMoreAttempts = true;
    _loadErrorMessage = null;
    _lastAttemptDoc = null;
    _attempts = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    _results = <String, Map<String, dynamic>>{};
    _viewData = const TestHistoryViewData(
      filteredAttempts: <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      totalTests: 0,
      avgScore: 0,
      bestScore: 0,
      totalMinutes: 0,
    );
  }

  void _handleHistoryScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 500) return;
    _loadMoreHistory();
  }

  Future<void> _refresh() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      TestHistoryViewModelService.invalidateScope(userId, selectedExamId);
      ResultDataService.invalidateUserScope(userId: userId, examId: selectedExamId);
    }
    await _loadInitialHistory(forceRefresh: true);
  }

  Future<void> _warmVisibleMetadata(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    if (attempts.isEmpty) return;

    final examIdsToLoad = <String>{};
    final testKeysToLoad = <String>{};
    final futures = <Future<void>>[];

    for (final doc in attempts) {
      final data = doc.data();
      final examId = (data['examId'] ?? '').toString();
      final testId = (data['testId'] ?? '').toString();
      if (examId.isNotEmpty &&
          !_examNameCache.containsKey(examId) &&
          _examNameRequestsInFlight.add(examId)) {
        examIdsToLoad.add(examId);
        futures.add(_loadExamName(examId));
      }

      final testKey = '$examId|$testId';
      if (examId.isNotEmpty &&
          testId.isNotEmpty &&
          !_testNameCache.containsKey(testKey) &&
          _testNameRequestsInFlight.add(testKey)) {
        testKeysToLoad.add(testKey);
        futures.add(_loadTestName(examId, testId));
      }
    }

    if (futures.isEmpty) return;

    await Future.wait(futures);
    if (!mounted) return;

    setState(() {
      _rebuildViewData();
      for (final examId in examIdsToLoad) {
        _examNameRequestsInFlight.remove(examId);
      }
      for (final testKey in testKeysToLoad) {
        _testNameRequestsInFlight.remove(testKey);
      }
    });
  }

  Future<void> _loadExamName(String examId) async {
    try {
      final name = ((await ExamMetadataCacheService.getExamName(examId)) ?? 'Exam')
          .toString();
      _examNameCache[examId] = name;
    } catch (_) {
      _examNameCache[examId] = 'Exam';
    }
  }

  Future<void> _loadTestName(String examId, String testId) async {
    final key = '$examId|$testId';
    try {
      final name =
          ((await ExamMetadataCacheService.getTestName(examId, testId)) ?? 'Test')
              .toString();
      _testNameCache[key] = name;
    } catch (_) {
      _testNameCache[key] = 'Test';
    }
  }

  void _rebuildViewData() {
    _viewData = TestHistoryViewModelService.buildViewData(
      attempts: _attempts,
      results: _results,
      searchText: _searchText,
      typeFilter: _typeFilter,
      scoreFilter: _scoreFilter,
      sortBy: _sortBy,
      titleText: _titleText,
      examNameFor: _examDisplayName,
      testNameFor: _testDisplayName,
      testTypeForAttempt: _testType,
      scorePercent: _scorePercent,
      attemptMinutes: _attemptMinutes,
    );
  }

  Future<void> _loadInitialHistory({bool forceRefresh = false}) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      _resetLoadedData();
      _isInitialLoading = true;
    });

    final expectedExamId = selectedExamId;
    try {
      var effectiveExamId = expectedExamId;
      TestHistoryPage page;
      try {
        page = await TestHistoryViewModelService.loadPage(
          userId: userId,
          examId: effectiveExamId,
          pageSize: _historyPageSize,
          forceRefresh: forceRefresh,
        );
      } catch (_) {
        if ((effectiveExamId ?? '').isEmpty) rethrow;
        effectiveExamId = null;
        page = await TestHistoryViewModelService.loadPage(
          userId: userId,
          examId: null,
          pageSize: _historyPageSize,
          forceRefresh: forceRefresh,
        );
      }
      if (!mounted || expectedExamId != selectedExamId) return;

      _attempts = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
        page.attempts,
      );
      _results = Map<String, Map<String, dynamic>>.from(page.results);
      _lastAttemptDoc = page.lastAttemptDoc;
      _hasMoreAttempts = page.hasMore;
      _loadErrorMessage = null;
      _rebuildViewData();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _warmVisibleMetadata(_attempts);
      });
      setState(() {
        selectedExamId = effectiveExamId;
        _isInitialLoading = false;
      });
    } catch (_) {
      if (!mounted || expectedExamId != selectedExamId) return;
      setState(() {
        _isInitialLoading = false;
        _loadErrorMessage =
            'Could not load test history. Please check your connection and try again.';
      });
    }
  }

  Future<void> _loadMoreHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null ||
        _isInitialLoading ||
        _isLoadingMore ||
        !_hasMoreAttempts ||
        _lastAttemptDoc == null) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    final expectedExamId = selectedExamId;
    try {
      final page = await TestHistoryViewModelService.loadPage(
        userId: userId,
        examId: expectedExamId,
        pageSize: _historyPageSize,
        startAfter: _lastAttemptDoc,
      );
      if (!mounted || expectedExamId != selectedExamId) return;

      final existingIds = _attempts.map((doc) => doc.id).toSet();
      for (final doc in page.attempts) {
        if (existingIds.add(doc.id)) {
          _attempts.add(doc);
        }
      }
      _results.addAll(page.results);
      _lastAttemptDoc = page.lastAttemptDoc;
      _hasMoreAttempts = page.hasMore;
      _rebuildViewData();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _warmVisibleMetadata(page.attempts);
      });
      setState(() {
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || expectedExamId != selectedExamId) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (FirebaseAuth.instance.currentUser?.uid == null) {
      return const Scaffold(body: Center(child: Text('User not logged in')));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: selectedExamId,
              userExamIds: userExamIds,
              showBackButton: true,
              onExamChanged: (id) {
                setState(() {
                  selectedExamId = id;
                  _resetLoadedData();
                });
                _loadInitialHistory();
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _buildHistoryBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summarySection(
    BuildContext context, {
    required int totalTests,
    required double avgScore,
    required double bestScore,
    required int totalMinutes,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF24439A), Color(0xFF3459B9)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Track all your completed tests',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PerformanceTrendsScreen(
                        initialExamId: selectedExamId,
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E3A8A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View Trends',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _historyMetric('Tests Attempted', '$totalTests'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _historyMetric(
                  'Average Score',
                  '${avgScore.toStringAsFixed(0)}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _historyMetric(
                  'Best Score',
                  '${bestScore.toStringAsFixed(0)}%',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _historyMetric('Total Time', _formatHours(totalMinutes)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyMetric(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search tests...',
                hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
                filled: true,
                fillColor: colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
              color: colorScheme.surface,
            ),
            child: IconButton(
              onPressed: _openSortSheet,
              icon: Icon(
                Icons.tune,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtersSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip(
            label: 'All',
            selected: _typeFilter == 'all',
            onTap: () => _typeFilter = 'all',
          ),
          _filterChip(
            label: 'Mock',
            selected: _typeFilter == 'mock',
            onTap: () => _typeFilter = 'mock',
          ),
          _filterChip(
            label: 'Practice',
            selected: _typeFilter == 'practice',
            onTap: () => _typeFilter = 'practice',
          ),
          _filterChip(
            label: '80%+',
            selected: _scoreFilter == 'high',
            onTap: () => _scoreFilter = _scoreFilter == 'high' ? 'all' : 'high',
          ),
          _filterChip(
            label: 'Needs Revision',
            selected: _scoreFilter == 'revision',
            onTap: () => _scoreFilter = _scoreFilter == 'revision'
                ? 'all'
                : 'revision',
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        setState(() {
          onTap();
          _rebuildViewData();
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _openSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Newest First'),
                trailing: _sortBy == 'newest' ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _sortBy = 'newest';
                    _rebuildViewData();
                  });
                },
              ),
              ListTile(
                title: const Text('Oldest First'),
                trailing: _sortBy == 'oldest' ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _sortBy = 'oldest';
                    _rebuildViewData();
                  });
                },
              ),
              ListTile(
                title: const Text('Highest Score'),
                trailing: _sortBy == 'score_high'
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _sortBy = 'score_high';
                    _rebuildViewData();
                  });
                },
              ),
              ListTile(
                title: const Text('Lowest Score'),
                trailing: _sortBy == 'score_low'
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _sortBy = 'score_low';
                    _rebuildViewData();
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSolutionScreen(
    Map<String, dynamic> data,
    Map<String, dynamic> result,
  ) async {
    final examId = (data['examId'] ?? '').toString();
    final testId = (data['testId'] ?? '').toString();
    final sections = examId.isEmpty || testId.isEmpty
        ? <SectionBean>[]
        : await ExamMetadataCacheService.getSectionBeans(examId, testId);
    if (!mounted) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ExamResultScreen(
              questions: result['question'] ?? const [],
              answers: result['answers'] ?? const <String, dynamic>{},
              correct: _toInt(result['correct']) ?? 0,
              section: sections,
              incorrect: _toInt(result['incorrect']) ?? 0,
              unanswered: _toInt(result['unanswered']) ?? 0,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.02, 0.02),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  String _examDisplayName(String examId) {
    if (examId.isEmpty) return 'Exam';
    final cached = _examNameCache[examId];
    if (cached != null && cached.isNotEmpty) return cached;
    return 'Exam';
  }

  String _testDisplayName(String examId, String testId) {
    if (testId.isEmpty) return 'Test';
    final key = '$examId|$testId';
    final cached = _testNameCache[key];
    if (cached != null && cached.isNotEmpty) return cached;
    return 'Test';
  }

  void _openRetakeTest(String examId, String testId) {
    if (examId.isEmpty || testId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot retake this test')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TestRunnerScreen(examId: examId, testId: testId),
      ),
    );
  }

  Widget _buildHistoryBody() {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadErrorMessage != null) {
      return OfflineState(
        message: _loadErrorMessage!,
        onRetry: _refresh,
      );
    }

    if (_attempts.isEmpty) {
      final emptyExamId = selectedExamId;
      return Center(
        child: Text(
          (emptyExamId ?? '').isNotEmpty
              ? 'No test history found for the selected exam.'
              : 'No test history found.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: 4 + _viewData.filteredAttempts.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _summarySection(
              context,
              totalTests: _viewData.totalTests,
              avgScore: _viewData.avgScore,
              bestScore: _viewData.bestScore,
              totalMinutes: _viewData.totalMinutes,
            );
          }
          if (index == 1) {
            return _searchSection();
          }
          if (index == 2) {
            return _filtersSection();
          }
          if (index == 3) {
            return _viewData.filteredAttempts.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No matching tests found.'),
                  )
                : const SizedBox.shrink();
          }

          final listIndex = index - 4;
          if (listIndex >= _viewData.filteredAttempts.length) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final doc = _viewData.filteredAttempts[listIndex];
          return _AttemptCard(
            key: ValueKey(doc.id),
            doc: doc,
            result: _results[doc.id] ?? const <String, dynamic>{},
            examName: _examDisplayName(
              (doc.data()['examId'] ?? '').toString(),
            ),
            testName: _testDisplayName(
              (doc.data()['examId'] ?? '').toString(),
              (doc.data()['testId'] ?? '').toString(),
            ),
            onOpenSolutions: _openSolutionScreen,
            onRetake: _openRetakeTest,
            attemptMinutesForDoc: _attemptMinutes,
            scorePercentForAttempt: _scorePercent,
            toInt: _toInt,
            testTypeForAttempt: _testType,
            prettyDate: _formatPrettyDate,
          );
        },
      ),
    );
  }

  double _scorePercent(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
  ) {
    final normalizedCounts = ResultDataService.normalizeCounts(
      attempt: attempt,
      result: result,
    );
    final correct = normalizedCounts['correct'] ?? 0;
    final wrong = normalizedCounts['incorrect'] ?? 0;
    final skipped = normalizedCounts['unanswered'] ?? 0;

    final total = (correct + wrong + skipped) > 0
        ? (correct + wrong + skipped)
        : 20;

    return (correct / total) * 100;
  }

  int _attemptMinutes(QueryDocumentSnapshot<Map<String, dynamic>> attemptDoc) {
    final data = attemptDoc.data();

    final direct = _toInt(data['timeTaken']);
    if (direct != null) return direct;

    final started = (data['startedAt'] as Timestamp?)?.toDate();
    final submitted = (data['submittedAt'] as Timestamp?)?.toDate();

    if (started != null && submitted != null) {
      final diff = submitted.difference(started).inMinutes;
      return diff < 0 ? 0 : diff;
    }

    return 0;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _testType(Map<String, dynamic> data) {
    final testId = (data['testId'] ?? '').toString().toLowerCase();
    if (testId.contains('practice')) return 'Practice Test';
    return 'Mock Test';
  }

  String _titleText(Map<String, dynamic> data) {
    final exam = (data['examId'] ?? '').toString().toUpperCase();
    final testId = (data['testId'] ?? '').toString();
    return '$exam ${_testType(data)} #$testId';
  }

  String _formatPrettyDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatHours(int totalMinutes) {
    if (totalMinutes <= 0) return '0h';
    return '${totalMinutes ~/ 60}h';
  }
}

class _AttemptCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, dynamic> result;
  final String examName;
  final String testName;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>)
      onOpenSolutions;
  final void Function(String examId, String testId) onRetake;
  final int Function(QueryDocumentSnapshot<Map<String, dynamic>>) attemptMinutesForDoc;
  final double Function(Map<String, dynamic>, Map<String, dynamic>)
      scorePercentForAttempt;
  final int? Function(dynamic value) toInt;
  final String Function(Map<String, dynamic>) testTypeForAttempt;
  final String Function(DateTime date) prettyDate;

  const _AttemptCard({
    super.key,
    required this.doc,
    required this.result,
    required this.examName,
    required this.testName,
    required this.onOpenSolutions,
    required this.onRetake,
    required this.attemptMinutesForDoc,
    required this.scorePercentForAttempt,
    required this.toInt,
    required this.testTypeForAttempt,
    required this.prettyDate,
  });

  @override
  State<_AttemptCard> createState() => _AttemptCardState();
}

class _AttemptCardState extends State<_AttemptCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final data = widget.doc.data();
    final normalizedCounts = ResultDataService.normalizeCounts(
      attempt: data,
      result: widget.result,
    );
    final correct = normalizedCounts['correct'] ?? 0;
    final wrong = normalizedCounts['incorrect'] ?? 0;
    final skipped = normalizedCounts['unanswered'] ?? 0;
    final totalQuestions = (correct + wrong + skipped) > 0
        ? (correct + wrong + skipped)
        : 20;
    final percent = widget.scorePercentForAttempt(data, widget.result);
    final rank = widget.toInt(widget.result['rank']) ?? widget.toInt(data['rank']) ?? 0;
    final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
    final timeTaken = widget.attemptMinutesForDoc(widget.doc);
    final examIdRaw = (data['examId'] ?? '').toString();
    final testIdRaw = (data['testId'] ?? '').toString();
    final testType = widget.testTypeForAttempt(data);
    final isGoodScore = percent >= 80;
    final boxBg = isGoodScore
        ? const Color(0xFFE7F6EC)
        : const Color(0xFFF8F1DF);
    final scoreColor = isGoodScore
        ? const Color(0xFF169D4A)
        : const Color(0xFFD97706);

    return InkWell(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.testName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _cardChip(widget.examName),
                _cardChip(testType),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      startedAt == null ? '' : widget.prettyDate(startedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: boxBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$correct/$totalQuestions',
                          style: TextStyle(
                            color: scoreColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 36,
                          ),
                        ),
                        Text(
                          '${percent.toStringAsFixed(0)}% Score',
                          style: TextStyle(color: scoreColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.emoji_events_outlined,
                    color: scoreColor,
                    size: 26,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _cardStatItem('#$rank', 'Rank')),
                const SizedBox(width: 8),
                Expanded(
                  child: _cardStatItem(
                    '$correct',
                    'Correct',
                    valueColor: const Color(0xFF169D4A),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _cardStatItem(
                    '$wrong',
                    'Wrong',
                    valueColor: const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _cardStatItem('$skipped', 'Skipped')),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Time: $timeTaken min',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    widget.onOpenSolutions(data, widget.result);
                  },
                  child: Text(
                    'View Solutions ->',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: _isExpanded
                  ? TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      tween: Tween<double>(begin: 0, end: 1),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * 6),
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  widget.onRetake(examIdRaw, testIdRaw);
                                },
                                icon: const Icon(Icons.restart_alt, size: 16),
                                label: const Text('Retake'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    widget.onOpenSolutions(data, widget.result),
                                icon: const Icon(
                                  Icons.insights_outlined,
                                  size: 16,
                                ),
                                label: const Text('Insights'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardChip(String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _cardStatItem(
    String value,
    String label, {
    Color? valueColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedValueColor = valueColor ?? colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: resolvedValueColor,
              fontSize: 26,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
