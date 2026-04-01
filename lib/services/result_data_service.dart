import 'package:cloud_firestore/cloud_firestore.dart';

import 'result_schema_contract.dart';

/// Canonical contract:
/// - `testAttempts/{attemptId}` is the source attempt record
/// - `results/{attemptId}` stores the result for the same attempt
///
/// Legacy fallback remains for older data where result doc ids may not match
/// attempt ids. New writes should always use `results/{attemptId}`.
class ResultDataService {
  const ResultDataService._();

  static Map<String, int> normalizeCounts({
    required Map<String, dynamic> attempt,
    required Map<String, dynamic> result,
  }) {
    final answers = _readAnswers(result['answers'] ?? attempt['answers']);
    final questionIds = _readQuestionIds(result['question'] ?? attempt['question']);
    final correct = _toInt(result['correct']) ?? 0;
    final unanswered = _toInt(result['unanswered']) ?? _toInt(attempt['skipped']) ?? 0;
    final storedIncorrect =
        _toInt(result['incorrect']) ?? _toInt(attempt['wrong']) ?? 0;

    if (answers.isEmpty || questionIds.isEmpty) {
      return {
        'correct': correct,
        'incorrect': storedIncorrect,
        'unanswered': unanswered,
      };
    }

    final answeredCount = answers.values.where((value) => value.trim().isNotEmpty).length;
    final normalizedIncorrect = answeredCount > correct ? answeredCount - correct : 0;
    final normalizedUnanswered = questionIds.length > answeredCount
        ? questionIds.length - answeredCount
        : 0;

    return {
      'correct': correct,
      'incorrect': normalizedIncorrect,
      'unanswered': normalizedUnanswered,
    };
  }

  static Future<Map<String, Map<String, dynamic>>> loadResultsMap({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> attempts,
    required String userId,
    String? examId,
  }) async {
    if (attempts.isEmpty) return {};

    final ids = attempts.map((attempt) => attempt.id).toList();
    final out = <String, Map<String, dynamic>>{};

    try {
      for (int i = 0; i < ids.length; i += 10) {
        final end = (i + 10) > ids.length ? ids.length : (i + 10);
        final chunk = ids.sublist(i, end);
        final snap = await FirebaseFirestore.instance
            .collection(ResultSchemaContract.resultCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          out[doc.id] = doc.data();
        }
      }
    } catch (_) {
      // Fallback matcher below handles older data if direct ids are absent.
    }

    final unresolved = attempts.where((attempt) => !out.containsKey(attempt.id)).toList();
    if (unresolved.isEmpty) return out;

    QuerySnapshot<Map<String, dynamic>> allResults;
    try {
      var query = FirebaseFirestore.instance
          .collection(ResultSchemaContract.resultCollection)
          .where('userId', isEqualTo: userId);
      if (examId != null && examId.isNotEmpty) {
        query = query.where('examId', isEqualTo: examId);
      }
      allResults = await query.get();
    } catch (_) {
      allResults = await FirebaseFirestore.instance
          .collection(ResultSchemaContract.resultCollection)
          .where('userId', isEqualTo: userId)
          .get();
    }

    final buckets =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in allResults.docs) {
      final data = doc.data();
      final key =
          '${(data['examId'] ?? '').toString()}|${(data['testId'] ?? '').toString()}';
      buckets.putIfAbsent(key, () => []).add(doc);
    }

    final usedResultDocIds = <String>{};
    for (final attempt in unresolved) {
      final data = attempt.data();
      final key =
          '${(data['examId'] ?? '').toString()}|${(data['testId'] ?? '').toString()}';
      final candidates = buckets[key] ?? const [];
      if (candidates.isEmpty) continue;

      final attemptTs =
          _toDate(data['submittedAt']) ??
          _toDate(data['startedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      QueryDocumentSnapshot<Map<String, dynamic>>? best;
      var bestDelta = 1 << 62;
      for (final candidate in candidates) {
        if (usedResultDocIds.contains(candidate.id)) continue;
        final resultTs =
            _toDate(candidate.data()['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final delta =
            (resultTs.millisecondsSinceEpoch - attemptTs.millisecondsSinceEpoch)
                .abs();
        if (delta < bestDelta) {
          bestDelta = delta;
          best = candidate;
        }
      }

      if (best != null) {
        out[attempt.id] = best.data();
        usedResultDocIds.add(best.id);
      }
    }

    return out;
  }

  static Future<Map<String, dynamic>> resolveResultForAttempt({
    required String attemptId,
    required Map<String, dynamic> attemptData,
    required Map<String, dynamic> initialResultData,
  }) async {
    if (_hasCoreResultFields(initialResultData)) return initialResultData;

    try {
      final direct = await FirebaseFirestore.instance
          .collection(ResultSchemaContract.resultCollection)
          .doc(attemptId)
          .get();
      if (direct.exists) {
        return direct.data() ?? initialResultData;
      }
    } catch (_) {}

    final userId = (attemptData['userId'] ?? '').toString();
    final examId = (attemptData['examId'] ?? '').toString();
    final testId = (attemptData['testId'] ?? '').toString();
    if (userId.isEmpty || examId.isEmpty || testId.isEmpty) {
      return initialResultData;
    }

    QuerySnapshot<Map<String, dynamic>> legacyResults;
    try {
      legacyResults = await FirebaseFirestore.instance
          .collection(ResultSchemaContract.resultCollection)
          .where('userId', isEqualTo: userId)
          .where('examId', isEqualTo: examId)
          .where('testId', isEqualTo: testId)
          .get();
    } catch (_) {
      legacyResults = await FirebaseFirestore.instance
          .collection(ResultSchemaContract.resultCollection)
          .where('userId', isEqualTo: userId)
          .get();
    }

    if (legacyResults.docs.isEmpty) return initialResultData;

    final attemptTs =
        _toDate(attemptData['submittedAt']) ??
        _toDate(attemptData['startedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    QueryDocumentSnapshot<Map<String, dynamic>>? best;
    var bestDelta = 1 << 62;
    for (final candidate in legacyResults.docs) {
      final data = candidate.data();
      if ((data['examId'] ?? '').toString() != examId ||
          (data['testId'] ?? '').toString() != testId) {
        continue;
      }

      final resultTs =
          _toDate(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final delta =
          (resultTs.millisecondsSinceEpoch - attemptTs.millisecondsSinceEpoch)
              .abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = candidate;
      }
    }

    return best?.data() ?? initialResultData;
  }

  static bool _hasCoreResultFields(Map<String, dynamic> result) {
    return result.containsKey('correct') ||
        result.containsKey('incorrect') ||
        result.containsKey('unanswered') ||
        result.containsKey('score');
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

  static Map<String, String> _readAnswers(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    for (final entry in raw.entries) {
      out[entry.key.toString()] = entry.value?.toString() ?? '';
    }
    return out;
  }

  static List<String> _readQuestionIds(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((item) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        return (map['__id'] ?? map['id'] ?? '').toString();
      }
      return '';
    }).where((id) => id.isNotEmpty).toList();
  }
}
