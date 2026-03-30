import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/content_access_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/offline_state.dart';
import '../../widgets/top_header.dart';
import '../onboarding/select_exam_screen.dart';
import 'main_navigation.dart';
import 'pyq_screen.dart';
import 'subscription_screen.dart';
import 'test_detail_screen.dart';
import 'tests_screen.dart';

class SelectExamHome extends StatefulWidget {
  const SelectExamHome({super.key});

  @override
  State<SelectExamHome> createState() => _SelectExamHomeState();
}

class _SelectExamHomeState extends State<SelectExamHome> {
  static const List<String> _quotes = [
    'Success is the sum of small efforts, repeated day in and day out.',
    'Small progress each day adds up to big results.',
    'Focus on consistency. The rank will follow.',
    'Discipline turns ambition into a daily habit.',
  ];
  Future<_HomeVm>? _homeVmFuture;
  String _homeVmSignature = '';

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
    final parentContext = context;
    final messenger = ScaffoldMessenger.of(parentContext);
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final titleController = TextEditingController(
      text: goal?.title ?? activeExam?.title ?? '',
    );
    final descriptionController = TextEditingController(
      text:
          goal?.description ??
          activeExam?.description ??
          'Add a goal description to stay focused.',
    );
    DateTime? selectedDate = goal?.targetDate;
    bool isSaving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Current Goal'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Goal title',
                        hintText: 'Crack JEE Main 2026',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Goal description',
                        hintText: 'Complete weekly mocks and revise weak areas.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final pickerInitialDate = selectedDate == null
                                  ? todayDateOnly.add(const Duration(days: 30))
                                  : DateTime(
                                      selectedDate!.year,
                                      selectedDate!.month,
                                      selectedDate!.day,
                                    );
                              final safeInitialDate = pickerInitialDate.isBefore(
                                    todayDateOnly,
                                  )
                                  ? todayDateOnly
                                  : pickerInitialDate;
                              final picked = await showDatePicker(
                                context: parentContext,
                                initialDate: safeInitialDate,
                                firstDate: todayDateOnly,
                                lastDate: DateTime(2100),
                              );
                              if (!dialogContext.mounted) return;
                              if (picked != null) {
                                setDialogState(() {
                                  selectedDate = picked;
                                });
                              }
                            },
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(
                        selectedDate == null
                            ? 'Select target date'
                            : _formatGoalDate(selectedDate!),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() {
                            isSaving = true;
                          });
                          try {
                            final normalizedSelectedDate = selectedDate == null
                                ? null
                                : DateTime(
                                    selectedDate!.year,
                                    selectedDate!.month,
                                    selectedDate!.day,
                                  );
                            if (normalizedSelectedDate != null &&
                                normalizedSelectedDate.isBefore(todayDateOnly)) {
                              if (!dialogContext.mounted) return;
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Goal target date cannot be in the past.',
                                  ),
                                ),
                              );
                              setDialogState(() {
                                isSaving = false;
                              });
                              return;
                            }
                           await FirebaseFirestore.instance
                               .collection('users')
                               .doc(userId)
                              .set({
                                'currentGoal': {
                                  'title': titleController.text.trim(),
                                   'description': descriptionController.text.trim(),
                                   'targetDate': normalizedSelectedDate == null
                                       ? null
                                       : Timestamp.fromDate(normalizedSelectedDate),
                                   'examId': activeExam?.examId,
                                   'updatedAt': FieldValue.serverTimestamp(),
                                  },
                                }, SetOptions(merge: true));
                           if (!dialogContext.mounted) return;
                           Navigator.of(dialogContext).pop(true);
                         } on FirebaseException catch (e) {
                           if (!dialogContext.mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.message ?? 'Unable to save goal right now.',
                                ),
                              ),
                            );
                            setDialogState(() {
                              isSaving = false;
                            });
                          } catch (_) {
                            if (!dialogContext.mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Unable to save goal right now.'),
                              ),
                            );
                            setDialogState(() {
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    descriptionController.dispose();

    if (saved == true && mounted) {
      setState(() {});
    }
  }

  Future<_HomeVm> _loadVm({
    required String userId,
    required Map<String, dynamic> userData,
  }) async {
    final selectedExams = List<String>.from(
      userData['selectedExams'] ?? const [],
    );
    final preferredExamId = await UserExamPreferenceService.loadPreferredExamId(
      availableExamIds: selectedExams,
    );

    final examIds = selectedExams.toList();
    final examDocs = await Future.wait(
      examIds.map(
        (examId) =>
            FirebaseFirestore.instance.collection('exams').doc(examId).get(),
      ),
    );

    final exams = examDocs.map((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      return _ExamCardVm(
        examId: doc.id,
        title: (data['name'] ?? doc.id).toString(),
        description: (data['description'] ?? 'No description available.')
            .toString(),
      );
    }).toList();

    final activeExamId = selectedExams.contains(preferredExamId)
        ? preferredExamId
        : (selectedExams.isNotEmpty ? selectedExams.first : null);

    final baseFetches = await Future.wait([
      FirebaseFirestore.instance
          .collection('testAttempts')
          .where('userId', isEqualTo: userId)
          .get(),
      FirebaseFirestore.instance
          .collection('results')
          .where('userId', isEqualTo: userId)
          .get(),
    ]);
    final attemptsSnap = baseFetches[0] as QuerySnapshot<Map<String, dynamic>>;
    final resultsSnap = baseFetches[1] as QuerySnapshot<Map<String, dynamic>>;
    final completedAttempts = attemptsSnap.docs.where((doc) {
      final data = doc.data();
      return (data['status'] ?? '').toString() == 'completed';
    }).toList();

    int? bestRank;
    double? bestScorePct;
    for (final doc in resultsSnap.docs) {
      final data = doc.data();
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

    final featuredMockTests = <_FeaturedCardVm>[];
    final featuredPyqs = <_FeaturedCardVm>[];
    if (activeExamId != null) {
      final featuredConfigDoc = await FirebaseFirestore.instance
          .collection('exams')
          .doc(activeExamId)
          .collection('home_config')
          .doc('featured')
          .get();
      final featuredConfig = featuredConfigDoc.data() ?? const <String, dynamic>{};
      final featuredMockTestIds = List<String>.from(
        featuredConfig['featuredMockTestIds'] ?? const [],
      );
      final featuredPyqIds = List<String>.from(
        featuredConfig['featuredPyqIds'] ?? const [],
      );

      final featuredFetches = await Future.wait([
        Future.wait(
          featuredMockTestIds.map(
            (id) => FirebaseFirestore.instance
                .collection('exams')
                .doc(activeExamId)
                .collection('tests')
                .doc(id)
                .get(),
          ),
        ),
        Future.wait(
          featuredPyqIds.map(
            (id) => FirebaseFirestore.instance
                .collection('exams')
                .doc(activeExamId)
                .collection('pyqs')
                .doc(id)
                .get(),
          ),
        ),
      ]);

      final testDocs = (featuredFetches[0] as List<DocumentSnapshot<Map<String, dynamic>>>)
          .where((doc) => doc.exists && ContentAccessService.isVisibleNow(doc.data()))
          .toList();
      final pyqDocs = (featuredFetches[1] as List<DocumentSnapshot<Map<String, dynamic>>>)
          .where((doc) => doc.exists && ContentAccessService.isVisibleNow(doc.data()))
          .toList();

      for (final test in testDocs) {
        final data = test.data()!;
        featuredMockTests.add(
          _FeaturedCardVm(
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
                  builder: (_) => TestDetailScreen(
                    examId: activeExamId,
                    testId: test.id,
                  ),
                ),
              );
            },
          ),
        );
      }

      for (final pyq in pyqDocs) {
        final data = pyq.data()!;
        featuredPyqs.add(
          _FeaturedCardVm(
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
          ),
        );
      }
    }

    final greetingName = _firstName(
      (userData['name'] ?? FirebaseAuth.instance.currentUser?.displayName ?? '')
          .toString(),
    );

    final activeExam = exams.firstWhere(
      (exam) => exam.examId == activeExamId,
      orElse: () => exams.isNotEmpty
          ? exams.first
          : const _ExamCardVm(
              examId: '',
              title: 'No exam selected',
              description: 'Choose an exam to personalize your dashboard.',
            ),
    );

    final rawGoalData = userData['currentGoal'];
    final goalData = rawGoalData is Map
        ? Map<String, dynamic>.from(rawGoalData)
        : null;
    final currentGoal = _GoalVm.fromMap(goalData, fallbackExam: activeExam);

    return _HomeVm(
      greetingName: greetingName.isEmpty ? 'Learner' : greetingName,
      quote: _quoteForUser(userId),
      activeExam: activeExam.examId.isEmpty ? null : activeExam,
      selectedExams: exams,
      testsAttended: completedAttempts.length,
      bestRank: bestRank,
      bestScoreText: bestScorePct == null
          ? '--'
          : '${bestScorePct.round()}/100',
      currentGoal: currentGoal,
      featuredMockTests: featuredMockTests,
      featuredPyqs: featuredPyqs,
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
    final rawCurrentGoal = userData['currentGoal'];
    final currentGoal = rawCurrentGoal is Map
        ? Map<String, dynamic>.from(rawCurrentGoal)
        : null;
    final signature =
        '${(userData['name'] ?? '').toString()}|${selectedExams.join(',')}|'
        '${(currentGoal?['title'] ?? '').toString()}|'
        '${(currentGoal?['description'] ?? '').toString()}|'
        '${currentGoal?['targetDate'] ?? ''}';
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
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return OfflineState(
                message:
                    'Could not load your home screen. Please check your connection and try again.',
                onRetry: () {
                  if (!mounted) return;
                  setState(() {
                    _homeVmFuture = null;
                    _homeVmSignature = '';
                  });
                },
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
                    onRetry: () {
                      if (!mounted) return;
                      setState(() {
                        _homeVmFuture = null;
                        _homeVmSignature = '';
                      });
                    },
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
                      showExamDropdown: false,
                      onExamChanged: (examId) async {
                        await UserExamPreferenceService.savePreferredExamId(
                          examId,
                        );
                        if (!mounted) return;
                        _ensureHomeVm(
                          userId: user.uid,
                          userData: userData,
                          force: true,
                        );
                        setState(() {});
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
                            _buildGoalCard(
                              vm.currentGoal,
                              activeExam: vm.activeExam,
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
                                final navState = MainNavigation.maybeOf(context);
                                if (navState != null) {
                                  navState.switchToTab(
                                    3,
                                    analyticsExamId: vm.activeExam?.examId,
                                  );
                                  return;
                                }

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => MainNavigation(
                                      initialIndex: 3,
                                      initialAnalyticsExamId:
                                          vm.activeExam?.examId,
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
    required VoidCallback onEdit,
  }) {
    final remainingDays = goal?.targetDate == null
        ? null
        : math.max(0, goal!.targetDate!.difference(DateTime.now()).inDays);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
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
              const Expanded(
                child: Text(
                  'CURRENT GOAL',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFD6DDFF),
                  ),
                ),
              ),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            goal?.title ?? activeExam?.title ?? 'Choose your target exam',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            goal == null && activeExam == null
                ? 'Pick an exam to unlock your personalized study journey.'
                : remainingDays == null
                ? (goal?.description ??
                    activeExam?.description ??
                    'Define your current preparation goal.')
                : '${goal?.description ?? activeExam?.description ?? 'Stay on track with your study sprint.'} $remainingDays days remaining in this sprint.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFFE6EBFF),
            ),
          ),
          const SizedBox(height: 18),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
    final cards = [
      _StatCardVm(
        icon: Icons.event_available_rounded,
        iconColor: const Color(0xFF31459B),
        value: vm.testsAttended.toString(),
        label: 'Tests Attended',
      ),
      _StatCardVm(
        icon: Icons.workspace_premium_rounded,
        iconColor: const Color(0xFF16A34A),
        value: vm.bestRank == null ? '--' : '#${vm.bestRank}',
        label: 'Best Rank',
      ),
      _StatCardVm(
        icon: Icons.stars_rounded,
        iconColor: const Color(0xFFF97316),
        value: vm.bestScoreText,
        label: 'Best Score',
      ),
    ];

    return Row(
      children: cards.map((card) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: card == cards.last ? 0 : 12),
            child: SizedBox(
              height: 146,
              child: _buildStatCard(card),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatCard(_StatCardVm vm) {
    return Container(
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
    String message = 'No featured practice items available for your selected exam yet.',
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFF64748B)),
      ),
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

  String _quoteForUser(String userId) {
    if (userId.isEmpty) return _quotes.first;
    return _quotes[userId.codeUnits.fold<int>(0, (a, b) => a + b) %
        _quotes.length];
  }

  int? _remainingDays(String title) {
    final match = RegExp(r'(20\d{2})').firstMatch(title);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    if (year == null) return null;
    final end = DateTime(year, 12, 31);
    final now = DateTime.now();
    return math.max(0, end.difference(now).inDays);
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
    final title = (data?['title'] ?? fallbackExam?.title ?? '').toString().trim();
    final description = (data?['description'] ?? fallbackExam?.description ?? '')
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
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
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
