import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'result_data_service.dart';

class ExamAnalyticsBackfillService {
  ExamAnalyticsBackfillService._();

  static Future<void> backfillExamAnalyticsForExam({
    required String examId,
  }) async {
    if (examId.trim().isEmpty) return;

    final attemptsSnap = await FirebaseFirestore.instance
        .collection('testAttempts')
        .where('examId', isEqualTo: examId)
        .get();

    final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in attemptsSnap.docs) {
      final data = doc.data();
      final status = (data['status'] ?? 'completed').toString().toLowerCase();
      final userId = (data['userId'] ?? '').toString().trim();
      if (status != 'completed' || userId.isEmpty) continue;
      grouped.putIfAbsent(userId, () => <QueryDocumentSnapshot<Map<String, dynamic>>>[]).add(doc);
    }

    for (final entry in grouped.entries) {
      final attempts = entry.value
        ..sort((a, b) {
          final aTs = _toDate(a.data()['submittedAt']) ??
              _toDate(a.data()['startedAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTs = _toDate(b.data()['submittedAt']) ??
              _toDate(b.data()['startedAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return aTs.compareTo(bTs);
        });
      final summary = await _buildSummary(
        userId: entry.key,
        examId: examId,
        attempts: attempts,
      );
      if (summary == null) continue;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(entry.key)
          .collection('examAnalytics')
          .doc(examId)
          .set(summary, SetOptions(merge: true));
    }
  }

  static Future<Map<String, dynamic>?> _buildSummary({
    required String userId,
    required String examId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  }) async {
    if (attempts.isEmpty) return null;
    final attemptSignature = attempts
        .map((doc) {
          final data = doc.data();
          final stamp =
              (_toDate(data['submittedAt']) ?? _toDate(data['startedAt']))
                      ?.millisecondsSinceEpoch ??
                  0;
          return '${doc.id}:$stamp:${(data['status'] ?? '').toString()}';
        })
        .join('|');

    final resultMap = await ResultDataService.loadResultsMap(
      attempts: attempts,
      userId: userId,
      examId: examId,
    );
    final examDoc =
        await FirebaseFirestore.instance.collection('exams').doc(examId).get();
    final examName = (examDoc.data()?['name'] ?? 'Selected Exam').toString();
    final detail = await _loadQuestionDetails(attempts, resultMap);
    final testConfigs = await _loadTestConfigs(attempts);

    final trendPoints = <Map<String, dynamic>>[];
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
    double totalMarksLost = 0;
    var hasNegativeMarking = false;
    double totalSecondsPerQuestion = 0;
    int secondsPerQuestionCount = 0;
    DateTime lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);

    for (int i = 0; i < attempts.length; i++) {
      final attempt = attempts[i].data();
      final result = resultMap[attempts[i].id] ?? const <String, dynamic>{};
      final date = _toDate(attempt['submittedAt']) ??
          _toDate(attempt['startedAt']) ??
          DateTime.now();
      if (date.isAfter(lastUpdated)) lastUpdated = date;

      final score = _scorePct(attempt, result);
      final percentile = (_toDouble(result['percentile']) ?? score).clamp(0.0, 100.0);
      final rank = _toInt(result['rank']) ?? 0;
      final normalizedCounts = ResultDataService.normalizeCounts(
        attempt: attempt,
        result: result,
      );
      final correct = normalizedCounts['correct'] ?? 0;
      final incorrect = normalizedCounts['incorrect'] ?? 0;
      final unanswered = normalizedCounts['unanswered'] ?? 0;
      final testConfig =
          testConfigs['$examId|${(attempt['testId'] ?? '').toString()}'];
      final negativeMarkingEnabled =
          (testConfig?['negativeMarkingEnabled'] == true) ||
              ((_toDouble(testConfig?['negativeMarks']) ?? 0) > 0);
      final penaltyPerWrong = _toDouble(testConfig?['negativeMarks']) ?? 0.0;
      final marksPerQuestion =
          _toDouble(testConfig?['marksPerQuestion']) ??
              _toDouble(testConfig?['positiveMarks']) ??
              0.0;
      if (negativeMarkingEnabled) hasNegativeMarking = true;
      totalMarksLost +=
          incorrect * (negativeMarkingEnabled ? penaltyPerWrong : marksPerQuestion);
      final questionCount = ((correct + incorrect + unanswered) > 0
          ? (correct + incorrect + unanswered)
          : (detail['totalsByAttempt']?[attempts[i].id] ?? 0)) as int;

      final secondsPerQuestion = _secondsPerQuestion(attempt, result, questionCount);
      if (secondsPerQuestion != null) {
        totalSecondsPerQuestion += secondsPerQuestion;
        secondsPerQuestionCount++;
        timeScoreTrend.add(math.max(0.0, 100 - secondsPerQuestion));
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
      trendPoints.add({
        'label': 'T${i + 1}',
        'score': score,
        'date': Timestamp.fromDate(date),
        'extra': percentile,
      });
    }

    final avgScore = totalScore / attempts.length;
    final avgPercentile = totalPercentile / attempts.length;
    final avgSecondsPerQuestion = secondsPerQuestionCount == 0
        ? 0.0
        : totalSecondsPerQuestion / secondsPerQuestionCount;

    final subjects = List<Map<String, dynamic>>.from(detail['subjects'] ?? const [])
      ..sort(
        (a, b) => (_toDouble(b['accuracy']) ?? 0).compareTo(_toDouble(a['accuracy']) ?? 0),
      );
    final chapters = List<Map<String, dynamic>>.from(detail['chapters'] ?? const [])
      ..sort(
        (a, b) =>
            (_toDouble(a['proficiency']) ?? 0).compareTo(_toDouble(b['proficiency']) ?? 0),
      );
    final chapterAttempts =
        List<Map<String, dynamic>>.from(detail['chapterAttempts'] ?? const []);

    final consistency = _consistencyScore(trendPoints);
    final scoreBalance = _scoreBalance(subjects);
    final frequency = _testFrequency(attempts);
    final timeMgmt = (100 - (avgSecondsPerQuestion * 0.9)).clamp(0.0, 100.0);
    final speed = (100 - (avgSecondsPerQuestion * 1.1)).clamp(0.0, 100.0);
    final readiness = ((avgScore * 0.45) +
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
    final safeAttempts =
        totalQuestions == 0 ? 0.0 : (totalCorrect * 100.0 / totalQuestions);
    final focusSubject =
        subjects.isEmpty ? 'General' : (subjects.last['name'] ?? 'General').toString();
    final timeSlices = _timeSlicesForSubjects(subjects);

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

    return {
      'schemaVersion': 1,
      'attemptSignature': attemptSignature,
      'summary': {
        'examName': examName,
        'lastUpdated': Timestamp.fromDate(
          lastUpdated == DateTime.fromMillisecondsSinceEpoch(0)
              ? DateTime.now()
              : lastUpdated,
        ),
        'testsTaken': attempts.length,
        'totalQuestions': totalQuestions,
        'totalMinutes': totalMinutes,
        'avgScore': avgScore,
        'maxScore': maxScore,
        'avgPercentile': avgPercentile,
        'bestRank': bestRank,
        'readiness': readiness,
        'delta': delta,
        'focusSubject': focusSubject,
        'totalCorrect': totalCorrect,
        'totalIncorrect': totalIncorrect,
        'totalSkipped': totalSkipped,
        'avgSecondsPerQuestion': avgSecondsPerQuestion,
        'trendPoints': trendPoints,
        'subjects': subjects,
        'chapters': chapters,
        'chapterAttempts': chapterAttempts,
        'timeSlices': timeSlices,
        'timeScoreTrend': timeScoreTrend,
        'timeInsight': timeInsight,
        'riskBars': riskBars.take(6).toList(),
        'marksLost': totalMarksLost,
        'hasNegativeMarking': hasNegativeMarking,
        'riskAccuracy': riskAccuracy,
        'safeAttempts': safeAttempts,
        'accuracyStability': consistency,
        'scoreBalance': scoreBalance,
        'testFrequency': frequency,
        'timeMgmt': timeMgmt,
        'speed': speed,
        'consistencyLabel': consistencyLabel,
        'recommendations': const <Map<String, dynamic>>[],
        'gainPotential': 0.0,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static Future<Map<String, dynamic>> _loadQuestionDetails(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    Map<String, Map<String, dynamic>> resultMap,
  ) async {
    final subjects = <String, Map<String, dynamic>>{};
    final chapters = <String, Map<String, dynamic>>{};
    final totalsByAttempt = <String, int>{};
    final chapterAttempts = <Map<String, dynamic>>[];
    final questionCache = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    final sectionNameCache = <String, Map<String, String>>{};

    for (int attemptIndex = 0; attemptIndex < attempts.length; attemptIndex++) {
      final attemptDoc = attempts[attemptIndex];
      final attempt = attemptDoc.data();
      final examId = (attempt['examId'] ?? '').toString();
      final testId = (attempt['testId'] ?? '').toString();
      if (examId.isEmpty || testId.isEmpty) continue;
      final cacheKey = '$examId|$testId';
      final embeddedQuestions =
          _readEmbeddedQuestions(resultMap[attemptDoc.id]?['question'] ?? attempt['question']);
      List<QueryDocumentSnapshot<Map<String, dynamic>>> firestoreQuestions = const [];
      if (embeddedQuestions.isEmpty) {
        firestoreQuestions = questionCache.putIfAbsent(cacheKey, () => []);
        if (firestoreQuestions.isEmpty) {
          try {
            final snap = await FirebaseFirestore.instance
                .collection('exams')
                .doc(examId)
                .collection('tests')
                .doc(testId)
                .collection('questions')
                .get();
            questionCache[cacheKey] = snap.docs;
            firestoreQuestions = snap.docs;
          } catch (_) {}
        }
      }
      final sectionNames = sectionNameCache.putIfAbsent(
        cacheKey,
        () => <String, String>{},
      );
      if (sectionNames.isEmpty) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('exams')
              .doc(examId)
              .collection('tests')
              .doc(testId)
              .collection('sections')
              .get();
          for (final doc in snap.docs) {
            final name = (doc.data()['name'] ?? '').toString().trim();
            if (name.isNotEmpty) sectionNames[doc.id] = name;
          }
        } catch (_) {}
      }

      final totalQuestions =
          embeddedQuestions.isNotEmpty ? embeddedQuestions.length : firestoreQuestions.length;
      totalsByAttempt[attemptDoc.id] = totalQuestions;
      final answers = _answersMap(resultMap[attemptDoc.id]?['answers'] ?? attempt['answers']);
      final perQuestionSeconds =
          _secondsPerQuestion(attempt, resultMap[attemptDoc.id] ?? const <String, dynamic>{}, totalQuestions) ?? 0.0;
      final attemptChapterMetrics = <String, Map<String, dynamic>>{};
      final attemptDate = _toDate(attempt['submittedAt']) ??
          _toDate(attempt['startedAt']) ??
          DateTime.now();
      final label = 'T${attemptIndex + 1}';

      final iterable = embeddedQuestions.isNotEmpty
          ? embeddedQuestions
          : firestoreQuestions.map((doc) => doc.data()).toList();
      for (final question in iterable) {
        final questionId =
            (question['__id'] ?? question['id'] ?? '').toString();
        final subjectName = _subjectName(question, sectionNames);
        final chapterName = _chapterName(question, subjectName);
        final selected = _normalizeAnswerValue(
          answers[embeddedQuestions.isNotEmpty ? questionId : questionId] ??
              answers[questionId] ??
              '',
        );
        final correct = _optionLetter(question['correctOption']);
        final isAttempted = selected.isNotEmpty;
        final isCorrect = isAttempted && selected == correct;

        final subjectMetric = subjects.putIfAbsent(
          subjectName,
          () => {
            'name': subjectName,
            'total': 0,
            'attempted': 0,
            'correct': 0,
            'totalSeconds': 0.0,
          },
        );
        subjectMetric['total'] = (subjectMetric['total'] as int) + 1;
        if (isAttempted) {
          subjectMetric['attempted'] = (subjectMetric['attempted'] as int) + 1;
        }
        if (isCorrect) {
          subjectMetric['correct'] = (subjectMetric['correct'] as int) + 1;
        }
        subjectMetric['totalSeconds'] =
            (subjectMetric['totalSeconds'] as double) + perQuestionSeconds;

        final chapterKey = '$subjectName|$chapterName';
        final chapterMetric = chapters.putIfAbsent(
          chapterKey,
          () => {
            'name': chapterName,
            'subject': subjectName,
            'total': 0,
            'attempted': 0,
            'correct': 0,
          },
        );
        chapterMetric['total'] = (chapterMetric['total'] as int) + 1;
        if (isAttempted) {
          chapterMetric['attempted'] = (chapterMetric['attempted'] as int) + 1;
        }
        if (isCorrect) {
          chapterMetric['correct'] = (chapterMetric['correct'] as int) + 1;
        }

        final attemptChapterMetric = attemptChapterMetrics.putIfAbsent(
          chapterKey,
          () => {
            'name': chapterName,
            'subject': subjectName,
            'total': 0,
            'attempted': 0,
            'correct': 0,
          },
        );
        attemptChapterMetric['total'] = (attemptChapterMetric['total'] as int) + 1;
        if (isAttempted) {
          attemptChapterMetric['attempted'] =
              (attemptChapterMetric['attempted'] as int) + 1;
        }
        if (isCorrect) {
          attemptChapterMetric['correct'] =
              (attemptChapterMetric['correct'] as int) + 1;
        }
      }

      for (final metric in attemptChapterMetrics.values) {
        final total = metric['total'] as int;
        final attempted = metric['attempted'] as int;
        final correct = metric['correct'] as int;
        chapterAttempts.add({
          'label': label,
          'date': Timestamp.fromDate(attemptDate),
          'subject': metric['subject'],
          'chapter': metric['name'],
          'accuracy': total == 0 ? 0.0 : (correct * 100.0 / total),
          'avgMinutesPerQuestion': perQuestionSeconds / 60.0,
          'totalQuestions': total,
          'attempted': attempted,
          'correct': correct,
          'skipped': math.max(0, total - attempted),
        });
      }
    }

    final subjectList = subjects.values.map((metric) {
      final total = metric['total'] as int;
      final attempted = metric['attempted'] as int;
      final correct = metric['correct'] as int;
      final totalSeconds = (metric['totalSeconds'] as num).toDouble();
      return {
        ...metric,
        'accuracy': total == 0 ? 0.0 : (correct * 100.0 / total),
        'coverage': total == 0 ? 0.0 : (attempted * 100.0 / total),
        'avgSeconds': total == 0 ? 0.0 : (totalSeconds / total),
        'shortName': (metric['name'] as String).length <= 10
            ? metric['name']
            : '${(metric['name'] as String).substring(0, 9)}...',
      };
    }).toList(growable: false);

    final chapterList = chapters.values.map((metric) {
      final total = metric['total'] as int;
      final attempted = metric['attempted'] as int;
      final correct = metric['correct'] as int;
      final proficiency = attempted == 0 ? 0.0 : (correct * 100.0 / attempted);
      return {
        ...metric,
        'accuracy': total == 0 ? 0.0 : (correct * 100.0 / total),
        'proficiency': proficiency,
      };
    }).toList(growable: false);

    return {
      'subjects': subjectList,
      'chapters': chapterList,
      'totalsByAttempt': totalsByAttempt,
      'chapterAttempts': chapterAttempts,
    };
  }

  static Future<Map<String, Map<String, dynamic>>> _loadTestConfigs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
  ) async {
    final configs = <String, Map<String, dynamic>>{};
    for (final attemptDoc in attempts) {
      final attempt = attemptDoc.data();
      final examId = (attempt['examId'] ?? '').toString();
      final testId = (attempt['testId'] ?? '').toString();
      if (examId.isEmpty || testId.isEmpty) continue;
      final key = '$examId|$testId';
      if (configs.containsKey(key)) continue;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('exams')
            .doc(examId)
            .collection('tests')
            .doc(testId)
            .get();
        configs[key] = snap.data() ?? const <String, dynamic>{};
      } catch (_) {
        configs[key] = const <String, dynamic>{};
      }
    }
    return configs;
  }

  static List<Map<String, dynamic>> _readEmbeddedQuestions(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item.map((key, value) => MapEntry(key.toString(), value))))
        .toList(growable: false);
  }

  static Map<String, String> _answersMap(dynamic raw) {
    final out = <String, String>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      out[entry.key.toString()] = (entry.value ?? '').toString();
    }
    return out;
  }

  static String _optionLetter(dynamic index) {
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
        return (index ?? '').toString().trim().toUpperCase();
    }
  }

  static String _normalizeAnswerValue(dynamic value) {
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

  static String _subjectName(Map<String, dynamic> question, Map<String, String> sectionNames) {
    final directName =
        (question['subject'] ?? question['sectionName'] ?? question['section'])?.toString().trim();
    if (directName != null && directName.isNotEmpty) return directName;
    final sectionId = question['sectionId']?.toString().trim();
    if (sectionId != null && sectionId.isNotEmpty) {
      final mappedName = sectionNames[sectionId]?.trim();
      if (mappedName != null && mappedName.isNotEmpty) return mappedName;
    }
    return 'General';
  }

  static String _chapterName(Map<String, dynamic> question, String fallbackSubject) {
    return (question['chapter'] ??
            question['chapterName'] ??
            question['topic'] ??
            question['topicName'] ??
            fallbackSubject)
        .toString();
  }

  static double _scorePct(Map<String, dynamic> attempt, Map<String, dynamic> result) {
    final normalizedCounts = ResultDataService.normalizeCounts(attempt: attempt, result: result);
    final correct = normalizedCounts['correct'] ?? _toInt(result['score']) ?? 0;
    final incorrect = normalizedCounts['incorrect'] ?? 0;
    final unanswered = normalizedCounts['unanswered'] ?? 0;
    final total = (correct + incorrect + unanswered) > 0 ? (correct + incorrect + unanswered) : 20;
    return (correct * 100.0 / total).clamp(0.0, 100.0);
  }

  static double? _secondsPerQuestion(
    Map<String, dynamic> attempt,
    Map<String, dynamic> result,
    int fallbackQuestions,
  ) {
    final mins = _attemptMinutes(attempt);
    final normalizedCounts = ResultDataService.normalizeCounts(attempt: attempt, result: result);
    final totalQuestions = (normalizedCounts['correct'] ?? 0) +
        (normalizedCounts['incorrect'] ?? 0) +
        (normalizedCounts['unanswered'] ?? 0);
    final effectiveQuestions = totalQuestions > 0 ? totalQuestions : fallbackQuestions;
    if (mins <= 0 || effectiveQuestions <= 0) return null;
    return (mins * 60.0) / effectiveQuestions;
  }

  static int _attemptMinutes(Map<String, dynamic> attempt) {
    final timeTaken = _toInt(attempt['timeTaken']);
    if (timeTaken != null) return timeTaken;
    final started = _toDate(attempt['startedAt']);
    final submitted = _toDate(attempt['submittedAt']);
    if (started == null || submitted == null) return 0;
    return submitted.difference(started).inMinutes;
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

  static double _consistencyScore(List<Map<String, dynamic>> points) {
    if (points.length <= 1) return 50;
    final values = points.map((e) => _toDouble(e['score']) ?? 0).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
            .map((value) => math.pow(value - mean, 2))
            .reduce((a, b) => a + b) /
        values.length;
    final deviation = math.sqrt(variance);
    return (100 - deviation * 2.4).clamp(0.0, 100.0);
  }

  static double _scoreBalance(List<Map<String, dynamic>> subjects) {
    if (subjects.isEmpty) return 0;
    final values = subjects.map((e) => _toDouble(e['accuracy']) ?? 0).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final spread =
        values.map((value) => (value - mean).abs()).reduce((a, b) => a + b) /
            values.length;
    return (100 - spread * 1.6).clamp(0.0, 100.0);
  }

  static double _coverageScore(List<Map<String, dynamic>> subjects) {
    if (subjects.isEmpty) return 0;
    return subjects.map((subject) => _toDouble(subject['coverage']) ?? 0).reduce((a, b) => a + b) /
        subjects.length;
  }

  static List<Map<String, dynamic>> _timeSlicesForSubjects(List<Map<String, dynamic>> subjects) {
    const palette = <int>[0xFF4B72F1, 0xFF31B56A, 0xFFF2A126, 0xFFEB5757];
    final visibleSubjects = subjects.take(4).toList();
    final totalSeconds = visibleSubjects.fold<double>(
      0.0,
      (runningTotal, subject) => runningTotal + (_toDouble(subject['totalSeconds']) ?? 0),
    );
    return visibleSubjects.asMap().entries.map((entry) {
      final index = entry.key;
      final subject = entry.value;
      final label = (subject['shortName'] ?? subject['name'] ?? '').toString();
      final subjectSeconds = _toDouble(subject['totalSeconds']) ?? 0;
      return {
        'label': label,
        'value': totalSeconds <= 0 ? 0.0 : (subjectSeconds * 100.0 / totalSeconds),
        'color': palette[index % palette.length],
      };
    }).toList(growable: false);
  }

  static double _testFrequency(List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts) {
    if (attempts.length <= 1) return 45;
    final dates = attempts
        .map((doc) => _toDate(doc.data()['submittedAt']) ?? _toDate(doc.data()['startedAt']))
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

  static double _halfAverage(List<Map<String, dynamic>> points, bool firstHalf) {
    if (points.isEmpty) return 0;
    final mid = points.length ~/ 2;
    final slice = firstHalf ? points.sublist(0, math.max(1, mid)) : points.sublist(mid);
    if (slice.isEmpty) return 0;
    return slice.map((point) => _toDouble(point['score']) ?? 0).reduce((a, b) => a + b) /
        slice.length;
  }
}
