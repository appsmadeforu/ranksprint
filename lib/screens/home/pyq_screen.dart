import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/content_access_service.dart';
import '../../services/subscription_access_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/top_header.dart';
import 'pyq_chapters_screen.dart';
import 'subscription_screen.dart';
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
  Set<String> _activePlanIds = <String>{};
  List<String> _examSubscriptionPlanIds = const [];

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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final exams = List<String>.from(doc.data()?['selectedExams'] ?? []);
    final preferredExamId = await UserExamPreferenceService.loadPreferredExamId(
      availableExamIds: exams,
    );

    if (!mounted) return;
    setState(() {
      userExamIds = exams;
      selectedExamId = preferredExamId;
    });

    if (selectedExamId != null) {
      await _loadExamAccess(selectedExamId!);
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
    _loadExamAccess(preferredExamId);
  }

  Future<void> _loadExamAccess(String examId) async {
    final activePlanIds =
        await SubscriptionAccessService.getCurrentUserActivePlanIds();
    final examDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .get();

    if (!mounted) return;

    setState(() {
      _activePlanIds = activePlanIds;
      _examSubscriptionPlanIds = SubscriptionAccessService.readPlanIds(
        examDoc.data(),
      );
    });
  }

  Stream<QuerySnapshot> _getPyqs(String examId) {
    return ContentAccessService.publishedPyqsQuery(examId).snapshots();
  }

  void _openSubscription({
    required List<String> requiredPlanIds,
    required String itemLabel,
    required String itemType,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubscriptionScreen(
          initialExamId: selectedExamId,
          initialPlanId: requiredPlanIds.isNotEmpty
              ? requiredPlanIds.first
              : null,
          lockedItemLabel: itemLabel,
          lockedItemType: itemType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSelectedExamId =
        selectedExamId != null && userExamIds.contains(selectedExamId)
        ? selectedExamId
        : (userExamIds.isNotEmpty ? userExamIds.first : null);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: effectiveSelectedExamId,
              userExamIds: userExamIds,
              onExamChanged: (id) {
                setState(() => selectedExamId = id);
                _loadExamAccess(id);
              },
            ),
            const SizedBox(height: 8),

            Expanded(
              child: effectiveSelectedExamId == null
                  ? const Center(child: Text("No exam selected"))
                  : StreamBuilder<QuerySnapshot>(
                      stream: _getPyqs(effectiveSelectedExamId),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs =
                            snapshot.data!.docs
                                .cast<
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >()
                                .where(_isPublishedPyq)
                                .toList()
                              ..sort(ContentAccessService.compareCreatedAtAsc);

                        if (docs.isEmpty) {
                          return const Center(child: Text("No PYQs available"));
                        }

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
                                  final data =
                                      doc.data() as Map<String, dynamic>? ?? {};
                                  final access =
                                      ContentAccessService.resolveAccess(
                                        itemData: data,
                                        examPlanIds: _examSubscriptionPlanIds,
                                        activePlanIds: _activePlanIds,
                                      );
                                  final requiredPlanIds =
                                      access.requiredPlanIds;
                                  final isLocked = access.isLocked;

                                  return FutureBuilder<
                                    QuerySnapshot<Map<String, dynamic>>
                                  >(
                                    future:
                                        ContentAccessService.publishedPyqChaptersQuery(
                                          examId: selectedExamId!,
                                          subjectId: doc.id,
                                        ).get(),
                                    builder: (context, chapterSnap) {
                                      final paperCount = chapterSnap.hasData
                                          ? chapterSnap.data!.docs
                                                .where(_isPublishedPyq)
                                                .length
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
                                                ).withValues(alpha: 0.1),
                                                onTap: isLocked
                                                    ? () => _openSubscription(
                                                        requiredPlanIds:
                                                            requiredPlanIds,
                                                        itemLabel: title
                                                            .toString(),
                                                        itemType: 'pyq',
                                                      )
                                                    : () {
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
                                                      },
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

                                            if (isLocked)
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
                                                          .withValues(
                                                            alpha: 0.6,
                                                          ),
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

  bool _isPublishedPyq(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return ContentAccessService.isVisibleNow(data);
  }
}
