import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/content_access_service.dart';
import '../../services/subscription_access_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/offline_state.dart';
import '../../widgets/top_header.dart';
import 'test_detail_screen.dart';
import 'subscription_screen.dart';

class TestsScreen extends StatefulWidget {
  final String? selectedExam;

  const TestsScreen({super.key, this.selectedExam});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  List<String> userExamIds = [];
  Set<String> _userGroupIds = <String>{};
  String? selectedExamId;
  bool _examIsPremium = false;
  List<String> _examSubscriptionPlanIds = const [];
  Map<String, List<String>> _testPlanIdsById = const {};
  Set<String> _activePlanIds = <String>{};
  _TestListFilter _testListFilter = _TestListFilter.all;

  @override
  void initState() {
    super.initState();
    UserExamPreferenceService.preferredExamNotifier.addListener(
      _handlePreferredExamChanged,
    );
    _loadUserExams();
  }

  @override
  void dispose() {
    UserExamPreferenceService.preferredExamNotifier.removeListener(
      _handlePreferredExamChanged,
    );
    super.dispose();
  }

  Future<void> _loadUserExams() async {
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final exams = List<String>.from(doc['selectedExams'] ?? []);

    if (exams.isNotEmpty) {
      final preferredExamId =
          widget.selectedExam != null && exams.contains(widget.selectedExam)
          ? widget.selectedExam
          : await UserExamPreferenceService.loadPreferredExamId(
              availableExamIds: exams,
            );
      if (!mounted) return;
      setState(() {
        userExamIds = exams;
        _userGroupIds = ContentAccessService.readUserGroupIds(doc.data());
        selectedExamId = preferredExamId;
      });

      _loadExamMetadata(selectedExamId!);
      _loadActivePlans();
    }
  }

  void _handlePreferredExamChanged() {
    final preferredExamId =
        UserExamPreferenceService.preferredExamNotifier.value;
    if (!mounted ||
        preferredExamId == null ||
        preferredExamId == selectedExamId ||
        !userExamIds.contains(preferredExamId)) {
      return;
    }

    setState(() {
      selectedExamId = preferredExamId;
    });
    _loadExamMetadata(preferredExamId);
  }

  Future<void> _loadActivePlans() async {
    try {
      final activePlanIds =
          await SubscriptionAccessService.getCurrentUserActivePlanIds();
      if (!mounted) return;
      setState(() {
        _activePlanIds = activePlanIds;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activePlanIds = <String>{};
      });
    }
  }

  Future<void> _loadExamMetadata(String examId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('exams')
          .doc(examId)
          .get();

      if (!mounted || selectedExamId != examId) return;

      final data = doc.data();
      final examPlanIds = SubscriptionAccessService.readPlanIds(data);
      final scope = await SubscriptionAccessService.getExamSubscriptionScope(
        examId,
      );
      if (!mounted || selectedExamId != examId) return;
      final combinedExamPlanIds = <String>{
        ...examPlanIds,
        ...scope.examPlanIds,
      }.toList(growable: false);

      final isPremium =
          data != null && combinedExamPlanIds.isNotEmpty;

      setState(() {
        _examIsPremium = isPremium;
        _examSubscriptionPlanIds = combinedExamPlanIds;
        _testPlanIdsById = scope.testPlanIdsById;
      });
    } catch (_) {
      if (!mounted || selectedExamId != examId) return;
      setState(() {
        _examIsPremium = false;
        _examSubscriptionPlanIds = const [];
        _testPlanIdsById = const {};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (selectedExamId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            // =======================
            // TOP HEADER
            // =======================
            TopHeader(
              selectedExamId: selectedExamId,
              userExamIds: userExamIds,
              onExamChanged: (value) {
                if (!mounted) return;
                setState(() {
                  selectedExamId = value;
                });
                _loadExamMetadata(value);
              },
            ),

            const SizedBox(height: 12),

            // =======================
            // TITLE SECTION
            // =======================
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Mock Tests",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "Practice full-length and sectional tests",
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chips = _TestListFilter.values.map((filter) {
                    final selected = _testListFilter == filter;
                    return InkWell(
                      onTap: () => setState(() => _testListFilter = filter),
                      borderRadius: BorderRadius.circular(999),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF2F3E8F)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF2F3E8F)
                                : const Color(0xFFD8DEEA),
                          ),
                        ),
                        child: Text(
                          filter.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF5B6478),
                          ),
                        ),
                      ),
                    );
                  }).toList();

                  if (constraints.maxWidth < 360) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < chips.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            chips[i],
                          ],
                        ],
                      ),
                    );
                  }

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: chips,
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // =======================
            // TEST LIST
            // =======================
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                key: ValueKey('attempts-$selectedExamId'),
                stream: FirebaseFirestore.instance
                    .collection('testAttempts')
                    .where(
                      'userId',
                      isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                    )
                    .where('examId', isEqualTo: selectedExamId)
                    .snapshots(),
                builder: (context, attemptsSnap) {
                  if (attemptsSnap.hasError) {
                    return const OfflineState(
                      message:
                          'Could not load test attempts. Please check your connection and try again.',
                    );
                  }
                  if (!attemptsSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final Map<String, int> attemptsByTestId = {};
                  for (final d in attemptsSnap.data!.docs) {
                    final data = d.data();
                    final testId = (data['testId'] ?? '').toString();
                    if (testId.isEmpty) continue;
                    attemptsByTestId[testId] =
                        (attemptsByTestId[testId] ?? 0) + 1;
                  }

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    key: ValueKey('tests-$selectedExamId'),
                    stream: ContentAccessService.publishedTestsQuery(
                      selectedExamId!,
                    ).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const OfflineState(
                          message:
                              'Could not load tests. Please check your connection and try again.',
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final tests = snapshot.data!.docs
                          .cast<QueryDocumentSnapshot<Map<String, dynamic>>>()
                          .where(_isTestVisible)
                          .toList();

                      final filteredTests = _applyTestFilter(
                        tests: tests,
                        attemptsByTestId: attemptsByTestId,
                      );

                      if (filteredTests.isEmpty) {
                        return Center(
                          child: Text(
                            _testListFilter == _TestListFilter.all
                                ? "No tests available"
                                : "No ${_testListFilter.emptyLabel} tests found",
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredTests.length,
                        itemBuilder: (context, index) {
                          final testDoc = filteredTests[index];
                          final usedAttempts =
                              attemptsByTestId[testDoc.id] ?? 0;
                          return _buildTestCard(testDoc, usedAttempts);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isTestVisible(QueryDocumentSnapshot<Map<String, dynamic>> test) {
    final data = test.data();
    return ContentAccessService.isVisibleToUser(
      itemData: data,
      userId: FirebaseAuth.instance.currentUser?.uid,
      userGroupIds: _userGroupIds,
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyTestFilter({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> tests,
    required Map<String, int> attemptsByTestId,
  }) {
    final items = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(tests);
    switch (_testListFilter) {
      case _TestListFilter.all:
        items.sort(ContentAccessService.compareCreatedAtAsc);
        return items;
      case _TestListFilter.attempted:
        final filtered = items
            .where((test) => (attemptsByTestId[test.id] ?? 0) > 0)
            .toList()
          ..sort(ContentAccessService.compareCreatedAtAsc);
        return filtered;
      case _TestListFilter.notAttempted:
        final filtered = items
            .where((test) => (attemptsByTestId[test.id] ?? 0) == 0)
            .toList()
          ..sort(ContentAccessService.compareCreatedAtAsc);
        return filtered;
      case _TestListFilter.latest:
        items.sort((a, b) => ContentAccessService.compareCreatedAtAsc(b, a));
        return items;
    }
  }

  Widget _buildTestCard(QueryDocumentSnapshot test, int usedAttempts) {
    final title = test['name'] ?? test.id;

    final Map<String, dynamic>? testData = test.data() as Map<String, dynamic>?;

    final durationVal =
        (testData != null &&
            testData.containsKey('timing') &&
            testData['timing'] is Map &&
            (testData['timing'] as Map).containsKey('totalDurationMinutes'))
        ? testData['timing']['totalDurationMinutes']
        : (testData != null ? testData['totalDurationMinutes'] : null);

    final duration = durationVal?.toString() ?? '0';
    final marks = test['totalMarks'] ?? test['marks'] ?? 0;
    final maxAttempts = test['attemptLimit'] ?? test['maxAttempts'] ?? 0;
    final maxAttemptsInt = int.tryParse(maxAttempts.toString()) ?? 0;
    final limitReached = maxAttemptsInt > 0 && usedAttempts >= maxAttemptsInt;
    final attemptsText = maxAttemptsInt > 0
        ? "Attempts: $usedAttempts/$maxAttemptsInt"
        : "Attempts: $usedAttempts";

    final Map<String, dynamic>? tdata = test.data() as Map<String, dynamic>?;
    final scopedPlanIds = _testPlanIdsById[test.id] ?? const <String>[];
    final effectiveTestData = scopedPlanIds.isNotEmpty &&
            (tdata == null ||
                SubscriptionAccessService.readPlanIds(tdata).isEmpty)
        ? <String, dynamic>{
            ...?tdata,
            'subscriptionPlanIds': scopedPlanIds,
          }
        : tdata;

    final access = ContentAccessService.resolveAccess(
      itemData: effectiveTestData,
      examPlanIds: _examSubscriptionPlanIds,
      activePlanIds: _activePlanIds,
      fallbackPremium: _examIsPremium,
    );
    final requiredPlanIds = access.requiredPlanIds;
    final isLocked = access.isLocked;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      child: Material(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          splashColor: const Color(0xFF2F6FEB).withValues(alpha: 0.1),
          onTap: () {
            if (isLocked) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubscriptionScreen(
                    initialExamId: selectedExamId,
                    initialPlanId:
                        requiredPlanIds.isNotEmpty ? requiredPlanIds.first : null,
                    lockedItemLabel: title.toString(),
                    lockedItemType: 'test',
                  ),
                ),
              );
              return;
            }
            if (limitReached) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TestDetailScreen(examId: selectedExamId!, testId: test.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isLocked
                        ? Colors.grey.shade200
                        : const Color(0xFFEFF3FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isLocked ? Icons.lock_outline : Icons.assignment,
                    color: isLocked ? Colors.grey : const Color(0xFF2F6FEB),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        "$duration min • $marks marks",
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        attemptsText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: limitReached
                      ? null
                      : () {
                          if (isLocked) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SubscriptionScreen(
                                  initialExamId: selectedExamId,
                                  initialPlanId: requiredPlanIds.isNotEmpty
                                      ? requiredPlanIds.first
                                      : null,
                                  lockedItemLabel: title.toString(),
                                  lockedItemType: 'test',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TestDetailScreen(
                                examId: selectedExamId!,
                                testId: test.id,
                              ),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLocked
                        ? Colors.white
                        : const Color(0xFF2F3E8F),
                    side: isLocked
                        ? const BorderSide(color: Colors.orange)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: isLocked ? 0 : 2,
                  ),
                  child: Text(
                    isLocked
                        ? "Unlock"
                        : (limitReached
                              ? "Limit Reached"
                              : (usedAttempts > 0 ? "Reattempt" : "Attempt")),
                    style: TextStyle(
                      color: isLocked
                          ? Colors.orange
                          : (limitReached ? Colors.grey : Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _TestListFilter {
  all('All'),
  attempted('Attempted'),
  notAttempted('Not Attempted'),
  latest('Latest');

  const _TestListFilter(this.label);

  final String label;

  String get emptyLabel {
    switch (this) {
      case _TestListFilter.all:
        return 'available';
      case _TestListFilter.attempted:
        return 'attempted';
      case _TestListFilter.notAttempted:
        return 'not attempted';
      case _TestListFilter.latest:
        return 'latest';
    }
  }
}
