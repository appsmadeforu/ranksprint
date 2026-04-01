import 'package:cloud_firestore/cloud_firestore.dart';

import 'result_schema_contract.dart';

class LeaderboardBackfillService {
  LeaderboardBackfillService._();

  static Future<void> syncExamLeaderboardSummary({
    required String examId,
  }) async {
    if (examId.trim().isEmpty) return;

    final resultsSnap = await FirebaseFirestore.instance
        .collection(ResultSchemaContract.resultCollection)
        .where('examId', isEqualTo: examId)
        .get();

    final byUser = <String, _ExamLeaderboardAgg>{};
    for (final doc in resultsSnap.docs) {
      final data = doc.data();
      final userId = (data['userId'] ?? '').toString().trim();
      if (userId.isEmpty) continue;
      final agg = byUser.putIfAbsent(
        userId,
        () => _ExamLeaderboardAgg(userId: userId),
      );
      final score = _toDouble(data['score']);
      final percentile = _toDouble(data['percentile']);
      agg.testsTaken++;
      agg.totalScore += score;
      agg.totalPercentile += percentile;
      if (score > agg.bestScore) {
        agg.bestScore = score;
      }
      if (percentile > agg.bestPercentile) {
        agg.bestPercentile = percentile;
      }
      final updatedAt = _timeMillis(
        data['leaderboardUpdatedAt'] ?? data['createdAt'],
      );
      if (updatedAt > agg.lastUpdatedAtMillis) {
        agg.lastUpdatedAtMillis = updatedAt;
      }
    }

    if (byUser.isEmpty) return;

    final rows = byUser.values.toList()
      ..sort((a, b) {
        final avgScoreDiff = b.avgScore.compareTo(a.avgScore);
        if (avgScoreDiff != 0) return avgScoreDiff;
        final avgPercentileDiff = b.avgPercentile.compareTo(a.avgPercentile);
        if (avgPercentileDiff != 0) return avgPercentileDiff;
        final bestScoreDiff = b.bestScore.compareTo(a.bestScore);
        if (bestScoreDiff != 0) return bestScoreDiff;
        return a.userId.compareTo(b.userId);
      });

    final userNames = await _loadUserNames(rows.map((row) => row.userId));
    var rank = 0;
    var lastAvgScore = double.nan;
    var lastAvgPercentile = double.nan;
    var batch = FirebaseFirestore.instance.batch();
    var opCount = 0;
    final leaderboardRef = FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .collection('leaderboard');

    for (int index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (index == 0 ||
          row.avgScore != lastAvgScore ||
          row.avgPercentile != lastAvgPercentile) {
        rank = index + 1;
        lastAvgScore = row.avgScore;
        lastAvgPercentile = row.avgPercentile;
      }

      batch.set(leaderboardRef.doc(row.userId), {
        'userId': row.userId,
        'displayName': userNames[row.userId] ?? row.userId,
        'testsTaken': row.testsTaken,
        'avgScore': row.avgScore,
        'avgPercentile': row.avgPercentile,
        'bestScore': row.bestScore,
        'bestPercentile': row.bestPercentile,
        'rank': rank,
        'updatedAt': Timestamp.now(),
        'lastResultAt': row.lastUpdatedAtMillis > 0
            ? Timestamp.fromMillisecondsSinceEpoch(row.lastUpdatedAtMillis)
            : Timestamp.now(),
      });
      opCount++;

      if (opCount >= 450) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) {
      await batch.commit();
    }
  }

  static Future<Map<String, String>> _loadUserNames(Iterable<String> userIds) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    final names = <String, String>{};
    if (ids.isEmpty) return names;

    for (int i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, (i + 10).clamp(0, ids.length));
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final rawName = (data['name'] ?? data['displayName'] ?? doc.id)
            .toString()
            .trim();
        names[doc.id] = rawName.isEmpty ? doc.id : rawName;
      }
      for (final id in chunk) {
        names.putIfAbsent(id, () => id);
      }
    }
    return names;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _timeMillis(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    return 0;
  }
}

class _ExamLeaderboardAgg {
  final String userId;
  int testsTaken = 0;
  double totalScore = 0;
  double totalPercentile = 0;
  double bestScore = 0;
  double bestPercentile = 0;
  int lastUpdatedAtMillis = 0;

  _ExamLeaderboardAgg({required this.userId});

  double get avgScore => testsTaken == 0 ? 0 : totalScore / testsTaken;
  double get avgPercentile =>
      testsTaken == 0 ? 0 : totalPercentile / testsTaken;
}
