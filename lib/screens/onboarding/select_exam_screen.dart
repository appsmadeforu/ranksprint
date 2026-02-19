import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SelectExamScreen extends StatefulWidget {
  const SelectExamScreen({super.key});

  @override
  State<SelectExamScreen> createState() => _SelectExamScreenState();
}

class _SelectExamScreenState extends State<SelectExamScreen> {
  List<String> selectedExamIds = [];
  bool loading = false;

  Future<List<QueryDocumentSnapshot>> _fetchExams() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('exams')
        .where('isActive', isEqualTo: true)
        .get();

    return snapshot.docs;
  }

  void _toggleExam(String examId) {
    setState(() {
      if (selectedExamIds.contains(examId)) {
        selectedExamIds.remove(examId);
      } else {
        selectedExamIds.add(examId);
      }
    });
  }

  Future<void> _saveExams() async {
    if (selectedExamIds.isEmpty) return;

    setState(() => loading = true);

    final user = FirebaseAuth.instance.currentUser!;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      "phone": user.phoneNumber,
      "selectedExams": selectedExamIds,
      // align with seeded user structure
      "subscriptionIds": [],
      "subscriptionStatus": "free",
      "createdAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<QueryDocumentSnapshot>>(
        future: _fetchExams(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final exams = snapshot.data!;

          if (exams.isEmpty) {
            return const Center(child: Text("No exams available"));
          }

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 40),

                const Text(
                  "Select Your Exams",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 20),

                Expanded(
                  child: ListView.builder(
                    itemCount: exams.length,
                    itemBuilder: (context, index) {
                      final exam = exams[index];
                      final examId = exam.id;
                      final title = exam['name'] ?? exam.id;
                      final desc = exam['description'] ?? '';

                      final isSelected = selectedExamIds.contains(examId);

                      return GestureDetector(
                        onTap: () => _toggleExam(examId),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF1F3A8A)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      desc,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: isSelected
                                    ? const Color(0xFF1F3A8A)
                                    : Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: loading ? null : _saveExams,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F3A8A),
                    ),
                    child: loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            "Continue (${selectedExamIds.length} selected)",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
