import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/result_data_service.dart';
import '../../widgets/top_header.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String? selectedExamId;
  List<String> userExamIds = [];
  final TextEditingController _leaderboardSearchController =
      TextEditingController();
  String _leaderboardQuery = '';
  final Map<String, String> _userNameCache = <String, String>{};
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _questionCache =
      <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

  @override
  void initState() {
    super.initState();
    _loadUserExams();
  }

  Future<void> _loadUserExams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final exams = List<String>.from(doc.data()?['selectedExams'] ?? []);

    setState(() {
      userExamIds = exams;
      selectedExamId = exams.isNotEmpty ? exams.first : null;
    });
  }

  @override
  void dispose() {
    _leaderboardSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: selectedExamId,
              userExamIds: userExamIds,
              onExamChanged: (examId) {
                setState(() {
                  selectedExamId = examId;
                });
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: selectedExamId == null
                  ? const Center(child: Text('No exam selected'))
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const TabBar(
                                indicatorColor: Color(0xFF2F6FEB),
                                labelColor: Colors.black,
                                tabs: [
                                  Tab(text: 'Leaderboard'),
                                  Tab(text: 'Dashboard'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildLeaderboard(),
                                _buildDashboard(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboard() {
    final currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('results')
          .where('examId', isEqualTo: selectedExamId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs.cast<QueryDocumentSnapshot>();
        if (docs.isEmpty) {
          return const Center(child: Text('No leaderboard data'));
        }

        final entries = _aggregateLeaderboard(docs);
        if (entries.isEmpty) {
          return const Center(child: Text('No leaderboard data'));
        }

        return FutureBuilder<List<_LeaderboardRow>>(
          future: _hydrateLeaderboard(entries),
          builder: (context, rowsSnap) {
            if (!rowsSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allRows = rowsSnap.data!;
            final visibleRows = allRows.where(_matchesLeaderboardQuery).toList();

            if (visibleRows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildLeaderboardSearch(),
                    const Expanded(
                      child: Center(child: Text('No leaderboard matches found')),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildLeaderboardSearch(),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visibleRows.length,
                      itemBuilder: (context, index) {
                        final row = visibleRows[index];
                        return _buildLeaderboardCard(
                          row: row,
                          isCurrentUser:
                              currentUser != null &&
                              currentUser.uid == row.entry.userId,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLeaderboardSearch() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: _leaderboardSearchController,
        onChanged: (value) {
          setState(() {
            _leaderboardQuery = value.trim().toLowerCase();
          });
        },
        decoration: InputDecoration(
          hintText: 'Search by name or rank...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Future<List<_LeaderboardRow>> _hydrateLeaderboard(
    List<_LeaderboardAgg> entries,
  ) async {
    await _loadUserDisplayNames(entries.map((entry) => entry.userId));

    return List.generate(entries.length, (index) {
      final entry = entries[index];
      return _LeaderboardRow(
        entry: entry,
        rank: index + 1,
        displayName: _userNameCache[entry.userId] ?? entry.userId,
      );
    });
  }

  Future<void> _loadUserDisplayNames(Iterable<String> userIds) async {
    final missing = userIds
        .where((id) => id.isNotEmpty && !_userNameCache.containsKey(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;

    for (int i = 0; i < missing.length; i += 10) {
      final chunk = missing.sublist(i, (i + 10).clamp(0, missing.length));
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        final found = <String>{};
        for (final doc in snap.docs) {
          final data = doc.data();
          _userNameCache[doc.id] =
              (data['name'] ?? data['displayName'] ?? doc.id).toString();
          found.add(doc.id);
        }

        for (final id in chunk) {
          _userNameCache.putIfAbsent(id, () => id);
        }
      } catch (_) {
        for (final id in chunk) {
          _userNameCache.putIfAbsent(id, () => id);
        }
      }
    }
  }

  bool _matchesLeaderboardQuery(_LeaderboardRow row) {
    if (_leaderboardQuery.isEmpty) return true;

    return row.displayName.toLowerCase().contains(_leaderboardQuery) ||
        row.rank.toString().contains(_leaderboardQuery);
  }

  Widget _buildLeaderboardCard({
    required _LeaderboardRow row,
    required bool isCurrentUser,
  }) {
    final rank = row.rank;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: isCurrentUser
                ? const LinearGradient(
                    colors: [Color(0xFF2F6FEB), Color(0xFF6EA8FF)],
                  )
                : null,
            color: isCurrentUser ? null : Colors.white,
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: isCurrentUser
                  ? Colors.white.withValues(alpha: 0.95)
                  : Colors.white,
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: rank == 1
                        ? Colors.amber
                        : rank == 2
                        ? Colors.grey
                        : rank == 3
                        ? Colors.brown
                        : const Color(0xFFEFF3FF),
                  ),
                  child: Center(
                    child: rank <= 3
                        ? const Icon(
                            Icons.emoji_events,
                            color: Colors.white,
                          )
                        : Text(
                            '#$rank',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2F6FEB),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.displayName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${row.entry.testsTaken} tests - ${row.entry.avgPercentile.toStringAsFixed(1)} %ile',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      row.entry.avgScore.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCurrentUser ? 'your score' : 'avg score',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('User not logged in'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('testAttempts')
          .where('examId', isEqualTo: selectedExamId)
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final attempts = snap.data!.docs
            .cast<QueryDocumentSnapshot<Map<String, dynamic>>>()
            .where((doc) {
              final status = (doc.data()['status'] ?? 'completed')
                  .toString()
                  .toLowerCase();
              return status == 'completed';
            })
            .toList()
          ..sort((a, b) {
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

        if (attempts.isEmpty) {
          return const Center(child: Text('No analytics data'));
        }

        return FutureBuilder<_DashboardVm>(
          future: _loadDashboardVm(user.uid, selectedExamId!, attempts),
          builder: (context, vmSnap) {
            if (!vmSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final vm = vmSnap.data!;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _metricCard(
                          icon: Icons.checklist_rounded,
                          iconColor: const Color(0xFF16A34A),
                          value: '${vm.testsTaken}',
                          label: 'Tests Taken',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricCard(
                          icon: Icons.workspace_premium_outlined,
                          iconColor: const Color(0xFFF97316),
                          value: vm.bestRank > 0 ? '${vm.bestRank}' : '-',
                          label: 'Top Rank',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricCard(
                          icon: Icons.query_stats_rounded,
                          iconColor: const Color(0xFF1D4ED8),
                          value: '${vm.avgScore.toStringAsFixed(0)}%',
                          label: 'Avg Score',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _dashboardSection(
                    title: 'Performance Trend',
                    child: Column(
                      children: [
                        SizedBox(
                          height: 180,
                          child: vm.trend.length < 2
                              ? const Center(
                                  child: Text(
                                    'Need at least 2 attempts to show trend',
                                  ),
                                )
                              : _DashboardTrendChart(points: vm.trend),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _dashboardSection(
                    title: 'Subject-wise Accuracy',
                    child: vm.subjects.isEmpty
                        ? const Text('No subject data available')
                        : Column(
                            children: vm.subjects
                                .map(
                                  (subject) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _subjectRow(subject),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                  const SizedBox(height: 16),
                  _dashboardSection(
                    title: 'Time per Question',
                    child: Column(
                      children: [
                        SizedBox(
                          height: 170,
                          child: _TimePerQuestionChart(buckets: vm.timeBuckets),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Average time: ${vm.avgSecondsPerQuestion.toStringAsFixed(0)} seconds per question',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (vm.improvements.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7E8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF4C95D)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Areas to Improve',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...vm.improvements.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFDE68A),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${item.accuracy.toStringAsFixed(0)}% accuracy',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<_DashboardVm> _loadDashboardVm(
    String userId,
    String examId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    // Dashboard metrics are derived from completed attempt/result pairs.
    final resultMap = await _loadDashboardResultMap(attempts, userId, examId);
    final subjects = await _dashboardSubjectStats(attempts);
    subjects.sort((a, b) => b.accuracy.compareTo(a.accuracy));

    final trend = <_DashboardPoint>[];
    final timeBuckets = <_TimeBucket>[
      _TimeBucket(label: '0-30s', minSeconds: 0, maxSeconds: 30),
      _TimeBucket(label: '30-60s', minSeconds: 30, maxSeconds: 60),
      _TimeBucket(label: '60-90s', minSeconds: 60, maxSeconds: 90),
      _TimeBucket(label: '90s+', minSeconds: 90, maxSeconds: null),
    ];

    double totalScore = 0;
    double totalSecondsPerQuestion = 0;
    int spqCount = 0;
    int bestRank = 0;

    for (int i = 0; i < attempts.length; i++) {
      final attempt = attempts[i].data();
      final result = resultMap[attempts[i].id] ?? const <String, dynamic>{};
      final score = _dashboardScorePct(attempt, result);
      totalScore += score;
      trend.add(_DashboardPoint(label: 'Test ${i + 1}', value: score));

      final rank = _toInt(result['rank']) ?? 0;
      if (rank > 0 && (bestRank == 0 || rank < bestRank)) {
        bestRank = rank;
      }

      final secondsPerQuestion = _secondsPerQuestion(attempt, result);
      if (secondsPerQuestion != null) {
        totalSecondsPerQuestion += secondsPerQuestion;
        spqCount++;
        for (final bucket in timeBuckets) {
          if (bucket.matches(secondsPerQuestion)) {
            bucket.count++;
            break;
          }
        }
      }
    }

    final avgScore = attempts.isEmpty ? 0.0 : totalScore / attempts.length;
    final avgSecondsPerQuestion =
        spqCount == 0 ? 0.0 : totalSecondsPerQuestion / spqCount;

    return _DashboardVm(
      testsTaken: attempts.length,
      bestRank: bestRank,
      avgScore: avgScore,
      trend: trend,
      subjects: subjects,
      timeBuckets: timeBuckets,
      avgSecondsPerQuestion: avgSecondsPerQuestion,
      improvements: List<_SubjectMetric>.from(
        subjects.reversed.take(2).toList().reversed,
      ),
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadDashboardResultMap(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    String userId,
    String examId,
  ) async {
    return ResultDataService.loadResultsMap(
      attempts: attempts,
      userId: userId,
      examId: examId,
    );
  }

  Future<List<_SubjectMetric>> _dashboardSubjectStats(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    final out = <String, _SubjectMetric>{};

    for (final attemptDoc in attempts) {
      final attempt = attemptDoc.data();
      final examId = (attempt['examId'] ?? '').toString();
      final testId = (attempt['testId'] ?? '').toString();
      if (examId.isEmpty || testId.isEmpty) continue;

      final cacheKey = '$examId|$testId';
      if (!_questionCache.containsKey(cacheKey)) {
        try {
          final qs = await FirebaseFirestore.instance
              .collection('exams')
              .doc(examId)
              .collection('tests')
              .doc(testId)
              .collection('questions')
              .get();
          _questionCache[cacheKey] = qs.docs;
        } catch (_) {
          _questionCache[cacheKey] = const [];
        }
      }

      final questions = _questionCache[cacheKey] ?? const [];
      final answers = <String, String>{};
      if (attempt['answers'] is Map) {
        final raw = attempt['answers'] as Map;
        for (final entry in raw.entries) {
          answers[entry.key.toString()] = (entry.value ?? '').toString();
        }
      }

      for (final qDoc in questions) {
        final question = qDoc.data();
        final subject =
            (question['subject'] ??
                    question['sectionName'] ??
                    question['section'] ??
                    'General')
                .toString();
        final metric = out.putIfAbsent(subject, () => _SubjectMetric(subject));
        metric.total++;
        final selected = answers[qDoc.id] ?? '';
        final correct = (question['correctOption'] ?? '').toString();
        if (selected.isNotEmpty && selected == correct) {
          metric.correct++;
        }
      }
    }

    return out.values.toList();
  }

  double _dashboardScorePct(Map<String, dynamic> attempt, Map<String, dynamic> result) {
    final correct = _toInt(result['correct']) ?? _toInt(result['score']) ?? 0;
    final incorrect = _toInt(result['incorrect']) ?? _toInt(attempt['wrong']) ?? 0;
    final unanswered =
        _toInt(result['unanswered']) ?? _toInt(attempt['skipped']) ?? 0;
    final total = (correct + incorrect + unanswered) > 0
        ? (correct + incorrect + unanswered)
        : 20;
    return (correct * 100.0 / total).clamp(0.0, 100.0);
  }

  double? _secondsPerQuestion(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
  ) {
    final mins = _attemptMinutes(attempt);
    final totalQuestions =
        _toInt(result['correct']) != null ||
            _toInt(result['incorrect']) != null ||
            _toInt(result['unanswered']) != null
        ? (_toInt(result['correct']) ?? 0) +
              (_toInt(result['incorrect']) ?? 0) +
              (_toInt(result['unanswered']) ?? 0)
        : _toInt(result['totalQuestions']) ?? 0;
    if (mins <= 0 || totalQuestions <= 0) return null;
    return (mins * 60.0) / totalQuestions;
  }

  int _attemptMinutes(Map<String, dynamic> attempt) {
    final timeTaken = _toInt(attempt['timeTaken']);
    if (timeTaken != null) return timeTaken;
    final started = _toDate(attempt['startedAt']);
    final submitted = _toDate(attempt['submittedAt']);
    if (started == null || submitted == null) return 0;
    return submitted.difference(started).inMinutes;
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Widget _dashboardSection({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6DBE4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6DBE4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _subjectRow(_SubjectMetric subject) {
    final color = _subjectColor(subject.name);
    return Row(
      children: [
        Expanded(
          child: Text(
            subject.name,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (subject.accuracy / 100).clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFE5E7EB),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 34,
          child: Text(
            '${subject.accuracy.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  List<_LeaderboardAgg> _aggregateLeaderboard(
    List<QueryDocumentSnapshot> docs,
  ) {
    final byUser = <String, _LeaderboardAgg>{};

    for (final d in docs) {
      final data = d.data() as Map<String, dynamic>;
      final uid = (data['userId'] ?? '').toString();
      if (uid.isEmpty) continue;

      final score = (data['score'] as num?)?.toDouble() ?? 0.0;
      final percentile = (data['percentile'] as num?)?.toDouble() ?? 0.0;

      final agg = byUser.putIfAbsent(uid, () => _LeaderboardAgg(userId: uid));
      agg.testsTaken += 1;
      agg.totalScore += score;
      agg.totalPercentile += percentile;
      if (score > agg.bestScore) agg.bestScore = score;
    }

    final out = byUser.values.toList();
    for (final e in out) {
      final count = e.testsTaken == 0 ? 1 : e.testsTaken;
      e.avgScore = e.totalScore / count;
      e.avgPercentile = e.totalPercentile / count;
    }

    out.sort((a, b) {
      final byAvg = b.avgScore.compareTo(a.avgScore);
      if (byAvg != 0) return byAvg;
      final byBest = b.bestScore.compareTo(a.bestScore);
      if (byBest != 0) return byBest;
      return b.testsTaken.compareTo(a.testsTaken);
    });

    return out;
  }

}

class _LeaderboardAgg {
  final String userId;
  int testsTaken = 0;
  double totalScore = 0;
  double totalPercentile = 0;
  double bestScore = 0;
  double avgScore = 0;
  double avgPercentile = 0;

  _LeaderboardAgg({required this.userId});
}

class _LeaderboardRow {
  final _LeaderboardAgg entry;
  final int rank;
  final String displayName;

  const _LeaderboardRow({
    required this.entry,
    required this.rank,
    required this.displayName,
  });
}

class _SubjectMetric {
  final String name;
  int total = 0;
  int correct = 0;

  _SubjectMetric(this.name);

  double get accuracy => total == 0 ? 0 : (correct * 100.0 / total);
}

class _DashboardVm {
  final int testsTaken;
  final int bestRank;
  final double avgScore;
  final List<_DashboardPoint> trend;
  final List<_SubjectMetric> subjects;
  final List<_TimeBucket> timeBuckets;
  final double avgSecondsPerQuestion;
  final List<_SubjectMetric> improvements;

  const _DashboardVm({
    required this.testsTaken,
    required this.bestRank,
    required this.avgScore,
    required this.trend,
    required this.subjects,
    required this.timeBuckets,
    required this.avgSecondsPerQuestion,
    required this.improvements,
  });
}

class _DashboardPoint {
  final String label;
  final double value;

  const _DashboardPoint({required this.label, required this.value});
}

class _TimeBucket {
  final String label;
  final double minSeconds;
  final double? maxSeconds;
  int count = 0;

  _TimeBucket({
    required this.label,
    required this.minSeconds,
    required this.maxSeconds,
  });

  bool matches(double value) {
    final lowerOk = value >= minSeconds;
    final upperOk = maxSeconds == null ? true : value < maxSeconds!;
    return lowerOk && upperOk;
  }
}

class _DashboardTrendChart extends StatelessWidget {
  final List<_DashboardPoint> points;

  const _DashboardTrendChart({required this.points});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _DashboardTrendPainter(points: points),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: points
              .map(
                (point) => Expanded(
                  child: Text(
                    point.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _DashboardTrendPainter extends CustomPainter {
  final List<_DashboardPoint> points;

  _DashboardTrendPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final left = 22.0;
    final top = 12.0;
    final right = size.width - 8;
    final bottom = size.height - 14;
    final width = right - left;
    final height = bottom - top;

    final grid = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = top + (height * i / 4);
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }

    final axis = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(left, top), Offset(left, bottom), axis);
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), axis);

    if (points.isEmpty) return;

    final path = Path();
    final linePaint = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dotPaint = Paint()..color = const Color(0xFF1E3A8A);

    for (int i = 0; i < points.length; i++) {
      final x = left + (width * i / (points.length == 1 ? 1 : points.length - 1));
      final y = bottom - (points[i].value.clamp(0.0, 100.0) / 100) * height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _DashboardTrendPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _TimePerQuestionChart extends StatelessWidget {
  final List<_TimeBucket> buckets;

  const _TimePerQuestionChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final maxCount = buckets.fold<int>(0, (max, bucket) {
      return bucket.count > max ? bucket.count : max;
    });
    final safeMax = maxCount == 0 ? 1 : maxCount;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: buckets
          .map(
            (bucket) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${bucket.count}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 120 * (bucket.count / safeMax),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF97316),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bucket.label,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

Color _subjectColor(String subject) {
  final normalized = subject.trim().toLowerCase();
  if (normalized.isEmpty) {
    return const Color(0xFF16A34A);
  }

  const palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFFF97316),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFFCA8A04),
    Color(0xFFDB2777),
  ];

  var hash = 0;
  for (final unit in normalized.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }

  return palette[hash % palette.length];
}
