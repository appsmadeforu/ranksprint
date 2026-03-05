import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
                  ? const Center(child: Text('No exam selected'))
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

  Widget _buildLeaderboard() {
    final currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('results')
          .where('examId', isEqualTo: selectedExamId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs.cast<QueryDocumentSnapshot>();
        if (docs.isEmpty) {
          return const Center(child: Text('No leaderboard data'));
        }

        final entries = _aggregateLeaderboard(docs);
        if (entries.isEmpty) {
          return const Center(child: Text('No leaderboard data'));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final e = entries[index];
            final isCurrentUser = currentUser != null && currentUser.uid == e.userId;

            return Container(
              margin: const EdgeInsets.only(bottom: 18),
              child: Material(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white,
                elevation: 3,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: isCurrentUser
                        ? Border.all(color: const Color(0xFF2F6FEB), width: 2)
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF3FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                              '#${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2F6FEB),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .doc(e.userId)
                                .get(),
                            builder: (context, userSnap) {
                              String displayName = e.userId;
                              if (userSnap.hasData && userSnap.data!.exists) {
                                final udata = userSnap.data!.data() as Map<String, dynamic>;
                                displayName = (udata['name'] ?? e.userId).toString();
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${e.testsTaken} tests - ${e.avgPercentile.toStringAsFixed(1)} %ile',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              e.avgScore.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'avg score',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
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

  Widget _buildDashboard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('User not logged in'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('results')
          .where('examId', isEqualTo: selectedExamId)
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No analytics data'));
        }

        final records = docs
            .map((d) => d.data() as Map<String, dynamic>)
            .toList()
          ..sort((a, b) {
            final aTs = (a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bTs = (b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return aTs.compareTo(bTs);
          });

        final total = records.length;
        double avg = 0;
        int best = 0;
        final recentScores = <double>[];

        for (final data in records) {
          final score = (data['score'] as num?)?.toDouble() ?? 0;
          avg += score;
          if (score.toInt() > best) best = score.toInt();
          recentScores.add(score);
        }

        avg = avg / (total == 0 ? 1 : total);
        final chartScores = recentScores.length > 8
            ? recentScores.sublist(recentScores.length - 8)
            : recentScores;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _buildPremiumCard(
                child: Row(
                  children: [
                    _buildStat('Attempts', '$total'),
                    _buildStat('Avg Score', avg.toStringAsFixed(1)),
                    _buildStat('Best Score', '$best'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildPremiumCard(
                child: SizedBox(
                  height: 160,
                  child: _buildScoreTrend(chartScores),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScoreTrend(List<double> scores) {
    if (scores.isEmpty) {
      return const Center(child: Text('No trend data'));
    }

    final maxVal = scores.reduce((a, b) => a > b ? a : b);
    final safeMax = maxVal <= 0 ? 1.0 : maxVal;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(scores.length, (i) {
        final s = scores[i];
        final h = (s / safeMax) * 120;
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(s.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
            const SizedBox(height: 4),
            Container(
              width: 18,
              height: h < 4 ? 4 : h,
              decoration: BoxDecoration(
                color: const Color(0xFF2F6FEB),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        );
      }),
    );
  }

  List<_LeaderboardAgg> _aggregateLeaderboard(List<QueryDocumentSnapshot> docs) {
    final byUser = <String, _LeaderboardAgg>{};

    for (final d in docs) {
      final data = d.data() as Map<String, dynamic>;
      final uid = (data['userId'] ?? '').toString();
      if (uid.isEmpty) continue;

      final score = (data['score'] as num?)?.toDouble() ?? 0.0;
      final percentile = (data['percentile'] as num?)?.toDouble() ?? 0.0;

      final agg = byUser.putIfAbsent(uid, () => _LeaderboardAgg(userId: uid));
      agg.testsTaken += 1;
      agg.totalScore += score;
      agg.totalPercentile += percentile;
      if (score > agg.bestScore) agg.bestScore = score;
    }

    final out = byUser.values.toList();
    for (final e in out) {
      final count = e.testsTaken == 0 ? 1 : e.testsTaken;
      e.avgScore = e.totalScore / count;
      e.avgPercentile = e.totalPercentile / count;
    }

    out.sort((a, b) {
      final byAvg = b.avgScore.compareTo(a.avgScore);
      if (byAvg != 0) return byAvg;
      final byBest = b.bestScore.compareTo(a.bestScore);
      if (byBest != 0) return byBest;
      return b.testsTaken.compareTo(a.testsTaken);
    });

    return out;
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

class _LeaderboardAgg {
  final String userId;
  int testsTaken = 0;
  double totalScore = 0;
  double totalPercentile = 0;
  double bestScore = 0;
  double avgScore = 0;
  double avgPercentile = 0;

  _LeaderboardAgg({required this.userId});
}
