import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/result_data_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/top_header.dart';
import 'test_history_screen.dart';
import 'tests_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  String? selectedExamId;
  List<String> userExamIds = [];
  final TextEditingController _leaderboardSearchController =
      TextEditingController();
  String _leaderboardQuery = '';
  final Map<String, String> _userNameCache = <String, String>{};
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _questionCache =
      <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  _DashboardTrendMode _trendMode = _DashboardTrendMode.avg;
  _SubjectViewMode _subjectViewMode = _SubjectViewMode.score;
  final PageController _heroPageController = PageController();
  int _heroPageIndex = 0;
  late final AnimationController _liveBlinkController;

  @override
  void initState() {
    super.initState();
    _liveBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    UserExamPreferenceService.preferredExamNotifier.addListener(
      _handlePreferredExamChanged,
    );
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
    final preferredExamId = await UserExamPreferenceService.loadPreferredExamId(
      availableExamIds: exams,
    );
    if (!mounted) return;
    setState(() {
      userExamIds = exams;
      selectedExamId = preferredExamId;
    });
  }

  @override
  void dispose() {
    UserExamPreferenceService.preferredExamNotifier.removeListener(
      _handlePreferredExamChanged,
    );
    _leaderboardSearchController.dispose();
    _heroPageController.dispose();
    _liveBlinkController.dispose();
    super.dispose();
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5FB),
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
            const SizedBox(height: 10),
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
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x120F172A),
                                    blurRadius: 18,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const TabBar(
                                indicator: BoxDecoration(
                                  color: Color(0xFF263D9A),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(14),
                                  ),
                                ),
                                indicatorSize: TabBarIndicatorSize.tab,
                                labelColor: Colors.white,
                                unselectedLabelColor: Color(0xFF67728A),
                                dividerColor: Colors.transparent,
                                tabs: [
                                  Tab(text: 'Leaderboard'),
                                  Tab(text: 'Dashboard'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
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
            final visibleRows = allRows
                .where(_matchesLeaderboardQuery)
                .toList();

            if (visibleRows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildLeaderboardSearch(),
                    const Expanded(
                      child: Center(
                        child: Text('No leaderboard matches found'),
                      ),
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
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
            borderRadius: BorderRadius.circular(16),
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

        for (final doc in snap.docs) {
          final data = doc.data();
          _userNameCache[doc.id] =
              (data['name'] ?? data['displayName'] ?? doc.id).toString();
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
                        ? const Icon(Icons.emoji_events, color: Colors.white)
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
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('testAttempts')
          .where('examId', isEqualTo: selectedExamId)
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final attempts =
            snap.data!.docs.where((doc) {
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
            final displayPoints = _displayTrendPoints(vm.trendPoints);

            return RefreshIndicator(
              onRefresh: () async {
                if (!mounted) return;
                setState(() {});
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 22),
                children: [
                  _dashboardHero(vm),
                  const SizedBox(height: 14),
                  _performanceTrendCard(vm, displayPoints),
                  const SizedBox(height: 14),
                  _subjectWiseCard(vm),
                  const SizedBox(height: 14),
                  _chapterHeatmapCard(vm),
                  const SizedBox(height: 14),
                  _timeAnalyticsCard(vm),
                  const SizedBox(height: 14),
                  _riskBehaviourCard(vm),
                  const SizedBox(height: 14),
                  _competitionComparisonCard(vm),
                  const SizedBox(height: 14),
                  _consistencyRadarCard(vm),
                  const SizedBox(height: 14),
                  _recommendationsCard(vm),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _dashboardHero(_DashboardVm vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Analytics',
                    style: TextStyle(
                      color: Color(0xFF1E2A67),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${vm.testsTaken} tests analyzed - Updated ${_relativeTime(vm.lastUpdated)}',
                    style: const TextStyle(
                      color: Color(0xFF8A93AB),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F9EA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBDE9C9)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.35, end: 1).animate(
                      CurvedAnimation(
                        parent: _liveBlinkController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: const Icon(
                      Icons.circle,
                      size: 10,
                      color: Color(0xFF31B56A),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Live',
                    style: TextStyle(
                      color: Color(0xFF1E8B4B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Performance Overview',
                style: TextStyle(
                  color: Color(0xFF1E2A67),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                final nextPage = (_heroPageIndex + 1) % 3;
                _heroPageController.animateToPage(
                  nextPage,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                );
              },
              child: const Text(
                'Swipe ->',
                style: TextStyle(
                  color: Color(0xFF3F63E0),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 308,
          child: PageView(
            controller: _heroPageController,
            onPageChanged: (index) {
              setState(() {
                _heroPageIndex = index;
              });
            },
            children: [
              _readinessHeroCard(vm),
              _rankProjectionHeroCard(vm),
              _accuracySpeedHeroCard(vm),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final selected = index == _heroPageIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: selected ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF2E4BCB)
                    : const Color(0xFFC8D1EA),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _heroMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFFDCE4FF), fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassStat({
    required String label,
    required String value,
    String? helper,
    Color? emphasize,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFFDCE4FF), fontSize: 9),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: emphasize ?? Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 3),
            Text(
              helper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFD6E1FF), fontSize: 8),
            ),
          ],
        ],
      ),
    );
  }

  Widget _readinessHeroCard(_DashboardVm vm) {
    return _heroShell(
      colors: const [Color(0xFF2A409F), Color(0xFF3D63DB)],
      badgeText: '${vm.delta >= 0 ? '+' : ''}${vm.delta.toStringAsFixed(0)}',
      badgeSuffix: '%',
      badgeIcon: Icons.trending_up_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroHeader(
            eyebrow: 'EXAM READINESS',
            title: vm.examName,
            subtitle: 'Updated ${_relativeTime(vm.lastUpdated)}',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (vm.readiness / 100).clamp(0.0, 1.0),
                        strokeWidth: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF66EA8A),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${vm.readiness.round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Text(
                          'Ready',
                          style: TextStyle(
                            color: Color(0xFFD6E1FF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _glassStat(
                            label: 'Rank',
                            value: vm.bestRank > 0 ? '#${vm.bestRank}' : '-',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _glassStat(
                            label: 'Percentile',
                            value: vm.avgPercentile.toStringAsFixed(1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _glassStat(
                            label: 'Avg Score',
                            value: '${vm.avgScore.round()}/100',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _glassStat(
                            label: 'Tests Done',
                            value: '${vm.testsTaken}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF39C87D).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF7BE495).withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              vm.delta >= 0
                  ? '+${vm.delta.toStringAsFixed(0)} marks improvement in last 3 tests!'
                  : '${vm.delta.toStringAsFixed(0)} marks against your recent 3 tests.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankProjectionHeroCard(_DashboardVm vm) {
    return _heroShell(
      colors: const [Color(0xFF4A3096), Color(0xFF5A3DB4)],
      badgeText: 'Improving',
      badgeIcon: Icons.arrow_upward_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroHeader(
            eyebrow: 'RANK PROJECTION',
            title: 'AI Predicted Range',
            subtitle: 'Based on ${vm.testsTaken} mock tests',
          ),
          const SizedBox(height: 14),
          const Text(
            'Predicted Rank',
            style: TextStyle(color: Color(0xFFD7CBFF), fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            _predictedRankRange(vm),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rank Trend (lower = better)',
                  style: TextStyle(color: Color(0xFFD7CBFF), fontSize: 10),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 64,
                  child: _SparkLine(points: _rankProjectionPoints(vm)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accuracySpeedHeroCard(_DashboardVm vm) {
    final total = math.max(
      1,
      vm.totalCorrect + vm.totalSkipped + vm.totalIncorrect,
    );
    final accuracy = vm.totalCorrect * 100.0 / total;
    final skip = vm.totalSkipped * 100.0 / total;
    final wrong = vm.totalIncorrect * 100.0 / total;

    return _heroShell(
      colors: const [Color(0xFF15528D), Color(0xFF2872B3)],
      badgeText: '',
      badgeIcon: Icons.gps_fixed_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroHeader(
            eyebrow: 'ACCURACY & SPEED',
            title: 'Last 5 Tests Average',
            subtitle: 'Updated ${_relativeTime(vm.lastUpdated)}',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _glassStat(
                  label: 'Accuracy',
                  value: '${accuracy.round()}%',
                  helper:
                      '${vm.delta >= 0 ? '+' : ''}${vm.delta.toStringAsFixed(0)} this week',
                  emphasize: const Color(0xFF66EA8A),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _glassStat(
                  label: 'Avg Time/Q',
                  value: '${vm.avgSecondsPerQuestion.toStringAsFixed(0)}s',
                  helper: 'Optimal range',
                  emphasize: const Color(0xFFFFC142),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _glassStat(
                  label: 'Neg Marks',
                  value: '-${vm.negativeMarksLost}',
                  helper:
                      '-${math.max(0, vm.negativeMarksLost ~/ math.max(1, vm.testsTaken))} vs last',
                  emphasize: const Color(0xFFFF7474),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Correct',
                  style: TextStyle(color: Color(0xFFD6E1FF), fontSize: 11),
                ),
              ),
              Text(
                'Skip',
                style: TextStyle(color: Color(0xFFD6E1FF), fontSize: 11),
              ),
              SizedBox(width: 52),
              Text(
                'Wrong',
                style: TextStyle(color: Color(0xFFD6E1FF), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: math.max(1, accuracy.round()),
                    child: Container(color: const Color(0xFF41E188)),
                  ),
                  Expanded(
                    flex: math.max(1, skip.round()),
                    child: Container(color: const Color(0xFFFFC232)),
                  ),
                  Expanded(
                    flex: math.max(1, wrong.round()),
                    child: Container(color: const Color(0xFFFF7474)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${accuracy.round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              Text(
                '${skip.round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
              const Spacer(),
              Text(
                '${wrong.round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroShell({
    required List<Color> colors,
    required Widget child,
    required String badgeText,
    required IconData badgeIcon,
    String? badgeSuffix,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26233A8B),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -10,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -22,
            bottom: -30,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF63D598).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          badgeIcon,
                          size: 14,
                          color: const Color(0xFF66EA8A),
                        ),
                        if (badgeText.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '$badgeText${badgeSuffix ?? ''}',
                            style: const TextStyle(
                              color: Color(0xFF66EA8A),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              child,
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroHeader({
    required String eyebrow,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: Color(0xFFD6E1FF),
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFFD6E1FF), fontSize: 10),
        ),
      ],
    );
  }

  String _predictedRankRange(_DashboardVm vm) {
    final baseRank = vm.bestRank > 0
        ? vm.bestRank
        : math.max(200, ((100 - vm.avgPercentile) * 20).round());
    final lower = math.max(1, (baseRank * 0.82).round());
    final upper = math.max(lower + 1, (baseRank * 1.12).round());
    return '#${_compactNumber(lower)}-${_compactNumber(upper)}';
  }

  List<double> _rankProjectionPoints(_DashboardVm vm) {
    final baseRank = vm.bestRank > 0
        ? vm.bestRank.toDouble()
        : math.max(200, ((100 - vm.avgPercentile) * 20).round()).toDouble();
    final source = vm.trendPoints.isEmpty
        ? <double>[baseRank, baseRank * 0.96, baseRank * 0.92, baseRank * 0.88]
        : vm.trendPoints
              .map((point) => math.max(1.0, baseRank - point.score * 3.2))
              .toList();
    return source.take(6).toList();
  }

  String _compactNumber(int value) {
    final text = value.toString();
    final parts = <String>[];
    for (int i = 0; i < text.length; i++) {
      final fromEnd = text.length - i;
      parts.add(text[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) {
        parts.add(',');
      }
    }
    return parts.join();
  }

  Widget _performanceTrendCard(
    _DashboardVm vm,
    List<_TrendPoint> displayPoints,
  ) {
    return _dashboardSection(
      title: 'Performance Trend',
      subtitle:
          'Last ${vm.testsTaken} tests - score out of 100 - platform average from live results',
      trailing: _segmentedPill<_DashboardTrendMode>(
        value: _trendMode,
        options: const {
          _DashboardTrendMode.avg: 'AVG',
          _DashboardTrendMode.max: 'MAX',
        },
        onChanged: (mode) => setState(() => _trendMode = mode),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 190,
            child: displayPoints.length < 2
                ? const Center(
                    child: Text('Need at least 2 attempts to show trend'),
                  )
                : _TrendChart(
                    points: displayPoints,
                    platformAvg: vm.platformAvg,
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: _StatChip(label: 'You', dotColor: Color(0xFF315CF7)),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: _StatChip(
                  label: 'Platform Avg',
                  dotColor: Color(0xFF9EA4B2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniMetric(
                  label: 'Best',
                  value: '${vm.maxScore.round()}',
                  color: const Color(0xFF1B45D0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      TestHistoryScreen(initialExamId: selectedExamId),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2D4FCA),
              side: const BorderSide(color: Color(0xFFD9DFF0)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text(
              'View Full Performance',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subjectWiseCard(_DashboardVm vm) {
    return _dashboardSection(
      title: 'Subject Wise Performance',
      subtitle: 'Your score, accuracy, and average time by subject',
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _segmentedPill<_SubjectViewMode>(
              value: _subjectViewMode,
              options: const {
                _SubjectViewMode.score: 'Score',
                _SubjectViewMode.accuracy: 'Accuracy',
                _SubjectViewMode.time: 'Time',
              },
              onChanged: (mode) => setState(() => _subjectViewMode = mode),
            ),
          ),
          const SizedBox(height: 14),
          if (vm.subjects.isEmpty)
            const Text('No subject data available')
          else
            Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: vm.subjects.take(4).map((subject) {
                    final maxValue = _subjectMaxValue(vm.subjects);
                    final value = _subjectMetricValue(subject);
                    final height = maxValue <= 0
                        ? 0.0
                        : 120 * (value / maxValue);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          children: [
                            Text(
                              _subjectMetricLabel(subject),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              height: 126,
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: height.clamp(10.0, 120.0),
                                decoration: BoxDecoration(
                                  color: _subjectColor(subject.name),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              subject.shortName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF6C748A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: vm.subjects.take(4).map((subject) {
                      return _LegendDot(
                        color: _subjectColor(subject.name),
                        label: subject.name,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF4C95D)),
                  ),
                  child: Text(
                    'A weak accuracy dip was detected in ${vm.focusSubject}.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A5A11),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TestHistoryScreen(initialExamId: selectedExamId),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2D4FCA),
                    side: const BorderSide(color: Color(0xFFD9DFF0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text(
                    'View Subject Insights',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _chapterHeatmapCard(_DashboardVm vm) {
    return _dashboardSection(
      title: 'Chapter Proficiency Heatmap',
      subtitle: 'Topic-level accuracy from your answered questions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._groupedChapterRows(vm.chapters),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TestsScreen(selectedExam: selectedExamId),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFF3E8),
              foregroundColor: const Color(0xFFAA5A11),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              minimumSize: const Size.fromHeight(42),
            ),
            child: const Text(
              'Practice Weak Topics',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeAnalyticsCard(_DashboardVm vm) {
    return _dashboardSection(
      title: 'Time Management Analytics',
      subtitle: 'Timer per question and time score from recent attempts',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _miniSurface(
                  title: 'Time per Subject',
                  child: Column(
                    children: [
                      SizedBox(
                        height: 120,
                        child: _DonutChart(slices: vm.timeSlices),
                      ),
                      const SizedBox(height: 10),
                      ...vm.timeSlices.map(
                        (slice) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: slice.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${slice.label} ${slice.value.round()}%',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF6C748A),
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
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniSurface(
                  title: 'Time vs Score',
                  child: Column(
                    children: [
                      SizedBox(
                        height: 120,
                        child: _SparkLine(points: vm.timeScoreTrend),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF3FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Best ${vm.avgSecondsPerQuestion.toStringAsFixed(1)} s/question',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF3352D6),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD6E1FF)),
            ),
            child: Text(
              vm.timeInsight,
              style: const TextStyle(fontSize: 12, color: Color(0xFF49608F)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskBehaviourCard(_DashboardVm vm) {
    return _dashboardSection(
      title: 'Risk Behaviour Analytics',
      subtitle: 'Attempt quality based on correct, wrong, and skipped answers',
      child: Column(
        children: [
          SizedBox(height: 150, child: _BarSparkChart(values: vm.riskBars)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _riskStatCard(
                  label: 'Neg. Marks Lost',
                  value: '-${vm.negativeMarksLost}',
                  subtitle: 'from wrong answers',
                  tone: _RiskTone.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _riskStatCard(
                  label: 'Risk Accuracy',
                  value: '${vm.riskAccuracy.toStringAsFixed(0)}%',
                  subtitle: 'on attempted questions',
                  tone: _RiskTone.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _riskStatCard(
                  label: 'Safe Attempts',
                  value: '${vm.safeAttempts.toStringAsFixed(0)}%',
                  subtitle: 'precision zone',
                  tone: _RiskTone.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _competitionComparisonCard(_DashboardVm vm) {
    return _dashboardSection(
      title: 'Competition Comparison',
      subtitle:
          'Your exam-level standing against current live leaderboard stats',
      child: Column(
        children: [
          ...vm.comparisonRows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _comparisonRow(row),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              vm.rankGapText,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF2846A3),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _comparisonRow(_ComparisonRow row) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2B3551),
                ),
              ),
            ),
            Text(
              row.totalLabel,
              style: const TextStyle(fontSize: 11, color: Color(0xFF7B849A)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _compareLine('You', row.you, const Color(0xFF4B72F1)),
        const SizedBox(height: 6),
        _compareLine('Average', row.average, const Color(0xFFF2A126)),
        const SizedBox(height: 6),
        _compareLine('Topper', row.topper, const Color(0xFF24B26A)),
      ],
    );
  }

  Widget _compareLine(String label, double value, Color color) {
    final safeValue = value.clamp(0.0, 100.0);
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6C748A)),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: safeValue / 100,
              minHeight: 8,
              backgroundColor: const Color(0xFFE8ECF6),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            safeValue.toStringAsFixed(0),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2B3551),
            ),
          ),
        ),
      ],
    );
  }

  Widget _consistencyRadarCard(_DashboardVm vm) {
    return _dashboardSection(
      title: 'Consistency Radar',
      subtitle: 'Multi-dimension performance snapshot',
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: _Radar(
              items: [
                _RadarPoint('Accuracy Stability', vm.accuracyStability),
                _RadarPoint('Score Balance', vm.scoreBalance),
                _RadarPoint('Test Frequency', vm.testFrequency),
                _RadarPoint('Time Discipline', vm.timeMgmt),
                _RadarPoint('Attempt Pace', vm.speed),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFF4ECFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD9C7FF)),
            ),
            child: Column(
              children: [
                Text(
                  vm.consistencyLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B46C1),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your routine stays steadier when you keep a fixed test rhythm.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFF7B849A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationsCard(_DashboardVm vm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F317B), Color(0xFF31479F)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F1F317B),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI Focus Recommendations',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Personalized from ${vm.testsTaken} completed tests',
            style: const TextStyle(color: Color(0xFFCDD6FF), fontSize: 11),
          ),
          const SizedBox(height: 14),
          ...vm.recommendations.map(
            (item) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(item.icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: const TextStyle(
                            color: Color(0xFFD2DAFF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Total Gain Potential  +${vm.gainPotential.round()} Marks',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF73F49A),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TestsScreen(selectedExam: selectedExamId),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1F317B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(
                'Start New Map',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardSection({
    required String title,
    required Widget child,
    String? subtitle,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E7F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C2747),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7B849A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _segmentedPill<T>({
    required T value,
    required Map<T, String> options,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.entries.map((entry) {
          final selected = entry.key == value;
          return GestureDetector(
            onTap: () => onChanged(entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF2A48C8) : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF6C748A),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _miniSurface({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E7F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3E4A69),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _riskStatCard({
    required String label,
    required String value,
    required String subtitle,
    required _RiskTone tone,
  }) {
    final style = switch (tone) {
      _RiskTone.red => (
        bg: const Color(0xFFFFF0EF),
        border: const Color(0xFFFFD8D4),
        text: const Color(0xFFDC4C3E),
      ),
      _RiskTone.orange => (
        bg: const Color(0xFFFFF7EB),
        border: const Color(0xFFF7DEB2),
        text: const Color(0xFFA96A00),
      ),
      _RiskTone.green => (
        bg: const Color(0xFFF0FFF3),
        border: const Color(0xFFC7EFCF),
        text: const Color(0xFF149750),
      ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF7B849A)),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: style.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: Color(0xFF7B849A)),
          ),
        ],
      ),
    );
  }

  double _subjectMetricValue(_SubjectMetric subject) {
    switch (_subjectViewMode) {
      case _SubjectViewMode.score:
        return subject.score;
      case _SubjectViewMode.accuracy:
        return subject.accuracy;
      case _SubjectViewMode.time:
        return subject.avgSeconds;
    }
  }

  double _subjectMaxValue(List<_SubjectMetric> subjects) {
    if (subjects.isEmpty) return 1;
    var maxValue = 0.0;
    for (final subject in subjects.take(4)) {
      maxValue = math.max(maxValue, _subjectMetricValue(subject));
    }
    return maxValue <= 0 ? 1 : maxValue;
  }

  String _subjectMetricLabel(_SubjectMetric subject) {
    switch (_subjectViewMode) {
      case _SubjectViewMode.score:
        return subject.score.toStringAsFixed(0);
      case _SubjectViewMode.accuracy:
        return '${subject.accuracy.toStringAsFixed(0)}%';
      case _SubjectViewMode.time:
        return '${subject.avgSeconds.toStringAsFixed(0)}s';
    }
  }

  List<Widget> _groupedChapterRows(List<_ChapterMetric> chapters) {
    if (chapters.isEmpty) {
      return const [Text('No chapter-level data available yet')];
    }

    final bySubject = <String, List<_ChapterMetric>>{};
    for (final chapter in chapters.take(12)) {
      bySubject
          .putIfAbsent(chapter.subject, () => <_ChapterMetric>[])
          .add(chapter);
    }

    return bySubject.entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.key,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF243158),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.value.map((chapter) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: chapter.badgeColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: chapter.badgeColor.withValues(alpha: 0.38),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapter.shortName,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2B3551),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${chapter.accuracy.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: chapter.badgeColor,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    }).toList();
  }

  List<_TrendPoint> _displayTrendPoints(List<_TrendPoint> points) {
    if (_trendMode == _DashboardTrendMode.avg) return points;

    final out = <_TrendPoint>[];
    var currentMax = 0.0;
    for (final point in points) {
      currentMax = math.max(currentMax, point.score);
      out.add(
        _TrendPoint(
          label: point.label,
          score: currentMax,
          date: point.date,
          extra: point.extra,
        ),
      );
    }
    return out;
  }

  Future<_DashboardVm> _loadDashboardVm(
    String userId,
    String examId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    final examDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .get();
    final examName = (examDoc.data()?['name'] ?? 'Selected Exam').toString();

    final resultMap = await ResultDataService.loadResultsMap(
      attempts: attempts,
      userId: userId,
      examId: examId,
    );
    final detail = await _loadQuestionDetails(attempts, resultMap);
    final leaderboardRows = await _loadExamLeaderboardRows(examId);

    final trendPoints = <_TrendPoint>[];
    final riskBars = <double>[];
    final timeScoreTrend = <double>[];

    double totalScore = 0;
    double totalPercentile = 0;
    double maxScore = 0;
    int bestRank = 0;
    int totalMinutes = 0;
    int totalQuestions = 0;
    int totalCorrect = 0;
    int totalIncorrect = 0;
    int totalSkipped = 0;
    double totalSecondsPerQuestion = 0;
    int secondsPerQuestionCount = 0;
    DateTime lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);

    final timeBuckets = <_TimeBucket>[
      _TimeBucket(label: 'Fast', color: const Color(0xFF4B72F1)),
      _TimeBucket(label: 'Ideal', color: const Color(0xFF31B56A)),
      _TimeBucket(label: 'Slow', color: const Color(0xFFF2A126)),
    ];

    for (int i = 0; i < attempts.length; i++) {
      final attempt = attempts[i].data();
      final result = resultMap[attempts[i].id] ?? const <String, dynamic>{};
      final date =
          _toDate(attempt['submittedAt']) ??
          _toDate(attempt['startedAt']) ??
          DateTime.now();
      if (date.isAfter(lastUpdated)) {
        lastUpdated = date;
      }

      final score = _scorePct(attempt, result);
      final percentile = (_toDouble(result['percentile']) ?? score).clamp(
        0.0,
        100.0,
      );
      final rank = _toInt(result['rank']) ?? 0;
      final correct = _toInt(result['correct']) ?? 0;
      final incorrect =
          _toInt(result['incorrect']) ?? _toInt(attempt['wrong']) ?? 0;
      final unanswered =
          _toInt(result['unanswered']) ?? _toInt(attempt['skipped']) ?? 0;
      final questionCount = (correct + incorrect + unanswered) > 0
          ? (correct + incorrect + unanswered)
          : detail.totalQuestionsForAttempt(attempts[i].id);

      final secondsPerQuestion = _secondsPerQuestion(
        attempt,
        result,
        questionCount,
      );
      if (secondsPerQuestion != null) {
        totalSecondsPerQuestion += secondsPerQuestion;
        secondsPerQuestionCount++;
        timeScoreTrend.add(math.max(0.0, 100 - secondsPerQuestion));
        if (secondsPerQuestion <= 35) {
          timeBuckets[0].count++;
        } else if (secondsPerQuestion <= 75) {
          timeBuckets[1].count++;
        } else {
          timeBuckets[2].count++;
        }
      } else {
        timeScoreTrend.add(score);
      }

      totalScore += score;
      totalPercentile += percentile;
      maxScore = math.max(maxScore, score);
      if (rank > 0 && (bestRank == 0 || rank < bestRank)) {
        bestRank = rank;
      }
      totalQuestions += questionCount;
      totalCorrect += correct;
      totalIncorrect += incorrect;
      totalSkipped += unanswered;
      totalMinutes += _attemptMinutes(attempt);
      riskBars.add(incorrect.toDouble());
      trendPoints.add(
        _TrendPoint(
          label: 'T${i + 1}',
          score: score,
          date: date,
          extra: percentile,
        ),
      );
    }

    final avgScore = totalScore / attempts.length;
    final avgPercentile = totalPercentile / attempts.length;
    final avgSecondsPerQuestion = secondsPerQuestionCount == 0
        ? 0.0
        : totalSecondsPerQuestion / secondsPerQuestionCount;

    final subjects = detail.subjects.values.toList()
      ..sort((a, b) => b.accuracy.compareTo(a.accuracy));
    final chapters = detail.chapters.values.toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));

    final avgLeaderboardScore = leaderboardRows.isEmpty
        ? 0.0
        : leaderboardRows
                  .map((row) => row.entry.avgScore)
                  .reduce((a, b) => a + b) /
              leaderboardRows.length;
    final topLeaderboardScore = leaderboardRows.isEmpty
        ? avgScore
        : leaderboardRows.first.entry.avgScore;
    final myLeaderboardRow = leaderboardRows
        .cast<_LeaderboardRow?>()
        .firstWhere((row) => row?.entry.userId == userId, orElse: () => null);

    final consistency = _consistencyScore(trendPoints);
    final scoreBalance = _scoreBalance(subjects);
    final frequency = _testFrequency(attempts);
    final timeMgmt = (100 - (avgSecondsPerQuestion * 0.9)).clamp(0.0, 100.0);
    final speed = (100 - (avgSecondsPerQuestion * 1.1)).clamp(0.0, 100.0);
    final accuracyStability = consistency;
    final readiness =
        ((avgScore * 0.45) +
                (consistency * 0.2) +
                (timeMgmt * 0.15) +
                (_coverageScore(subjects) * 0.2))
            .clamp(0.0, 100.0);

    final firstHalfAvg = _halfAverage(trendPoints, true);
    final secondHalfAvg = _halfAverage(trendPoints, false);
    final delta = secondHalfAvg - firstHalfAvg;
    final riskAccuracy = totalCorrect + totalIncorrect == 0
        ? 0.0
        : (totalCorrect * 100.0 / (totalCorrect + totalIncorrect));
    final safeAttempts = totalQuestions == 0
        ? 0.0
        : (totalCorrect * 100.0 / totalQuestions);
    final focusSubject = subjects.isEmpty ? 'General' : subjects.last.name;

    final timeSliceTotal = timeBuckets.fold<int>(
      0,
      (sum, bucket) => sum + bucket.count,
    );
    final timeSlices = timeBuckets
        .map(
          (bucket) => _TimeSlice(
            label: bucket.label,
            value: timeSliceTotal == 0
                ? 0
                : (bucket.count * 100.0 / timeSliceTotal),
            color: bucket.color,
          ),
        )
        .toList();

    final comparisonRows = <_ComparisonRow>[
      _ComparisonRow(
        label: 'Overall Score',
        totalLabel: '/ 100',
        you: avgScore,
        average: avgLeaderboardScore,
        topper: topLeaderboardScore.clamp(0.0, 100.0),
      ),
      ...subjects
          .take(4)
          .map(
            (subject) => _ComparisonRow(
              label: subject.name,
              totalLabel: '/ 100',
              you: subject.accuracy,
              average: (subject.accuracy * 0.88).clamp(0.0, 100.0),
              topper: math.min(100.0, subject.accuracy + 12),
            ),
          ),
    ];

    final weakChapters = chapters.take(3).toList();
    final recommendations = weakChapters.isEmpty
        ? <_Recommendation>[
            const _Recommendation(
              title: 'Attempt More Tests',
              subtitle: 'Complete a few more papers to unlock recommendations',
              icon: Icons.timeline_rounded,
            ),
          ]
        : weakChapters.map((chapter) {
            return _Recommendation(
              title: chapter.name,
              subtitle:
                  '${chapter.subject} - ${math.max(0, 100 - chapter.accuracy.round())}% focus potential',
              icon: Icons.auto_awesome,
            );
          }).toList();

    final rankGapText = myLeaderboardRow == null
        ? 'Keep attempting tests to enter the live ranking pool.'
        : myLeaderboardRow.rank <= 3
        ? 'You are already in the top tier for this exam.'
        : 'You are ${myLeaderboardRow.rank - 3} places away from the Top 3.';

    final consistencyLabel = consistency >= 75
        ? 'Highly Consistent Performer'
        : consistency >= 55
        ? 'Moderately Consistent Performer'
        : 'Consistency Needs Work';

    final timeInsight = avgSecondsPerQuestion <= 35
        ? 'Your timing is efficient. Keep this pace without compromising accuracy.'
        : avgSecondsPerQuestion <= 75
        ? 'Your pacing is balanced, but a few quicker decisions can boost attempts.'
        : 'You spend too long on harder questions. Try a faster review loop.';

    return _DashboardVm(
      examName: examName,
      lastUpdated: lastUpdated == DateTime.fromMillisecondsSinceEpoch(0)
          ? DateTime.now()
          : lastUpdated,
      testsTaken: attempts.length,
      totalQuestions: totalQuestions,
      totalMinutes: totalMinutes,
      avgScore: avgScore,
      maxScore: maxScore,
      avgPercentile: avgPercentile,
      bestRank: bestRank,
      readiness: readiness,
      delta: delta,
      focusSubject: focusSubject,
      totalCorrect: totalCorrect,
      totalIncorrect: totalIncorrect,
      totalSkipped: totalSkipped,
      avgSecondsPerQuestion: avgSecondsPerQuestion,
      platformAvg: avgLeaderboardScore,
      trendPoints: trendPoints,
      subjects: subjects,
      chapters: chapters,
      timeSlices: timeSlices,
      timeScoreTrend: timeScoreTrend,
      timeInsight: timeInsight,
      riskBars: riskBars.take(6).toList(),
      negativeMarksLost: totalIncorrect,
      riskAccuracy: riskAccuracy,
      safeAttempts: safeAttempts,
      comparisonRows: comparisonRows,
      rankGapText: rankGapText,
      accuracyStability: accuracyStability,
      scoreBalance: scoreBalance,
      testFrequency: frequency,
      timeMgmt: timeMgmt,
      speed: speed,
      consistencyLabel: consistencyLabel,
      recommendations: recommendations,
      gainPotential: weakChapters.fold<double>(
        0,
        (sum, chapter) => sum + (100 - chapter.accuracy) * 0.15,
      ),
    );
  }

  Future<_QuestionDetailBundle> _loadQuestionDetails(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    Map<String, Map<String, dynamic>> resultMap,
  ) async {
    final subjects = <String, _SubjectMetric>{};
    final chapters = <String, _ChapterMetric>{};
    final totalsByAttempt = <String, int>{};

    for (final attemptDoc in attempts) {
      final attempt = attemptDoc.data();
      final examId = (attempt['examId'] ?? '').toString();
      final testId = (attempt['testId'] ?? '').toString();
      if (examId.isEmpty || testId.isEmpty) continue;

      final cacheKey = '$examId|$testId';
      if (!_questionCache.containsKey(cacheKey)) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('exams')
              .doc(examId)
              .collection('tests')
              .doc(testId)
              .collection('questions')
              .get();
          _questionCache[cacheKey] = snap.docs;
        } catch (_) {
          _questionCache[cacheKey] = const [];
        }
      }

      final questions = _questionCache[cacheKey] ?? const [];
      totalsByAttempt[attemptDoc.id] = questions.length;
      final answers = _answersMap(attempt['answers']);
      final perQuestionSeconds =
          _secondsPerQuestion(
            attempt,
            resultMap[attemptDoc.id] ?? const <String, dynamic>{},
            questions.length,
          ) ??
          0.0;

      for (final qDoc in questions) {
        final question = qDoc.data();
        final subjectName = _subjectName(question);
        final chapterName = _chapterName(question);
        final selected = answers[qDoc.id] ?? '';
        final correct = (question['correctOption'] ?? '').toString();
        final isAttempted = selected.isNotEmpty;
        final isCorrect = isAttempted && selected == correct;

        final subjectMetric = subjects.putIfAbsent(
          subjectName,
          () => _SubjectMetric(subjectName),
        );
        subjectMetric.total++;
        if (isAttempted) subjectMetric.attempted++;
        if (isCorrect) subjectMetric.correct++;
        subjectMetric.totalSeconds += perQuestionSeconds;

        final chapterKey = '$subjectName|$chapterName';
        final chapterMetric = chapters.putIfAbsent(
          chapterKey,
          () => _ChapterMetric(name: chapterName, subject: subjectName),
        );
        chapterMetric.total++;
        if (isAttempted) chapterMetric.attempted++;
        if (isCorrect) chapterMetric.correct++;
      }
    }

    return _QuestionDetailBundle(
      subjects: subjects,
      chapters: chapters,
      totalsByAttempt: totalsByAttempt,
    );
  }

  Future<List<_LeaderboardRow>> _loadExamLeaderboardRows(String examId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('results')
          .where('examId', isEqualTo: examId)
          .get();
      final entries = _aggregateLeaderboard(
        snap.docs.cast<QueryDocumentSnapshot>(),
      );
      return _hydrateLeaderboard(entries);
    } catch (_) {
      return const <_LeaderboardRow>[];
    }
  }

  Map<String, String> _answersMap(dynamic raw) {
    final out = <String, String>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      out[entry.key.toString()] = (entry.value ?? '').toString();
    }
    return out;
  }

  String _subjectName(Map<String, dynamic> question) {
    return (question['subject'] ??
            question['sectionName'] ??
            question['section'] ??
            'General')
        .toString();
  }

  String _chapterName(Map<String, dynamic> question) {
    return (question['chapter'] ??
            question['chapterName'] ??
            question['topic'] ??
            question['topicName'] ??
            _subjectName(question))
        .toString();
  }

  double _scorePct(Map<String, dynamic> attempt, Map<String, dynamic> result) {
    final correct = _toInt(result['correct']) ?? _toInt(result['score']) ?? 0;
    final incorrect =
        _toInt(result['incorrect']) ?? _toInt(attempt['wrong']) ?? 0;
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
    int fallbackQuestions,
  ) {
    final mins = _attemptMinutes(attempt);
    final totalQuestions =
        (_toInt(result['correct']) ?? 0) +
        (_toInt(result['incorrect']) ?? 0) +
        (_toInt(result['unanswered']) ?? 0);
    final effectiveQuestions = totalQuestions > 0
        ? totalQuestions
        : fallbackQuestions;
    if (mins <= 0 || effectiveQuestions <= 0) return null;
    return (mins * 60.0) / effectiveQuestions;
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

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  double _consistencyScore(List<_TrendPoint> points) {
    if (points.length <= 1) return 50;
    final values = points.map((e) => e.score).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values
            .map((value) => math.pow(value - mean, 2))
            .reduce((a, b) => a + b) /
        values.length;
    final deviation = math.sqrt(variance);
    return (100 - deviation * 2.4).clamp(0.0, 100.0);
  }

  double _scoreBalance(List<_SubjectMetric> subjects) {
    if (subjects.isEmpty) return 0;
    final values = subjects.map((e) => e.accuracy).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final spread =
        values.map((value) => (value - mean).abs()).reduce((a, b) => a + b) /
        values.length;
    return (100 - spread * 1.6).clamp(0.0, 100.0);
  }

  double _coverageScore(List<_SubjectMetric> subjects) {
    if (subjects.isEmpty) return 0;
    return subjects.map((subject) => subject.coverage).reduce((a, b) => a + b) /
        subjects.length;
  }

  double _testFrequency(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) {
    if (attempts.length <= 1) return 45;
    final dates =
        attempts
            .map(
              (doc) =>
                  _toDate(doc.data()['submittedAt']) ??
                  _toDate(doc.data()['startedAt']),
            )
            .whereType<DateTime>()
            .toList()
          ..sort();
    if (dates.length <= 1) return 45;

    var totalGap = 0.0;
    for (int i = 1; i < dates.length; i++) {
      totalGap += dates[i].difference(dates[i - 1]).inDays.abs().toDouble();
    }
    final avgGap = totalGap / (dates.length - 1);
    return (100 - avgGap * 6).clamp(0.0, 100.0);
  }

  double _halfAverage(List<_TrendPoint> points, bool firstHalf) {
    if (points.isEmpty) return 0;
    final mid = points.length ~/ 2;
    final slice = firstHalf
        ? points.sublist(0, math.max(1, mid))
        : points.sublist(mid);
    if (slice.isEmpty) return 0;
    return slice.map((point) => point.score).reduce((a, b) => a + b) /
        slice.length;
  }

  String _relativeTime(DateTime value) {
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} mins ago';
    if (diff.inDays < 1) return '${diff.inHours} hrs ago';
    return '${diff.inDays} days ago';
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

enum _DashboardTrendMode { avg, max }

enum _SubjectViewMode { score, accuracy, time }

enum _RiskTone { red, orange, green }

class _QuestionDetailBundle {
  final Map<String, _SubjectMetric> subjects;
  final Map<String, _ChapterMetric> chapters;
  final Map<String, int> totalsByAttempt;

  const _QuestionDetailBundle({
    required this.subjects,
    required this.chapters,
    required this.totalsByAttempt,
  });

  int totalQuestionsForAttempt(String attemptId) =>
      totalsByAttempt[attemptId] ?? 0;
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

class _DashboardVm {
  final String examName;
  final DateTime lastUpdated;
  final int testsTaken;
  final int totalQuestions;
  final int totalMinutes;
  final double avgScore;
  final double maxScore;
  final double avgPercentile;
  final int bestRank;
  final double readiness;
  final double delta;
  final String focusSubject;
  final int totalCorrect;
  final int totalIncorrect;
  final int totalSkipped;
  final double avgSecondsPerQuestion;
  final double platformAvg;
  final List<_TrendPoint> trendPoints;
  final List<_SubjectMetric> subjects;
  final List<_ChapterMetric> chapters;
  final List<_TimeSlice> timeSlices;
  final List<double> timeScoreTrend;
  final String timeInsight;
  final List<double> riskBars;
  final int negativeMarksLost;
  final double riskAccuracy;
  final double safeAttempts;
  final List<_ComparisonRow> comparisonRows;
  final String rankGapText;
  final double accuracyStability;
  final double scoreBalance;
  final double testFrequency;
  final double timeMgmt;
  final double speed;
  final String consistencyLabel;
  final List<_Recommendation> recommendations;
  final double gainPotential;

  const _DashboardVm({
    required this.examName,
    required this.lastUpdated,
    required this.testsTaken,
    required this.totalQuestions,
    required this.totalMinutes,
    required this.avgScore,
    required this.maxScore,
    required this.avgPercentile,
    required this.bestRank,
    required this.readiness,
    required this.delta,
    required this.focusSubject,
    required this.totalCorrect,
    required this.totalIncorrect,
    required this.totalSkipped,
    required this.avgSecondsPerQuestion,
    required this.platformAvg,
    required this.trendPoints,
    required this.subjects,
    required this.chapters,
    required this.timeSlices,
    required this.timeScoreTrend,
    required this.timeInsight,
    required this.riskBars,
    required this.negativeMarksLost,
    required this.riskAccuracy,
    required this.safeAttempts,
    required this.comparisonRows,
    required this.rankGapText,
    required this.accuracyStability,
    required this.scoreBalance,
    required this.testFrequency,
    required this.timeMgmt,
    required this.speed,
    required this.consistencyLabel,
    required this.recommendations,
    required this.gainPotential,
  });
}

class _TrendPoint {
  final String label;
  final double score;
  final DateTime date;
  final double extra;

  const _TrendPoint({
    required this.label,
    required this.score,
    required this.date,
    required this.extra,
  });
}

class _SubjectMetric {
  final String name;
  int total = 0;
  int attempted = 0;
  int correct = 0;
  double totalSeconds = 0;

  _SubjectMetric(this.name);

  double get accuracy => total == 0 ? 0 : (correct * 100.0 / total);
  double get coverage => total == 0 ? 0 : (attempted * 100.0 / total);
  double get score => accuracy;
  double get avgSeconds => total == 0 ? 0 : (totalSeconds / total);
  String get shortName =>
      name.length <= 10 ? name : '${name.substring(0, 9)}...';
}

class _ChapterMetric {
  final String name;
  final String subject;
  int total = 0;
  int attempted = 0;
  int correct = 0;

  _ChapterMetric({required this.name, required this.subject});

  double get accuracy => total == 0 ? 0 : (correct * 100.0 / total);
  Color get badgeColor {
    if (accuracy >= 75) return const Color(0xFF31B56A);
    if (accuracy >= 50) return const Color(0xFFF2A126);
    return const Color(0xFFEB5757);
  }

  String get shortName =>
      name.length <= 10 ? name : '${name.substring(0, 9)}...';
}

class _TimeBucket {
  final String label;
  final Color color;
  int count = 0;

  _TimeBucket({required this.label, required this.color});
}

class _TimeSlice {
  final String label;
  final double value;
  final Color color;

  const _TimeSlice({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _ComparisonRow {
  final String label;
  final String totalLabel;
  final double you;
  final double average;
  final double topper;

  const _ComparisonRow({
    required this.label,
    required this.totalLabel,
    required this.you,
    required this.average,
    required this.topper,
  });
}

class _Recommendation {
  final String title;
  final String subtitle;
  final IconData icon;

  const _Recommendation({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF7B849A)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF273352),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color dotColor;

  const _StatChip({required this.label, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF69748B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6C748A)),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<_TrendPoint> points;
  final double platformAvg;

  const _TrendChart({required this.points, required this.platformAvg});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendPainter(points: points, platformAvg: platformAvg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Spacer(),
            Row(
              children: points
                  .map(
                    (point) => Expanded(
                      child: Text(
                        point.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF8B93A8),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<_TrendPoint> points;
  final double platformAvg;

  const _TrendPainter({required this.points, required this.platformAvg});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    const top = 12.0;
    const rightPad = 12.0;
    const bottomPad = 28.0;
    final width = size.width - left - rightPad;
    final height = size.height - top - bottomPad;
    final right = left + width;
    final bottom = top + height;

    final grid = Paint()
      ..color = const Color(0xFFE6EBF4)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = top + (height * i / 4);
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }

    final axis = Paint()
      ..color = const Color(0xFFD4DBE9)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(left, top), Offset(left, bottom), axis);
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), axis);

    final platformY = bottom - (platformAvg.clamp(0.0, 100.0) / 100.0) * height;
    final platformPaint = Paint()
      ..color = const Color(0xFF9EA4B2)
      ..strokeWidth = 1.5;
    var x = left;
    while (x < right) {
      canvas.drawLine(
        Offset(x, platformY),
        Offset(math.min(x + 6, right), platformY),
        platformPaint,
      );
      x += 10;
    }

    if (points.isEmpty) return;

    final path = Path();
    final fillPath = Path();
    final linePaint = Paint()
      ..color = const Color(0xFF315CF7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x33315CF7), Color(0x00315CF7)],
      ).createShader(Rect.fromLTWH(left, top, width, height));
    final dotPaint = Paint()..color = const Color(0xFF315CF7);

    for (int i = 0; i < points.length; i++) {
      final px = left + (width * i / math.max(1, points.length - 1));
      final py = bottom - (points[i].score.clamp(0.0, 100.0) / 100.0) * height;
      if (i == 0) {
        path.moveTo(px, py);
        fillPath.moveTo(px, bottom);
        fillPath.lineTo(px, py);
      } else {
        path.lineTo(px, py);
        fillPath.lineTo(px, py);
      }
      canvas.drawCircle(Offset(px, py), 3.5, dotPaint);
    }
    fillPath.lineTo(right, bottom);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.platformAvg != platformAvg;
  }
}

class _DonutChart extends StatelessWidget {
  final List<_TimeSlice> slices;

  const _DonutChart({required this.slices});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DonutPainter(slices),
      child: const SizedBox.expand(),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<_TimeSlice> slices;

  const _DonutPainter(this.slices);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: math.min(size.width, size.height) * 0.34,
    );
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..color = const Color(0xFFE8ECF6);
    canvas.drawArc(rect, 0, math.pi * 2, false, bg);

    double start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = (slice.value / 100) * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..color = slice.color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}

class _SparkLine extends StatelessWidget {
  final List<double> points;

  const _SparkLine({required this.points});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparkLinePainter(points),
      child: const SizedBox.expand(),
    );
  }
}

class _SparkLinePainter extends CustomPainter {
  final List<double> points;

  const _SparkLinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.isEmpty ? const [0.0, 0.0] : points;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final spread = math.max(1.0, maxValue - minValue);
    final left = 8.0;
    final top = 12.0;
    final right = size.width - 8;
    final bottom = size.height - 12;
    final width = right - left;
    final height = bottom - top;

    final grid = Paint()
      ..color = const Color(0xFFE8ECF6)
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      final y = top + height * (i / 3);
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }

    final path = Path();
    final dot = Paint()..color = const Color(0xFF5B74F7);
    final line = Paint()
      ..color = const Color(0xFF5B74F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (int i = 0; i < values.length; i++) {
      final x = left + width * (i / math.max(1, values.length - 1));
      final y = bottom - ((values[i] - minValue) / spread) * height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, dot);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _SparkLinePainter oldDelegate) =>
      oldDelegate.points != points;
}

class _BarSparkChart extends StatelessWidget {
  final List<double> values;

  const _BarSparkChart({required this.values});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: values.asMap().entries.map((entry) {
        final maxValue = values.isEmpty ? 1.0 : values.reduce(math.max);
        final normalized = maxValue <= 0 ? 0.0 : entry.value / maxValue;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  entry.value.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6C748A),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 110 * normalized.clamp(0.12, 1.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF98A1B2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'T${entry.key + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6C748A),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RadarPoint {
  final String label;
  final double value;

  const _RadarPoint(this.label, this.value);
}

class _Radar extends StatelessWidget {
  final List<_RadarPoint> items;

  const _Radar({required this.items});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RadarPainter(items),
      child: const SizedBox.expand(),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<_RadarPoint> items;

  const _RadarPainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 12);
    final radius = math.min(size.width, size.height) * 0.28;
    final grid = Paint()
      ..color = const Color(0xFFD6DDED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int level = 1; level <= 4; level++) {
      canvas.drawPath(
        _polygon(center, radius * (level / 4), items.length),
        grid,
      );
    }

    for (int i = 0; i < items.length; i++) {
      final angle = _angle(i, items.length);
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, end, grid);

      final text = TextPainter(
        text: TextSpan(
          text: items[i].label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6C748A)),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90);
      text.paint(
        canvas,
        Offset(
          center.dx + (radius + 18) * math.cos(angle) - text.width / 2,
          center.dy + (radius + 18) * math.sin(angle) - text.height / 2,
        ),
      );
    }

    final shape = Path();
    for (int i = 0; i < items.length; i++) {
      final currentRadius = (items[i].value.clamp(0.0, 100.0) / 100.0) * radius;
      final angle = _angle(i, items.length);
      final point = Offset(
        center.dx + currentRadius * math.cos(angle),
        center.dy + currentRadius * math.sin(angle),
      );
      if (i == 0) {
        shape.moveTo(point.dx, point.dy);
      } else {
        shape.lineTo(point.dx, point.dy);
      }
    }
    shape.close();

    final fill = Paint()
      ..color = const Color(0xFF5B74F7).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF315CF7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(shape, fill);
    canvas.drawPath(shape, stroke);
  }

  Path _polygon(Offset center, double radius, int sides) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = _angle(i, sides);
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  double _angle(int index, int total) =>
      (-math.pi / 2) + (2 * math.pi * index / total);

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.items != items;
}

Color _subjectColor(String subject) {
  final normalized = subject.trim().toLowerCase();
  if (normalized.isEmpty) {
    return const Color(0xFF16A34A);
  }

  const palette = <Color>[
    Color(0xFF4B72F1),
    Color(0xFF31B56A),
    Color(0xFFF2A126),
    Color(0xFFEB5757),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFF14B8A6),
    Color(0xFFEC4899),
  ];

  var hash = 0;
  for (final unit in normalized.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}
