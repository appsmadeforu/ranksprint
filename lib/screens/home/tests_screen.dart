import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'test_detail_screen.dart';

class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  List<String> userExamIds = [];
  String? selectedExamId;
  bool _examIsPremium = false;
  // cache whether the current user has an active subscription that covers a given exam
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
        selectedExamId = exams.first;
      });
      // load metadata for the initially selected exam
      _loadExamMetadata(exams.first);
      _checkUserHasPlanForExam(exams.first);
    }
  }

  Future<void> _checkUserHasPlanForExam(String examId) async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final subIds = List<String>.from(userDoc.data()?['subscriptionIds'] ?? []);

      bool has = false;
      for (final sid in subIds) {
        final sdoc = await FirebaseFirestore.instance.collection('subscriptions').doc(sid).get();
        if (!sdoc.exists) continue;
        final sdata = sdoc.data() ?? {};
        if ((sdata['status'] ?? '') != 'active') continue;
        final planId = sdata['planId'] as String?;
        if (planId == null) continue;
        final pdoc = await FirebaseFirestore.instance.collection('subscriptionPlans').doc(planId).get();
        if (!pdoc.exists) continue;
        final pdata = pdoc.data() ?? {};
        final included = List<String>.from(pdata['examsIncluded'] ?? []);
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
      final doc = await FirebaseFirestore.instance.collection('exams').doc(examId).get();
      final data = doc.data();
      final isPremium = (data != null && (data['subscriptionPlanIds'] is List) && (data['subscriptionPlanIds'] as List).isNotEmpty);
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
            // ======================
            // TOP HEADER ROW (FIGMA STYLE)
            // ======================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('exams')
                        .where('isActive', isEqualTo: true)
                        .get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox();
                      }

                      final exams = snapshot.data!.docs;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedExamId,
                            icon: const Icon(Icons.keyboard_arrow_down),
                            items: exams.map((exam) {
                              final isUnlocked = userExamIds.contains(exam.id);

                              return DropdownMenuItem<String>(
                                value: exam.id,
                                enabled: isUnlocked,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      exam['name'] ?? exam.id,
                                      style: TextStyle(
                                        color: isUnlocked
                                            ? Colors.black
                                            : Colors.grey,
                                      ),
                                    ),

                                    if (!isUnlocked)
                                      const Icon(
                                        Icons.lock_outline,
                                        size: 18,
                                        color: Colors.grey,
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null && userExamIds.contains(value)) {
                                setState(() {
                                  selectedExamId = value;
                                });
                                _loadExamMetadata(value);
                                _checkUserHasPlanForExam(value);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),

                  // Bell Icon
                  Stack(
                    children: [
                      const Icon(Icons.notifications_none, size: 28),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ======================
            // TEST LIST
            // ======================
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
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
                    padding: const EdgeInsets.all(16),
                    itemCount: tests.length,
                    itemBuilder: (context, index) {
                      return _buildTestCard(tests[index]);
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

  Widget _buildTestCard(QueryDocumentSnapshot test) {
  final title = test['name'] ?? test.id;

  final Map<String, dynamic>? testData = test.data() as Map<String, dynamic>?;
  final durationVal = (testData != null && testData.containsKey('timing') && testData['timing'] is Map && (testData['timing'] as Map).containsKey('totalDurationMinutes'))
    ? testData['timing']['totalDurationMinutes']
    : (testData != null ? testData['totalDurationMinutes'] : null);
  final duration = durationVal?.toString() ?? '0';

  final marks = test['totalMarks'] ?? test['marks'] ?? 0;
  final maxAttempts = test['attemptLimit'] ?? test['maxAttempts'] ?? 0;
  // derive premium from parent exam metadata; fallback to any explicit test field if present
  final Map<String, dynamic>? tdata = test.data() as Map<String, dynamic>?;
  final isPremium = (tdata != null && tdata.containsKey('isPremium')) ? (tdata['isPremium'] ?? false) : _examIsPremium;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(
            "$duration min • $marks marks",
            style: const TextStyle(color: Colors.grey),
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Attempts: 0/$maxAttempts"),

              ElevatedButton(
                onPressed: () async {
                  final hasPlan = _userHasPlanForExam[selectedExamId] ?? false;
                  final isLocked = isPremium && !hasPlan;

                  if (isLocked) {
                    // show upgrade dialog
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Premium Test'),
                        content: const Text('This test is available for subscribers only. Manage your subscription to unlock.'),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: const Text('Close'),
                          ),
                          TextButton(
                            onPressed: () async {
                              // copy manage URL to clipboard as a simple action
                              final scaffold = ScaffoldMessenger.of(context);
                              Navigator.pop(context);
                              final user = FirebaseAuth.instance.currentUser;
                              String manageUrl = 'https://ranksprint.ai/manage-subscription';
                              if (user != null) {
                                final udoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                                final subs = List<String>.from(udoc.data()?['subscriptionIds'] ?? []);
                                if (subs.isNotEmpty) {
                                  manageUrl = 'https://ranksprint.ai/manage-subscription?sub=${subs.first}';
                                }
                              }
                              Clipboard.setData(ClipboardData(text: manageUrl));
                              scaffold.showSnackBar(const SnackBar(content: Text('Manage subscription URL copied to clipboard')));
                            },
                            child: const Text('Manage Subscription'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  // navigate to test detail screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TestDetailScreen(examId: selectedExamId!, testId: test.id),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPremium
                      ? Colors.white
                      : const Color(0xFF2F3E8F),
                  side: isPremium
                      ? const BorderSide(color: Colors.orange)
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  (isPremium && !(_userHasPlanForExam[selectedExamId] ?? false)) ? 'Unlock' : 'Attempt',
                  style: TextStyle(
                    color: (isPremium && !(_userHasPlanForExam[selectedExamId] ?? false)) ? Colors.orange : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
