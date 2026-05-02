import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ranksprint/sections/section_bean.dart';
import 'package:ranksprint/sections/section_service.dart';
import 'package:ranksprint/services/exam_metadata_cache_service.dart';
import 'package:ranksprint/services/result_data_service.dart';
import 'package:share_plus/share_plus.dart' as share_plus;

import '../../examSummary/exam_summary_screen.dart';
import 'main_navigation.dart';
import '../../widgets/top_header.dart';

class TestSolutionScreen extends StatefulWidget {
  final String attemptId;
  final Map<String, dynamic> attemptData;
  final Map<String, dynamic> resultData;

  const TestSolutionScreen({
    super.key,
    required this.attemptId,
    required this.attemptData,
    required this.resultData,
  });

  @override
  State<TestSolutionScreen> createState() => _TestSolutionScreenState();
}

class _TestSolutionScreenState extends State<TestSolutionScreen> {
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.ranksprint.app';
  late final Future<_Vm> _future;
  SectionService sectionService = SectionService();
  List<SectionBean> sectionBeans = [];

  @override
  void initState() {
    super.initState();
    _future = _loadVm();
  }

  Future<_Vm> _loadVm() async {
    final attempt = widget.attemptData;
    final resolvedResult = await ResultDataService.resolveResultForAttempt(
      attemptId: widget.attemptId,
      attemptData: attempt,
      initialResultData: widget.resultData,
    );
    final result = await _waitForLeaderboardMetrics(resolvedResult);

    final examId = (attempt['examId'] ?? '').toString();
    final testId = (attempt['testId'] ?? '').toString();
    final examName =
        ((await ExamMetadataCacheService.getExamName(examId)) ?? examId)
            .trim();
    final testName =
        ((await ExamMetadataCacheService.getTestName(examId, testId)) ?? testId)
            .trim();
    sectionBeans = await ExamMetadataCacheService.getSectionBeans(examId, testId);
    final answersRaw = attempt['answers'];
    final answers = <String, String>{};
    if (answersRaw is Map) {
      for (final e in answersRaw.entries) {
        answers[e.key.toString()] = e.value?.toString() ?? '';
      }
    }

    final normalizedCounts = ResultDataService.normalizeCounts(
      attempt: attempt,
      result: result,
    );
    int correct = normalizedCounts['correct'] ?? 0;
    int incorrect = normalizedCounts['incorrect'] ?? 0;
    int skipped = normalizedCounts['unanswered'] ?? 0;
    int rank = _toInt(result['rank']) ?? 0;
    double percentile = _toDouble(result['percentile']) ?? 0;

    final sectionStats = <String, _SectionStats>{};
    if (examId.isNotEmpty && testId.isNotEmpty) {
      final qSnap = await ExamMetadataCacheService.getQuestions(examId, testId);

      for (final q in qSnap) {
        final qData = q.data();
        final section = _sectionName(qData);
        final st = sectionStats.putIfAbsent(
          section,
          () => _SectionStats(section),
        );
        final selected = answers[q.id];
        final correctOption = ExamResultScreenState.optionLetter(
          qData['correctOption'],
        );
        if (selected == null || selected.isEmpty) {
          st.skipped++;
        } else if (selected == correctOption) {
          st.correct++;
        } else {
          st.incorrect++;
        }
      }
    }

    final total = (correct + incorrect + skipped) > 0
        ? (correct + incorrect + skipped)
        : 20;
    final scorePct = total > 0 ? (correct * 100.0 / total) : 0.0;
    final timeMinutes = _timeMinutes(widget.attemptData);

    final sections = _orderedSectionStats(sectionStats);

    final trend = await _loadTrendPoints(
      userId: (attempt['userId'] ?? '').toString(),
      examId: examId,
      testId: testId,
    );

    return _Vm(
      examId: examId,
      examName: examName,
      testName: testName,
      resultData: result,
      correct: correct,
      incorrect: incorrect,
      skipped: skipped,
      rank: rank,
      percentile: percentile,
      total: total,
      scorePct: scorePct,
      timeMinutes: timeMinutes,
      sections: sections,
      trend: trend,
      attemptedAccuracy: (correct + incorrect) == 0
          ? 0
          : (correct * 100.0 / (correct + incorrect)),
    );
  }

  Future<List<_TrendPoint>> _loadTrendPoints({
    required String userId,
    required String examId,
    required String testId,
  }) async {
    if (userId.isEmpty || examId.isEmpty || testId.isEmpty) return const [];

    final attemptsSnap = await FirebaseFirestore.instance
        .collection('testAttempts')
        .where('userId', isEqualTo: userId)
        .where('examId', isEqualTo: examId)
        .where('testId', isEqualTo: testId)
        .get();

    if (attemptsSnap.docs.isEmpty) return const [];

    final attempts = attemptsSnap.docs.toList()
      ..sort((a, b) {
        final aTs =
            _toDate(a.data()['startedAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTs =
            _toDate(b.data()['startedAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aTs.compareTo(bTs);
      });

    final resultById = await ResultDataService.loadResultsMap(
      attempts: attempts,
      userId: userId,
      examId: examId,
    );

    final points = <_TrendPoint>[];
    for (int i = 0; i < attempts.length; i++) {
      final attempt = attempts[i];
      final a = attempt.data();
      Map<String, dynamic> r =
          resultById[attempt.id] ?? const <String, dynamic>{};
      final acc = _computeAttemptedAccuracyPct(a, r);
      final mins = _timeMinutes(a).toDouble();
      points.add(
        _TrendPoint(
          attemptNumber: i + 1,
          timeMinutes: mins,
          accuracy: acc,
        ),
      );
    }

    if (points.length <= 8) return points;
    return points.sublist(points.length - 8);
  }

  double _computeAttemptedAccuracyPct(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
  ) {
    final normalizedCounts = ResultDataService.normalizeCounts(
      attempt: attempt,
      result: result,
    );
    final correct = normalizedCounts['correct'] ?? 0;
    final incorrect = normalizedCounts['incorrect'] ?? 0;
    final attempted = correct + incorrect;
    return attempted == 0 ? 0 : (correct * 100.0 / attempted);
  }

  String _sectionName(Map<String, dynamic> qData) {
    final sectionId = (qData['sectionId'] ?? '').toString();
    if (sectionId.isNotEmpty) {
      for (final section in sectionBeans) {
        final beanId = (section.id ?? '').toString();
        if (beanId == sectionId) {
          final beanName = (section.name ?? '').toString().trim();
          if (beanName.isNotEmpty) return beanName;
        }
      }
    }
    return (qData['sectionName'] ??
            qData['sectionTitle'] ??
            qData['section'] ??
            qData['subject'] ??
            qData['topic'] ??
            'General')
        .toString();
  }

  List<_SectionStats> _orderedSectionStats(
    Map<String, _SectionStats> statsMap,
  ) {
    final ordered = <_SectionStats>[];
    final seen = <String>{};

    for (final section in sectionBeans) {
      final name = (section.name ?? '').toString().trim();
      if (name.isEmpty) continue;
      final stats = statsMap[name] ?? _SectionStats(name);
      ordered.add(stats);
      seen.add(name);
    }

    for (final entry in statsMap.entries) {
      if (seen.add(entry.key)) {
        ordered.add(entry.value);
      }
    }

    return ordered;
  }

  int _timeMinutes(Map<String, dynamic> data) {
    final direct = _toInt(data['timeTaken']);
    if (direct != null) return direct;
    final started = (data['startedAt'] as Timestamp?)?.toDate();
    final submitted = (data['submittedAt'] as Timestamp?)?.toDate();
    if (started != null && submitted != null) {
      return submitted.difference(started).inMinutes.clamp(0, 100000);
    }
    return 0;
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

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Vm>(
      future: _future,
      builder: (context, snapshot) {
        final vm = snapshot.data;
        return PopScope(
          canPop: vm == null || vm.examId.isEmpty,
          onPopInvokedWithResult: (_, __) {
            if (vm != null && vm.examId.isNotEmpty) {
              _goToTestsScreen(vm.examId);
            }
          },
          child: Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          body: SafeArea(
            child: !snapshot.hasData
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      TopHeader(
                        selectedExamId: vm!.examId.isEmpty ? null : vm.examId,
                        userExamIds: vm.examId.isEmpty ? const [] : [vm.examId],
                        onExamChanged: (_) {},
                        showExamDropdown: false,
                        showBackButton: true,
                        enableTitleNavigation: false,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          child: Column(
                            children: [
                              _topScore(vm),
                              const SizedBox(height: 10),
                              _performanceOverview(vm),
                              const SizedBox(height: 10),
                              _distributionGraph(vm),
                              const SizedBox(height: 10),
                              _sectionWise(vm),
                              const SizedBox(height: 10),
                              _correctAnswersComparison(vm),
                              const SizedBox(height: 10),
                              _timeAccuracyTrend(vm),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _shareResult(vm),
                                  icon: const Icon(Icons.share, size: 16),
                                  label: const Text('Share Result'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          bottomNavigationBar: !snapshot.hasData
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _openSolutions(vm!),
                        icon: const Icon(
                          Icons.visibility,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'View Solution',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                ),
        ));
      },
    );
  }

  Future<Map<String, dynamic>> _waitForLeaderboardMetrics(
    Map<String, dynamic> initialResult,
  ) async {
    if (_hasLeaderboardMetrics(initialResult)) {
      return initialResult;
    }

    var latest = initialResult;
    for (int i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        final snap = await FirebaseFirestore.instance
            .collection('results')
            .doc(widget.attemptId)
            .get();
        if (!snap.exists) {
          continue;
        }
        latest = snap.data() ?? latest;
        if (_hasLeaderboardMetrics(latest)) {
          return latest;
        }
      } catch (_) {
        break;
      }
    }

    return latest;
  }

  bool _hasLeaderboardMetrics(Map<String, dynamic> result) {
    final rank = _toInt(result['rank']) ?? 0;
    final percentile = _toDouble(result['percentile']) ?? 0;
    return rank > 0 || percentile > 0;
  }

  void _openSolutions(_Vm vm) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ExamResultScreen(
          questions: vm.resultData['question'],
          answers: vm.resultData['answers'],
          correct: vm.resultData['correct'],
          section: sectionBeans,
          incorrect: vm.resultData['incorrect'],
          unanswered: vm.resultData['unanswered'],
          returnToTestsExamId: vm.examId,
        ),
      ),
    );
  }

  void _goToTestsScreen(String examId) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainNavigation(
          initialIndex: 1,
          initialTestsExamId: examId,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  Widget _topScore(_Vm vm) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF1E40AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(0),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 21,
            backgroundColor: Color(0xFF4967CC),
            child: Icon(
              Icons.emoji_events_outlined,
              color: Colors.orange,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${vm.correct}/${vm.total}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${vm.scorePct.toStringAsFixed(0)}% Score',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _miniTile('${vm.rank}', 'Rank')),
              const SizedBox(width: 8),
              Expanded(
                child: _miniTile(
                  vm.percentile.toStringAsFixed(1),
                  'Percentile',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _miniTile('${vm.timeMinutes} min', 'Time Taken')),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Percentile Progress',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: (vm.percentile / 100).clamp(0, 1),
              backgroundColor: Colors.white24,
              color: const Color(0xFF22C55E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniTile(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _performanceOverview(_Vm vm) {
    return _card(
      title: 'Performance Overview',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _dotMetric(vm.correct, 'Correct', const Color(0xFF16A34A)),
          _dotMetric(vm.incorrect, 'Incorrect', const Color(0xFFDC2626)),
          _dotMetric(vm.skipped, 'Skipped', const Color(0xFF9CA3AF)),
        ],
      ),
    );
  }

  Widget _distributionGraph(_Vm vm) {
    final total = vm.total <= 0 ? 1 : vm.total;
    final c = vm.correct / total;
    final i = vm.incorrect / total;
    final s = vm.skipped / total;
    return _card(
      title: 'Response Distribution',
      child: Column(
        children: [
          _animatedBar('Correct', c, const Color(0xFF16A34A), vm.correct),
          const SizedBox(height: 8),
          _animatedBar('Incorrect', i, const Color(0xFFDC2626), vm.incorrect),
          const SizedBox(height: 8),
          _animatedBar('Skipped', s, const Color(0xFF9CA3AF), vm.skipped),
        ],
      ),
    );
  }

  Widget _animatedBar(String label, double value, Color color, int count) {
    final safe = value.clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: safe),
              builder: (context, v, _) {
                return LinearProgressIndicator(
                  minHeight: 8,
                  value: v,
                  backgroundColor: const Color(0xFFE5E7EB),
                  color: color,
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _dotMetric(int value, String label, Color color) {
    return Column(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 6),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }

  Widget _sectionWise(_Vm vm) {
    if (vm.sections.isEmpty) {
      return _card(
        title: 'Section-wise Analysis',
        child: const Text(
          'No section data found.',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }

    return _card(
      title: 'Section-wise Analysis',
      child: Column(
        children: vm.sections.map((s) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      s.attempted == 0
                          ? '--'
                          : '${s.accuracy.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Color(0xFF1D4ED8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: s.attempted == 0 ? 0 : s.accuracy / 100,
                    backgroundColor: const Color(0xFFE5E7EB),
                    color: const Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.correct} correct          ${s.incorrect} incorrect          ${s.skipped} skipped          ${s.attempted}/${s.total} attempted',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _correctAnswersComparison(_Vm vm) {
    final sections = vm.sections;
    if (sections.isEmpty) {
      return _card(
        title: 'Subject Breakdown',
        child: const Text(
          'No subject data available yet.',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }

    return _card(
      title: 'Subject Breakdown',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Correct answers in each subject, filled by percentage',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 14),
          ...sections.map((s) {
            final ratio = s.total == 0 ? 0.0 : s.correct / s.total;
            final correctPct = ratio * 100;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      s.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        tween: Tween<double>(begin: 0, end: ratio.clamp(0, 1)),
                        builder: (context, value, _) {
                          return LinearProgressIndicator(
                            minHeight: 14,
                            value: value,
                            backgroundColor: const Color(0xFFE5E7EB),
                            color: const Color(0xFF16A34A),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 94,
                    child: Text(
                      '${correctPct.toStringAsFixed(0)}% (${s.correct}/${s.total})',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _timeAccuracyTrend(_Vm vm) {
    if (vm.trend.length < 2) {
      return _card(
        title: 'Attempt vs Accuracy Trend',
        child: const Text(
          'Need at least 2 attempts to show trend.',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }

    return _card(
      title: 'Attempt vs Accuracy Trend',
      child: SizedBox(height: 170, child: _LineTrendChart(points: vm.trend)),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Future<void> _shareResult(_Vm vm) async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;

      await share_plus.Share.share(
        _buildShareMessage(vm),
        subject: 'My RankSprint result',
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the share sheet right now.'),
        ),
      );
    }
  }

  String _buildShareMessage(_Vm vm) {
    final bestSection = vm.sections.where((s) => s.attempted > 0).fold<
      _SectionStats?
    >(null, (best, section) {
      if (best == null || section.accuracy > best.accuracy) {
        return section;
      }
      return best;
    });
    final latestTrend = vm.trend.isEmpty ? null : vm.trend.last;
    final completedLabel = [vm.examName, vm.testName]
        .where((value) => value.trim().isNotEmpty)
        .join(' ')
        .trim();
    final title = completedLabel.isEmpty ? 'my test' : completedLabel;

    final buffer = StringBuffer()
      ..writeln('I just completed $title on RankSprintAI')
      ..writeln(
        'Score: ${vm.correct}/${vm.total} (${vm.scorePct.toStringAsFixed(0)}%)',
      )
      ..writeln(
        'Attempted accuracy: ${vm.attemptedAccuracy.toStringAsFixed(0)}%',
      )
      ..writeln(
        'Rank: ${vm.rank} | Percentile: ${vm.percentile.toStringAsFixed(1)}',
      )
      ..writeln('Time taken: ${vm.timeMinutes} min');

    if (bestSection != null) {
      buffer.writeln(
        'Strongest section: ${bestSection.name} (${bestSection.accuracy.toStringAsFixed(0)}% accuracy)',
      );
    }
    if (latestTrend != null) {
      buffer.writeln(
        'Recent progress: ${latestTrend.accuracy.toStringAsFixed(0)}% accuracy on attempt ${latestTrend.attemptNumber}',
      );
    }

    buffer
      ..writeln('#RankSprintAI')
      ..write(_playStoreUrl);
    return buffer.toString();
  }
}

class _Vm {
  final String examId;
  final String examName;
  final String testName;
  final Map<String, dynamic> resultData;
  final int correct;
  final int incorrect;
  final int skipped;
  final int rank;
  final double percentile;
  final int total;
  final double scorePct;
  final int timeMinutes;
  final List<_SectionStats> sections;
  final List<_TrendPoint> trend;
  final double attemptedAccuracy;

  _Vm({
    required this.examId,
    required this.examName,
    required this.testName,
    required this.resultData,
    required this.correct,
    required this.incorrect,
    required this.skipped,
    required this.rank,
    required this.percentile,
    required this.total,
    required this.scorePct,
    required this.timeMinutes,
    required this.sections,
    required this.trend,
    required this.attemptedAccuracy,
  });
}

class _SectionStats {
  final String name;
  int correct = 0;
  int incorrect = 0;
  int skipped = 0;

  _SectionStats(this.name);

  int get total => correct + incorrect + skipped;
  int get attempted => correct + incorrect;
  double get accuracy => attempted == 0 ? 0 : (correct * 100.0 / attempted);
}

class _TrendPoint {
  final int attemptNumber;
  final double timeMinutes;
  final double accuracy;

  const _TrendPoint({
    required this.attemptNumber,
    required this.timeMinutes,
    required this.accuracy,
  });
}

class _LineTrendChart extends StatelessWidget {
  final List<_TrendPoint> points;

  const _LineTrendChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final minAttempt = points.first.attemptNumber;
    final maxAttempt = points.last.attemptNumber;
    final attemptRange = math.max(1, maxAttempt - minAttempt).toDouble();

    return CustomPaint(
      painter: _LineTrendPainter(
        points: points,
        minAttempt: minAttempt,
        attemptRange: attemptRange,
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 36, right: 8, top: 8, bottom: 22),
        child: Stack(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '100%',
                style: TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
              ),
            ),
            const Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                '0%',
                style: TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Attempt $minAttempt',
                style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                'Attempt $maxAttempt',
                style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineTrendPainter extends CustomPainter {
  final List<_TrendPoint> points;
  final int minAttempt;
  final double attemptRange;

  _LineTrendPainter({
    required this.points,
    required this.minAttempt,
    required this.attemptRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotTop = 10.0;
    final plotBottom = size.height - 28.0;
    final plotLeft = 36.0;
    final plotRight = size.width - 8.0;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;

    final grid = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = plotTop + (plotHeight * i / 4);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), grid);
    }

    final path = Path();
    final dotPaint = Paint()..color = const Color(0xFF1E3A8A);
    final linePaint = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final x =
          plotLeft +
          (((p.attemptNumber - minAttempt) / attemptRange).clamp(0.0, 1.0) *
              plotWidth);
      final y = plotBottom - ((p.accuracy.clamp(0, 100)) / 100.0) * plotHeight;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _LineTrendPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
