import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'pyq_chapters_screen.dart';

class PyqScreen extends StatefulWidget {
  const PyqScreen({super.key});

  @override
  State<PyqScreen> createState() => _PyqScreenState();
}

class _PyqScreenState extends State<PyqScreen> {
  String? selectedExamId;
  // whether current user has plan that includes a given exam
  final Map<String, bool> _userHasPlanForExam = {};

  /// Fetch user's selected exams
  Future<List<String>> _getUserExams() async {
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data();
    if (data == null) return [];

    return List<String>.from(data['selectedExams'] ?? []);
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

  /// Fetch PYQ subjects for a particular exam (seeder stores pyqs under exams/{examId}/pyqs)
  Stream<QuerySnapshot> _getPyqExamsFor(String examId) {
    return FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .collection('pyqs')
        .snapshots();
  }

  // Note: exam names are fetched directly in the dropdown to match TestsScreen style

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<String>>(
        future: _getUserExams(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userExamIds = userSnapshot.data!;

          if (userExamIds.isEmpty) {
            return const Center(
              child: Text(
                "Please select exams first",
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          // default to first selected exam if not yet chosen
          selectedExamId ??= userExamIds.first;
          // ensure we check plan for the selected exam
          _checkUserHasPlanForExam(selectedExamId!);

          return StreamBuilder<QuerySnapshot>(
            stream: _getPyqExamsFor(selectedExamId!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;

              if (docs.isEmpty) {
                return const Center(child: Text("No PYQs available for this exam"));
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Top header: exam selector + notifications (match ProfileScreen)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('exams')
                                .where('isActive', isEqualTo: true)
                                .get(),
                            builder: (context, examSnap) {
                              if (!examSnap.hasData) return const SizedBox();

                              final exams = examSnap.data!.docs;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedExamId,
                                    icon: const Icon(Icons.keyboard_arrow_down),
                                    items: exams.map((exam) {
                                      final isUnlocked = userExamIds.contains(exam.id) || (_userHasPlanForExam[exam.id] ?? false);

                                      return DropdownMenuItem<String>(
                                        value: exam.id,
                                        enabled: isUnlocked,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              exam['name'] ?? exam.id,
                                              style: TextStyle(color: isUnlocked ? Colors.black : Colors.grey),
                                            ),
                                            if (!isUnlocked)
                                              const Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        final isUnlocked = userExamIds.contains(value) || (_userHasPlanForExam[value] ?? false);
                                        if (isUnlocked) {
                                          setState(() {
                                            selectedExamId = value;
                                          });
                                          _checkUserHasPlanForExam(value);
                                        }
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          ),

                          // Bell Icon (notification dot)
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

                    const SizedBox(height: 20),

                    const Text(
                      "Previous Year Questions",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 8),

                    const Text("Access exam papers organized by subject and chapter", style: TextStyle(color: Colors.grey)),

                    const SizedBox(height: 16),

                    // Subjects list as rounded cards
                    Expanded(
                      child: ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final title = doc['name'] ?? doc.id;
                          final isExamUnlocked = userExamIds.contains(selectedExamId) || (_userHasPlanForExam[selectedExamId] ?? false);
                          final chapterCount = doc.reference.collection('chapters').get().then((snap) => snap.size).catchError((_) => 0);

                          return FutureBuilder<int>(
                            future: chapterCount,
                            builder: (context, ctSnap) {
                              final count = ctSnap.hasData ? ctSnap.data! : 0;

                              return Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  leading: Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(color: const Color(0xFFEFF3FF), borderRadius: BorderRadius.circular(12)),
                                    child: const Icon(Icons.menu_book, color: Color(0xFF2F3E8F)),
                                  ),
                                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(count > 0 ? '$count papers available' : 'Tap to view chapters', style: const TextStyle(color: Colors.grey)),
                                  trailing: isExamUnlocked
                                      ? const Icon(Icons.chevron_right)
                                      : Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: const [
                                            Icon(Icons.lock_outline, color: Colors.grey),
                                            SizedBox(height: 4),
                                            Text('Unlock', style: TextStyle(color: Color(0xFFF37A1C), fontSize: 12)),
                                          ],
                                        ),
                                  onTap: isExamUnlocked
                                      ? () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => PyqChaptersScreen(examId: selectedExamId!, subjectId: doc.id, subjectName: title),
                                            ),
                                          );
                                        }
                                      : () {
                                          // Prompt to manage subscription
                                          showDialog(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('Locked Content'),
                                              content: const Text('This subject is available to subscribers. Manage subscription to unlock.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                                                TextButton(
                                                  onPressed: () {
                                                    Clipboard.setData(ClipboardData(text: 'https://ranksprint.ai/manage-subscription'));
                                                    Navigator.pop(context);
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manage subscription URL copied to clipboard')));
                                                  },
                                                  child: const Text('Manage Subscription', style: TextStyle(color: Color(0xFFF37A1C))),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
