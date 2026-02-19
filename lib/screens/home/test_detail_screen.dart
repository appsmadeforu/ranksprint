import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'test_runner_screen.dart';

class TestDetailScreen extends StatelessWidget {
  final String examId;
  final String testId;

  const TestDetailScreen({super.key, required this.examId, required this.testId});

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadTest() {
    return FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .collection('tests')
        .doc(testId)
        .get();
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
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: _loadTest(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final data = snapshot.data!.data() ?? {};

            final title = data['name'] ?? testId;
            final duration = (data['timing'] is Map && data['timing']['totalDurationMinutes'] != null)
                ? data['timing']['totalDurationMinutes'].toString()
                : (data['totalDurationMinutes']?.toString() ?? '0');
            final totalMarks = (data['totalMarks'] ?? 0).toString();
            final questions = (data['totalQuestions'] ?? 0).toString();
            final marksPer = (data['marksPerQuestion'] ?? data['marksPerQuestion'] ?? 0).toString();
            final negative = (data['negativeMarks'] ?? 0).toString();

            final instructions = (data['instructions'] is List) ? List<String>.from(data['instructions']) : <String>[
              'Each question carries $marksPer marks',
              'Follow test rules as provided',
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back + title row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
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
                      gradient: const LinearGradient(colors: [Color(0xFF3A53B7), Color(0xFF1F3A8A)]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _infoTile('Duration', '$duration min')),
                            const SizedBox(width: 12),
                            Expanded(child: _infoTile('Total Marks', totalMarks)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _infoTile('Questions', questions)),
                            const SizedBox(width: 12),
                            Expanded(child: _infoTile('Marking', '+$marksPer/-$negative')),
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
                        const Text('Instructions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        ...List.generate(instructions.length, (i) {
                          final it = instructions[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(radius: 10, backgroundColor: const Color(0xFFEFF3FF), child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF2F3E8F), fontSize: 12))),
                                const SizedBox(width: 10),
                                Expanded(child: Text(it, style: const TextStyle(color: Colors.black87))),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 18),

                        // Legend
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Question Status Legend', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: const [
                                    _LegendChip(color: Colors.green, label: 'Answered'),
                                    _LegendChip(color: Colors.red, label: 'Not Answered'),
                                    _LegendChip(color: Colors.purple, label: 'Marked for Review'),
                                    _LegendChip(color: Colors.grey, label: 'Not Visited'),
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
                          decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFE6C6))),
                          child: Row(
                            children: const [
                              Icon(Icons.info_outline, color: Color(0xFFB76B00)),
                              SizedBox(width: 8),
                              Expanded(child: Text('Important: Make sure you have a stable internet connection during the test.')),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TestRunnerScreen(examId: examId, testId: testId),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2F3E8F),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Start Test', style: TextStyle(color: Colors.white, fontSize: 16)),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
