import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/top_header.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
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
              onExamChanged: (examId) {
                setState(() {
                  selectedExamId = examId;
                });
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: selectedExamId == null
                  ? const Center(child: Text("No exam selected"))
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const TabBar(
                                indicatorColor: Color(0xFF2F6FEB),
                                labelColor: Colors.black,
                                tabs: [
                                  Tab(text: 'Leaderboard'),
                                  Tab(text: 'Dashboard'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildLeaderboard(),
                                _buildDashboard(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // LEADERBOARD (UI UPGRADED + NAME FIX)
  // =========================
  Widget _buildLeaderboard() {
    final currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('results')
          .where('examId', isEqualTo: selectedExamId)
          .orderBy('score', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return const Center(child: Text('No leaderboard data'));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final userId = data['userId'] ?? '';
            final score = data['score'] ?? 0;
            final testsTaken = data['testsTaken'] ?? 0;
            final percentile = data['percentile'] ?? 0;

            final isCurrentUser =
                currentUser != null && currentUser.uid == userId;

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: isCurrentUser
                        ? const LinearGradient(
                            colors: [Color(0xFF2F6FEB), Color(0xFF6EA8FF)],
                          )
                        : null,
                    color: isCurrentUser ? null : Colors.white,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: isCurrentUser
                          ? Colors.white.withOpacity(0.95)
                          : Colors.white,
                    ),
                    child: Row(
                      children: [
                        // 🏅 Rank Badge
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index == 0
                                ? Colors.amber
                                : index == 1
                                ? Colors.grey
                                : index == 2
                                ? Colors.brown
                                : const Color(0xFFEFF3FF),
                          ),
                          child: Center(
                            child: index < 3
                                ? const Icon(
                                    Icons.emoji_events,
                                    color: Colors.white,
                                  )
                                : Text(
                                    '#${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2F6FEB),
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // 👤 User Name + Stats
                        Expanded(
                          child: FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .doc(userId)
                                .get(),
                            builder: (context, userSnap) {
                              String displayName = userId;

                              if (userSnap.hasData && userSnap.data!.exists) {
                                final udata =
                                    userSnap.data!.data()
                                        as Map<String, dynamic>;
                                displayName = udata['name'] ?? userId;
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.bar_chart,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$testsTaken tests • $percentile %ile',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        // 💎 Score
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$score',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'points',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // =========================
  // DASHBOARD (UI MATCHED)
  // =========================
  Widget _buildDashboard() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('results')
          .where('examId', isEqualTo: selectedExamId)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return const Center(child: Text('No analytics data'));
        }

        int total = docs.length;
        double avg = 0;
        int best = 0;

        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final score = (data['score'] ?? 0) as num;
          avg += score.toDouble();
          if (score.toInt() > best) best = score.toInt();
        }

        avg = avg / total;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _buildPremiumCard(
                child: Row(
                  children: [
                    _buildStat("Attempts", "$total"),
                    _buildStat("Avg Score", avg.toStringAsFixed(1)),
                    _buildStat("Best Score", "$best"),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildPremiumCard(
                child: const SizedBox(
                  height: 160,
                  child: Center(child: Text("Performance chart placeholder")),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPremiumCard({required Widget child}) {
    return Material(
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      elevation: 3,
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }

  Widget _buildStat(String title, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
