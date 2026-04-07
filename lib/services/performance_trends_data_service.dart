import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'exam_metadata_cache_service.dart';
import 'result_data_service.dart';

enum PerformanceTrendsWindow {
  d7('Last 7 Days'),
  d30('Last 30 Days'),
  d90('3 Months'),
  all('All Time');

  const PerformanceTrendsWindow(this.label);
  final String label;

  DateTime? cutoff(DateTime now) {
    switch (this) {
      case PerformanceTrendsWindow.d7:
        return now.subtract(const Duration(days: 7));
      case PerformanceTrendsWindow.d30:
        return now.subtract(const Duration(days: 30));
      case PerformanceTrendsWindow.d90:
        return now.subtract(const Duration(days: 90));
      case PerformanceTrendsWindow.all:
        return null;
    }
  }
}

class PerformanceTrendsPoint {
  final DateTime date;
  final double score;

  const PerformanceTrendsPoint(this.date, this.score);
}

class PerformanceTrendsWeeklyStat {
  final String label;
  final int attempts;
  final int minutes;
  final double score;

  const PerformanceTrendsWeeklyStat({
    required this.label,
    required this.attempts,
    required this.minutes,
    required this.score,
  });
}

class PerformanceTrendsSubjectMetric {
  final String name;
  int attempted = 0;
  int total = 0;
  int attemptedQuestions = 0;
  int correct = 0;

  PerformanceTrendsSubjectMetric(this.name);

  double get accuracy => total == 0 ? 0 : (correct * 100.0 / total);
  double get coverage => total == 0 ? 0 : (attemptedQuestions * 100.0 / total);
}

class PerformanceTrendsVm {
  final String cacheKey;
  final int tests;
  final int totalMinutes;
  final double avg;
  final String bestSubject;
  final double delta;
  final List<PerformanceTrendsPoint> points;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts;
  final Map<String, Map<String, dynamic>> results;
  final double speed;
  final double skillAcc;
  final double consistency;
  final double timeMgmt;
  final String bestSkill;
  final String focusArea;
  final List<PerformanceTrendsWeeklyStat> weekly;
  final String? latestAttemptId;
  final Map<String, dynamic>? latestAttemptData;
  final Map<String, dynamic>? latestResultData;

  const PerformanceTrendsVm({
    required this.cacheKey,
    required this.tests,
    required this.totalMinutes,
    required this.avg,
    required this.bestSubject,
    required this.delta,
    required this.points,
    required this.attempts,
    required this.results,
    required this.speed,
    required this.skillAcc,
    required this.consistency,
    required this.timeMgmt,
    required this.bestSkill,
    required this.focusArea,
    required this.weekly,
    required this.latestAttemptId,
    required this.latestAttemptData,
    required this.latestResultData,
  });
}

class PerformanceTrendsDeferredVmData {
  final String bestSubject;
  final List<PerformanceTrendsSubjectMetric> subjects;
  final List<PerformanceTrendsSubjectMetric> strengths;
  final List<PerformanceTrendsSubjectMetric> improvements;
  final double coverage;
  final double difficulty;
  final String bestSkill;
  final String focusArea;
  final List<String> insights;

  const PerformanceTrendsDeferredVmData({
    required this.bestSubject,
    required this.subjects,
    required this.strengths,
    required this.improvements,
    required this.coverage,
    required this.difficulty,
    required this.bestSkill,
    required this.focusArea,
    required this.insights,
  });
}

class PerformanceTrendsDataService {
  PerformanceTrendsDataService._();

  static const int platformAvgSampleSize = 250;
  static const int subjectStatsAttemptLimit = 8;

  static final Map<String, Future<PerformanceTrendsVm>> _vmFutureCache =
      <String, Future<PerformanceTrendsVm>>{};
  static final Map<String, Future<PerformanceTrendsDeferredVmData>>
      _deferredVmFutureCache =
      <String, Future<PerformanceTrendsDeferredVmData>>{};
  static final Map<String, Future<double>> _platformAvgFutureCache =
      <String, Future<double>>{};

  static Future<PerformanceTrendsVm> vmFuture({
    required String userId,
    required String examId,
    required PerformanceTrendsWindow window,
  }) {
    final key = '$userId|$examId|${window.name}';
    return _vmFutureCache.putIfAbsent(key, () => _loadVm(userId, examId, window));
  }

  static Future<PerformanceTrendsDeferredVmData> deferredVmFuture(
    PerformanceTrendsVm vm,
  ) {
    final key = '${vm.cacheKey}|deferred';
    return _deferredVmFutureCache.putIfAbsent(key, () => _loadDeferredVmData(vm));
  }

  static Future<double> platformAvgFuture({
    required String examId,
    required PerformanceTrendsWindow window,
  }) {
    final key = '$examId|${window.name}';
    return _platformAvgFutureCache.putIfAbsent(
      key,
      () => _platformAvg(examId, window.cutoff(DateTime.now())),
    );
  }

  static void prefetch({
    required String userId,
    required String examId,
    required PerformanceTrendsWindow window,
  }) {
    final vmKey = '$userId|$examId|${window.name}';
    _vmFutureCache.putIfAbsent(vmKey, () => _loadVm(userId, examId, window));
    _deferredVmFutureCache.putIfAbsent(
      '$vmKey|deferred',
      () async {
        final vm = await _vmFutureCache[vmKey]!;
        return _loadDeferredVmData(vm);
      },
    );
    _platformAvgFutureCache.putIfAbsent(
      '$examId|${window.name}',
      () => _platformAvg(examId, window.cutoff(DateTime.now())),
    );
  }

  static void invalidate({
    required String userId,
    required String examId,
    PerformanceTrendsWindow? window,
  }) {
    final base = '$userId|$examId|';
    _vmFutureCache.removeWhere(
      (key, _) => key.startsWith(base) && (window == null || key.endsWith(window.name)),
    );
    _deferredVmFutureCache.removeWhere(
      (key, _) => key.startsWith(base) && (window == null || key.contains('|${window.name}|')),
    );
    _platformAvgFutureCache.removeWhere(
      (key, _) => key.startsWith('$examId|') && (window == null || key.endsWith(window.name)),
    );
  }

  static Future<PerformanceTrendsVm> _loadVm(
    String uid,
    String examId,
    PerformanceTrendsWindow window,
  ) async {
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

    final attempts = attemptSnap.docs.where((d) {
      final data = d.data();
      final attemptExamId = (data['examId'] ?? '').toString();
      final status = (data['status'] ?? 'completed').toString();
      final date = _attemptDate(data);
      if (attemptExamId != examId) return false;
      if (status != 'completed' || date == null) return false;
      if (cutoff == null) return true;
      return !date.isBefore(cutoff);
    }).toList()
      ..sort(
        (a, b) => (_attemptDate(a.data()) ?? DateTime(2000)).compareTo(
          _attemptDate(b.data()) ?? DateTime(2000),
        ),
      );

    final results = await ResultDataService.loadResultsMap(
      attempts: attempts,
      userId: uid,
      examId: examId,
    );

    final points = <PerformanceTrendsPoint>[];
    int totalMinutes = 0;
    double scoreSum = 0;
    String? latestAttemptId;
    Map<String, dynamic>? latestAttemptData;
    Map<String, dynamic>? latestResultData;
    for (final a in attempts) {
      final data = a.data();
      latestAttemptId = a.id;
      latestAttemptData = data;
      latestResultData = results[a.id];
      final score = _scorePct(data, results[a.id] ?? const <String, dynamic>{});
      points.add(PerformanceTrendsPoint(_attemptDate(data) ?? DateTime.now(), score));
      scoreSum += score;
      totalMinutes += _attemptMins(data);
    }

    final avg = attempts.isEmpty ? 0.0 : scoreSum / attempts.length;
    final first = _halfAvg(points, true);
    final second = _halfAvg(points, false);
    final delta = (second - first).clamp(-99.0, 99.0);
    final avgMins = attempts.isEmpty ? 0.0 : totalMinutes / attempts.length;
    final avgQ = _avgQuestions(attempts, results);
    final mpq = avgQ <= 0 ? 0.0 : avgMins / avgQ;
    final speed = (100 - (mpq * 8)).clamp(0.0, 100.0);
    final skillAcc = avg.clamp(0.0, 100.0);
    final consistency =
        (100 - (_std(points.map((e) => e.score).toList()) * 2)).clamp(0.0, 100.0);
    final timeMgmt = (100 - (mpq * 10)).clamp(0.0, 100.0);
    final weekly = _weeklyStats(attempts, results);

    return PerformanceTrendsVm(
      cacheKey: '$uid|$examId|${window.name}',
      tests: attempts.length,
      totalMinutes: totalMinutes,
      avg: avg,
      bestSubject: '-',
      delta: delta,
      points: points,
      attempts: attempts,
      results: results,
      speed: speed,
      skillAcc: skillAcc,
      consistency: consistency,
      timeMgmt: timeMgmt,
      bestSkill: _bestSkill(
        speed: speed,
        acc: skillAcc,
        consistency: consistency,
        timeMgmt: timeMgmt,
        difficulty: 0,
      ),
      focusArea: _focusArea(
        speed: speed,
        acc: skillAcc,
        consistency: consistency,
        timeMgmt: timeMgmt,
        difficulty: 0,
      ),
      weekly: weekly,
      latestAttemptId: latestAttemptId,
      latestAttemptData: latestAttemptData,
      latestResultData: latestResultData,
    );
  }

  static Future<PerformanceTrendsDeferredVmData> _loadDeferredVmData(
    PerformanceTrendsVm vm,
  ) async {
    final subjectMap = await _subjectStats(vm.attempts);
    final subjects = subjectMap.values.toList()
      ..sort((a, b) => b.accuracy.compareTo(a.accuracy));
    final coverage = subjects.isEmpty
        ? 0.0
        : (subjects.map((s) => s.coverage).reduce((a, b) => a + b) /
                  subjects.length)
              .clamp(0.0, 100.0);
    final difficulty = _difficulty(subjects);

    return PerformanceTrendsDeferredVmData(
      bestSubject: subjects.isEmpty ? '-' : subjects.first.name,
      subjects: subjects,
      strengths: List<PerformanceTrendsSubjectMetric>.from(subjects.take(4)),
      improvements: List<PerformanceTrendsSubjectMetric>.from(
        subjects.reversed.take(4).toList().reversed,
      ),
      coverage: coverage,
      difficulty: difficulty,
      bestSkill: _bestSkill(
        speed: vm.speed,
        acc: vm.skillAcc,
        consistency: vm.consistency,
        timeMgmt: vm.timeMgmt,
        difficulty: difficulty,
      ),
      focusArea: _focusArea(
        speed: vm.speed,
        acc: vm.skillAcc,
        consistency: vm.consistency,
        timeMgmt: vm.timeMgmt,
        difficulty: difficulty,
      ),
      insights: _insightLines(subjects, vm.delta, vm.weekly),
    );
  }

  static Future<double> _platformAvg(String examId, DateTime? cutoff) async {
    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('results')
          .where('examId', isEqualTo: examId)
          .limit(platformAvgSampleSize);
      if (cutoff != null) {
        q = q.where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff),
        );
      }
      final s = await q.get();
      if (s.docs.isEmpty) {
        final fallback = await FirebaseFirestore.instance
            .collection('results')
            .where('examId', isEqualTo: examId)
            .limit(platformAvgSampleSize)
            .get();
        if (fallback.docs.isEmpty) return 0;
        double fallbackSum = 0;
        for (final d in fallback.docs) {
          fallbackSum += _platformPct(d.data());
        }
        return fallbackSum / fallback.docs.length;
      }
      double sum = 0;
      for (final d in s.docs) {
        sum += _platformPct(d.data());
      }
      return sum / s.docs.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<Map<String, PerformanceTrendsSubjectMetric>> _subjectStats(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    final out = <String, PerformanceTrendsSubjectMetric>{};
    final recentAttempts = attempts.length <= subjectStatsAttemptLimit
        ? attempts
        : attempts.sublist(attempts.length - subjectStatsAttemptLimit);
    final questionFutures =
        <String, Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>{};

    for (final aDoc in recentAttempts) {
      final a = aDoc.data();
      final examId = (a['examId'] ?? '').toString();
      final testId = (a['testId'] ?? '').toString();
      if (examId.isEmpty || testId.isEmpty) continue;
      final key = '$examId|$testId';
      questionFutures.putIfAbsent(
        key,
        () => ExamMetadataCacheService.getQuestions(examId, testId),
      );
    }

    final cache = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final entry in questionFutures.entries) {
      cache[entry.key] = await entry.value;
    }

    for (final aDoc in recentAttempts) {
      final a = aDoc.data();
      final examId = (a['examId'] ?? '').toString();
      final testId = (a['testId'] ?? '').toString();
      if (examId.isEmpty || testId.isEmpty) continue;
      final questions = cache['$examId|$testId'] ?? const [];

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
        final metric = out.putIfAbsent(sub, () => PerformanceTrendsSubjectMetric(sub));
        metric.total++;
        final selected = answers[qDoc.id] ?? '';
        if (selected.isNotEmpty) metric.attemptedQuestions++;
        final correct = (q['correctOption'] ?? '').toString();
        if (selected.isNotEmpty && selected == correct) metric.correct++;
        touched.add(sub);
      }
      for (final t in touched) {
        out[t]?.attempted++;
      }
    }

    return out;
  }

  static List<PerformanceTrendsWeeklyStat> _weeklyStats(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    Map<String, Map<String, dynamic>> results,
  ) {
    final groups = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final attempt in attempts) {
      final date = _attemptDate(attempt.data());
      if (date == null) continue;
      final monday = date.subtract(Duration(days: date.weekday - 1));
      final key = '${monday.year}-${monday.month}-${monday.day}';
      groups.putIfAbsent(key, () => <QueryDocumentSnapshot<Map<String, dynamic>>>[]).add(attempt);
    }

    final out = <PerformanceTrendsWeeklyStat>[];
    final keys = groups.keys.toList()..sort();
    for (final key in keys) {
      final weekAttempts = groups[key]!;
      var minutes = 0;
      var scoreSum = 0.0;
      for (final attempt in weekAttempts) {
        minutes += _attemptMins(attempt.data());
        scoreSum += _scorePct(
          attempt.data(),
          results[attempt.id] ?? const <String, dynamic>{},
        );
      }
      out.add(
        PerformanceTrendsWeeklyStat(
          label: key,
          attempts: weekAttempts.length,
          minutes: minutes,
          score: weekAttempts.isEmpty ? 0 : scoreSum / weekAttempts.length,
        ),
      );
    }
    return out.reversed.take(6).toList().reversed.toList();
  }

  static double _avgQuestions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    Map<String, Map<String, dynamic>> results,
  ) {
    if (attempts.isEmpty) return 0;
    double sum = 0;
    for (final a in attempts) {
      final data = a.data();
      final r = results[a.id] ?? const <String, dynamic>{};
      final c = _toInt(r['correct']) ?? (data['answers'] as Map?)?.length ?? 0;
      final i = _toInt(r['incorrect']) ?? _toInt(data['wrong']) ?? 0;
      final u = _toInt(r['unanswered']) ?? _toInt(data['skipped']) ?? 0;
      final total = (c + i + u) > 0 ? (c + i + u) : 20;
      sum += total;
    }
    return sum / attempts.length;
  }

  static double _halfAvg(List<PerformanceTrendsPoint> points, bool first) {
    if (points.isEmpty) return 0;
    final half = (points.length / 2).ceil();
    final slice = first ? points.take(half) : points.skip(points.length - half);
    final list = slice.toList();
    if (list.isEmpty) return 0;
    return list.map((e) => e.score).reduce((a, b) => a + b) / list.length;
  }

  static double _difficulty(List<PerformanceTrendsSubjectMetric> subjects) {
    if (subjects.isEmpty) return 0;
    final avg =
        subjects.map((s) => 100 - s.accuracy).reduce((a, b) => a + b) / subjects.length;
    return avg.clamp(0.0, 100.0);
  }

  static List<String> _insightLines(
    List<PerformanceTrendsSubjectMetric> subjects,
    double delta,
    List<PerformanceTrendsWeeklyStat> weekly,
  ) {
    final lines = <String>[];
    if (delta > 0) {
      lines.add('Your recent scores are trending upward.');
    } else if (delta < 0) {
      lines.add('Recent scores dipped slightly. A review pass may help.');
    }
    if (subjects.isNotEmpty) {
      lines.add('Strongest area: ${subjects.first.name}.');
      lines.add('Lowest area: ${subjects.last.name}.');
    }
    if (weekly.isNotEmpty) {
      final latest = weekly.last;
      lines.add(
        'Latest week: ${latest.attempts} tests with ${latest.score.toStringAsFixed(0)}% average.',
      );
    }
    if (lines.isEmpty) {
      lines.add('Take a few more tests to unlock deeper insights.');
    }
    return lines;
  }

  static String _bestSkill({
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
    final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  static String _focusArea({
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
    final sorted = map.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return sorted.first.key;
  }

  static double _platformPct(Map<String, dynamic> d) {
    final c = _toInt(d['correct']) ?? 0;
    final i = _toInt(d['incorrect']) ?? 0;
    final u = _toInt(d['unanswered']) ?? 0;
    final total = c + i + u;
    if (total > 0) return (c * 100.0 / total).clamp(0.0, 100.0);
    return (_toDouble(d['score']) ?? 0).clamp(0.0, 100.0);
  }

  static double _scorePct(Map<String, dynamic> a, Map<String, dynamic> r) {
    final c = _toInt(r['correct']) ?? (a['answers'] as Map?)?.length ?? 0;
    final i = _toInt(r['incorrect']) ?? _toInt(a['wrong']) ?? 0;
    final u = _toInt(r['unanswered']) ?? _toInt(a['skipped']) ?? 0;
    final total = (c + i + u) > 0 ? (c + i + u) : 20;
    return (c * 100.0 / total).clamp(0.0, 100.0);
  }

  static DateTime? _attemptDate(Map<String, dynamic> d) =>
      _toDate(d['submittedAt']) ?? _toDate(d['startedAt']);

  static int _attemptMins(Map<String, dynamic> d) {
    final direct = _toInt(d['timeTaken']);
    if (direct != null) return direct;
    final started = _toDate(d['startedAt']);
    final submitted = _toDate(d['submittedAt']);
    if (started != null && submitted != null) {
      final diff = submitted.difference(started).inMinutes;
      return diff < 0 ? 0 : diff;
    }
    return 0;
  }

  static double _std(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((value) => math.pow(value - mean, 2)).reduce((a, b) => a + b) /
            values.length;
    return math.sqrt(variance);
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
