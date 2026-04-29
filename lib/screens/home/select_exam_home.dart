import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/content_access_service.dart';
import '../../services/subscription_access_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/offline_state.dart';
import '../../widgets/top_header.dart';
import '../onboarding/select_exam_screen.dart';
import 'main_navigation.dart';
import 'pyq_screen.dart';
import 'subject_insights_screen.dart';
import 'subscription_screen.dart';
import 'test_detail_screen.dart';
import 'test_history_screen.dart';
import 'tests_screen.dart';

class SelectExamHome extends StatefulWidget {
  const SelectExamHome({super.key});

  @override
  State<SelectExamHome> createState() => _SelectExamHomeState();
}

class _SelectExamHomeState extends State<SelectExamHome> {
  static const List<String> _fallbackQuotes = [
    'Success is the sum of small efforts, repeated day in and day out.',
    'Small progress each day adds up to big results.',
    'Focus on consistency. The rank will follow.',
    'Discipline turns ambition into a daily habit.',
  ];
  Future<_HomeVm>? _homeVmFuture;
  String _homeVmSignature = '';
  int _reloadTick = 0;

  void _retryHomeLoad() {
    if (!mounted) return;
    setState(() {
      _homeVmFuture = null;
      _homeVmSignature = '';
      _reloadTick++;
    });
  }
  Future<void> _removeExam(String examId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'selectedExams': FieldValue.arrayRemove([examId]),
    });
  }

  Future<void> _confirmRemoveExam(_ExamCardVm exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Remove Exam'),
          content: Text('Do you want to remove ${exam.title}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _removeExam(exam.examId);
    }
  }

  Future<void> _editGoal({
    required String userId,
    required _GoalVm? goal,
    required _ExamCardVm? activeExam,
  }) async {
    final activeExamId = activeExam?.examId.trim() ?? '';
    if (activeExamId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an exam before setting a goal.')),
      );
      return;
    }
    final parentContext = context;
    final messenger = ScaffoldMessenger.of(parentContext);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _EditGoalDialog(
        userId: userId,
        activeExamId: activeExamId,
        activeExam: activeExam,
        goal: goal,
        messenger: messenger,
        parentContext: parentContext,
        formatGoalDate: _formatGoalDate,
      ),
    );

    if (saved == true && mounted) {
      setState(() {});
    }
  }

  Future<List<_ExamCardVm>> _loadSelectedExams(
    List<String> selectedExamIds,
  ) async {
    if (selectedExamIds.isEmpty) return const <_ExamCardVm>[];
    final examDocs = await Future.wait(
      selectedExamIds.map(
        (examId) =>
            FirebaseFirestore.instance.collection('exams').doc(examId).get(),
      ),
    );
    return examDocs
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          return _ExamCardVm(
            examId: doc.id,
            title: (data['name'] ?? doc.id).toString(),
            description: (data['description'] ?? 'No description available.')
                .toString(),
          );
        })
        .toList(growable: false);
  }

  Future<_HomeStatsVm> _loadHomeStats({
    required String userId,
    required String? activeExamId,
  }) async {
    if (activeExamId != null && activeExamId.isNotEmpty) {
      try {
        final summaryDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('examHomeSummary')
            .doc(activeExamId)
            .get();
        final summary = summaryDoc.data();
        if (summary != null) {
          final testsAttended = _asInt(
            summary['testsAttended'] ?? summary['completedAttempts'],
          );
          final bestRank = _asInt(summary['bestRank']);
          final bestScore = _asDouble(summary['bestScorePercent']);
          if (testsAttended != null || bestRank != null || bestScore != null) {
            return _HomeStatsVm(
              testsAttended: testsAttended ?? 0,
              bestRank: bestRank,
              bestScoreText: bestScore == null
                  ? '--'
                  : '${bestScore.round()}/100',
            );
          }
        }
      } catch (_) {
        // Fall back to direct queries when no summary document is available.
      }
    }

    final baseFetches = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
      FirebaseFirestore.instance
          .collection('testAttempts')
          .where('userId', isEqualTo: userId)
          .get(),
      FirebaseFirestore.instance
          .collection('results')
          .where('userId', isEqualTo: userId)
          .get(),
    ]);
    final attemptsSnap = baseFetches[0];
    final resultsSnap = baseFetches[1];
    final completedAttempts = attemptsSnap.docs.where((doc) {
      final data = doc.data();
      if ((data['status'] ?? '').toString() != 'completed') {
        return false;
      }
      if (activeExamId == null || activeExamId.isEmpty) {
        return true;
      }
      return (data['examId'] ?? '').toString() == activeExamId;
    }).length;

    int? bestRank;
    double? bestScorePct;
    for (final doc in resultsSnap.docs) {
      final data = doc.data();
      if (activeExamId != null &&
          activeExamId.isNotEmpty &&
          (data['examId'] ?? '').toString() != activeExamId) {
        continue;
      }
      final rank = _asInt(data['rank']);
      if (rank != null && (bestRank == null || rank < bestRank)) {
        bestRank = rank;
      }

      final scorePct = _scorePercent(data);
      if (scorePct != null &&
          (bestScorePct == null || scorePct > bestScorePct)) {
        bestScorePct = scorePct;
      }
    }

    return _HomeStatsVm(
      testsAttended: completedAttempts,
      bestRank: bestRank,
      bestScoreText: bestScorePct == null
          ? '--'
          : '${bestScorePct.round()}/100',
    );
  }

  Future<_FeaturedContentVm> _loadFeaturedContent(String activeExamId) async {
    final featuredConfigDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(activeExamId)
        .collection('home_config')
        .doc('featured')
        .get();
    final featuredConfig =
        featuredConfigDoc.data() ?? const <String, dynamic>{};
    final featuredMockTestIds = List<String>.from(
      featuredConfig['featuredMockTestIds'] ?? const [],
    );
    final featuredPyqIds = List<String>.from(
      featuredConfig['featuredPyqIds'] ?? const [],
    );

    final featuredFetches =
        await Future.wait<List<QueryDocumentSnapshot<Map<String, dynamic>>>>([
          _loadFeaturedCollectionDocs(
            parentPath: 'exams/$activeExamId/tests',
            docIds: featuredMockTestIds,
          ),
          _loadFeaturedCollectionDocs(
            parentPath: 'exams/$activeExamId/pyqs',
            docIds: featuredPyqIds,
          ),
        ]);

    final featuredMockTests = featuredFetches[0]
        .where((doc) => ContentAccessService.isVisibleNow(doc.data()))
        .map((test) {
          final data = test.data();
          return _FeaturedCardVm(
            title: (data['name'] ?? test.id).toString(),
            badge: _isNewItem(data) ? 'NEW' : 'TEST',
            meta: _testMetaLabel(data),
            icon: Icons.quiz_outlined,
            iconTint: const Color(0xFF31459B),
            badgeColor: _isNewItem(data)
                ? const Color(0xFFE6F9EA)
                : const Color(0xFFE9ECFF),
            badgeTextColor: _isNewItem(data)
                ? const Color(0xFF168A3D)
                : const Color(0xFF31459B),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      TestDetailScreen(examId: activeExamId, testId: test.id),
                ),
              );
            },
          );
        })
        .toList(growable: false);

    final featuredPyqs = featuredFetches[1]
        .where((doc) => ContentAccessService.isVisibleNow(doc.data()))
        .map((pyq) {
          final data = pyq.data();
          return _FeaturedCardVm(
            title: (data['name'] ?? pyq.id).toString(),
            badge: 'PYQ',
            meta: '${_pyqPaperCountLabel(data)} papers',
            icon: Icons.description_outlined,
            iconTint: const Color(0xFF31459B),
            badgeColor: const Color(0xFFE9ECFF),
            badgeTextColor: const Color(0xFF31459B),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const PyqScreen()));
            },
          );
        })
        .toList(growable: false);

    return _FeaturedContentVm(
      featuredMockTests: featuredMockTests,
      featuredPyqs: featuredPyqs,
    );
  }

  Future<bool> _hasAvailablePlansForExam(String? examId) async {
    final normalizedExamId = (examId ?? '').trim();
    if (normalizedExamId.isEmpty) return false;

    try {
      final examDoc = await FirebaseFirestore.instance
          .collection('exams')
          .doc(normalizedExamId)
          .get();
      final examData = examDoc.data() ?? const <String, dynamic>{};
      final examPlanIds = List<String>.from(
        examData['subscriptionPlanIds'] ?? const <String>[],
      ).where((id) => id.trim().isNotEmpty).toSet();

      final plansSnap = await FirebaseFirestore.instance
          .collection('subscriptionPlans')
          .get();

      for (final doc in plansSnap.docs) {
        final data = doc.data();
        final features = Map<String, dynamic>.from(
          data['features'] ?? const <String, dynamic>{},
        );
        final hasFeatureFlag = features['isActive'] is bool;
        final hasTopLevelFlag = data['isActive'] is bool;
        final isActive = hasFeatureFlag
            ? features['isActive'] == true
            : hasTopLevelFlag
                ? data['isActive'] == true
                : true;
        if (!isActive) {
          continue;
        }
        if (examPlanIds.contains(doc.id)) {
          return true;
        }
        if (SubscriptionAccessService.planIncludesExam(
          data['examsIncluded'],
          normalizedExamId,
        )) {
          return true;
        }
      }
    } catch (_) {
      // Keep the home screen resilient if plan metadata cannot be loaded.
    }

    return false;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadFeaturedCollectionDocs({
    required String parentPath,
    required List<String> docIds,
  }) async {
    if (docIds.isEmpty)
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    final chunks = <List<String>>[];
    for (int i = 0; i < docIds.length; i += 10) {
      final end = math.min(i + 10, docIds.length);
      chunks.add(docIds.sublist(i, end));
    }

    final snapshots = await Future.wait(
      chunks.map(
        (chunk) => FirebaseFirestore.instance
            .collection(parentPath)
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      ),
    );

    final docMap = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        docMap[doc.id] = doc;
      }
    }

    return docIds
        .map((id) => docMap[id])
        .whereType<QueryDocumentSnapshot<Map<String, dynamic>>>()
        .toList(growable: false);
  }

  Future<_HomeVm> _loadVm({
    required String userId,
    required Map<String, dynamic> userData,
  }) async {
    final selectedExamIds = List<String>.from(
      userData['selectedExams'] ?? const <String>[],
    );
    final preferredExamId = await UserExamPreferenceService.loadPreferredExamId(
      availableExamIds: selectedExamIds,
    );
    final activeExamId =
        preferredExamId != null && selectedExamIds.contains(preferredExamId)
        ? preferredExamId
        : (selectedExamIds.isNotEmpty ? selectedExamIds.first : null);

    final selectedExams = await _loadSelectedExams(selectedExamIds);
    final activeExam = selectedExams.firstWhere(
      (exam) => exam.examId == activeExamId,
      orElse: () => selectedExams.isNotEmpty
          ? selectedExams.first
          : const _ExamCardVm(
              examId: '',
              title: 'No exam selected',
              description: 'Choose an exam to personalize your dashboard.',
            ),
    );
    final stats = await _loadHomeStats(
      userId: userId,
      activeExamId: activeExamId,
    );
    final featured = activeExamId == null || activeExamId.isEmpty
        ? const _FeaturedContentVm.empty()
        : await _loadFeaturedContent(activeExamId);
    final hasAvailablePlans = await _hasAvailablePlansForExam(activeExamId);

    final greetingName = _firstName(
      (userData['name'] ?? FirebaseAuth.instance.currentUser?.displayName ?? '')
          .toString(),
    );
    final goalData = _goalDataForExam(userData, activeExam.examId);
    final currentGoal = _GoalVm.fromMap(
      goalData,
      fallbackExam: activeExam.examId.isEmpty ? null : activeExam,
    );

    final dailyQuote = await _loadDailyQuote();

    return _HomeVm(
      greetingName: greetingName.isEmpty ? 'Learner' : greetingName,
      quote: dailyQuote,
      activeExam: activeExam.examId.isEmpty ? null : activeExam,
      selectedExams: selectedExams,
      testsAttended: stats.testsAttended,
      bestRank: stats.bestRank,
      bestScoreText: stats.bestScoreText,
      currentGoal: currentGoal,
      hasAvailablePlans: hasAvailablePlans,
      featuredMockTests: featured.featuredMockTests,
      featuredPyqs: featured.featuredPyqs,
    );
  }

  void _ensureHomeVm({
    required String userId,
    required Map<String, dynamic> userData,
    bool force = false,
  }) {
    final selectedExams = List<String>.from(
      userData['selectedExams'] ?? const [],
    );
    final preferredExamId =
        UserExamPreferenceService.preferredExamNotifier.value;
    final activeExamId =
        preferredExamId != null && selectedExams.contains(preferredExamId)
        ? preferredExamId
        : (selectedExams.isNotEmpty ? selectedExams.first : '');
    final currentGoal = _goalDataForExam(userData, activeExamId);
    final signature =
        '${(userData['name'] ?? '').toString()}|'
        '$activeExamId|'
        '${selectedExams.join(',')}|'
        '${(currentGoal?['title'] ?? '').toString()}|'
        '${(currentGoal?['description'] ?? '').toString()}|'
        '${currentGoal?['targetDate'] ?? ''}|'
        '${currentGoal?['updatedAt'] ?? ''}';
    if (!force && _homeVmFuture != null && _homeVmSignature == signature) {
      return;
    }
    _homeVmSignature = signature;
    _homeVmFuture = _loadVm(userId: userId, userData: userData);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('User not logged in')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey('select-exam-home-${user.uid}-$_reloadTick'),
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return OfflineState(
                message:
                    'Could not load your home screen. Please check your connection and try again.',
                onRetry: _retryHomeLoad,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final userData = snapshot.data!.data() ?? const <String, dynamic>{};
            _ensureHomeVm(userId: user.uid, userData: userData);
            return FutureBuilder<_HomeVm>(
              future: _homeVmFuture,
              builder: (context, vmSnap) {
                if (vmSnap.hasError) {
                  return OfflineState(
                    message:
                        'Could not load your home screen. Please check your connection and try again.',
                    onRetry: _retryHomeLoad,
                  );
                }
                if (!vmSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final vm = vmSnap.data!;
                final selectedExamIds = vm.selectedExams
                    .map((exam) => exam.examId)
                    .toList();
                return Column(
                  children: [
                    TopHeader(
                      selectedExamId: vm.activeExam?.examId,
                      userExamIds: selectedExamIds,
                      showExamDropdown: true,
                      onExamChanged: (examId) {
                        if (!mounted) return;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _ensureHomeVm(
                            userId: user.uid,
                            userData: userData,
                            force: true,
                          );
                          setState(() {});
                        });
                      },
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, ${vm.greetingName} 👋',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Ready to boost your rank today?',
                              style: TextStyle(
                                fontSize: 15,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _buildQuoteCard(vm.quote),
                            const SizedBox(height: 22),
                            const Text(
                              'Current Goal',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildGoalCard(
                              vm.currentGoal,
                              activeExam: vm.activeExam,
                              showViewPlan: vm.hasAvailablePlans,
                              onEdit: () => _editGoal(
                                userId: user.uid,
                                goal: vm.currentGoal,
                                activeExam: vm.activeExam,
                              ),
                            ),
                            const SizedBox(height: 26),
                            const Text(
                              'Your Selected Exams',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (vm.selectedExams.isEmpty)
                              _buildEmptyExamCard()
                            else
                              ...vm.selectedExams.map((exam) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _buildExamCard(exam),
                                );
                              }),
                            const SizedBox(height: 18),
                            _buildSectionHeader(
                              title: 'Quick Stats',
                              actionLabel: 'View Analytics',
                              onTap: () {
                                final navState = MainNavigation.maybeOf(
                                  context,
                                );
                                if (navState != null) {
                                  navState.switchToTab(
                                    3,
                                    analyticsExamId: vm.activeExam?.examId,
                                    analyticsTabIndex: 0,
                                  );
                                  return;
                                }

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => MainNavigation(
                                      initialIndex: 3,
                                      initialAnalyticsExamId:
                                          vm.activeExam?.examId,
                                      initialAnalyticsTabIndex: 0,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            _buildStatsRow(vm),
                            const SizedBox(height: 26),
                            _buildSectionHeader(
                              title: 'Featured Mock Tests',
                              actionLabel: 'See All',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TestsScreen(
                                      selectedExam: vm.activeExam?.examId,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            if (vm.featuredMockTests.isEmpty)
                              _buildEmptyFeaturedCard()
                            else
                              ...vm.featuredMockTests.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _buildFeaturedCard(item),
                                );
                              }),
                            const SizedBox(height: 26),
                            _buildSectionHeader(
                              title: 'Featured PYQs',
                              actionLabel: 'See All',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PyqScreen(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            if (vm.featuredPyqs.isEmpty)
                              _buildEmptyFeaturedCard(
                                message:
                                    'No featured PYQs available for your selected exam yet.',
                              )
                            else
                              ...vm.featuredPyqs.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _buildFeaturedCard(item),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF31459B),
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SelectExamScreen()));
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildQuoteCard(String quote) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.format_quote_rounded, color: Color(0xFFC7D2FE)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '"$quote"',
              style: const TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                height: 1.6,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard(
    _GoalVm? goal, {
    required _ExamCardVm? activeExam,
    required bool showViewPlan,
    required VoidCallback onEdit,
  }) {
    final remainingDays = goal?.targetDate == null
        ? null
        : math.max(0, goal!.targetDate!.difference(DateTime.now()).inDays);
    final title = goal?.title ?? activeExam?.title ?? 'Choose your target exam';
    final description =
        goal?.description ??
        activeExam?.description ??
        'Define your current preparation goal.';
    final deadlineLabel = goal?.targetDate == null
        ? null
        : 'Ends on ${_formatGoalDate(goal!.targetDate!)}';
    final daysLeftLabel = remainingDays == null
        ? null
        : '$remainingDays ${remainingDays == 1 ? 'day' : 'days'} left';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF31459B), Color(0xFF3A4DB3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2431459B),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onEdit,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.transparent,
                  highlightColor: Colors.white.withValues(alpha: 0.14),
                  hoverColor: Colors.transparent,
                  splashFactory: InkRipple.splashFactory,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.topRight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined, size: 17),
                tooltip: 'Edit goal',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            goal == null && activeExam == null
                ? 'Pick an exam to unlock your personalized study journey.'
                : description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFFE6EBFF),
            ),
          ),
          if (deadlineLabel != null || daysLeftLabel != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (deadlineLabel != null)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildGoalMetaChip(
                        icon: Icons.event_rounded,
                        label: deadlineLabel,
                      ),
                    ),
                  ),
                if (daysLeftLabel != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _buildGoalMetaChip(
                      icon: Icons.timelapse_rounded,
                      label: daysLeftLabel,
                    ),
                  ),
              ],
            ),
          ],
          if (showViewPlan) ...[
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SubscriptionScreen(initialExamId: activeExam?.examId),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF31459B),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View Plan',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(width: 10),
                  Icon(Icons.arrow_forward_rounded),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGoalMetaChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamCard(_ExamCardVm exam) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEDF3FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Color(0xFF31459B),
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  exam.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmRemoveExam(exam),
            icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyExamCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'No exams selected yet. Tap the + button to add one.',
        style: TextStyle(color: Color(0xFF64748B)),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            actionLabel,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF31459B),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(_HomeVm vm) {
    final resolvedExamId = vm.activeExam?.examId.isNotEmpty == true
        ? vm.activeExam!.examId
        : (vm.selectedExams.isNotEmpty ? vm.selectedExams.first.examId : null);

    final cards = [
      _StatCardVm(
        icon: Icons.event_available_rounded,
        iconColor: const Color(0xFF31459B),
        value: vm.testsAttended.toString(),
        label: 'Tests Attended',
        onTap: () {
          if (resolvedExamId == null || resolvedExamId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select an exam first')),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TestHistoryScreen(initialExamId: resolvedExamId),
            ),
          );
        },
      ),
      _StatCardVm(
        icon: Icons.workspace_premium_rounded,
        iconColor: const Color(0xFF16A34A),
        value: vm.bestRank == null ? '--' : '#${vm.bestRank}',
        label: 'Best Rank',
        onTap: () {
          if (resolvedExamId == null || resolvedExamId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select an exam first')),
            );
            return;
          }
          final navState = MainNavigation.maybeOf(context);
          if (navState != null) {
            navState.switchToTab(
              3,
              analyticsExamId: resolvedExamId,
              analyticsTabIndex: 1,
            );
            return;
          }

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MainNavigation(
                initialIndex: 3,
                initialAnalyticsExamId: resolvedExamId,
                initialAnalyticsTabIndex: 1,
              ),
            ),
          );
        },
      ),
      _StatCardVm(
        icon: Icons.stars_rounded,
        iconColor: const Color(0xFFF97316),
        value: vm.bestScoreText,
        label: 'Best Score',
        onTap: () {
          if (resolvedExamId == null || resolvedExamId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select an exam first')),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SubjectInsightsScreen(examId: resolvedExamId),
            ),
          );
        },
      ),
    ];

    return Row(
      children: cards.map((card) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: card == cards.last ? 0 : 12),
            child: SizedBox(height: 146, child: _buildStatCard(card)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatCard(_StatCardVm vm) {
    final child = Container(
      height: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Icon(vm.icon, color: vm.iconColor, size: 22),
          const SizedBox(height: 14),
          Text(
            vm.value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            vm.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.3,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );

    if (vm.onTap == null) {
      return child;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: vm.onTap,
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
    );
  }

  Widget _buildFeaturedCard(_FeaturedCardVm item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(item.icon, color: item.iconTint, size: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: item.badgeColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.badge,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: item.badgeTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: item.onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF31459B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Start',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFeaturedCard({
    String message =
        'No featured practice items available for your selected exam yet.',
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF64748B))),
    );
  }

  String _formatGoalDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }

  String _firstName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  Future<String> _loadDailyQuote() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('quotes')
          .limit(1)
          .get();
      final data = snapshot.docs.isNotEmpty ? snapshot.docs.first.data() : null;
      final rawQuotes = data?['quote_list'];
      final quotes = rawQuotes is Iterable
          ? rawQuotes
                .map((item) => item?.toString().trim() ?? '')
                .where((item) => item.isNotEmpty)
                .toList()
          : _fallbackQuotes;
      return _quoteForDate(quotes);
    } catch (_) {
      return _quoteForDate(_fallbackQuotes);
    }
  }

  String _quoteForDate(List<String> quotes) {
    final availableQuotes = quotes.isEmpty ? _fallbackQuotes : quotes;
    if (availableQuotes.length == 1) return availableQuotes.first;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final todayIndex = _dailyQuoteIndex(today, availableQuotes.length);
    final yesterdayIndex = _dailyQuoteIndex(yesterday, availableQuotes.length);

    if (todayIndex != yesterdayIndex) {
      return availableQuotes[todayIndex];
    }

    return availableQuotes[(todayIndex + 1) % availableQuotes.length];
  }

  int _dailyQuoteIndex(DateTime date, int length) {
    final dayNumber =
        date.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    final seededValue = (dayNumber * 1103515245 + 12345) & 0x7fffffff;
    return seededValue % length;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _scorePercent(Map<String, dynamic> data) {
    final score = _asDouble(data['score'] ?? data['marksObtained']);
    final total = _asDouble(
      data['totalMarks'] ?? data['maxMarks'] ?? data['marks'],
    );
    if (score == null) return null;
    if (total != null && total > 0) {
      return (score / total) * 100;
    }
    return score <= 100 ? score : null;
  }

  double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static bool _isNewItem(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    if (createdAt is! Timestamp) return false;
    return DateTime.now().difference(createdAt.toDate()).inDays <= 14;
  }

  static String _testMetaLabel(Map<String, dynamic> data) {
    final totalQuestions =
        data['totalQuestions'] ??
        data['questionCount'] ??
        data['questionsCount'];
    if (totalQuestions != null) {
      return '$totalQuestions Qs';
    }
    final duration =
        data['totalDurationMinutes'] ??
        (data['timing'] is Map
            ? (data['timing'] as Map)['totalDurationMinutes']
            : null);
    if (duration != null) {
      return '$duration mins';
    }
    return 'Mock Test';
  }

  static String _pyqPaperCountLabel(Map<String, dynamic> data) {
    final count = data['paperCount'] ?? data['count'];
    return count?.toString() ?? 'Practice';
  }

  Map<String, dynamic>? _goalDataForExam(
    Map<String, dynamic> userData,
    String? examId,
  ) {
    final normalizedExamId = (examId ?? '').trim();
    if (normalizedExamId.isNotEmpty) {
      final rawExamGoals = userData['examGoals'];
      if (rawExamGoals is Map) {
        final goalForExam = rawExamGoals[normalizedExamId];
        if (goalForExam is Map) {
          return Map<String, dynamic>.from(goalForExam);
        }
      }
    }

    final legacyGoal = userData['currentGoal'];
    if (legacyGoal is! Map) return null;

    final mappedLegacyGoal = Map<String, dynamic>.from(legacyGoal);
    final legacyExamId = (mappedLegacyGoal['examId'] ?? '').toString().trim();
    if (normalizedExamId.isEmpty ||
        legacyExamId.isEmpty ||
        legacyExamId == normalizedExamId) {
      return mappedLegacyGoal;
    }
    return null;
  }
}

class _HomeVm {
  const _HomeVm({
    required this.greetingName,
    required this.quote,
    required this.activeExam,
    required this.selectedExams,
    required this.testsAttended,
    required this.bestRank,
    required this.bestScoreText,
    required this.currentGoal,
    required this.hasAvailablePlans,
    required this.featuredMockTests,
    required this.featuredPyqs,
  });

  final String greetingName;
  final String quote;
  final _ExamCardVm? activeExam;
  final List<_ExamCardVm> selectedExams;
  final int testsAttended;
  final int? bestRank;
  final String bestScoreText;
  final _GoalVm? currentGoal;
  final bool hasAvailablePlans;
  final List<_FeaturedCardVm> featuredMockTests;
  final List<_FeaturedCardVm> featuredPyqs;
}

class _EditGoalDialog extends StatefulWidget {
  const _EditGoalDialog({
    required this.userId,
    required this.activeExamId,
    required this.activeExam,
    required this.goal,
    required this.messenger,
    required this.parentContext,
    required this.formatGoalDate,
  });

  final String userId;
  final String activeExamId;
  final _ExamCardVm? activeExam;
  final _GoalVm? goal;
  final ScaffoldMessengerState messenger;
  final BuildContext parentContext;
  final String Function(DateTime value) formatGoalDate;

  @override
  State<_EditGoalDialog> createState() => _EditGoalDialogState();
}

class _EditGoalDialogState extends State<_EditGoalDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late DateTime? _selectedDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.goal?.title ?? widget.activeExam?.title ?? '',
    );
    _descriptionController = TextEditingController(
      text:
          widget.goal?.description ??
          widget.activeExam?.description ??
          'Add a goal description to stay focused.',
    );
    _selectedDate = widget.goal?.targetDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    if (_isSaving) return;
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final pickerInitialDate = _selectedDate == null
        ? todayDateOnly.add(const Duration(days: 30))
        : DateTime(
            _selectedDate!.year,
            _selectedDate!.month,
            _selectedDate!.day,
          );
    final safeInitialDate = pickerInitialDate.isBefore(todayDateOnly)
        ? todayDateOnly
        : pickerInitialDate;
    final picked = await showDatePicker(
      context: widget.parentContext,
      initialDate: safeInitialDate,
      firstDate: todayDateOnly,
      lastDate: DateTime(2100),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _selectedDate = picked;
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final normalizedSelectedDate = _selectedDate == null
        ? null
        : DateTime(
            _selectedDate!.year,
            _selectedDate!.month,
            _selectedDate!.day,
          );
    if (normalizedSelectedDate != null &&
        normalizedSelectedDate.isBefore(todayDateOnly)) {
      widget.messenger.showSnackBar(
        const SnackBar(
          content: Text('Goal target date cannot be in the past.'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({
            'examGoals': {
              widget.activeExamId: {
                'title': _titleController.text.trim(),
                'description': _descriptionController.text.trim(),
                'targetDate': normalizedSelectedDate == null
                    ? null
                    : Timestamp.fromDate(normalizedSelectedDate),
                'examId': widget.activeExamId,
                'updatedAt': FieldValue.serverTimestamp(),
              },
            },
          }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      widget.messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? 'Unable to save goal right now.')),
      );
      setState(() {
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      widget.messenger.showSnackBar(
        const SnackBar(content: Text('Unable to save goal right now.')),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF8FAFF),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Edit Goal',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF31459B),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Goal title',
                hintText: 'Crack JEE Main 2026',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFDCE4F5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFDCE4F5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color(0xFF31459B),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Goal description',
                hintText: 'Complete weekly mocks and revise weak areas.',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFDCE4F5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFDCE4F5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color(0xFF31459B),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Deadline',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: _isSaving ? null : _pickDate,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFDCE4F5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: Color(0xFF31459B),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedDate == null
                              ? 'Select target date'
                              : widget.formatGoalDate(_selectedDate!),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _selectedDate == null
                                ? const Color(0xFF6B7280)
                                : const Color(0xFF111827),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF64748B),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF31459B),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _HomeStatsVm {
  const _HomeStatsVm({
    required this.testsAttended,
    required this.bestRank,
    required this.bestScoreText,
  });

  final int testsAttended;
  final int? bestRank;
  final String bestScoreText;
}

class _FeaturedContentVm {
  const _FeaturedContentVm({
    required this.featuredMockTests,
    required this.featuredPyqs,
  });

  const _FeaturedContentVm.empty()
    : featuredMockTests = const <_FeaturedCardVm>[],
      featuredPyqs = const <_FeaturedCardVm>[];

  final List<_FeaturedCardVm> featuredMockTests;
  final List<_FeaturedCardVm> featuredPyqs;
}

class _GoalVm {
  const _GoalVm({
    required this.title,
    required this.description,
    required this.targetDate,
    required this.examId,
  });

  final String title;
  final String description;
  final DateTime? targetDate;
  final String? examId;

  static _GoalVm? fromMap(
    Map<String, dynamic>? data, {
    required _ExamCardVm? fallbackExam,
  }) {
    if (data == null && fallbackExam == null) return null;
    final title = (data?['title'] ?? fallbackExam?.title ?? '')
        .toString()
        .trim();
    final description =
        (data?['description'] ?? fallbackExam?.description ?? '')
            .toString()
            .trim();
    final targetDateValue = data?['targetDate'];
    final targetDate = targetDateValue is Timestamp
        ? targetDateValue.toDate()
        : null;
    final examId = (data?['examId'] ?? fallbackExam?.examId)?.toString();
    if (title.isEmpty && description.isEmpty && targetDate == null) {
      return null;
    }
    return _GoalVm(
      title: title,
      description: description,
      targetDate: targetDate,
      examId: examId,
    );
  }
}

class _ExamCardVm {
  const _ExamCardVm({
    required this.examId,
    required this.title,
    required this.description,
  });

  final String examId;
  final String title;
  final String description;
}

class _StatCardVm {
  const _StatCardVm({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final VoidCallback? onTap;
}

class _FeaturedCardVm {
  const _FeaturedCardVm({
    required this.title,
    required this.badge,
    required this.meta,
    required this.icon,
    required this.iconTint,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.onTap,
  });

  final String title;
  final String badge;
  final String meta;
  final IconData icon;
  final Color iconTint;
  final Color badgeColor;
  final Color badgeTextColor;
  final VoidCallback onTap;
}
