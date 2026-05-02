import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/content_access_service.dart';
import '../../services/subscription_access_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/offline_state.dart';
import '../../widgets/top_header.dart';
import 'pyq_chapters_screen.dart';
import 'subscription_screen.dart';

class PyqScreen extends StatefulWidget {
  const PyqScreen({super.key});

  @override
  State<PyqScreen> createState() => _PyqScreenState();
}

class _PyqScreenState extends State<PyqScreen> {
  String? selectedExamId;
  List<String> userExamIds = [];
  final Map<String, Future<Map<String, int>>> _subjectPaperCountsFutures = {};
  List<String> _examSubscriptionPlanIds = const [];
  Map<String, List<String>> _pyqPlanIdsById = const {};
  Set<String> _activePlanIds = <String>{};
  bool _examIsPremium = false;
  int _reloadTick = 0;

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
    if (preferredExamId != null) {
      _loadExamSubscriptionScope(preferredExamId);
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
    _loadExamSubscriptionScope(preferredExamId);
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

  Future<void> _loadExamSubscriptionScope(String examId) async {
    try {
      final examDoc = await FirebaseFirestore.instance
          .collection('exams')
          .doc(examId)
          .get();
      final examData = examDoc.data();
      final directExamPlanIds = SubscriptionAccessService.readPlanIds(examData);
      final scope = await SubscriptionAccessService.getExamSubscriptionScope(
        examId,
      );
      if (!mounted || selectedExamId != examId) return;
      final combinedExamPlanIds = <String>{
        ...directExamPlanIds,
        ...scope.examPlanIds,
      }.toList(growable: false);
      setState(() {
        _examSubscriptionPlanIds = combinedExamPlanIds;
        _pyqPlanIdsById = scope.pyqPlanIdsById;
        _examIsPremium = combinedExamPlanIds.isNotEmpty;
      });
    } catch (_) {
      if (!mounted || selectedExamId != examId) return;
      setState(() {
        _examSubscriptionPlanIds = const [];
        _pyqPlanIdsById = const {};
        _examIsPremium = false;
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getPyqs(String examId) {
    return ContentAccessService.publishedPyqsQuery(examId).snapshots();
  }

  Future<Map<String, int>> _loadSubjectQuestionCounts(
    String examId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> subjects,
  ) {
    return _subjectPaperCountsFutures.putIfAbsent(examId, () async {
      final countEntries = await Future.wait(
        subjects.map((subject) async {
          final snapshot = await FirebaseFirestore.instance
              .collection('exams')
              .doc(examId)
              .collection('pyqs')
              .doc(subject.id)
              .collection('chapters')
              .get();
          var total = 0;
          for (final doc in snapshot.docs) {
            final data = doc.data();
            total += _readCount(
              data['questionCount'] ?? data['paperCount'] ?? data['count'],
            );
          }
          return MapEntry(subject.id, total);
        }),
      );
      return Map<String, int>.fromEntries(countEntries);
    });
  }

  int _readCount(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  void _retryLoad({String? examId}) {
    if (!mounted) return;
    setState(() {
      if (examId == null) {
        _subjectPaperCountsFutures.clear();
      } else {
        _subjectPaperCountsFutures.remove(examId);
      }
      _reloadTick++;
    });
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
        child: Container(
          color: const Color(0xFFF5F6FA),
          child: Column(
            children: [
              TopHeader(
                selectedExamId: effectiveSelectedExamId,
                userExamIds: userExamIds,
                onExamChanged: (id) {
                  if (!mounted) return;
                  setState(() => selectedExamId = id);
                  _loadExamSubscriptionScope(id);
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: effectiveSelectedExamId == null
                    ? const Center(child: Text("No exam selected"))
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        key: ValueKey(
                          'pyq-stream-$effectiveSelectedExamId-$_reloadTick',
                        ),
                        stream: _getPyqs(effectiveSelectedExamId),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return OfflineState(
                              message:
                                  'Could not load PYQs. Please check your connection and try again.',
                              onRetry: () => _retryLoad(
                                examId: effectiveSelectedExamId,
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                           final docs = snapshot.data!.docs.toList()
                             ..sort(ContentAccessService.compareCreatedAtAsc);

                          if (docs.isEmpty) {
                            return const Center(child: Text("No PYQs available"));
                          }

                           return FutureBuilder<Map<String, int>>(
                              key: ValueKey(
                                'pyq-counts-$effectiveSelectedExamId-$_reloadTick',
                              ),
                              future: _loadSubjectQuestionCounts(
                                effectiveSelectedExamId,
                                docs,
                              ),
                             builder: (context, countsSnapshot) {
                               if (countsSnapshot.hasError) {
                                 return OfflineState(
                                   message:
                                       'Could not load PYQ details. Please check your connection and try again.',
                                   onRetry: () => _retryLoad(
                                     examId: effectiveSelectedExamId,
                                   ),
                                 );
                               }
                                final questionCounts =
                                    countsSnapshot.data ?? const <String, int>{};
                               return LayoutBuilder(
                                 builder: (context, constraints) {
                                   return SingleChildScrollView(
                                     padding: const EdgeInsets.symmetric(horizontal: 16),
                                     child: ConstrainedBox(
                                       constraints: BoxConstraints(
                                         minHeight: constraints.maxHeight,
                                       ),
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
                                              "Access exam questions organized by subject and chapter",
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey,
                                             ),
                                           ),
                                           const SizedBox(height: 20),
                                           ListView.builder(
                                             shrinkWrap: true,
                                             physics:
                                                 const NeverScrollableScrollPhysics(),
                                             itemCount: docs.length,
                                             itemBuilder: (context, index) {
                                               final doc = docs[index];
                                                final title = doc['name'] ?? doc.id;
                                                final questionCount =
                                                    questionCounts[doc.id] ?? 0;
                                                final subjectData = doc.data();
                                                final scopedPlanIds =
                                                    _pyqPlanIdsById[doc.id] ??
                                                    const <String>[];
                                                final effectiveSubjectData =
                                                    scopedPlanIds.isNotEmpty &&
                                                        SubscriptionAccessService
                                                            .readPlanIds(
                                                              subjectData,
                                                            )
                                                            .isEmpty
                                                    ? <String, dynamic>{
                                                        ...subjectData,
                                                        'subscriptionPlanIds':
                                                            scopedPlanIds,
                                                      }
                                                    : subjectData;
                                                final access =
                                                    ContentAccessService
                                                        .resolveAccess(
                                                          itemData:
                                                              effectiveSubjectData,
                                                          examPlanIds:
                                                              _examSubscriptionPlanIds,
                                                          activePlanIds:
                                                              _activePlanIds,
                                                          fallbackPremium:
                                                              _examIsPremium,
                                                        );
                                                final requiredPlanIds =
                                                    access.requiredPlanIds;
                                                final isLocked = access.isLocked;
                                                return Container(
                                                  margin: const EdgeInsets.only(
                                                    bottom: 16,
                                                  ),
                                                 child: Material(
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
                                                      onTap: () {
                                                        if (isLocked) {
                                                          Navigator.push<bool>(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (_) =>
                                                                  SubscriptionScreen(
                                                                    initialExamId:
                                                                        effectiveSelectedExamId,
                                                                    initialPlanId:
                                                                        requiredPlanIds.isNotEmpty
                                                                        ? requiredPlanIds.first
                                                                        : null,
                                                                    lockedItemLabel:
                                                                        title.toString(),
                                                                    lockedItemType:
                                                                        'pyq',
                                                                  ),
                                                            ),
                                                          ).then((subscribed) {
                                                            if (subscribed == true) {
                                                              SubscriptionAccessService.clearCache();
                                                              _loadActivePlans();
                                                            }
                                                          });
                                                          return;
                                                        }
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                PyqChaptersScreen(
                                                                  examId:
                                                                      effectiveSelectedExamId,
                                                                  subjectId:
                                                                      doc.id,
                                                                  subjectName:
                                                                      title,
                                                                ),
                                                          ),
                                                        );
                                                      },
                                                     child: Padding(
                                                       padding:
                                                           const EdgeInsets.all(18),
                                                       child: Row(
                                                         children: [
                                                           Container(
                                                             width: 52,
                                                             height: 52,
                                                             decoration: BoxDecoration(
                                                                color: isLocked
                                                                    ? Colors.grey.shade200
                                                                    : const Color(
                                                                        0xFFEFF3FF,
                                                                      ),
                                                               borderRadius:
                                                                   BorderRadius.circular(
                                                                     14,
                                                                   ),
                                                             ),
                                                              child: Icon(
                                                                isLocked
                                                                    ? Icons.lock_outline
                                                                    : Icons.menu_book,
                                                                color: isLocked
                                                                    ? Colors.grey
                                                                    : const Color(
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
                                                                   style:
                                                                       const TextStyle(
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
                                                                    "$questionCount questions available",
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
                                                         ],
                                                       ),
                                                     ),
                                                   ),
                                                 ),
                                               );
                                             },
                                           ),
                                         ],
                                       ),
                                     ),
                                   );
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
      ),
    );
  }

}
