import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'test_runner_screen.dart';

class TestDetailScreen extends StatelessWidget {
  final String examId;
  final String testId;

  const TestDetailScreen({
    super.key,
    required this.examId,
    required this.testId,
  });

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadTest() {
    return FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .collection('tests')
        .doc(testId)
        .get();
  }

  Future<int> _loadCompletedAttemptCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final snap = await FirebaseFirestore.instance
        .collection('testAttempts')
        .where('userId', isEqualTo: user.uid)
        .where('examId', isEqualTo: examId)
        .where('testId', isEqualTo: testId)
        .get();
    return snap.docs.length;
  }

  Widget _infoTile(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future:
              Future.wait<dynamic>([
                _loadTest(),
                _loadCompletedAttemptCount(),
              ]).then((values) {
                final testDoc =
                    values[0] as DocumentSnapshot<Map<String, dynamic>>;
                final completedAttempts = values[1] as int;
                return {
                  'test': testDoc.data() ?? <String, dynamic>{},
                  'completedAttempts': completedAttempts,
                };
              }),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final payload = snapshot.data!;
            final data = payload['test'] as Map<String, dynamic>;
            final completedAttempts = payload['completedAttempts'] as int;

            final title = data['name'] ?? testId;
            final duration =
                (data['timing'] is Map &&
                    data['timing']['totalDurationMinutes'] != null)
                ? data['timing']['totalDurationMinutes'].toString()
                : (data['totalDurationMinutes']?.toString() ?? '0');
            final totalMarks = (data['totalMarks'] ?? 0).toString();
            final questions = (data['totalQuestions'] ?? 0).toString();
            final marksPer =
                (data['marksPerQuestion'] ?? data['marksPerQuestion'] ?? 0)
                    .toString();
            final negative = (data['negativeMarks'] ?? 0).toString();

            final instructions = (data['instructions'] is List)
                ? List<String>.from(data['instructions'])
                : <String>[
                    'Each question carries $marksPer marks',
                    'Follow test rules as provided',
                  ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back + title row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),

                // Blue info box
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3A53B7), Color(0xFF1F3A8A)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _infoTile('Duration', '$duration min'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _infoTile('Total Marks', totalMarks),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _infoTile('Questions', questions)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _infoTile(
                                'Marking',
                                '+$marksPer/-$negative',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // Instructions
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Instructions',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(instructions.length, (i) {
                          final it = instructions[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 10,
                                  backgroundColor: colorScheme.primaryContainer,
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    it,
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 18),

                        // Legend
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.flag_outlined,
                                      size: 18,
                                      color: colorScheme.primary,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Question Status Legend',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: const [
                                    _LegendChip(
                                      color: Colors.green,
                                      label: 'Answered',
                                    ),
                                    _LegendChip(
                                      color: Colors.red,
                                      label: 'Not Answered',
                                    ),
                                    _LegendChip(
                                      color: Colors.purple,
                                      label: 'Marked for Review',
                                    ),
                                    _LegendChip(
                                      color: Colors.grey,
                                      label: 'Not Visited',
                                    ),
                                    _LegendChip(
                                      color: Colors.blue,
                                      label: 'Answered & Marked',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Important
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colorScheme.tertiary),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: colorScheme.tertiary,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Important: Make sure you have a stable internet connection during the test.',
                                  style: TextStyle(
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                // Start Test button
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TestRunnerScreen(
                              examId: examId,
                              testId: testId,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                          completedAttempts > 0 ? 'Reattempt' : 'Start Test',
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontSize: 15,
                          ),
                        ),
                      ),
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
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
