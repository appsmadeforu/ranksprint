import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/top_header.dart';

class TestHistoryScreen extends StatefulWidget {
  const TestHistoryScreen({super.key});

  @override
  State<TestHistoryScreen> createState() => _TestHistoryScreenState();
}

class _TestHistoryScreenState extends State<TestHistoryScreen> {
  String? selectedExamId;
  List<String> userExamIds = [];

  @override
  void initState() {
    super.initState();
    _loadUserExams();
  }

  Future<void> _loadUserExams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final exams = List<String>.from(doc['selectedExams'] ?? []);
    setState(() {
      userExamIds = exams;
      if (exams.isNotEmpty) {
        selectedExamId = exams.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('User not logged in')));
    }

    return Scaffold(
      appBar: null,
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: selectedExamId,
              userExamIds: userExamIds,
              onExamChanged: (id) {
                setState(() {
                  selectedExamId = id;
                });
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('testAttempts')
                    .where('userId', isEqualTo: userId)
                    .orderBy('startedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('No test history found.'));
                  }

                  final attempts = snapshot.data!.docs;
                  // Calculate summary stats
                  final totalTests = attempts.length;
                  final avgScore =
                      attempts
                          .map((doc) => _getScore(doc))
                          .fold<double>(0, (a, b) => a + b) /
                      (totalTests > 0 ? totalTests : 1);
                  final bestScore = attempts
                      .map((doc) => _getScore(doc))
                      .fold<double>(0, (a, b) => a > b ? a : b);
                  final totalTime = attempts
                      .map((doc) => _getTime(doc))
                      .fold<int>(0, (a, b) => a + b);

                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        // Summary Card
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2F3E8F),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _summaryItem('Tests', '$totalTests'),
                              _summaryItem(
                                'Avg Score',
                                '${avgScore.toStringAsFixed(0)}%',
                              ),
                              _summaryItem(
                                'Best Score',
                                '${bestScore.toStringAsFixed(0)}%',
                              ),
                              _summaryItem(
                                'Time',
                                '${(totalTime / 60).toStringAsFixed(0)}h',
                              ),
                            ],
                          ),
                        ),
                        // Search bar (UI only, not functional here)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search tests...',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Test Attempts List
                        ...attempts
                            .map((doc) => _testAttemptCard(doc))
                            .toList(),
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

  Widget _summaryItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _testAttemptCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final score = _getScore(doc);
    final correct = (data['answers'] as Map?)?.length ?? 0;
    final wrong = (data['wrong'] as int?) ?? 0;
    final skipped = (data['skipped'] as int?) ?? 0;
    final rank = (data['rank'] as int?) ?? 0;
    final examId = data['examId'] ?? '';
    final testType = data['status'] == 'completed'
        ? 'Mock Test'
        : 'Practice Test';
    final startedAt = (data['startedAt'] is Timestamp)
        ? (data['startedAt'] as Timestamp).toDate()
        : null;
    final timeTaken = _getTime(doc);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${examId.toString()} ${testType}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(startedAt != null ? '${_formatDate(startedAt)}' : ''),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: score >= 80 ? Colors.green[100] : Colors.orange[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${score.toStringAsFixed(0)}/20\n${(score * 5).toStringAsFixed(0)}% Score',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('#$rank', 'Rank'),
                _statItem('$correct', 'Correct'),
                _statItem('$wrong', 'Wrong'),
                _statItem('$skipped', 'Skipped'),
              ],
            ),
            const SizedBox(height: 8),
            Text('Time: $timeTaken min'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  // TODO: Implement View Solutions navigation
                },
                child: const Text('View Solutions →'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  static double _getScore(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // Example: correct answers / total questions * 100
    final correct = (data['answers'] as Map?)?.length ?? 0;
    final total = 20; // Adjust if you store total questions
    return (correct / total) * 100;
  }

  static int _getTime(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // Example: time in minutes, adjust if you store differently
    return (data['timeTaken'] as int?) ?? 90;
  }
}
