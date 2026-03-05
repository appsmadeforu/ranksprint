import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/top_header.dart';
import 'test_detail_screen.dart';
import 'subscription_screen.dart';

class TestsScreen extends StatefulWidget {
  final String? selectedExam;

  const TestsScreen({super.key, this.selectedExam});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  List<String> userExamIds = [];
  String? selectedExamId;
  bool _examIsPremium = false;

  final Map<String, bool> _userHasPlanForExam = {};

  @override
  void initState() {
    super.initState();
    _loadUserExams();
  }

  Future<void> _loadUserExams() async {
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final exams = List<String>.from(doc['selectedExams'] ?? []);

    if (exams.isNotEmpty) {
      setState(() {
        userExamIds = exams;

        if (widget.selectedExam != null &&
            exams.contains(widget.selectedExam)) {
          selectedExamId = widget.selectedExam;
        } else {
          selectedExamId = exams.first;
        }
      });

      _loadExamMetadata(selectedExamId!);
      _checkUserHasPlanForExam(selectedExamId!);
    }
  }

  Future<void> _checkUserHasPlanForExam(String examId) async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final subIds = List<String>.from(
        userDoc.data()?['subscriptionIds'] ?? [],
      );

      bool has = false;

      for (final sid in subIds) {
        final sdoc = await FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(sid)
            .get();

        if (!sdoc.exists) continue;

        final sdata = sdoc.data() ?? {};
        if ((sdata['status'] ?? '') != 'active') continue;

        final planId = sdata['planId'] as String?;
        if (planId == null) continue;

        final pdoc = await FirebaseFirestore.instance
            .collection('subscriptionPlans')
            .doc(planId)
            .get();

        if (!pdoc.exists) continue;

        final included = List<String>.from(pdoc.data()?['examsIncluded'] ?? []);

        if (included.contains(examId)) {
          has = true;
          break;
        }
      }

      setState(() {
        _userHasPlanForExam[examId] = has;
      });
    } catch (_) {
      setState(() {
        _userHasPlanForExam[examId] = false;
      });
    }
  }

  Future<void> _loadExamMetadata(String examId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('exams')
          .doc(examId)
          .get();

      final data = doc.data();

      final isPremium =
          (data != null &&
          (data['subscriptionPlanIds'] is List) &&
          (data['subscriptionPlanIds'] as List).isNotEmpty);

      setState(() {
        _examIsPremium = isPremium;
      });
    } catch (_) {
      setState(() {
        _examIsPremium = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (selectedExamId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            // =======================
            // TOP HEADER
            // =======================
            TopHeader(
              selectedExamId: selectedExamId,
              userExamIds: userExamIds,
              onExamChanged: (value) {
                setState(() {
                  selectedExamId = value;
                });
                _loadExamMetadata(value);
                _checkUserHasPlanForExam(value);
              },
            ),

            const SizedBox(height: 12),

            // =======================
            // TITLE SECTION
            // =======================
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Mock Tests",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "Practice full-length and sectional tests",
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // =======================
            // TEST LIST
            // =======================
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('testAttempts')
                    .where(
                      'userId',
                      isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                    )
                    .where('examId', isEqualTo: selectedExamId)
                    .snapshots(),
                builder: (context, attemptsSnap) {
                  final Map<String, int> attemptsByTestId = {};
                  if (attemptsSnap.hasData) {
                    for (final d in attemptsSnap.data!.docs) {
                      final data = d.data() as Map<String, dynamic>;
                      final testId = (data['testId'] ?? '').toString();
                      if (testId.isEmpty) continue;
                      // Count only submitted attempts so in-progress starts do not inflate limits.
                      final isCompleted =
                          (data['status'] ?? '').toString() == 'completed';
                      if (!isCompleted) continue;
                      attemptsByTestId[testId] =
                          (attemptsByTestId[testId] ?? 0) + 1;
                    }
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('exams')
                        .doc(selectedExamId)
                        .collection('tests')
                        .orderBy('createdAt')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final tests = snapshot.data!.docs;

                      if (tests.isEmpty) {
                        return const Center(child: Text("No tests available"));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: tests.length,
                        itemBuilder: (context, index) {
                          final testDoc = tests[index];
                          final usedAttempts = attemptsByTestId[testDoc.id] ?? 0;
                          return _buildTestCard(testDoc, usedAttempts);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestCard(QueryDocumentSnapshot test, int usedAttempts) {
    final title = test['name'] ?? test.id;

    final Map<String, dynamic>? testData = test.data() as Map<String, dynamic>?;

    final durationVal =
        (testData != null &&
            testData.containsKey('timing') &&
            testData['timing'] is Map &&
            (testData['timing'] as Map).containsKey('totalDurationMinutes'))
        ? testData['timing']['totalDurationMinutes']
        : (testData != null ? testData['totalDurationMinutes'] : null);

    final duration = durationVal?.toString() ?? '0';
    final marks = test['totalMarks'] ?? test['marks'] ?? 0;
    final maxAttempts = test['attemptLimit'] ?? test['maxAttempts'] ?? 0;
    final maxAttemptsInt = int.tryParse(maxAttempts.toString()) ?? 0;
    final limitReached = maxAttemptsInt > 0 && usedAttempts >= maxAttemptsInt;
    final attemptsText = maxAttemptsInt > 0
        ? "Attempts: $usedAttempts/$maxAttemptsInt"
        : "Attempts: $usedAttempts";

    final Map<String, dynamic>? tdata = test.data() as Map<String, dynamic>?;

    final isPremium = (tdata != null && tdata.containsKey('isPremium'))
        ? (tdata['isPremium'] ?? false)
        : _examIsPremium;

    final hasPlan = _userHasPlanForExam[selectedExamId] ?? false;

    final isLocked = isPremium && !hasPlan;
    final isDisabled = isLocked || limitReached;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      child: Material(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          splashColor: const Color(0xFF2F6FEB).withOpacity(0.1),
          onTap: () {
            if (isLocked) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              );
              return;
            }
            if (limitReached) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TestDetailScreen(examId: selectedExamId!, testId: test.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isLocked
                        ? Colors.grey.shade200
                        : const Color(0xFFEFF3FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isLocked ? Icons.lock_outline : Icons.assignment,
                    color: isLocked ? Colors.grey : const Color(0xFF2F6FEB),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "$duration min • $marks marks",
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        attemptsText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: isDisabled
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TestDetailScreen(
                                examId: selectedExamId!,
                                testId: test.id,
                              ),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLocked
                        ? Colors.white
                        : const Color(0xFF2F3E8F),
                    side: isLocked
                        ? const BorderSide(color: Colors.orange)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: isLocked ? 0 : 2,
                  ),
                  child: Text(
                    isLocked
                        ? "Unlock"
                        : (limitReached ? "Limit Reached" : "Attempt"),
                    style: TextStyle(
                      color: isLocked
                          ? Colors.orange
                          : (limitReached ? Colors.grey : Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
