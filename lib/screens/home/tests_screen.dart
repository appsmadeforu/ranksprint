import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  List<String> userExamIds = [];
  String? selectedExamId;

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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedExamId,
                            icon: const Icon(Icons.keyboard_arrow_down),
                            items: exams.map((exam) {
                              final isPremium = exam['isPremium'] ?? false;
                              final isUnlocked = userExamIds.contains(exam.id) ;

                              return DropdownMenuItem<String>(
                                value: exam.id,
                                enabled: isUnlocked,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      exam['title'],
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
                              if (value != null &&
                                  userExamIds.contains(value)) {
                                setState(() {
                                  selectedExamId = value;
                                });
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
                    .orderBy('order')
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
    final title = test['title'];
    final duration = test['duration'];
    final marks = test['marks'];
    final maxAttempts = test['maxAttempts'];
    final isPremium = test['isPremium'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
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
                onPressed: () {},
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
                  isPremium ? "Unlock" : "Attempt",
                  style: TextStyle(
                    color: isPremium ? Colors.orange : Colors.white,
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
