import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../widgets/top_header.dart';
import 'pyq_chapters_screen.dart';
import 'tests_screen.dart';
import 'analytics_screen.dart';
import 'profile_screen.dart';

class PyqScreen extends StatefulWidget {
  const PyqScreen({super.key});

  @override
  State<PyqScreen> createState() => _PyqScreenState();
}

class _PyqScreenState extends State<PyqScreen> {
  String? selectedExamId;
  List<String> userExamIds = [];

  @override
  void initState() {
    super.initState();
    _loadUserExams();
  }

  Future<void> _loadUserExams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final exams = List<String>.from(doc.data()?['selectedExams'] ?? []);

    setState(() {
      userExamIds = exams;
      selectedExamId = exams.isNotEmpty ? exams.first : null;
    });
  }

  Stream<QuerySnapshot> _getPyqs(String examId) {
    return FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .collection('pyqs')
        .snapshots();
  }

  void _showSubscriptionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Unlock Full Access",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Subscribe to access all PYQs, premium tests and analytics.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2F6FEB),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text("View Subscription Plans"),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Maybe Later"),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: selectedExamId,
              userExamIds: userExamIds,
              onExamChanged: (id) {
                setState(() => selectedExamId = id);
              },
            ),
            const SizedBox(height: 8),

            Expanded(
              child: selectedExamId == null
                  ? const Center(child: Text("No exam selected"))
                  : StreamBuilder<QuerySnapshot>(
                      stream: _getPyqs(selectedExamId!),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = snapshot.data!.docs;

                        if (docs.isEmpty) {
                          return const Center(child: Text("No PYQs available"));
                        }

                        final isUnlocked = userExamIds.contains(selectedExamId);

                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              const Text(
                                "Previous Year Questions",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Access exam papers organized by subject and chapter",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 20),

                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: docs.length,
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final title = doc['name'] ?? doc.id;

                                  return FutureBuilder<QuerySnapshot>(
                                    future: doc.reference
                                        .collection('chapters')
                                        .get(),
                                    builder: (context, chapterSnap) {
                                      final paperCount = chapterSnap.hasData
                                          ? chapterSnap.data!.size
                                          : 0;

                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: Stack(
                                          children: [
                                            Material(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              color: Colors.white,
                                              elevation: 3,
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                                splashColor: const Color(
                                                  0xFF2F6FEB,
                                                ).withOpacity(0.1),
                                                onTap: isUnlocked
                                                    ? () {
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                PyqChaptersScreen(
                                                                  examId:
                                                                      selectedExamId!,
                                                                  subjectId:
                                                                      doc.id,
                                                                  subjectName:
                                                                      title,
                                                                ),
                                                          ),
                                                        );
                                                      }
                                                    : _showSubscriptionSheet,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    18,
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 52,
                                                        height: 52,
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFEFF3FF,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                14,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.menu_book,
                                                          color: Color(
                                                            0xFF2F6FEB,
                                                          ),
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
                                                              style: const TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            Text(
                                                              "$paperCount papers available",
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        13,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const Icon(
                                                        Icons.chevron_right,
                                                        color: Colors.grey,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),

                                            if (!isUnlocked)
                                              Positioned.fill(
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  child: BackdropFilter(
                                                    filter: ImageFilter.blur(
                                                      sigmaX: 4,
                                                      sigmaY: 4,
                                                    ),
                                                    child: Container(
                                                      color: Colors.white
                                                          .withOpacity(0.6),
                                                      alignment:
                                                          Alignment.center,
                                                      child: const Text(
                                                        "Unlock with Subscription →",
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFFF37A1C,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const TestsScreen()),
            );
          }
          if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
            );
          }
          if (index == 3) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'Tests'),
          BottomNavigationBarItem(icon: Icon(Icons.description), label: 'PYQs'),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
