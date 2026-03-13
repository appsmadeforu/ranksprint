import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/result_data_service.dart';
import '../../widgets/top_header.dart';
import 'performance_trends_screen.dart';
import 'test_solution_screen.dart';
import 'test_runner_screen.dart';

class TestHistoryScreen extends StatefulWidget {
  final String? initialExamId;

  const TestHistoryScreen({super.key, this.initialExamId});

  @override
  State<TestHistoryScreen> createState() => _TestHistoryScreenState();
}

class _TestHistoryScreenState extends State<TestHistoryScreen> {
  String? selectedExamId;
  List<String> userExamIds = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  String _typeFilter = 'all';
  String _scoreFilter = 'all';
  String _sortBy = 'newest';
  final Set<String> _expandedAttemptIds = <String>{};
  final Map<String, String> _examNameCache = <String, String>{};
  final Map<String, String> _testNameCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadUserExams();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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

    setState(() {
      userExamIds = exams;
      if (widget.initialExamId != null &&
          exams.contains(widget.initialExamId)) {
        selectedExamId = widget.initialExamId;
      } else {
        selectedExamId = exams.isNotEmpty ? exams.first : null;
      }
    });
  }

  Query<Map<String, dynamic>> _attemptsQuery(String userId) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('testAttempts')
        .where('userId', isEqualTo: userId);

    if (selectedExamId != null && selectedExamId!.isNotEmpty) {
      query = query.where('examId', isEqualTo: selectedExamId);
    }

    return query;
  }

  bool _matchesSearch(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    if (_searchText.isEmpty) return true;

    final data = doc.data();
    final testId = (data['testId'] ?? '').toString().toLowerCase();
    final examId = (data['examId'] ?? '').toString().toLowerCase();
    final title = _titleText(data).toLowerCase();

    return testId.contains(_searchText) ||
        examId.contains(_searchText) ||
        title.contains(_searchText);
  }

  Future<Map<String, Map<String, dynamic>>> _loadResultsMap(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    if (attempts.isEmpty) return {};
    final first = attempts.first.data();
    return ResultDataService.loadResultsMap(
      attempts: attempts,
      userId: (first['userId'] ?? '').toString(),
      examId: selectedExamId ?? (first['examId'] ?? '').toString(),
    );
  }

  bool _passesTypeFilter(Map<String, dynamic> data) {
    if (_typeFilter == 'all') return true;
    final isPractice = _testType(data) == 'Practice Test';
    if (_typeFilter == 'mock') return !isPractice;
    if (_typeFilter == 'practice') return isPractice;
    return true;
  }

  bool _passesScoreFilter(
    Map<String, dynamic> data,
    Map<String, dynamic> result,
  ) {
    if (_scoreFilter == 'all') return true;
    final score = _scorePercent(data, result);
    if (_scoreFilter == 'high') return score >= 80;
    if (_scoreFilter == 'revision') return score < 50;
    return true;
  }

  void _sortItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, Map<String, dynamic>> results,
  ) {
    docs.sort((a, b) {
      final aData = a.data();
      final bData = b.data();
      final aScore = _scorePercent(
        aData,
        results[a.id] ?? const <String, dynamic>{},
      );
      final bScore = _scorePercent(
        bData,
        results[b.id] ?? const <String, dynamic>{},
      );
      final aTs =
          (aData['startedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final bTs =
          (bData['startedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

      switch (_sortBy) {
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
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('User not logged in')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: selectedExamId,
              userExamIds: userExamIds,
              onExamChanged: (id) {
                setState(() {
                  selectedExamId = id;
                });
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _attemptsQuery(userId).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    final emptyExamId = selectedExamId;
                    return Center(
                      child: Text(
                        (emptyExamId ?? '').isNotEmpty
                            ? 'No test history found for the selected exam.'
                            : 'No test history found.',
                      ),
                    );
                  }

                  final attempts =
                      List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                        snapshot.data!.docs,
                      )..sort((a, b) {
                        final aTs = a.data()['startedAt'] as Timestamp?;
                        final bTs = b.data()['startedAt'] as Timestamp?;
                        final aMs = aTs?.millisecondsSinceEpoch ?? 0;
                        final bMs = bTs?.millisecondsSinceEpoch ?? 0;
                        return bMs.compareTo(aMs);
                      });
                  final filtered = attempts.where(_matchesSearch).toList();

                  return FutureBuilder<Map<String, Map<String, dynamic>>>(
                    future: _loadResultsMap(filtered),
                    builder: (context, resultSnap) {
                      if (resultSnap.connectionState ==
                              ConnectionState.waiting &&
                          !resultSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final results =
                          resultSnap.data ?? <String, Map<String, dynamic>>{};

                      final interactive = filtered
                          .where(
                            (doc) =>
                                _passesTypeFilter(doc.data()) &&
                                _passesScoreFilter(
                                  doc.data(),
                                  results[doc.id] ?? const <String, dynamic>{},
                                ),
                          )
                          .toList();
                      _sortItems(interactive, results);

                      final totalTests = interactive.length;
                      final avgScore = _avgScore(interactive, results);
                      final bestScore = _bestScore(interactive, results);
                      final totalMinutes = interactive
                          .map(_attemptMinutes)
                          .fold<int>(0, (a, b) => a + b);

                      return RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                          children: [
                            _summarySection(
                              context,
                              totalTests: totalTests,
                              avgScore: avgScore,
                              bestScore: bestScore,
                              totalMinutes: totalMinutes,
                            ),
                            _searchSection(),
                            _filtersSection(),
                            if (interactive.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('No matching tests found.'),
                              ),
                            ...interactive.map(
                              (doc) => _attemptCard(
                                doc,
                                results[doc.id] ?? const <String, dynamic>{},
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
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
                      builder: (_) => const PerformanceTrendsScreen(),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search tests...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(10),
              color: const Color(0xFFF3F4F6),
            ),
            child: IconButton(
              onPressed: _openSortSheet,
              icon: const Icon(Icons.tune, color: Colors.black87, size: 20),
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
            onTap: () => setState(() => _typeFilter = 'all'),
          ),
          _filterChip(
            label: 'Mock',
            selected: _typeFilter == 'mock',
            onTap: () => setState(() => _typeFilter = 'mock'),
          ),
          _filterChip(
            label: 'Practice',
            selected: _typeFilter == 'practice',
            onTap: () => setState(() => _typeFilter = 'practice'),
          ),
          _filterChip(
            label: '80%+',
            selected: _scoreFilter == 'high',
            onTap: () => setState(
              () => _scoreFilter = _scoreFilter == 'high' ? 'all' : 'high',
            ),
          ),
          _filterChip(
            label: 'Needs Revision',
            selected: _scoreFilter == 'revision',
            onTap: () => setState(
              () => _scoreFilter = _scoreFilter == 'revision'
                  ? 'all'
                  : 'revision',
            ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A8A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF1E3A8A) : const Color(0xFFD1D5DB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : const Color(0xFF374151),
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
                  setState(() => _sortBy = 'newest');
                },
              ),
              ListTile(
                title: const Text('Oldest First'),
                trailing: _sortBy == 'oldest' ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _sortBy = 'oldest');
                },
              ),
              ListTile(
                title: const Text('Highest Score'),
                trailing: _sortBy == 'score_high'
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _sortBy = 'score_high');
                },
              ),
              ListTile(
                title: const Text('Lowest Score'),
                trailing: _sortBy == 'score_low'
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _sortBy = 'score_low');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openSolutionScreen(
    String attemptId,
    Map<String, dynamic> data,
    Map<String, dynamic> result,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) =>
            TestSolutionScreen(
              attemptId: attemptId,
              attemptData: data,
              resultData: result,
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
    _primeExamName(examId);
    return 'Exam';
  }

  String _testDisplayName(String examId, String testId) {
    if (testId.isEmpty) return 'Test';
    final key = '$examId|$testId';
    final cached = _testNameCache[key];
    if (cached != null && cached.isNotEmpty) return cached;
    _primeTestName(examId, testId);
    return 'Test';
  }

  Future<void> _primeExamName(String examId) async {
    if (examId.isEmpty || _examNameCache.containsKey(examId)) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('exams')
          .doc(examId)
          .get();
      final name = (doc.data()?['name'] ?? 'Exam').toString();
      if (!mounted) return;
      setState(() {
        _examNameCache[examId] = name;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _examNameCache[examId] = 'Exam';
      });
    }
  }

  Future<void> _primeTestName(String examId, String testId) async {
    final key = '$examId|$testId';
    if (examId.isEmpty || testId.isEmpty || _testNameCache.containsKey(key)) {
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('exams')
          .doc(examId)
          .collection('tests')
          .doc(testId)
          .get();
      final name = (doc.data()?['name'] ?? 'Test').toString();
      if (!mounted) return;
      setState(() {
        _testNameCache[key] = name;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testNameCache[key] = 'Test';
      });
    }
  }

  Widget _attemptCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> result,
  ) {
    final data = doc.data();
    final correct =
        _toInt(result['correct']) ?? (data['answers'] as Map?)?.length ?? 0;
    final wrong = _toInt(result['incorrect']) ?? _toInt(data['wrong']) ?? 0;
    final skipped =
        _toInt(result['unanswered']) ?? _toInt(data['skipped']) ?? 0;

    final totalQuestions = (correct + wrong + skipped) > 0
        ? (correct + wrong + skipped)
        : 20;
    final percent = (correct / totalQuestions) * 100;

    final rank = _toInt(result['rank']) ?? _toInt(data['rank']) ?? 0;
    final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
    final timeTaken = _attemptMinutes(doc);
    final examIdRaw = (data['examId'] ?? '').toString();
    final testIdRaw = (data['testId'] ?? '').toString();
    final examName = _examDisplayName(examIdRaw);
    final testName = _testDisplayName(examIdRaw, testIdRaw);
    final testType = _testType(data);
    final isExpanded = _expandedAttemptIds.contains(doc.id);

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
          if (isExpanded) {
            _expandedAttemptIds.remove(doc.id);
          } else {
            _expandedAttemptIds.add(doc.id);
          }
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
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
                    testName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF9CA3AF),
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
                _chip(examName),
                _chip(testType),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: Color(0xFF6B7280),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      startedAt == null ? '' : _formatPrettyDate(startedAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
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
                Expanded(child: _statItem('#$rank', 'Rank')),
                const SizedBox(width: 8),
                Expanded(
                  child: _statItem(
                    '$correct',
                    'Correct',
                    valueColor: const Color(0xFF169D4A),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statItem(
                    '$wrong',
                    'Wrong',
                    valueColor: const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _statItem('$skipped', 'Skipped')),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 16,
                  color: Color(0xFF6B7280),
                ),
                const SizedBox(width: 6),
                Text(
                  'Time: $timeTaken min',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF374151),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    _openSolutionScreen(doc.id, data, result);
                  },
                  child: const Text(
                    'View Solutions ->',
                    style: TextStyle(
                      color: Color(0xFF1D4ED8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: isExpanded
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
                                  if (examIdRaw.isEmpty || testIdRaw.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Cannot retake this test',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TestRunnerScreen(
                                        examId: examIdRaw,
                                        testId: testIdRaw,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.restart_alt, size: 16),
                                label: const Text('Retake'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _openSolutionScreen(doc.id, data, result),
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

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF1D4ED8),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statItem(
    String value,
    String label, {
    Color valueColor = const Color(0xFF111827),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: valueColor,
              fontSize: 26,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  double _avgScore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    Map<String, Map<String, dynamic>> results,
  ) {
    if (attempts.isEmpty) return 0;

    double sum = 0;
    for (final attempt in attempts) {
      sum += _scorePercent(
        attempt.data(),
        results[attempt.id] ?? const <String, dynamic>{},
      );
    }

    return sum / attempts.length;
  }

  double _bestScore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    Map<String, Map<String, dynamic>> results,
  ) {
    double best = 0;
    for (final attempt in attempts) {
      final score = _scorePercent(
        attempt.data(),
        results[attempt.id] ?? const <String, dynamic>{},
      );
      if (score > best) best = score;
    }
    return best;
  }

  double _scorePercent(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
  ) {
    final correct =
        _toInt(result['correct']) ?? (attempt['answers'] as Map?)?.length ?? 0;
    final wrong = _toInt(result['incorrect']) ?? _toInt(attempt['wrong']) ?? 0;
    final skipped =
        _toInt(result['unanswered']) ?? _toInt(attempt['skipped']) ?? 0;

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
