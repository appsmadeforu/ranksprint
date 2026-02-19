import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TestRunnerScreen extends StatefulWidget {
  final String examId;
  final String testId;

  const TestRunnerScreen({super.key, required this.examId, required this.testId});

  @override
  State<TestRunnerScreen> createState() => _TestRunnerScreenState();
}

class _TestRunnerScreenState extends State<TestRunnerScreen> {
  String? attemptId;
  List<Map<String, dynamic>> questions = [];
  int currentIndex = 0;
  Map<String, String> answers = {}; // questionId -> selected option id
  Set<String> markedForReview = {};
  Set<String> visited = {};

  Timer? _timer;
  int remainingSeconds = 0;

  bool loading = false;

  Future<void> _startAttempt() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => loading = true);

    // create attempt doc
    final ref = FirebaseFirestore.instance.collection('testAttempts').doc();
    final attemptData = {
      'userId': user.uid,
      'examId': widget.examId,
      'testId': widget.testId,
      'attemptNumber': 1,
      'startedAt': Timestamp.now(),
      'status': 'in_progress',
      'answers': {},
    };
    await ref.set(attemptData);

    // load test metadata (for duration) and questions
    final testDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(widget.examId)
        .collection('tests')
        .doc(widget.testId)
        .get();

    int totalMinutes = 60;
    try {
      final tdata = testDoc.data();
      if (tdata != null && tdata['timing'] is Map && (tdata['timing']['totalDurationMinutes'] != null)) {
        totalMinutes = (tdata['timing']['totalDurationMinutes'] as num).toInt();
      }
    } catch (_) {}

    final qSnap = await FirebaseFirestore.instance
        .collection('exams')
        .doc(widget.examId)
        .collection('tests')
        .doc(widget.testId)
        .collection('questions')
        .orderBy('createdAt')
        .get();

    questions = qSnap.docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['__id'] = d.id;
      return m;
    }).toList();

    setState(() {
      attemptId = ref.id;
      remainingSeconds = totalMinutes * 60;
      loading = false;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (remainingSeconds <= 0) {
        t.cancel();
        _submitAttempt();
      } else {
        setState(() => remainingSeconds -= 1);
      }
    });
  }

  Future<void> _saveProgress() async {
    if (attemptId == null) return;
    final attemptRef = FirebaseFirestore.instance.collection('testAttempts').doc(attemptId);
    await attemptRef.update({
      'answers': answers,
      'markedForReview': markedForReview.toList(),
      'visited': visited.toList(),
      'lastSavedAt': Timestamp.now(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Progress saved')));
  }

  Future<void> _submitAttempt() async {
    if (attemptId == null) return;

    _timer?.cancel();

    final attemptRef = FirebaseFirestore.instance.collection('testAttempts').doc(attemptId);
    await attemptRef.update({'status': 'completed', 'submittedAt': Timestamp.now(), 'answers': answers});

    // compute a simple score for placeholder results
    int correct = 0;
    int total = questions.length;
    for (final q in questions) {
      final qid = q['__id'] as String;
      final selected = answers[qid];
      if (selected != null && q['correctOption'] != null && q['correctOption'].toString() == selected) {
        correct += 1;
      }
    }

    final score = correct; // simple 1 point per correct for placeholder

    final resRef = FirebaseFirestore.instance.collection('results').doc(attemptId);
    await resRef.set({
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'examId': widget.examId,
      'testId': widget.testId,
      'score': score,
      'correct': correct,
      'incorrect': total - correct,
      'unanswered': total - answers.length,
      'percentile': 0,
      'rank': 0,
      'createdAt': Timestamp.now(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Test submitted')));
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleReview(String qid) {
    setState(() {
      if (markedForReview.contains(qid)) {
        markedForReview.remove(qid);
      } else {
        markedForReview.add(qid);
      }
    });
  }

  void _selectOption(String qid, String optionId) {
    setState(() {
      answers[qid] = optionId;
      visited.add(qid);
    });
  }

  void _openPalette() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _saveProgress();
                      if (!mounted) return;
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.save_alt, color: Colors.white),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ECC71)),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _submitAttempt();
                    },
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Finish'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF1545A)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Questions Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(questions.length, (i) {
                  final q = questions[i];
                  final qid = q['__id'] as String;
                  final isVisited = visited.contains(qid);
                  final isAnswered = answers.containsKey(qid);
                  final isMarked = markedForReview.contains(qid);

                  Color bg = const Color(0xFFE8EBF3);
                  Color textC = const Color(0xFF2F3E8F);
                  if (isMarked) {
                    bg = const Color(0xFF6C63FF);
                    textC = Colors.white;
                  } else if (isAnswered) {
                    bg = const Color(0xFF2ECC71);
                    textC = Colors.white;
                  } else if (!isVisited) {
                    bg = const Color(0xFFEAEFF6);
                    textC = const Color(0xFF2F3E8F);
                  }

                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() => currentIndex = i);
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                      child: Text('${i + 1}', style: TextStyle(color: textC, fontWeight: FontWeight.bold)),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final hasAttempt = attemptId != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: _openPalette,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.menu, color: Color(0xFF2F6FEB)),
                    ),
                  ),
                  if (hasAttempt)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Text(_formatTime(remainingSeconds), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2F6FEB))),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              if (!hasAttempt)
                Expanded(
                  child: Center(
                    child: loading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: _startAttempt,
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
                            child: const Text('Start Test'),
                          ),
                  ),
                )
              else if (questions.isEmpty)
                const Expanded(child: Center(child: Text('No questions')))
              else
                // Question card and options
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: const Color(0xFFEFF8FF), borderRadius: BorderRadius.circular(20)),
                                    child: const Text('Clear Answer', style: TextStyle(color: Color(0xFF2F6FEB))),
                                  ),
                                  Row(children: [
                                    IconButton(onPressed: () {/* flag/warning */}, icon: const Icon(Icons.report_problem_outlined)),
                                    IconButton(onPressed: () {/* bookmark */}, icon: const Icon(Icons.bookmark_border)),
                                  ])
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text('${currentIndex + 1}. ${questions[currentIndex]['questionText'] ?? ''}', style: const TextStyle(fontSize: 18, height: 1.4)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Options
                      Expanded(
                        child: ListView.separated(
                          itemCount: (questions[currentIndex]['options'] as List?)?.length ?? 0,
                          separatorBuilder: (context, i) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final opts = (questions[currentIndex]['options'] as List).cast<Map<String, dynamic>>();
                            final opt = opts[i];
                            final optId = opt['id']?.toString() ?? String.fromCharCode(65 + i);
                            final optText = opt['text'] ?? '';
                            final qid = questions[currentIndex]['__id'] as String;
                            final selected = answers[qid];

                            final bool isSelected = selected == optId;

                            return Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: const Color(0xFFEAEFF6), child: Text(optId)),
                                title: Text(optText),
                                onTap: () => _selectOption(qid, optId),
                                tileColor: isSelected ? const Color(0xFFEEF6FF) : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      // bottom actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                final qid = questions[currentIndex]['__id'] as String;
                                _toggleReview(qid);
                              },
                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: const BorderSide(color: Color(0xFF2F6FEB))),
                              child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Review Later', style: TextStyle(color: Color(0xFF2F6FEB)))),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () {
                              // next question
                              setState(() {
                                if (currentIndex < questions.length - 1) {
                                  currentIndex += 1;
                                }
                              });
                            },
                            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: const Padding(padding: EdgeInsets.symmetric(vertical: 14, horizontal: 18), child: Icon(Icons.arrow_forward)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
