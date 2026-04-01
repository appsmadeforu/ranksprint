import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../examSummary/exam_summary_screen.dart';
import '../../sections/section_bean.dart';
import '../../sections/section_service.dart';
import '../../services/exam_metadata_cache_service.dart';
import '../../services/result_data_service.dart';

class SubjectInsightsScreen extends StatefulWidget {
  final String examId;

  const SubjectInsightsScreen({super.key, required this.examId});

  @override
  State<SubjectInsightsScreen> createState() => _SubjectInsightsScreenState();
}

class _SubjectInsightsScreenState extends State<SubjectInsightsScreen> {
  final Map<String, String> _testNameCache = <String, String>{};
  final ValueNotifier<_InsightMetric> _metricNotifier = ValueNotifier(
    _InsightMetric.score,
  );
  late final PageController _metricPageController;
  double? _competitionAverageCache;

  @override
  void initState() {
    super.initState();
    _metricPageController = PageController(
      initialPage: _InsightMetric.score.index,
    );
  }

  @override
  void dispose() {
    _metricPageController.dispose();
    _metricNotifier.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _attemptsQuery(String userId) {
    return FirebaseFirestore.instance
        .collection('testAttempts')
        .where('userId', isEqualTo: userId)
        .where('examId', isEqualTo: widget.examId);
  }

  Query<Map<String, dynamic>> _resultsQuery(String userId) {
    return FirebaseFirestore.instance
        .collection('results')
        .where('userId', isEqualTo: userId)
        .where('examId', isEqualTo: widget.examId);
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('User not logged in')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FC),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _attemptsQuery(userId).snapshots(),
          builder: (context, attemptSnap) {
            if (attemptSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!attemptSnap.hasData || attemptSnap.data!.docs.isEmpty) {
              return _emptyState(context);
            }

            final attempts =
                List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                  attemptSnap.data!.docs,
                ).where((doc) {
                  final data = doc.data();
                  final status = (data['status'] ?? 'completed').toString();
                  return status == 'completed' && _attemptDate(data) != null;
                }).toList()..sort((a, b) {
                  final aDate = _attemptDate(a.data()) ?? DateTime(2000);
                  final bDate = _attemptDate(b.data()) ?? DateTime(2000);
                  return aDate.compareTo(bDate);
                });

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _resultsQuery(userId).snapshots(),
              builder: (context, resultSnap) {
                final streamedResultCount = resultSnap.data?.docs.length ?? 0;
                return FutureBuilder<_SubjectInsightsVm>(
                  key: ValueKey(
                    '${widget.examId}:${attempts.length}:$streamedResultCount',
                  ),
                  future: _loadVm(userId, attempts),
                  builder: (context, vmSnap) {
                    if (vmSnap.connectionState == ConnectionState.waiting &&
                        !vmSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (vmSnap.hasError) {
                      return _errorState(context);
                    }
                    final vm = vmSnap.data;
                    if (vm == null || vm.attempts.isEmpty) {
                      return _emptyState(context);
                    }
                    return _body(context, vm);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, _SubjectInsightsVm vm) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        label: 'Latest Score',
                        value: vm.latestScore.toStringAsFixed(0),
                        change: _scoreHeadlineChange(vm),
                        positive: vm.scoreGrowth >= 0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard(
                        label: 'Best Score',
                        value: vm.bestScore.toStringAsFixed(0),
                        change: vm.bestScoreContext,
                        positive: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard(
                        label: 'Total Growth',
                        value: _scoreGrowthValue(vm),
                        change: vm.scoreGrowthContext,
                        positive: vm.scoreGrowth >= 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ValueListenableBuilder<_InsightMetric>(
                  valueListenable: _metricNotifier,
                  builder: (context, metric, child) {
                    return Column(
                      children: [
                        _metricTabs(metric),
                        const SizedBox(height: 14),
                        _trendCard(vm, metric),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                const Text(
                  'All Tests',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF14213D),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          sliver: SliverList.builder(
            itemCount: vm.attempts.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _attemptCard(vm.attempts[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 28,
            width: 28,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDCE3F4)),
            ),
            child: const Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: Color(0xFF27408B),
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Performance Explorer',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF18306B),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Full trend analysis with live subject insights',
                style: TextStyle(fontSize: 11, color: Color(0xFF7A849B)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required String change,
    required bool positive,
  }) {
    final changeColor = positive
        ? const Color(0xFF22B15D)
        : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E8F5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E1A33),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Color(0xFF97A1BA)),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2E68),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 42,
            child: Center(
              child: Text(
                change,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: changeColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTabs(_InsightMetric selectedMetric) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE1E6F2)),
      ),
      child: Row(
        children: _InsightMetric.values.map((metric) {
          final selected = metric == selectedMetric;
          return Expanded(
            child: InkWell(
              onTap: () => _animateToMetric(metric),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF273B83)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  metric.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : const Color(0xFF6E7890),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _trendCard(_SubjectInsightsVm vm, _InsightMetric metric) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E6F2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100E1A33),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 264,
            child: PageView.builder(
              controller: _metricPageController,
              onPageChanged: _handleMetricPageChanged,
              itemCount: _InsightMetric.values.length,
              itemBuilder: (context, index) {
                final pageMetric = _InsightMetric.values[index];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _trendCardPage(vm, pageMetric),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendCardPage(_SubjectInsightsVm vm, _InsightMetric metric) {
    return Column(
      key: ValueKey(metric),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metric == _InsightMetric.rank
              ? 'Rank Trend'
              : metric == _InsightMetric.subjects
              ? _subjectTrendTitle(vm)
              : 'Score Trend',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1D2D5B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          metric == _InsightMetric.rank
              ? 'Lower rank is better across your recent attempts'
              : metric == _InsightMetric.subjects
              ? _subjectTrendSubtitle(vm)
              : '',
          style: const TextStyle(fontSize: 10, color: Color(0xFF97A1BA)),
        ),
        SizedBox(height: metric == _InsightMetric.score ? 8 : 12),
        Expanded(
          child: _InsightTrendChart(
            points: vm.points,
            metric: metric,
            comparisonValue: vm.comparisonValue(metric),
            subjectSeries: vm.subjectSeries,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: _buildLegendItems(vm, metric),
        ),
      ],
    );
  }

  void _animateToMetric(_InsightMetric metric) {
    _metricNotifier.value = metric;
    if (!_metricPageController.hasClients) return;
    _metricPageController.animateToPage(
      metric.index,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleMetricPageChanged(int index) {
    final metric = _InsightMetric.values[index];
    if (_metricNotifier.value == metric) return;
    _metricNotifier.value = metric;
  }

  List<Widget> _buildLegendItems(
    _SubjectInsightsVm vm,
    _InsightMetric metric,
  ) {
    if (metric == _InsightMetric.subjects) {
      return vm.subjectSeries
          .map((series) => _LegendDot(color: series.color, label: series.name))
          .toList();
    }

    return [
      _LegendDot(
        color: metric == _InsightMetric.rank
            ? const Color(0xFF8B5CFF)
            : const Color(0xFF253C8B),
        label: metric == _InsightMetric.rank ? 'Your Rank' : 'Your Score',
      ),
      _LegendDot(
        color: const Color(0xFF6C88FF),
        label: metric == _InsightMetric.rank ? 'Best Rank' : 'Competition Avg',
        hollow: true,
      ),
    ];
  }

  String _subjectTrendTitle(_SubjectInsightsVm vm) {
    if (vm.subjectSeries.isEmpty) return 'Subject Trends';
    if (vm.subjectSeries.length == 1) {
      return '${vm.subjectSeries.first.name} Trend';
    }
    return '${vm.subjectSeries.map((series) => series.name).join(', ')} Trends';
  }

  String _subjectTrendSubtitle(_SubjectInsightsVm vm) {
    if (vm.subjectSeries.isEmpty) return 'Live subject performance over time';
    return vm.subjectSeries.map((series) => series.name).join(' | ');
  }

  Widget _attemptCard(_AttemptInsight attempt) {
    final value = attempt.scoreListLabel;
    final change = attempt.scoreDeltaLabel;
    final positive = attempt.scoreDelta >= 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showAttemptBottomSheet(attempt),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE0E6F4)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120E1A33),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  size: 20,
                  color: Color(0xFF5065B8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            attempt.testName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1C2F67),
                            ),
                          ),
                        ),
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F1E4A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      attempt.dateLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF445A93),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${attempt.rankLabel} - ${attempt.percentileLabel} - ${attempt.subjectCount} subjects',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF97A1BA),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      change,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: positive
                            ? const Color(0xFF22B15D)
                            : const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _scoreHeadlineChange(_SubjectInsightsVm vm) {
    return vm.scoreGrowth == 0
        ? 'steady'
        : '${vm.scoreGrowth >= 0 ? '+' : ''}${vm.scoreGrowth.toStringAsFixed(0)} pts';
  }

  String _scoreGrowthValue(_SubjectInsightsVm vm) {
    return '${vm.scoreGrowth >= 0 ? '+' : ''}${vm.scoreGrowth.toStringAsFixed(0)}';
  }

  Future<void> _showAttemptBottomSheet(_AttemptInsight attempt) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.72,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFDFEFF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9DFEE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                attempt.testName,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1C2F67),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Test attempt breakdown',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8B97B3),
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.of(sheetContext).pop(),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            height: 40,
                            width: 40,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF0F4FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF7B89AE),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _sheetStatCard(
                            label: 'Total Score',
                            value: attempt.scoreSheetLabel,
                            subtitle: attempt.scoreDeltaLabel,
                            subtitleColor: attempt.scoreDelta >= 0
                                ? const Color(0xFF22B15D)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _sheetStatCard(
                            label: 'Rank',
                            value: attempt.rankLabel,
                            subtitle: attempt.percentileLabel,
                            subtitleColor: const Color(0xFF7B89AE),
                            progress: attempt.percentile / 100,
                            progressColor: const Color(0xFF22B15D),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Subject Breakdown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF22356B),
                      ),
                    ),
                    const SizedBox(height: 12),
                     Expanded(
                        child: attempt.subjectBreakdown.isEmpty
                            ? const Center(
                                child: Text(
                                  'No subject breakdown available for this test.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFF7A849B)),
                                ),
                              )
                            : ListView.separated(
                         itemCount: attempt.subjectBreakdown.length,
                         separatorBuilder: (_, __) => const SizedBox(height: 14),
                         itemBuilder: (context, index) {
                           final subject = attempt.subjectBreakdown[index];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      subject.name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1B2E61),
                                      ),
                                   ),
                                  ),
                                  Text(
                                    '${subject.value.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1B2E61),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                               ClipRRect(
                                 borderRadius: BorderRadius.circular(999),
                                 child: LinearProgressIndicator(
                                   value: (subject.value / 100).clamp(0.0, 1.0),
                                   minHeight: 8,
                                   backgroundColor: const Color(0xFFE7ECF8),
                                   color: const Color(0xFF22B15D),
                                 ),
                               ),
                             ],
                           );
                          },
                        ),
                      ),
                     const SizedBox(height: 16),
                     SizedBox(
                       width: double.infinity,
                       child: ElevatedButton(
                         onPressed: () async {
                           Navigator.of(sheetContext).pop();
                           await _openExamResultScreen(attempt);
                         },
                         style: ElevatedButton.styleFrom(
                           backgroundColor: const Color(0xFF1C2F67),
                           foregroundColor: Colors.white,
                           padding: const EdgeInsets.symmetric(vertical: 14),
                           shape: RoundedRectangleBorder(
                             borderRadius: BorderRadius.circular(16),
                           ),
                         ),
                         child: const Text(
                           'View Solution',
                           style: TextStyle(
                             fontSize: 15,
                             fontWeight: FontWeight.w700,
                           ),
                         ),
                       ),
                     ),
                   ],
                 ),
               ),
            ),
          ),
        );
      },
    );
  }

  Widget _sheetStatCard({
    required String label,
    required String value,
    required String subtitle,
    required Color subtitleColor,
    double? progress,
    Color? progressColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF7B89AE)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF203775),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: subtitleColor,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0xFFE1E8F8),
                color: progressColor ?? const Color(0xFF22B15D),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const Expanded(
            child: Center(
              child: Text('No completed tests found for this exam yet.'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const Expanded(
            child: Center(
              child: Text('Could not load subject insights right now.'),
            ),
          ),
        ],
      ),
    );
  }

  Future<_SubjectInsightsVm> _loadVm(
    String userId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    final resultMap = await ResultDataService.loadResultsMap(
      attempts: attempts,
      userId: userId,
      examId: widget.examId,
    );
    final competitionAverage = await _competitionAverage();
    final overallSubjects = <String, _SubjectMetric>{};
    final points = <_InsightPoint>[];
    final attemptCards = <_AttemptInsight>[];
    final computedAttempts = <_ComputedAttemptInsight>[];
    for (final entry in attempts.asMap().entries) {
      try {
        final computed = await _buildAttemptInsight(
          entry.key,
          entry.value,
          resultMap[entry.value.id] ?? const <String, dynamic>{},
        );
        computedAttempts.add(computed);
      } catch (_) {
        // Skip malformed attempts instead of crashing the whole screen.
      }
    }

    double previousScore = 0;
    double previousSubjectAverage = 0;
    int previousRank = 0;

    for (final computed in computedAttempts) {
      for (final subject in computed.subjects) {
        final globalMetric = overallSubjects.putIfAbsent(
          subject.name,
          () => _SubjectMetric(subject.name),
        );
        globalMetric.total += subject.total;
        globalMetric.attempted += subject.attempted;
        globalMetric.correct += subject.correct;
        globalMetric.totalSeconds += subject.totalSeconds;
      }

      points.add(
        _InsightPoint(
          label: 'T${computed.index + 1}',
          date: computed.date,
          score: computed.score,
          rank: computed.rank,
          subjectAverage: computed.subjectAverage,
          coverage: computed.subjects.length.toDouble(),
          subjectScores: computed.subjectScores,
        ),
      );
      attemptCards.add(
        _AttemptInsight(
          id: computed.id,
          testName: computed.testName,
          date: computed.date,
          score: computed.score,
          scoreOutOf: computed.scoreOutOf,
          scoreDelta: computed.index == 0 ? 0 : computed.score - previousScore,
          rank: computed.rank,
          rankDelta: computed.index == 0 || computed.rank == 0 || previousRank == 0
              ? 0
              : computed.rank - previousRank,
          percentile: computed.percentile,
          subjectAverage: computed.subjectAverage,
          subjectDelta: computed.index == 0
              ? 0
              : computed.subjectAverage - previousSubjectAverage,
          bestSubject: computed.subjects.isEmpty
              ? 'General'
              : computed.subjects.first.name,
          focusSubject: computed.subjects.isEmpty
              ? 'General'
              : computed.subjects.last.name,
          subjectCount: computed.subjects.length,
          subjectBreakdown: computed.subjectBreakdown,
          attemptData: computed.attemptData,
          resultData: computed.resultData,
        ),
      );

      previousScore = computed.score;
      previousRank = computed.rank == 0 ? previousRank : computed.rank;
      previousSubjectAverage = computed.subjectAverage;
    }

    final topSubjects = overallSubjects.values.toList()
      ..sort((a, b) => b.accuracy.compareTo(a.accuracy));
    final latest = points.isEmpty ? null : points.last;
    final first = points.isEmpty ? null : points.first;
    final scoredAttempts = attemptCards.reversed.toList();
    final bestScore = points.isEmpty
        ? 0.0
        : points.map((point) => point.score).reduce(math.max);
    final bestSubjectAverage = points.isEmpty
        ? 0.0
        : points.map((point) => point.subjectAverage).reduce(math.max);
    final bestScoreAttempt = attemptCards.isEmpty
        ? null
        : attemptCards.reduce((a, b) => a.score >= b.score ? a : b);
    final bestRankAttempt = attemptCards.where((attempt) => attempt.rank > 0).fold<
      _AttemptInsight?
    >(
      null,
      (best, attempt) =>
          best == null || attempt.rank < best.rank ? attempt : best,
    );
    final bestSubjectAttempt = attemptCards.isEmpty
        ? null
        : attemptCards.reduce(
            (a, b) => a.subjectAverage >= b.subjectAverage ? a : b,
          );
    final rankValues = points
        .map((point) => point.rank)
        .where((rank) => rank > 0);
    final bestRank = rankValues.isEmpty ? 0 : rankValues.reduce(math.min);
    final subjectSeries = topSubjects.take(3).map((subject) {
      final values = points
          .map<double?>((point) => point.subjectScores[subject.name])
          .toList();
      return _SubjectSeries(
        name: subject.name,
        color: _subjectColor(subject.name),
        values: values,
      );
    }).toList();

    return _SubjectInsightsVm(
      points: points,
      attempts: scoredAttempts,
      topSubjects: topSubjects.take(3).toList(),
      subjectSeries: subjectSeries,
      latestScore: latest?.score ?? 0,
      bestScore: bestScore,
      latestRank: latest?.rank ?? 0,
      bestRank: bestRank,
      latestSubjectAverage: latest?.subjectAverage ?? 0,
      bestSubjectAverage: bestSubjectAverage,
      scoreGrowth: (latest?.score ?? 0) - (first?.score ?? 0),
      rankGrowth: (first?.rank ?? 0) == 0 || (latest?.rank ?? 0) == 0
          ? 0
          : (first!.rank - latest!.rank).toDouble(),
      subjectGrowth:
          (latest?.subjectAverage ?? 0) - (first?.subjectAverage ?? 0),
      competitionAverage: competitionAverage,
      bestScoreContext: bestScoreAttempt == null
          ? 'No score record yet'
          : '${bestScoreAttempt.testName} · ${bestScoreAttempt.dateLabel}',
      bestRankContext: bestRankAttempt == null
          ? 'No ranked tests yet'
          : '${bestRankAttempt.testName} · ${bestRankAttempt.percentileLabel}',
      bestSubjectContext: bestSubjectAttempt == null
          ? 'No subject data yet'
          : '${bestSubjectAttempt.bestSubject} led in ${bestSubjectAttempt.testName}',
      scoreGrowthContext: '${attempts.length} score snapshots analyzed',
      rankGrowthContext: '${attemptCards.where((attempt) => attempt.rank > 0).length} ranked tests analyzed',
      subjectGrowthContext: '${topSubjects.length} tracked subjects across ${attempts.length} tests',
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadQuestions(
    String examId,
    String testId,
  ) async {
    return ExamMetadataCacheService.getQuestions(examId, testId);
  }

  Future<Map<String, String>> _loadSectionNames(String examId, String testId) async {
    return ExamMetadataCacheService.getSectionNames(examId, testId);
  }

  Future<String> _testName(
    String examId,
    String testId, {
    required int fallbackIndex,
  }) async {
    if (testId.isEmpty || examId.isEmpty) return 'T$fallbackIndex';
    final key = '$examId|$testId';
    final cached = _testNameCache[key];
    if (cached != null) return cached;
    try {
      final name =
          ((await ExamMetadataCacheService.getTestName(examId, testId)) ??
                  'T$fallbackIndex')
              .toString();
      _testNameCache[key] = name;
      return name;
    } catch (_) {
      final fallback = 'T$fallbackIndex';
      _testNameCache[key] = fallback;
      return fallback;
    }
  }

  Future<double> _competitionAverage() async {
    if (_competitionAverageCache != null) return _competitionAverageCache!;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('results')
          .where('examId', isEqualTo: widget.examId)
          .get();
      if (snap.docs.isEmpty) {
        _competitionAverageCache = 0;
        return 0;
      }
      final total = snap.docs.fold<double>(
        0,
        (sum, doc) => sum + _platformScore(const <String, dynamic>{}, doc.data()),
      );
      _competitionAverageCache = total / snap.docs.length;
      return _competitionAverageCache!;
    } catch (_) {
      _competitionAverageCache = 0;
      return 0;
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

  double _scoreValue(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
  ) {
    final directScore =
        _toDouble(result['score']) ?? _toDouble(attempt['score']);
    if (directScore != null && directScore > 0) {
      return directScore;
    }
    return _accuracyPercent(attempt, result);
  }

  double _scoreOutOf(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> questions,
  ) {
    final questionMarks = questions.fold<double>(
      0,
      (sum, qDoc) => sum + (_toDouble(qDoc.data()['marks']) ?? 0),
    );
    if (questionMarks > 0) {
      return questionMarks;
    }
    final explicitTotal =
        _toDouble(result['totalMarks']) ??
        _toDouble(attempt['totalMarks']) ??
        _toDouble(result['maxScore']) ??
        _toDouble(attempt['maxScore']);
    if (explicitTotal != null && explicitTotal > 0) {
      return explicitTotal;
    }
    final directScore =
        _toDouble(result['score']) ?? _toDouble(attempt['score']);
    if (directScore == null || directScore <= 0) {
      return 100;
    }
    return 0;
  }

  double _accuracyPercent(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
  ) {
    final normalizedCounts = ResultDataService.normalizeCounts(
      attempt: attempt,
      result: result,
    );
    final correct = normalizedCounts['correct'] ?? 0;
    final incorrect = normalizedCounts['incorrect'] ?? 0;
    final unanswered = normalizedCounts['unanswered'] ?? 0;
    final total = (correct + incorrect + unanswered) > 0
        ? (correct + incorrect + unanswered)
        : 20;
    return (correct * 100.0 / total).clamp(0.0, 100.0);
  }

  double _platformScore(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
  ) {
    final directScore = _toDouble(result['score']);
    if (directScore != null && directScore > 0) {
      return directScore;
    }
    final normalizedCounts = ResultDataService.normalizeCounts(
      attempt: attempt,
      result: result,
    );
    final correct = normalizedCounts['correct'] ?? 0;
    final incorrect = normalizedCounts['incorrect'] ?? 0;
    final unanswered = normalizedCounts['unanswered'] ?? 0;
    final total = correct + incorrect + unanswered;
    if (total > 0) return (correct * 100.0 / total).clamp(0.0, 100.0);
    return (_toDouble(result['score']) ?? 0).clamp(0.0, 100.0);
  }

  Future<_ComputedAttemptInsight> _buildAttemptInsight(
    int index,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> result,
  ) async {
    final data = doc.data();
    final examId = (data['examId'] ?? '').toString();
    final testId = (data['testId'] ?? '').toString();
    final futures = await Future.wait<dynamic>([
      _loadQuestions(examId, testId),
      _loadSectionNames(examId, testId),
      _testName(examId, testId, fallbackIndex: index + 1),
    ]);
    final questions =
        futures[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final sectionNames = futures[1] as Map<String, String>;
    final testName = futures[2] as String;

    final localSubjects = <String, _SubjectMetric>{};
    final answers = _answersMap(data['answers']);
    final perQuestionSeconds =
        _secondsPerQuestion(data, result, math.max(questions.length, 1)) ?? 0.0;

    for (final qDoc in questions) {
      final question = qDoc.data();
      final subjectName = _subjectName(question, sectionNames);
      final selected = _normalizeAnswerValue(answers[qDoc.id] ?? '');
      final correct = _optionLetter(question['correctOption']);
      final attempted = selected.isNotEmpty;
      final isCorrect = attempted && selected == correct;

      final localMetric = localSubjects.putIfAbsent(
        subjectName,
        () => _SubjectMetric(subjectName),
      );
      localMetric.total++;
      if (attempted) localMetric.attempted++;
      if (isCorrect) localMetric.correct++;
      localMetric.totalSeconds += perQuestionSeconds;
    }

    final subjects = localSubjects.values.toList()
      ..sort((a, b) => b.accuracy.compareTo(a.accuracy));
    final subjectBreakdown = subjects
        .map(
          (subject) => _AttemptSubjectBreakdown(
            name: subject.name,
            value: subject.accuracy.clamp(0.0, 100.0),
          ),
        )
        .toList();
    final subjectScores = <String, double>{
      for (final subject in subjects) subject.name: subject.accuracy,
    };
    final subjectAverage = subjects.isEmpty
        ? 0.0
        : subjects.map((item) => item.accuracy).reduce((a, b) => a + b) /
              subjects.length;
    final date = _attemptDate(data) ?? DateTime.now();
    final score = _scoreValue(data, result);
    final scoreOutOf = _scoreOutOf(data, result, questions);
    final accuracyPercent = _accuracyPercent(data, result);
    final rank = _toInt(result['rank']) ?? _toInt(data['rank']) ?? 0;
    final percentile =
        (_toDouble(result['percentile']) ?? accuracyPercent).clamp(0.0, 100.0);

    return _ComputedAttemptInsight(
      index: index,
      id: doc.id,
      attemptData: data,
      resultData: result,
      testName: testName,
      date: date,
      score: score,
      scoreOutOf: scoreOutOf,
      rank: rank,
      percentile: percentile,
      subjects: subjects,
      subjectBreakdown: subjectBreakdown,
      subjectScores: subjectScores,
      subjectAverage: subjectAverage,
    );
  }

  Future<void> _openExamResultScreen(_AttemptInsight attempt) async {
    final examId = (attempt.attemptData['examId'] ?? '').toString();
    final testId = (attempt.attemptData['testId'] ?? '').toString();
    final sections = examId.isEmpty || testId.isEmpty
        ? <SectionBean>[]
        : await SectionService().getSections(examId, testId);
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExamResultScreen(
          questions: attempt.resultData['question'] ?? const [],
          answers: attempt.resultData['answers'] ?? const <String, dynamic>{},
          correct: _toInt(attempt.resultData['correct']) ?? 0,
          section: sections,
          incorrect: _toInt(attempt.resultData['incorrect']) ?? 0,
          unanswered: _toInt(attempt.resultData['unanswered']) ?? 0,
        ),
      ),
    );
  }

  double? _secondsPerQuestion(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
    int totalQuestions,
  ) {
    final minutes = _attemptMinutes(attempt);
    if (minutes <= 0 || totalQuestions <= 0) return null;
    final normalizedCounts = ResultDataService.normalizeCounts(
      attempt: attempt,
      result: result,
    );
    final answered =
        (normalizedCounts['correct'] ?? 0) +
        (normalizedCounts['incorrect'] ?? 0) +
        (normalizedCounts['unanswered'] ?? 0);
    final count = answered > 0 ? answered : totalQuestions;
    return (minutes * 60.0) / count;
  }

  int _attemptMinutes(Map<String, dynamic> attempt) {
    final direct = _toInt(attempt['timeTaken']);
    if (direct != null) return direct;
    final startedAt = _toDate(attempt['startedAt']);
    final submittedAt = _toDate(attempt['submittedAt']);
    if (startedAt != null && submittedAt != null) {
      return submittedAt.difference(startedAt).inMinutes.clamp(0, 100000);
    }
    return 0;
  }

  DateTime? _attemptDate(Map<String, dynamic> attempt) =>
      _toDate(attempt['submittedAt']) ?? _toDate(attempt['startedAt']);

  String _subjectName(
    Map<String, dynamic> question,
    Map<String, String> sectionNames,
  ) {
    final directName = (question['subject'] ??
            question['sectionName'] ??
            question['section'])
        ?.toString()
        .trim();
    if (directName != null && directName.isNotEmpty) {
      return directName;
    }

    final sectionId = question['sectionId']?.toString().trim();
    if (sectionId != null && sectionId.isNotEmpty) {
      final mappedName = sectionNames[sectionId]?.trim();
      if (mappedName != null && mappedName.isNotEmpty) {
        return mappedName;
      }
    }

    return 'General';
  }

  String _optionLetter(dynamic index) {
    switch (index?.toString()) {
      case '0':
        return 'A';
      case '1':
        return 'B';
      case '2':
        return 'C';
      case '3':
        return 'D';
      default:
        return '-';
    }
  }

  String _normalizeAnswerValue(dynamic value) {
    final raw = (value ?? '').toString().trim().toUpperCase();
    switch (raw) {
      case '0':
      case 'A':
        return 'A';
      case '1':
      case 'B':
        return 'B';
      case '2':
      case 'C':
        return 'C';
      case '3':
      case 'D':
        return 'D';
      default:
        return raw;
    }
  }

  int? _toInt(dynamic value) => value is int
      ? value
      : (value is num ? value.toInt() : int.tryParse(value?.toString() ?? ''));

  double? _toDouble(dynamic value) => value is double
      ? value
      : (value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? ''));

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

}

enum _InsightMetric {
  score('Score'),
  rank('Rank'),
  subjects('Subjects');

  const _InsightMetric(this.label);

  final String label;
}

class _SubjectInsightsVm {
  final List<_InsightPoint> points;
  final List<_AttemptInsight> attempts;
  final List<_SubjectMetric> topSubjects;
  final List<_SubjectSeries> subjectSeries;
  final double latestScore;
  final double bestScore;
  final int latestRank;
  final int bestRank;
  final double latestSubjectAverage;
  final double bestSubjectAverage;
  final double scoreGrowth;
  final double rankGrowth;
  final double subjectGrowth;
  final double competitionAverage;
  final String bestScoreContext;
  final String bestRankContext;
  final String bestSubjectContext;
  final String scoreGrowthContext;
  final String rankGrowthContext;
  final String subjectGrowthContext;

  const _SubjectInsightsVm({
    required this.points,
    required this.attempts,
    required this.topSubjects,
    required this.subjectSeries,
    required this.latestScore,
    required this.bestScore,
    required this.latestRank,
    required this.bestRank,
    required this.latestSubjectAverage,
    required this.bestSubjectAverage,
    required this.scoreGrowth,
    required this.rankGrowth,
    required this.subjectGrowth,
    required this.competitionAverage,
    required this.bestScoreContext,
    required this.bestRankContext,
    required this.bestSubjectContext,
    required this.scoreGrowthContext,
    required this.rankGrowthContext,
    required this.subjectGrowthContext,
  });

  double comparisonValue(_InsightMetric metric) {
    switch (metric) {
      case _InsightMetric.score:
        return competitionAverage;
      case _InsightMetric.rank:
        return bestRank <= 0 ? 0 : bestRank.toDouble();
      case _InsightMetric.subjects:
        if (attempts.isEmpty) return 0;
        return attempts
                .map((attempt) => attempt.subjectCount.toDouble())
                .reduce((a, b) => a + b) /
            attempts.length;
    }
  }

  String growthLabel(_InsightMetric metric) {
    switch (metric) {
      case _InsightMetric.score:
        return '${scoreGrowth >= 0 ? '+' : ''}${scoreGrowth.toStringAsFixed(0)}';
      case _InsightMetric.rank:
        return '${rankGrowth >= 0 ? '+' : ''}${rankGrowth.toStringAsFixed(0)}';
      case _InsightMetric.subjects:
        return '${subjectGrowth >= 0 ? '+' : ''}${subjectGrowth.toStringAsFixed(0)}';
    }
  }
}

class _InsightPoint {
  final String label;
  final DateTime date;
  final double score;
  final int rank;
  final double subjectAverage;
  final double coverage;
  final Map<String, double> subjectScores;

  const _InsightPoint({
    required this.label,
    required this.date,
    required this.score,
    required this.rank,
    required this.subjectAverage,
    required this.coverage,
    required this.subjectScores,
  });
}

class _SubjectSeries {
  final String name;
  final Color color;
  final List<double?> values;

  const _SubjectSeries({
    required this.name,
    required this.color,
    required this.values,
  });
}

class _AttemptInsight {
  final String id;
  final Map<String, dynamic> attemptData;
  final Map<String, dynamic> resultData;
  final String testName;
  final DateTime date;
  final double score;
  final double scoreOutOf;
  final double scoreDelta;
  final int rank;
  final int rankDelta;
  final double percentile;
  final double subjectAverage;
  final double subjectDelta;
  final String bestSubject;
  final String focusSubject;
  final int subjectCount;
  final List<_AttemptSubjectBreakdown> subjectBreakdown;

  const _AttemptInsight({
    required this.id,
    required this.attemptData,
    required this.resultData,
    required this.testName,
    required this.date,
    required this.score,
    required this.scoreOutOf,
    required this.scoreDelta,
    required this.rank,
    required this.rankDelta,
    required this.percentile,
    required this.subjectAverage,
    required this.subjectDelta,
    required this.bestSubject,
    required this.focusSubject,
    required this.subjectCount,
    required this.subjectBreakdown,
  });

  String get dateLabel => _formatDate(date);
  String get rankLabel => rank <= 0 ? '-' : '#$rank';
  String get scoreListLabel => scoreOutOf > 0
      ? '${score.toStringAsFixed(0)}/${scoreOutOf.toStringAsFixed(0)}'
      : score <= 100
      ? '${score.toStringAsFixed(0)}%'
      : score.toStringAsFixed(0);
  String get scoreSheetLabel => scoreListLabel;
  String get percentileLabel => '${percentile.toStringAsFixed(1)}th %ile';
  String get scoreDeltaLabel => scoreDelta == 0
      ? 'No change from previous test'
      : '${scoreDelta >= 0 ? '+' : ''}${scoreDelta.toStringAsFixed(0)} vs previous';
  String get rankDeltaLabel => rankDelta == 0
      ? 'No rank movement'
      : '${rankDelta < 0 ? '+' : ''}${rankDelta.abs()} rank shift';
  String get subjectDeltaLabel => subjectDelta == 0
      ? 'Subject average unchanged'
      : '${subjectDelta >= 0 ? '+' : ''}${subjectDelta.toStringAsFixed(0)} avg vs previous';
}

class _AttemptSubjectBreakdown {
  final String name;
  final double value;

  const _AttemptSubjectBreakdown({
    required this.name,
    required this.value,
  });
}

class _ComputedAttemptInsight {
  final int index;
  final String id;
  final Map<String, dynamic> attemptData;
  final Map<String, dynamic> resultData;
  final String testName;
  final DateTime date;
  final double score;
  final double scoreOutOf;
  final int rank;
  final double percentile;
  final List<_SubjectMetric> subjects;
  final List<_AttemptSubjectBreakdown> subjectBreakdown;
  final Map<String, double> subjectScores;
  final double subjectAverage;

  const _ComputedAttemptInsight({
    required this.index,
    required this.id,
    required this.attemptData,
    required this.resultData,
    required this.testName,
    required this.date,
    required this.score,
    required this.scoreOutOf,
    required this.rank,
    required this.percentile,
    required this.subjects,
    required this.subjectBreakdown,
    required this.subjectScores,
    required this.subjectAverage,
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
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool hollow;

  const _LegendDot({
    required this.color,
    required this.label,
    this.hollow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 10,
          width: 10,
          decoration: BoxDecoration(
            color: hollow ? Colors.transparent : color,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF7A849B)),
        ),
      ],
    );
  }
}

class _InsightTrendChart extends StatelessWidget {
  final List<_InsightPoint> points;
  final _InsightMetric metric;
  final double comparisonValue;
  final List<_SubjectSeries> subjectSeries;

  const _InsightTrendChart({
    required this.points,
    required this.metric,
    required this.comparisonValue,
    required this.subjectSeries,
  });

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const Center(child: Text('Need at least 2 tests to show a trend'));
    }

    if (!_hasTrendData()) {
      return Center(
        child: Text(
          metric == _InsightMetric.rank
              ? 'Need at least 2 ranked tests to show rank trend'
              : 'Not enough subject data to show a trend yet',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF7A849B)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _InsightTrendPainter(
            points: points,
            metric: metric,
            comparisonValue: comparisonValue,
            subjectSeries: subjectSeries,
          ),
        );
      },
    );
  }

  bool _hasTrendData() {
    switch (metric) {
      case _InsightMetric.score:
        return points.length >= 2;
      case _InsightMetric.rank:
        return points.where((point) => point.rank > 0).length >= 2;
      case _InsightMetric.subjects:
        final values = subjectSeries.expand((series) => series.values).whereType<double>();
        return values.length >= 2;
    }
  }
}

class _InsightTrendPainter extends CustomPainter {
  final List<_InsightPoint> points;
  final _InsightMetric metric;
  final double comparisonValue;
  final List<_SubjectSeries> subjectSeries;

  _InsightTrendPainter({
    required this.points,
    required this.metric,
    required this.comparisonValue,
    required this.subjectSeries,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final leftPad = metric == _InsightMetric.rank ? 40.0 : 28.0;
    const rightPad = 12.0;
    const topPad = 10.0;
    final bottomPad = metric == _InsightMetric.rank ? 34.0 : 20.0;
    final chartRect = Rect.fromLTWH(
      leftPad,
      topPad,
      size.width - leftPad - rightPad,
      size.height - topPad - bottomPad,
    );

    final gridPaint = Paint()
      ..color = const Color(0xFFD9E0F2)
      ..strokeWidth = 1;
    for (int i = 0; i < 5; i++) {
      final y = chartRect.top + (chartRect.height * i / 4);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final labelStyle = const TextStyle(fontSize: 10, color: Color(0xFF97A1BA));
    final tickStyle = TextStyle(
      fontSize: 9,
      color: metric == _InsightMetric.rank
          ? const Color(0xFFB192FF)
          : const Color(0xFF97A1BA),
    );

    if (metric == _InsightMetric.subjects) {
      final subjectValues = subjectSeries
          .expand((series) => series.values.whereType<double>())
          .toList();
      final minValue = subjectValues.isEmpty
          ? 0.0
          : math.max(0.0, subjectValues.reduce(math.min) - 10);
      final maxValue = subjectValues.isEmpty
          ? 100.0
          : math.min(100.0, subjectValues.reduce(math.max) + 10);
      final ticks = _subjectTicks(minValue, maxValue);
      _paintAxisLabels(
        canvas,
        chartRect,
        tickStyle,
        ticks,
        minValue: minValue,
        maxValue: maxValue,
        invert: false,
        formatter: (value) => '${value.toStringAsFixed(0)}%',
      );
      for (final series in subjectSeries) {
        _paintSeries(
          canvas,
          chartRect,
          series.values,
          minValue: minValue,
          maxValue: maxValue,
          lineColor: series.color,
          fill: false,
          invert: false,
        );
      }
    } else {
      final values = points.map<double?>((point) {
        switch (metric) {
          case _InsightMetric.score:
            return point.score;
          case _InsightMetric.rank:
            return point.rank <= 0 ? null : point.rank.toDouble();
          case _InsightMetric.subjects:
            return point.subjectAverage;
        }
      }).toList();

      double minValue;
      double maxValue;
      bool invert = false;
      if (metric == _InsightMetric.rank) {
        final allValues = [
          ...values.whereType<double>().where((value) => value > 0),
          if (comparisonValue > 0) comparisonValue,
        ];
        minValue = allValues.isEmpty ? 0 : allValues.reduce(math.min);
        maxValue = allValues.isEmpty ? 1 : allValues.reduce(math.max);
        final span = (maxValue - minValue).abs();
        minValue = math.max(1, minValue - math.max(100, span * 0.12));
        maxValue = maxValue + math.max(100, span * 0.12);
        invert = true;
      } else {
        final allValues = [
          ...values.whereType<double>(),
          if (comparisonValue > 0) comparisonValue,
        ];
        final rawMin = allValues.isEmpty ? 0.0 : allValues.reduce(math.min);
        final rawMax = allValues.isEmpty ? 100.0 : allValues.reduce(math.max);
        final span = (rawMax - rawMin).abs();
        minValue = math.max(0, rawMin - math.max(8, span * 0.18));
        maxValue = rawMax + math.max(8, span * 0.18);
      }
      if ((maxValue - minValue).abs() < 1) {
        maxValue = minValue + 1;
      }

      if (metric == _InsightMetric.rank) {
        _paintAxisLabels(
          canvas,
          chartRect,
          tickStyle,
          _rankTicks(minValue, maxValue),
          minValue: minValue,
          maxValue: maxValue,
          invert: true,
          formatter: _formatRankTick,
        );
      } else {
        _paintAxisLabels(
          canvas,
          chartRect,
          tickStyle,
          _scoreTicks(minValue, maxValue),
          minValue: minValue,
          maxValue: maxValue,
          invert: false,
          formatter: (value) => '${value.toStringAsFixed(0)}%',
        );
      }

      if (comparisonValue > 0) {
        final comparisonY = _yForValue(
          comparisonValue,
          chartRect,
          minValue: minValue,
          maxValue: maxValue,
          invert: invert,
        );
        final comparisonPaint = Paint()
          ..color = const Color(0xFF6C88FF)
          ..strokeWidth = 1.4;
        for (double x = chartRect.left; x < chartRect.right; x += 7) {
          final end = math.min(chartRect.right, x + 4);
          canvas.drawLine(
            Offset(x, comparisonY),
            Offset(end, comparisonY),
            comparisonPaint,
          );
        }
      }

      _paintSeries(
        canvas,
        chartRect,
        values,
        minValue: minValue,
        maxValue: maxValue,
        lineColor: metric == _InsightMetric.rank
            ? const Color(0xFF8B5CFF)
            : const Color(0xFF253C8B),
        fill: metric == _InsightMetric.score,
        invert: invert,
      );
    }

    for (int i = 0; i < points.length; i++) {
      final dx =
          chartRect.left +
          (chartRect.width * i / math.max(1, points.length - 1));
      final labelPainter = TextPainter(
        text: TextSpan(text: points[i].label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(dx - (labelPainter.width / 2), chartRect.bottom + 6),
      );
    }
  }

  void _paintSeries(
    Canvas canvas,
    Rect chartRect,
    List<double?> values, {
    required double minValue,
    required double maxValue,
    required Color lineColor,
    required bool fill,
    required bool invert,
  }) {
    final validIndexes = <int>[
      for (int i = 0; i < values.length; i++)
        if (values[i] != null) i,
    ];
    if (validIndexes.isEmpty) return;

    final segments = <List<int>>[];
    var current = <int>[];
    for (final index in validIndexes) {
      if (current.isEmpty || index == current.last + 1) {
        current.add(index);
      } else {
        segments.add(current);
        current = [index];
      }
    }
    if (current.isNotEmpty) {
      segments.add(current);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final segment in segments) {
      final linePath = Path();
      Path? fillPath;

      for (int j = 0; j < segment.length; j++) {
        final index = segment[j];
        final value = values[index]!;
        final dx =
            chartRect.left +
            (chartRect.width * index / math.max(1, values.length - 1));
        final dy = _yForValue(
          value,
          chartRect,
          minValue: minValue,
          maxValue: maxValue,
          invert: invert,
        );
        if (j == 0) {
          linePath.moveTo(dx, dy);
          if (fill) {
            fillPath =
                Path()
                  ..moveTo(dx, chartRect.bottom)
                  ..lineTo(dx, dy);
          }
        } else {
          linePath.lineTo(dx, dy);
          fillPath?.lineTo(dx, dy);
        }
      }

      if (fill && fillPath != null) {
        final lastIndex = segment.last;
        final lastDx =
            chartRect.left +
            (chartRect.width * lastIndex / math.max(1, values.length - 1));
        fillPath
          ..lineTo(lastDx, chartRect.bottom)
          ..close();
        final fillPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [lineColor.withValues(alpha: 0.18), Colors.transparent],
          ).createShader(chartRect);
        canvas.drawPath(fillPath, fillPaint);
      }

      if (segment.length > 1) {
        canvas.drawPath(linePath, linePaint);
      }
    }

    final pointPaint = Paint()..color = lineColor;
    final pointBorderPaint = Paint()..color = Colors.white;
    for (int i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) continue;
      final dx =
          chartRect.left +
          (chartRect.width * i / math.max(1, values.length - 1));
      final dy = _yForValue(
        value,
        chartRect,
        minValue: minValue,
        maxValue: maxValue,
        invert: invert,
      );
      canvas.drawCircle(Offset(dx, dy), 3.6, pointPaint);
      canvas.drawCircle(Offset(dx, dy), 1.6, pointBorderPaint);
    }
  }

  void _paintAxisLabels(
    Canvas canvas,
    Rect chartRect,
    TextStyle style,
    List<double> ticks, {
    required double minValue,
    required double maxValue,
    required bool invert,
    required String Function(double value) formatter,
  }) {
    if (ticks.isEmpty) return;
    double? lastPaintedY;
    String? lastPaintedLabel;
    for (final tick in ticks) {
      final y = _yForValue(
        tick,
        chartRect,
        minValue: minValue,
          maxValue: maxValue,
          invert: invert,
      );
      final label = formatter(tick);
      if (lastPaintedY != null &&
          (y - lastPaintedY).abs() < 14 &&
          lastPaintedLabel == label) {
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(0, y - (painter.height / 2)));
      lastPaintedY = y;
      lastPaintedLabel = label;
    }
  }

  double _yForValue(
    double value,
    Rect chartRect, {
    required double minValue,
    required double maxValue,
    required bool invert,
  }) {
    final range = (maxValue - minValue).abs() < 1 ? 1.0 : (maxValue - minValue);
    final normalized = ((value - minValue) / range).clamp(0.0, 1.0);
    return invert
        ? chartRect.top + (normalized * chartRect.height)
        : chartRect.bottom - (normalized * chartRect.height);
  }

  List<double> _rankTicks(double minValue, double maxValue) {
    if (minValue <= 0 || maxValue <= 0) {
      return const [1, 3500];
    }
    final start = math.max(1, minValue).toDouble();
    final end = math.max(start + 1, maxValue).toDouble();
    return [start, end];
  }

  List<double> _scoreTicks(double minValue, double maxValue) {
    return _evenTicks(minValue, maxValue, 5);
  }

  List<double> _subjectTicks(double minValue, double maxValue) {
    return _evenTicks(minValue, maxValue, 5);
  }

  List<double> _evenTicks(double minValue, double maxValue, int count) {
    if (count <= 1) return [minValue, maxValue];
    final range = (maxValue - minValue).abs() < 1 ? 1.0 : (maxValue - minValue);
    return List<double>.generate(
      count,
      (index) => minValue + (range * index / (count - 1)),
    );
  }

  String _formatRankTick(double value) {
    if (value <= 1) {
      return 'Best';
    }
    if (value < 1000) {
      return '#${value.toStringAsFixed(0)}';
    }
    if (value >= 1000) {
      final compact = value / 1000;
      final whole = compact.roundToDouble();
      final useWhole = (compact - whole).abs() < 0.05;
      return useWhole
          ? '#${whole.toStringAsFixed(0)}k'
          : '#${compact.toStringAsFixed(1)}k';
    }
    return '#${value.toStringAsFixed(0)}';
  }

  @override
  bool shouldRepaint(covariant _InsightTrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.metric != metric ||
        oldDelegate.comparisonValue != comparisonValue ||
        oldDelegate.subjectSeries != subjectSeries;
  }
}

String _formatDate(DateTime date) {
  const months = <String>[
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
  return '${months[date.month - 1]} ${date.day}';
}

Color _subjectColor(String subject) {
  final normalized = subject.trim().toLowerCase();
  const palette = <Color>[
    Color(0xFF4B72F1),
    Color(0xFF31B56A),
    Color(0xFFF2A126),
    Color(0xFFEB5757),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
  ];
  var hash = 0;
  for (final code in normalized.codeUnits) {
    hash = ((hash * 31) + code) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}
