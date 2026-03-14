import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/result_data_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/top_header.dart';
import 'test_history_screen.dart';
import 'tests_screen.dart';

class PerformanceTrendsScreen extends StatefulWidget {
  final String? initialExamId;

  const PerformanceTrendsScreen({super.key, this.initialExamId});

  @override
  State<PerformanceTrendsScreen> createState() =>
      _PerformanceTrendsScreenState();
}

class _PerformanceTrendsScreenState extends State<PerformanceTrendsScreen> {
  String? _examId;
  List<String> _examIds = [];
  _Window _window = _Window.d30;

  @override
  void initState() {
    super.initState();
    UserExamPreferenceService.preferredExamNotifier.addListener(
      _handlePreferredExamChanged,
    );
    _loadUserExams();
  }

  @override
  void dispose() {
    UserExamPreferenceService.preferredExamNotifier.removeListener(
      _handlePreferredExamChanged,
    );
    super.dispose();
  }

  Future<void> _loadUserExams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final exams = List<String>.from(doc.data()?['selectedExams'] ?? []);
    final preferredExamId =
        widget.initialExamId != null && exams.contains(widget.initialExamId)
        ? widget.initialExamId
        : await UserExamPreferenceService.loadPreferredExamId(
            availableExamIds: exams,
          );
    if (!mounted) return;
    setState(() {
      _examIds = exams;
      _examId = preferredExamId;
    });
  }

  void _handlePreferredExamChanged() {
    final preferredExamId =
        UserExamPreferenceService.preferredExamNotifier.value;
    if (!mounted ||
        preferredExamId == null ||
        preferredExamId == _examId ||
        !_examIds.contains(preferredExamId)) {
      return;
    }

    setState(() {
      _examId = preferredExamId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('User not logged in')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: _examId,
              userExamIds: _examIds,
              onExamChanged: (id) => setState(() => _examId = id),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _examId == null
                  ? const Center(child: Text('No exam selected'))
                  : FutureBuilder<_Vm>(
                      key: ValueKey<String>('${_examId ?? ''}:${_window.name}'),
                      future: _loadVm(uid, _examId!, _window),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return const Center(
                            child: Text(
                              'Could not load trends. Pull to retry.',
                            ),
                          );
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: Text('No performance data available'),
                          );
                        }
                        final vm = snap.data!;
                        return RefreshIndicator(
                          onRefresh: () async {
                            if (!mounted) return;
                            setState(() {});
                          },
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                            children: [
                              _hero(vm),
                              const SizedBox(height: 10),
                              _windowRow(),
                              const SizedBox(height: 10),
                              _scoreTrend(vm),
                              const SizedBox(height: 10),
                              _subjectCard(vm),
                              const SizedBox(height: 10),
                              _skills(vm),
                              const SizedBox(height: 10),
                              _weeklyActivity(vm),
                              const SizedBox(height: 10),
                              _performanceInsights(vm),
                              const SizedBox(height: 10),
                              _actionButtons(),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(_Vm vm) {
    return Container(
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
                      'Performance Trends',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Track your progress over time',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _window.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Current Average',
                  '${vm.avg.toStringAsFixed(0)}%',
                  '+${vm.delta.toStringAsFixed(0)}%',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _metric('Tests Attempted', '${vm.tests}', '')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _metric('Best Subject', vm.bestSubject, '')),
              const SizedBox(width: 8),
              Expanded(
                child: _metric('Total Time', _fmtMins(vm.totalMinutes), ''),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String title, String value, String delta) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
              if (delta.isNotEmpty)
                Text(
                  delta,
                  style: const TextStyle(
                    color: Color(0xFF86EFAC),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

  Widget _windowRow() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: _Window.values.map((w) {
          final s = w == _window;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _window = w),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: s
                        ? const Color(0xFF1E3A8A)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    w.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: s ? Colors.white : const Color(0xFF374151),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _scoreTrend(_Vm vm) {
    return _card(
      'Score Trend',
      Column(
        children: [
          SizedBox(
            height: 170,
            child: vm.points.length < 2
                ? const Center(
                    child: Text('Need at least 2 attempts to show trend'),
                  )
                : _TrendChart(points: vm.points, platformAvg: vm.platformAvg),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _Legend(color: Color(0xFF1E40AF), text: 'Your Score'),
              SizedBox(width: 12),
              _Legend(color: Color(0xFFF97316), text: 'Platform Average'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _small(
                  'Your Average',
                  '${vm.avg.toStringAsFixed(0)}%',
                  const Color(0xFF1E40AF),
                ),
              ),
              Expanded(
                child: _small(
                  'Platform Average',
                  '${vm.platformAvg.toStringAsFixed(0)}%',
                  const Color(0xFFF97316),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _small(String l, String v, Color c) {
    return Column(
      children: [
        Text(l, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
        const SizedBox(height: 4),
        Text(
          v,
          style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _subjectCard(_Vm vm) {
    return _card(
      'Subject-wise Performance',
      vm.subjects.isEmpty
          ? const Text('No subject data available')
          : Column(
              children: vm.subjects.map((s) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(
                          s.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (s.accuracy / 100).clamp(0.0, 1.0),
                            minHeight: 12,
                            backgroundColor: const Color(0xFFE5E7EB),
                            color: const Color(0xFF1E3A8A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 34,
                        child: Text(
                          s.accuracy.toStringAsFixed(0),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _skills(_Vm vm) {
    return _card(
      'Skills Assessment',
      Column(
        children: [
          SizedBox(
            height: 190,
            child: _Radar(
              items: [
                _R('Speed', vm.speed),
                _R('Accuracy', vm.skillAcc),
                _R('Consistency', vm.consistency),
                _R('Time Mgmt', vm.timeMgmt),
                _R('Difficulty', vm.difficulty),
              ],
            ),
          ),
          const Divider(height: 20, color: Color(0xFFE5E7EB)),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Best Skill',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vm.bestSkill,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF1E40AF),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6ED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Focus Area',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vm.focusArea,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFFEA580C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weeklyActivity(_Vm vm) {
    return _card(
      'Weekly Activity',
      vm.weekly.isEmpty
          ? const Text('No weekly activity yet')
          : Column(
              children: vm.weekly.map((w) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            w.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${w.score.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Color(0xFF1E3A8A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${w.attempts} tests',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _fmtMins(w.minutes),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: (w.score / 100).clamp(0.0, 1.0),
                          backgroundColor: const Color(0xFFE5E7EB),
                          color: const Color(0xFF1E3A8A),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _performanceInsights(_Vm vm) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFD3FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: Color(0xFF1E3A8A),
                child: Icon(Icons.lightbulb, color: Colors.white, size: 12),
              ),
              SizedBox(width: 8),
              Text(
                'Performance Insights',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You\'ve improved by ${vm.delta.toStringAsFixed(0)}% in the last ${_window.label.toLowerCase()}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
          ),
          const SizedBox(height: 8),
          ...vm.insights.map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      i,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TestHistoryScreen()),
              );
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              'View All Tests',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TestsScreen(selectedExam: _examId),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              'Take New Test',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  String _bestSkill({
    required double speed,
    required double acc,
    required double consistency,
    required double timeMgmt,
    required double difficulty,
  }) {
    final map = <String, double>{
      'Speed': speed,
      'Accuracy': acc,
      'Consistency': consistency,
      'Time Mgmt': timeMgmt,
      'Difficulty': difficulty,
    };
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  String _focusArea({
    required double speed,
    required double acc,
    required double consistency,
    required double timeMgmt,
    required double difficulty,
  }) {
    final map = <String, double>{
      'Speed': speed,
      'Accuracy': acc,
      'Consistency': consistency,
      'Time Mgmt': timeMgmt,
      'Difficulty': difficulty,
    };
    final sorted = map.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return sorted.first.key;
  }

  List<_WeeklyStat> _weeklyStats(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    Map<String, Map<String, dynamic>> results,
  ) {
    final now = DateTime.now();
    final stats = <_WeeklyStat>[];
    for (int i = 0; i < 4; i++) {
      final start = now.subtract(Duration(days: (4 - i) * 7));
      final end = now.subtract(Duration(days: (3 - i) * 7));
      final windowAttempts = attempts.where((a) {
        final d = _attemptDate(a.data());
        if (d == null) return false;
        if (i == 3) {
          return !d.isBefore(start) && !d.isAfter(now);
        }
        return !d.isBefore(start) && d.isBefore(end);
      }).toList();

      int mins = 0;
      double sum = 0;
      for (final a in windowAttempts) {
        mins += _attemptMins(a.data());
        sum += _scorePct(a.data(), results[a.id] ?? const <String, dynamic>{});
      }
      final avg = windowAttempts.isEmpty ? 0.0 : sum / windowAttempts.length;
      stats.add(
        _WeeklyStat(
          label: 'Week ${i + 1}',
          attempts: windowAttempts.length,
          minutes: mins,
          score: avg,
        ),
      );
    }
    return stats;
  }

  List<String> _insightLines(
    List<_SubjectMetric> subjects,
    double delta,
    List<_WeeklyStat> weekly,
  ) {
    final lines = <String>[];
    if (subjects.isNotEmpty) {
      lines.add(
        '${subjects.first.name} is your strongest subject with ${subjects.first.accuracy.toStringAsFixed(0)}% accuracy.',
      );
    }
    if (subjects.length > 1) {
      final weak = subjects.last;
      lines.add(
        'Focus more on ${weak.name} to boost your overall score (currently ${weak.accuracy.toStringAsFixed(0)}%).',
      );
    }

    final nonZeroWeeks = weekly.where((w) => w.score > 0).toList();
    if (nonZeroWeeks.length >= 2) {
      final trend = nonZeroWeeks.last.score - nonZeroWeeks.first.score;
      if (trend > 0) {
        lines.add(
          'Your recent weekly score trend is up by ${trend.toStringAsFixed(0)}%.',
        );
      }
    }

    if (delta > 0 && lines.length < 3) {
      lines.add(
        'Your overall score improved by ${delta.toStringAsFixed(0)}% in this period.',
      );
    }
    if (lines.isEmpty) {
      lines.add('Attempt more tests to unlock personalized insights.');
    }
    return lines.take(3).toList();
  }

  Widget _card(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Future<_Vm> _loadVm(String uid, String examId, _Window window) async {
    final cutoff = window.cutoff(DateTime.now());
    QuerySnapshot<Map<String, dynamic>> attemptSnap;
    try {
      attemptSnap = await FirebaseFirestore.instance
          .collection('testAttempts')
          .where('userId', isEqualTo: uid)
          .where('examId', isEqualTo: examId)
          .get();
    } catch (_) {
      attemptSnap = await FirebaseFirestore.instance
          .collection('testAttempts')
          .where('userId', isEqualTo: uid)
          .get();
    }

    final attempts =
        attemptSnap.docs.where((d) {
          final data = d.data();
          final attemptExamId = (data['examId'] ?? '').toString();
          final status = (data['status'] ?? 'completed').toString();
          final date = _attemptDate(data);
          if (attemptExamId != examId) return false;
          if (status != 'completed' || date == null) return false;
          if (cutoff == null) return true;
          return !date.isBefore(cutoff);
        }).toList()..sort(
          (a, b) => (_attemptDate(a.data()) ?? DateTime(2000)).compareTo(
            _attemptDate(b.data()) ?? DateTime(2000),
          ),
        );

    final results = await _loadResultMap(attempts, uid, examId);

    final points = <_P>[];
    int totalMinutes = 0;
    double scoreSum = 0;
    for (final a in attempts) {
      final data = a.data();
      final score = _scorePct(data, results[a.id] ?? const <String, dynamic>{});
      points.add(_P(_attemptDate(data) ?? DateTime.now(), score));
      scoreSum += score;
      totalMinutes += _attemptMins(data);
    }

    final avg = attempts.isEmpty ? 0.0 : scoreSum / attempts.length;
    final platformAvg = await _platformAvg(examId, cutoff);

    final subjectMap = await _subjectStats(attempts);
    final subjects = subjectMap.values.toList()
      ..sort((a, b) => b.accuracy.compareTo(a.accuracy));

    final first = _halfAvg(points, true);
    final second = _halfAvg(points, false);
    final delta = (second - first).clamp(-99.0, 99.0);

    final avgMins = attempts.isEmpty ? 0.0 : totalMinutes / attempts.length;
    final avgQ = _avgQuestions(attempts, results);
    final mpq = avgQ <= 0 ? 0.0 : avgMins / avgQ;
    final speed = (100 - (mpq * 8)).clamp(0.0, 100.0);
    final skillAcc = avg.clamp(0.0, 100.0);
    final consistency = (100 - (_std(points.map((e) => e.score).toList()) * 2))
        .clamp(0.0, 100.0);
    final coverage = subjects.isEmpty
        ? 0.0
        : (subjects.map((s) => s.coverage).reduce((a, b) => a + b) /
                  subjects.length)
              .clamp(0.0, 100.0);
    final difficulty = _difficulty(subjects);
    final timeMgmt = (100 - (mpq * 10)).clamp(0.0, 100.0);
    final weekly = _weeklyStats(attempts, results);

    return _Vm(
      tests: attempts.length,
      totalMinutes: totalMinutes,
      avg: avg,
      platformAvg: platformAvg,
      bestSubject: subjects.isEmpty ? '-' : subjects.first.name,
      delta: delta,
      points: points,
      subjects: subjects,
      strengths: List<_SubjectMetric>.from(subjects.take(4)),
      improvements: List<_SubjectMetric>.from(
        subjects.reversed.take(4).toList().reversed,
      ),
      speed: speed,
      skillAcc: skillAcc,
      consistency: consistency,
      coverage: coverage,
      difficulty: difficulty,
      timeMgmt: timeMgmt,
      bestSkill: _bestSkill(
        speed: speed,
        acc: skillAcc,
        consistency: consistency,
        timeMgmt: timeMgmt,
        difficulty: difficulty,
      ),
      focusArea: _focusArea(
        speed: speed,
        acc: skillAcc,
        consistency: consistency,
        timeMgmt: timeMgmt,
        difficulty: difficulty,
      ),
      weekly: weekly,
      insights: _insightLines(subjects, delta, weekly),
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadResultMap(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    String uid,
    String examId,
  ) async {
    return ResultDataService.loadResultsMap(
      attempts: attempts,
      userId: uid,
      examId: examId,
    );
  }

  Future<double> _platformAvg(String examId, DateTime? cutoff) async {
    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('results')
          .where('examId', isEqualTo: examId);
      if (cutoff != null) {
        q = q.where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff),
        );
      }
      final s = await q.get();
      if (s.docs.isEmpty) return 0;
      double sum = 0;
      for (final d in s.docs) {
        sum += _platformPct(d.data());
      }
      return sum / s.docs.length;
    } catch (_) {
      // If index/rules fail, return neutral platform average.
      return 0;
    }
  }

  Future<Map<String, _SubjectMetric>> _subjectStats(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    final out = <String, _SubjectMetric>{};
    final cache = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

    for (final aDoc in attempts) {
      final a = aDoc.data();
      final examId = (a['examId'] ?? '').toString();
      final testId = (a['testId'] ?? '').toString();
      if (examId.isEmpty || testId.isEmpty) continue;
      final key = '$examId|$testId';
      if (!cache.containsKey(key)) {
        try {
          final qs = await FirebaseFirestore.instance
              .collection('exams')
              .doc(examId)
              .collection('tests')
              .doc(testId)
              .collection('questions')
              .get();
          cache[key] = qs.docs;
        } catch (_) {
          cache[key] = const [];
        }
      }
      final questions = cache[key] ?? const [];

      final answers = <String, String>{};
      if (a['answers'] is Map) {
        final m = a['answers'] as Map;
        for (final e in m.entries) {
          answers[e.key.toString()] = (e.value ?? '').toString();
        }
      }

      final touched = <String>{};
      for (final qDoc in questions) {
        final q = qDoc.data();
        final sub =
            (q['subject'] ?? q['sectionName'] ?? q['section'] ?? 'General')
                .toString();
        final m = out.putIfAbsent(sub, () => _SubjectMetric(sub));
        m.total++;
        final sel = answers[qDoc.id] ?? '';
        if (sel.isNotEmpty) m.attemptedQuestions++;
        final corr = (q['correctOption'] ?? '').toString();
        if (sel.isNotEmpty && sel == corr) m.correct++;
        touched.add(sub);
      }
      for (final t in touched) {
        out[t]?.attempted++;
      }
    }

    return out;
  }

  double _platformPct(Map<String, dynamic> d) {
    final c = _toInt(d['correct']) ?? 0;
    final i = _toInt(d['incorrect']) ?? 0;
    final u = _toInt(d['unanswered']) ?? 0;
    final total = c + i + u;
    if (total > 0) return (c * 100.0 / total).clamp(0.0, 100.0);
    return (_toDouble(d['score']) ?? 0).clamp(0.0, 100.0);
  }

  double _scorePct(Map<String, dynamic> a, Map<String, dynamic> r) {
    final c = _toInt(r['correct']) ?? (a['answers'] as Map?)?.length ?? 0;
    final i = _toInt(r['incorrect']) ?? _toInt(a['wrong']) ?? 0;
    final u = _toInt(r['unanswered']) ?? _toInt(a['skipped']) ?? 0;
    final total = (c + i + u) > 0 ? (c + i + u) : 20;
    return (c * 100.0 / total).clamp(0.0, 100.0);
  }

  DateTime? _attemptDate(Map<String, dynamic> d) =>
      _toDate(d['submittedAt']) ?? _toDate(d['startedAt']);

  int _attemptMins(Map<String, dynamic> d) {
    final direct = _toInt(d['timeTaken']);
    if (direct != null) return direct;
    final s = _toDate(d['startedAt']);
    final e = _toDate(d['submittedAt']);
    if (s != null && e != null) {
      return e.difference(s).inMinutes.clamp(0, 100000);
    }
    return 0;
  }

  double _halfAvg(List<_P> points, bool firstHalf) {
    if (points.isEmpty) return 0;
    final mid = points.length ~/ 2;
    final seg = firstHalf
        ? points.sublist(0, math.max(1, mid))
        : points.sublist(mid);
    if (seg.isEmpty) return 0;
    return seg.map((e) => e.score).reduce((a, b) => a + b) / seg.length;
  }

  double _avgQuestions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    Map<String, Map<String, dynamic>> r,
  ) {
    if (attempts.isEmpty) return 0;
    double sum = 0;
    for (final a in attempts) {
      final d = a.data();
      final res = r[a.id] ?? const <String, dynamic>{};
      final c = _toInt(res['correct']) ?? (d['answers'] as Map?)?.length ?? 0;
      final i = _toInt(res['incorrect']) ?? _toInt(d['wrong']) ?? 0;
      final u = _toInt(res['unanswered']) ?? _toInt(d['skipped']) ?? 0;
      sum += (c + i + u) > 0 ? (c + i + u) : 20;
    }
    return sum / attempts.length;
  }

  double _std(List<double> v) {
    if (v.length <= 1) return 0;
    final mean = v.reduce((a, b) => a + b) / v.length;
    final varr =
        v.map((e) => (e - mean) * (e - mean)).reduce((a, b) => a + b) /
        v.length;
    return math.sqrt(varr);
  }

  double _difficulty(List<_SubjectMetric> s) {
    if (s.isEmpty) return 0;
    final good = s.where((e) => e.total >= 10 && e.accuracy >= 65).length;
    return ((good / s.length) * 100).clamp(0.0, 100.0);
  }

  int? _toInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? ''));
  double? _toDouble(dynamic v) => v is double
      ? v
      : (v is num ? v.toDouble() : double.tryParse(v?.toString() ?? ''));
  DateTime? _toDate(dynamic v) => v is Timestamp ? v.toDate() : null;

  String _fmtMins(int mins) {
    if (mins <= 0) return '0m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return h == 0 ? '${m}m' : '${h}h ${m.toString().padLeft(2, '0')}m';
  }
}

enum _Window {
  d7('Last 7 Days'),
  d30('Last 30 Days'),
  d90('3 Months'),
  all('All Time');

  const _Window(this.label);
  final String label;

  DateTime? cutoff(DateTime now) {
    switch (this) {
      case _Window.d7:
        return now.subtract(const Duration(days: 7));
      case _Window.d30:
        return now.subtract(const Duration(days: 30));
      case _Window.d90:
        return now.subtract(const Duration(days: 90));
      case _Window.all:
        return null;
    }
  }
}

class _Vm {
  final int tests;
  final int totalMinutes;
  final double avg;
  final double platformAvg;
  final String bestSubject;
  final double delta;
  final List<_P> points;
  final List<_SubjectMetric> subjects;
  final List<_SubjectMetric> strengths;
  final List<_SubjectMetric> improvements;
  final double speed;
  final double skillAcc;
  final double consistency;
  final double coverage;
  final double difficulty;
  final double timeMgmt;
  final String bestSkill;
  final String focusArea;
  final List<_WeeklyStat> weekly;
  final List<String> insights;

  _Vm({
    required this.tests,
    required this.totalMinutes,
    required this.avg,
    required this.platformAvg,
    required this.bestSubject,
    required this.delta,
    required this.points,
    required this.subjects,
    required this.strengths,
    required this.improvements,
    required this.speed,
    required this.skillAcc,
    required this.consistency,
    required this.coverage,
    required this.difficulty,
    required this.timeMgmt,
    required this.bestSkill,
    required this.focusArea,
    required this.weekly,
    required this.insights,
  });
}

class _P {
  final DateTime date;
  final double score;
  const _P(this.date, this.score);
}

class _WeeklyStat {
  final String label;
  final int attempts;
  final int minutes;
  final double score;

  const _WeeklyStat({
    required this.label,
    required this.attempts,
    required this.minutes,
    required this.score,
  });
}

class _SubjectMetric {
  final String name;
  int attempted = 0;
  int total = 0;
  int attemptedQuestions = 0;
  int correct = 0;

  _SubjectMetric(this.name);

  double get accuracy => total == 0 ? 0 : (correct * 100.0 / total);
  double get coverage => total == 0 ? 0 : (attemptedQuestions * 100.0 / total);
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points, required this.platformAvg});

  final List<_P> points;
  final double platformAvg;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendPainter(points, platformAvg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(points.first.date),
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
            ),
            Text(
              _fmt(points.last.date),
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    const m = [
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
    return '${m[d.month - 1]} ${d.day}';
  }
}

class _TrendPainter extends CustomPainter {
  final List<_P> points;
  final double platformAvg;
  _TrendPainter(this.points, this.platformAvg);

  @override
  void paint(Canvas canvas, Size size) {
    const l = 26.0;
    const r = 8.0;
    const t = 8.0;
    const b = 20.0;
    final left = l;
    final right = size.width - r;
    final top = t;
    final bottom = size.height - b;
    final w = right - left;
    final h = bottom - top;

    final grid = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = top + (h * i / 4);
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
    }

    final p = Path();
    final line = Paint()
      ..color = const Color(0xFF1E40AF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dot = Paint()..color = const Color(0xFF1E40AF);
    for (int i = 0; i < points.length; i++) {
      final x = left + (w * i / math.max(1, points.length - 1));
      final y = bottom - (points[i].score.clamp(0, 100) / 100.0) * h;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.8, dot);
    }
    canvas.drawPath(p, line);

    final py = bottom - (platformAvg.clamp(0, 100) / 100.0) * h;
    final pp = Paint()
      ..color = const Color(0xFFF97316)
      ..strokeWidth = 1.5;
    double x = left;
    while (x < right) {
      canvas.drawLine(Offset(x, py), Offset(math.min(x + 5, right), py), pp);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.platformAvg != platformAvg;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 14, height: 2, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }
}

class _R {
  final String label;
  final double value;
  const _R(this.label, this.value);
}

class _Radar extends StatelessWidget {
  final List<_R> items;
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
  final List<_R> items;
  _RadarPainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 + 8);
    final rad = math.min(size.width, size.height) * 0.34;
    final g = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int r = 1; r <= 4; r++) {
      canvas.drawPath(_poly(c, rad * (r / 4), items.length), g);
    }

    for (int i = 0; i < items.length; i++) {
      final a = _ang(i, items.length);
      final e = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
      canvas.drawLine(c, e, g);
      final tp = TextPainter(
        text: TextSpan(
          text: items[i].label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          c.dx + (rad + 12) * math.cos(a) - tp.width / 2,
          c.dy + (rad + 12) * math.sin(a) - tp.height / 2,
        ),
      );
    }

    final v = Path();
    for (int i = 0; i < items.length; i++) {
      final rr = (items[i].value.clamp(0, 100) / 100.0) * rad;
      final a = _ang(i, items.length);
      final p = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      if (i == 0) {
        v.moveTo(p.dx, p.dy);
      } else {
        v.lineTo(p.dx, p.dy);
      }
    }
    v.close();

    final fill = Paint()
      ..color = const Color(0xFF4F46E5).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final st = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(v, fill);
    canvas.drawPath(v, st);
  }

  Path _poly(Offset c, double r, int n) {
    final p = Path();
    for (int i = 0; i < n; i++) {
      final a = _ang(i, n);
      final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    p.close();
    return p;
  }

  double _ang(int i, int n) => (-math.pi / 2) + (2 * math.pi * i / n);

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.items != items;
}
