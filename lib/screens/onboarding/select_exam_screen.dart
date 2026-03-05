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
  bool initialized = false;

  Future<void> _loadUserSelectedExams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (doc.exists) {
      final data = doc.data();
      if (data != null && data['selectedExams'] is List) {
        selectedExamIds = List<String>.from(data['selectedExams']);
      }
    }

    setState(() {
      initialized = true;
    });
  }

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
    final userDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    await userDoc.set({
      "selectedExams": selectedExamIds,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() => loading = false);

    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    _loadUserSelectedExams();
  }

  @override
  Widget build(BuildContext context) {
    if (!initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: FutureBuilder<List<QueryDocumentSnapshot>>(
        future: _fetchExams(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final exams = snapshot.data!;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 30),

                  const Text(
                    "Select Your Exams",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 24),

                  Expanded(
                    child: ListView.builder(
                      itemCount: exams.length,
                      itemBuilder: (context, index) {
                        final exam = exams[index];
                        final examId = exam.id;
                        final title = exam['name'] ?? exam.id;
                        final desc = exam['description'] ?? '';

                        final isSelected = selectedExamIds.contains(examId);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 18),
                          child: Material(
                            borderRadius: BorderRadius.circular(18),
                            color: Colors.white,
                            elevation: 3,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _toggleExam(examId),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFFEFF3FF)
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        isSelected
                                            ? Icons.check
                                            : Icons.school_outlined,
                                        color: isSelected
                                            ? const Color(0xFF2F6FEB)
                                            : Colors.grey,
                                      ),
                                    ),

                                    const SizedBox(width: 16),

                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                            desc,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: loading ? null : _saveExams,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2F3E8F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
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

                  const SizedBox(height: 30),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
