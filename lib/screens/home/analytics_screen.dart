import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  Future<List<String>> _getUserExams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    if (data == null) return [];
    return List<String>.from(data['selectedExams'] ?? []);
  }

  @override
  Widget build(BuildContext context) {
    // We'll present a small Leaderboard / Dashboard UI using results collection
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: FutureBuilder<List<String>>(
          future: _getUserExams(),
          builder: (context, examSnap) {
            if (!examSnap.hasData) return const Center(child: CircularProgressIndicator());

            final exams = examSnap.data!;
            final selectedExam = exams.isNotEmpty ? exams.first : null;

            return Column(
              children: [
                // Top header (exam selector + bell) — simplified: show selected exam
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [Text(selectedExam != null ? selectedExam.toUpperCase() : 'SELECT', style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(width: 8), const Icon(Icons.keyboard_arrow_down, size: 20)]),
                      ),
                      const Spacer(),
                      Stack(
                        children: [
                          const Icon(Icons.notifications_none, size: 28),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Tabs
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                            child: TabBar(
                              indicator: BoxDecoration(color: const Color(0xFFF1F5FF), borderRadius: BorderRadius.circular(12)),
                              labelColor: Colors.black,
                              tabs: const [Tab(text: 'Leaderboard'), Tab(text: 'Dashboard')],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TabBarView(
                            children: [
                              // Leaderboard tab
                              Builder(builder: (context) {
                                if (selectedExam == null) return const Center(child: Text('No exam selected'));

                                final currentUser = FirebaseAuth.instance.currentUser;

                                return StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('results')
                                      .where('examId', isEqualTo: selectedExam)
                                      .orderBy('score', descending: true)
                                      .limit(50)
                                      .snapshots(),
                                  builder: (context, snap) {
                                    if (snap.hasError) {
                                      return Center(child: Text('Failed to load leaderboard: ${snap.error}'));
                                    }

                                    if (snap.connectionState == ConnectionState.waiting) {
                                      return const Center(child: CircularProgressIndicator());
                                    }

                                    if (!snap.hasData) return const Center(child: Text('No leaderboard data'));

                                    final docs = snap.data!.docs;
                                    if (docs.isEmpty) return const Center(child: Text('No leaderboard data'));

                                    return ListView.builder(
                                      padding: const EdgeInsets.all(16),
                                      itemCount: docs.length,
                                      itemBuilder: (context, index) {
                                        final doc = docs[index];
                                        final data = doc.data() as Map<String, dynamic>;
                                        final userId = (data['userId'] ?? '').toString();
                                        final score = data['score'] ?? 0;
                                        final testsTaken = data['testsTaken'] ?? 0;
                                        final percentile = data['percentile'] ?? 0;

                                        final isCurrentUser = currentUser != null && currentUser.uid == userId;

                                        // medal colors for top 3
                                        Color? medalColor;
                                        if (index == 0) medalColor = const Color(0xFFFFD700); // gold
                                        if (index == 1) medalColor = const Color(0xFFC0C0C0); // silver
                                        if (index == 2) medalColor = const Color(0xFFCD7F32); // bronze

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(12),
                                            border: isCurrentUser ? Border.all(color: const Color(0xFF2F6FEB), width: 2) : Border.all(color: Colors.transparent),
                                          ),
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            leading: CircleAvatar(
                                              backgroundColor: medalColor ?? const Color(0xFFF1F5FF),
                                              child: Text('#${index + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                            ),
                                            title: FutureBuilder<DocumentSnapshot>(
                                              future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
                                              builder: (context, userSnap) {
                                                final uname = userSnap.hasData && userSnap.data!.exists ? ((userSnap.data!.data() as Map<String, dynamic>)['name'] ?? userId) : userId;
                                                return Text(uname.toString(), style: const TextStyle(fontWeight: FontWeight.w600));
                                              },
                                            ),
                                            subtitle: Text('$testsTaken tests • $percentile %ile', style: const TextStyle(color: Colors.grey)),
                                            trailing: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text('$score', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                const SizedBox(height: 4),
                                                const Text('points', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              }),

                              // Dashboard tab: compute some simple aggregates from results
                              Builder(builder: (context) {
                                if (selectedExam == null) return const Center(child: Text('No exam selected'));
                                return FutureBuilder<QuerySnapshot>(
                                  future: FirebaseFirestore.instance.collection('results').where('examId', isEqualTo: selectedExam).get(),
                                  builder: (context, snap) {
                                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                                    final docs = snap.data!.docs;
                                    if (docs.isEmpty) return const Center(child: Text('No analytics data'));

                                    int total = docs.length;
                                    double avg = 0;
                                    int best = 0;
                                    for (final d in docs) {
                                      final mRaw = (d.data() as Map<String, dynamic>)['score'] ?? 0;
                                      final m = (mRaw is num) ? mRaw.toDouble() : double.tryParse(mRaw.toString()) ?? 0.0;
                                      avg += m;
                                      if (m.toInt() > best) best = m.toInt();
                                    }
                                    avg = avg / total;

                                    return Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Card(
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                const Text('Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                const SizedBox(height: 12),
                                                Row(children: [
                                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Attempts'), const SizedBox(height: 6), Text('$total', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))])),
                                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Avg Score'), const SizedBox(height: 6), Text(avg.toStringAsFixed(1), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))])),
                                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Best Score'), const SizedBox(height: 6), Text('$best', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))])),
                                                ]),
                                              ]),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          // small chart placeholder
                                          Card(
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            child: Container(height: 160, alignment: Alignment.center, child: const Text('Performance chart placeholder')),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
