import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ranksprint/sections/section_bean.dart';
import 'package:ranksprint/sections/section_service.dart';
import 'package:ranksprint/services/result_data_service.dart';

import '../../examSummary/exam_summary_screen.dart';
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
    final result = await ResultDataService.resolveResultForAttempt(
      attemptId: widget.attemptId,
      attemptData: attempt,
      initialResultData: widget.resultData,
    );

    final examId = (attempt['examId'] ?? '').toString();
    final testId = (attempt['testId'] ?? '').toString();
    sectionBeans = await sectionService.getSections(examId, testId);
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
      final qSnap = await FirebaseFirestore.instance
          .collection('exams')
          .doc(examId)
          .collection('tests')
          .doc(testId)
          .collection('questions')
          .get();

      for (final q in qSnap.docs) {
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
    for (final attempt in attempts) {
      final a = attempt.data();
      Map<String, dynamic> r =
          resultById[attempt.id] ?? const <String, dynamic>{};
      final acc = _computeAccuracyPct(a, r);
      final mins = _timeMinutes(a).toDouble();
      points.add(_TrendPoint(timeMinutes: mins, accuracy: acc));
    }

    if (points.length <= 8) return points;
    return points.sublist(points.length - 8);
  }

  double _computeAccuracyPct(
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
    return total == 0 ? 0 : (correct * 100.0 / total);
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

  List<_SectionStats> _orderedSectionStats(Map<String, _SectionStats> statsMap) {
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
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: FutureBuilder<_Vm>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final vm = snapshot.data!;
            return Column(
              children: [
                TopHeader(
                  selectedExamId: vm.examId.isEmpty ? null : vm.examId,
                  userExamIds: vm.examId.isEmpty ? const [] : [vm.examId],
                  onExamChanged: (_) {},
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
                        _accuracyComparison(vm),
                        const SizedBox(height: 10),
                        _timeAccuracyTrend(vm),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {

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
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.visibility,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'View Solutions',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A8A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Share result not wired yet'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.share, size: 16),
                            label: const Text('Share Result'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
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

  Widget _accuracyComparison(_Vm vm) {
    final sections = vm.sections;
    if (sections.isEmpty) {
      return _card(
        title: 'Accuracy Comparison',
        child: const Text(
          'No accuracy data available yet.',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }
    return _card(
      title: 'Accuracy Comparison',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Overall attempted accuracy: ${vm.attemptedAccuracy.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...sections.map((s) {
            final accuracy = s.attempted == 0 ? 0.0 : s.accuracy;
            final delta = accuracy - vm.attemptedAccuracy;
            final deltaColor = delta >= 0
                ? const Color(0xFF16A34A)
                : const Color(0xFFDC2626);
            final deltaText = s.attempted == 0
                ? 'No attempts yet'
                : delta == 0
                ? 'Matches overall'
                : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(0)} pts vs overall';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
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
                            : '${accuracy.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: s.attempted == 0 ? 0 : (accuracy / 100).clamp(0, 1),
                      backgroundColor: const Color(0xFFE5E7EB),
                      color: const Color(0xFF1E3A8A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$deltaText • ${s.attempted}/${s.total} attempted',
                    style: TextStyle(fontSize: 11, color: deltaColor),
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
        title: 'Time vs Accuracy Trend',
        child: const Text(
          'Need at least 2 attempts to show trend.',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }

    return _card(
      title: 'Time vs Accuracy Trend',
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
}

class _Vm {
  final String examId;
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
  final double timeMinutes;
  final double accuracy;

  const _TrendPoint({required this.timeMinutes, required this.accuracy});
}

class _LineTrendChart extends StatelessWidget {
  final List<_TrendPoint> points;

  const _LineTrendChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final minX = points
        .map((p) => p.timeMinutes)
        .reduce((a, b) => a < b ? a : b);
    final maxX = points
        .map((p) => p.timeMinutes)
        .reduce((a, b) => a > b ? a : b);
    final xRange = (maxX - minX).abs() < 1 ? 1.0 : (maxX - minX);

    return CustomPaint(
      painter: _LineTrendPainter(points: points, minX: minX, xRange: xRange),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 22),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${minX.toStringAsFixed(0)}m',
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
            ),
            Text(
              '${maxX.toStringAsFixed(0)}m',
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineTrendPainter extends CustomPainter {
  final List<_TrendPoint> points;
  final double minX;
  final double xRange;

  _LineTrendPainter({
    required this.points,
    required this.minX,
    required this.xRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotTop = 10.0;
    final plotBottom = size.height - 28.0;
    final plotLeft = 8.0;
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
      final x = plotLeft + ((p.timeMinutes - minX) / xRange) * plotWidth;
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
