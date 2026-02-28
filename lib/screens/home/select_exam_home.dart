import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../onboarding/select_exam_screen.dart';

class SelectExamHome extends StatelessWidget {
  const SelectExamHome({super.key});

  Future<void> _removeExam(String examId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({
      'selectedExams': FieldValue.arrayRemove([examId])
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("User not logged in")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data =
                snapshot.data!.data() as Map<String, dynamic>?;

            final List selectedExams =
                List.from(data?['selectedExams'] ?? []);

            if (selectedExams.isEmpty) {
              return const Center(
                child: Text("No exams selected"),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 30),

                  const Text(
                    "Your Selected Exams",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Expanded(
                    child: ListView.builder(
                      itemCount: selectedExams.length,
                      itemBuilder: (context, index) {
                        final examId = selectedExams[index];

                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('exams')
                              .doc(examId)
                              .get(),
                          builder: (context, examSnapshot) {
                            if (!examSnapshot.hasData) {
                              return const SizedBox();
                            }

                            final examData =
                                examSnapshot.data!.data()
                                    as Map<String, dynamic>?;

                            final title =
                                examData?['name'] ?? examId;
                            final desc =
                                examData?['description'] ?? '';

                            return Container(
                              margin:
                                  const EdgeInsets.only(bottom: 18),
                              child: Material(
                                borderRadius:
                                    BorderRadius.circular(18),
                                color: Colors.white,
                                elevation: 3,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.all(20),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration:
                                            BoxDecoration(
                                          color: const Color(
                                              0xFFEFF3FF),
                                          borderRadius:
                                              BorderRadius
                                                  .circular(14),
                                        ),
                                        child: const Icon(
                                          Icons.school,
                                          color:
                                              Color(0xFF2F6FEB),
                                        ),
                                      ),
                                      const SizedBox(width: 16),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [
                                            Text(
                                              title,
                                              style:
                                                  const TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(
                                                height: 6),
                                            Text(
                                              desc,
                                              style:
                                                  const TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // ❌ Remove Button
                                      IconButton(
                                        onPressed: () {
                                          _removeExam(examId);
                                        },
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),

      // ➕ Add Exam Floating Button
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2F3E8F),
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SelectExamScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}