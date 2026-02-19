import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TestRunnerScreen extends StatefulWidget {
  final String examId;
  final String testId;

  const TestRunnerScreen({
    super.key,
    required this.examId,
    required this.testId,
  });

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
    if (user == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be signed in to start a test'),
          ),
        );
      return;
    }

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

    // load test metadata (for duration)
    final testDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(widget.examId)
        .collection('tests')
        .doc(widget.testId)
        .get();

    int totalMinutes = 60;
    try {
      final tdata = testDoc.data();
      if (tdata != null &&
          tdata['timing'] is Map &&
          (tdata['timing']['totalDurationMinutes'] != null)) {
        totalMinutes = (tdata['timing']['totalDurationMinutes'] as num).toInt();
      }
    } catch (_) {}

    // fetch questions - try with orderBy first, fallback without orderBy if that fails
    List<QueryDocumentSnapshot<Map<String, dynamic>>> qdocs = [];
    try {
      final qSnap = await FirebaseFirestore.instance
          .collection('exams')
          .doc(widget.examId)
          .collection('tests')
          .doc(widget.testId)
          .collection('questions')
          .orderBy('createdAt')
          .get();
      qdocs = qSnap.docs;
    } catch (e) {
      // orderBy('createdAt') may fail if field missing or for security rules - retry without order
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not order questions: ${e.toString()} — retrying without order',
            ),
          ),
        );
      try {
        final qSnap = await FirebaseFirestore.instance
            .collection('exams')
            .doc(widget.examId)
            .collection('tests')
            .doc(widget.testId)
            .collection('questions')
            .get();
        qdocs = qSnap.docs;
      } catch (e2) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load questions: ${e2.toString()}'),
            ),
          );
        qdocs = [];
      }
    }

    // map to internal structure
    questions = qdocs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['__id'] = d.id;
      return m;
    }).toList();

    // debug logs to help runtime investigation
    // ignore: avoid_print
    print(
      'TestRunner: started attempt for exam=${widget.examId} test=${widget.testId} user=${user.uid} — questions found=${questions.length} ids=${qdocs.map((d) => d.id).toList()}',
    );

    setState(() {
      attemptId = ref.id;
      remainingSeconds = totalMinutes * 60;
      loading = false;
      currentIndex = 0;
      answers = {};
      markedForReview = {};
      visited = {};
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
    final attemptRef = FirebaseFirestore.instance
        .collection('testAttempts')
        .doc(attemptId);
    await attemptRef.update({
      'answers': answers,
      'markedForReview': markedForReview.toList(),
      'visited': visited.toList(),
      'lastSavedAt': Timestamp.now(),
    });
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Progress saved')));
  }

  Future<void> _submitAttempt() async {
    if (attemptId == null) return;

    _timer?.cancel();

    final attemptRef = FirebaseFirestore.instance
        .collection('testAttempts')
        .doc(attemptId);
    await attemptRef.update({
      'status': 'completed',
      'submittedAt': Timestamp.now(),
      'answers': answers,
    });

    // compute a simple score for placeholder results
    int correct = 0;
    int total = questions.length;
    for (final q in questions) {
      final qid = q['__id'] as String;
      final selected = answers[qid];
      if (selected != null &&
          q['correctOption'] != null &&
          q['correctOption'].toString() == selected) {
        correct += 1;
      }
    }

    final score = correct; // simple 1 point per correct for placeholder

    final resRef = FirebaseFirestore.instance
        .collection('results')
        .doc(attemptId);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Test submitted')));
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        int notVisited = 0;
        int answered = 0;
        int notAnswered = 0;
        int marked = 0;
        int answeredAndMarked = 0;

        for (final q in questions) {
          final qid = q['__id'] as String;

          final isVisited = visited.contains(qid);
          final isAnswered = answers.containsKey(qid);
          final isMarked = markedForReview.contains(qid);

          if (!isVisited) {
            notVisited++;
          } else if (!isAnswered) {
            notAnswered++;
          }

          if (isAnswered) answered++;
          if (isMarked && !isAnswered) marked++;
          if (isMarked && isAnswered) answeredAndMarked++;
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  "${widget.examId.toUpperCase()} - ${widget.testId}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                // Save + Finish
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _saveProgress();
                        if (!mounted) return;
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text("Save"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _submitAttempt();
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text("Finish"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                const Text(
                  "Questions Overview",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                // Overview Counters
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    _buildCounter(notVisited, "Not Visited", Colors.grey),
                    _buildCounter(notAnswered, "Not Answered", Colors.red),
                    _buildCounter(answered, "Answered", Colors.green),
                    _buildCounter(
                      marked,
                      "Marked for Review",
                      Colors.deepPurple,
                    ),
                    _buildCounter(
                      answeredAndMarked,
                      "Answered & Marked",
                      Colors.blue,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                const Text(
                  "Questions",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                // Grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: questions.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (_, i) {
                    final q = questions[i];
                    final qid = q['__id'] as String;

                    final isVisited = visited.contains(qid);
                    final isAnswered = answers.containsKey(qid);
                    final isMarked = markedForReview.contains(qid);

                    Color bg = const Color(0xFFEAEFF6);
                    Color textColor = Colors.black;

                    if (isMarked && isAnswered) {
                      bg = Colors.blue;
                      textColor = Colors.white;
                    } else if (isMarked) {
                      bg = Colors.deepPurple;
                      textColor = Colors.white;
                    } else if (isAnswered) {
                      bg = Colors.green;
                      textColor = Colors.white;
                    } else if (!isVisited) {
                      bg = Colors.grey.shade300;
                    } else {
                      bg = Colors.red;
                      textColor = Colors.white;
                    }

                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          currentIndex = i;
                        });
                      },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "${i + 1}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),
              ],
            ),
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

  Widget _buildCounter(int count, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
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
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.menu, color: Color(0xFF2F6FEB)),
                    ),
                  ),
                  if (hasAttempt)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formatTime(remainingSeconds),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2F6FEB),
                        ),
                      ),
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
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 14,
                              ),
                            ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF8FF),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Clear Answer',
                                      style: TextStyle(
                                        color: Color(0xFF2F6FEB),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () {
                                          /* flag/warning */
                                        },
                                        icon: const Icon(
                                          Icons.report_problem_outlined,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          /* bookmark */
                                        },
                                        icon: const Icon(Icons.bookmark_border),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${currentIndex + 1}. ${questions[currentIndex]['questionText'] ?? ''}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Options
                      Expanded(
                        child: ListView.separated(
                          itemCount:
                              (questions[currentIndex]['options'] as List?)
                                  ?.length ??
                              0,
                          separatorBuilder: (context, i) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final opts =
                                (questions[currentIndex]['options'] as List)
                                    .cast<Map<String, dynamic>>();
                            final opt = opts[i];
                            final optId =
                                opt['id']?.toString() ??
                                String.fromCharCode(65 + i);
                            final optText = opt['text'] ?? '';
                            final qid =
                                questions[currentIndex]['__id'] as String;
                            final selected = answers[qid];

                            final bool isSelected = selected == optId;

                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFEAEFF6),
                                  child: Text(optId),
                                ),
                                title: Text(optText),
                                onTap: () => _selectOption(qid, optId),
                                tileColor: isSelected
                                    ? const Color(0xFFEEF6FF)
                                    : null,
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
                                final qid =
                                    questions[currentIndex]['__id'] as String;
                                _toggleReview(qid);
                              },
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: const BorderSide(
                                  color: Color(0xFF2F6FEB),
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'Review Later',
                                  style: TextStyle(color: Color(0xFF2F6FEB)),
                                ),
                              ),
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
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 18,
                              ),
                              child: Icon(Icons.arrow_forward),
                            ),
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
