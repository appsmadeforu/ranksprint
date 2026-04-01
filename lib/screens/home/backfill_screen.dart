import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/exam_analytics_backfill_service.dart';
import '../../services/leaderboard_backfill_service.dart';
import '../../services/startup_prefetch_service.dart';

class BackfillScreen extends StatefulWidget {
  final String? selectedExamId;
  final List<String> userExamIds;

  const BackfillScreen({
    super.key,
    required this.selectedExamId,
    required this.userExamIds,
  });

  @override
  State<BackfillScreen> createState() => _BackfillScreenState();
}

class _BackfillScreenState extends State<BackfillScreen> {
  bool _isRunning = false;
  final List<String> _logs = <String>[];

  void _appendLog(String message) {
    setState(() {
      _logs.insert(0, message);
    });
  }

  Future<void> _runTask(
    String label,
    Future<void> Function() action,
  ) async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
    });
    _appendLog('$label started');
    try {
      await action();
      _appendLog('$label completed');
    } catch (error) {
      _appendLog('$label failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _backfillMyAnalyticsForExams(List<String> examIds) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _appendLog('No signed-in user found for analytics backfill.');
      return;
    }
    for (final examId in examIds.where((id) => id.trim().isNotEmpty)) {
      _appendLog('Refreshing analytics summary for $examId');
      await StartupPrefetchService.prefetchDashboardData(
        userId: user.uid,
        examId: examId,
        forceRefresh: true,
      );
    }
  }

  Future<void> _backfillAllUsersAnalyticsForExams(List<String> examIds) async {
    for (final examId in examIds.where((id) => id.trim().isNotEmpty)) {
      _appendLog('Rebuilding analytics summaries for all users in $examId');
      await ExamAnalyticsBackfillService.backfillExamAnalyticsForExam(
        examId: examId,
      );
    }
  }

  Future<void> _backfillLeaderboardForExams(List<String> examIds) async {
    for (final examId in examIds.where((id) => id.trim().isNotEmpty)) {
      _appendLog('Rebuilding leaderboard summary for $examId');
      await LeaderboardBackfillService.syncExamLeaderboardSummary(
        examId: examId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedExamId = widget.selectedExamId;
    final allExamIds = widget.userExamIds.where((id) => id.trim().isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Backfill Tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD9E1F2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Temporary one-off backfill screen.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current exam: ${selectedExamId ?? 'None'}\nSelected exams: ${allExamIds.isEmpty ? 'None' : allExamIds.join(', ')}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'This backfills your own analytics summaries and rebuilds leaderboard summaries for all users in each selected exam from existing result docs.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isRunning || selectedExamId == null
                ? null
                : () => _runTask(
                      'Selected exam analytics backfill',
                      () => _backfillMyAnalyticsForExams([selectedExamId]),
                    ),
            child: const Text('Backfill My Analytics For Current Exam'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isRunning || selectedExamId == null
                ? null
                : () => _runTask(
                      'All users current exam analytics backfill',
                      () => _backfillAllUsersAnalyticsForExams([selectedExamId]),
                    ),
            child: const Text('Backfill Analytics For All Users In Current Exam'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isRunning || allExamIds.isEmpty
                ? null
                : () => _runTask(
                      'All selected exams analytics backfill',
                      () => _backfillMyAnalyticsForExams(allExamIds),
                    ),
            child: const Text('Backfill My Analytics For All My Exams'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isRunning || allExamIds.isEmpty
                ? null
                : () => _runTask(
                      'All users all exams analytics backfill',
                      () => _backfillAllUsersAnalyticsForExams(allExamIds),
                    ),
            child: const Text('Backfill Analytics For All Users In All My Exams'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isRunning || selectedExamId == null
                ? null
                : () => _runTask(
                      'Selected exam leaderboard backfill',
                      () => _backfillLeaderboardForExams([selectedExamId]),
                    ),
            child: const Text('Backfill Leaderboard For All Users In Current Exam'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isRunning || allExamIds.isEmpty
                ? null
                : () => _runTask(
                      'All selected exams leaderboard backfill',
                      () => _backfillLeaderboardForExams(allExamIds),
                    ),
            child: const Text('Backfill Leaderboard For All Users In All My Exams'),
          ),
          const SizedBox(height: 20),
          if (_isRunning) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          const Text(
            'Run Log',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: _logs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No backfill runs yet.'),
                  )
                : Column(
                    children: _logs
                        .map(
                          (log) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.history, size: 18),
                            title: Text(log),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
