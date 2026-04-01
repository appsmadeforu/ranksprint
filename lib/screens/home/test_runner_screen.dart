import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ranksprint/screens/home/test_solution_screen.dart';
import 'package:ranksprint/sections/section_bean.dart';
import 'package:ranksprint/sections/section_service.dart';
import 'package:ranksprint/sections/sectionwise_navigation_screen.dart';
import 'package:ranksprint/services/leaderboard_backfill_service.dart';
import 'package:ranksprint/services/result_schema_contract.dart';
import 'package:ranksprint/services/startup_prefetch_service.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:ranksprint/services/html_helper.dart';

import '../../examSummary/exam_summary_screen.dart';

class TestRunnerScreen extends StatefulWidget {
  final String examId;
  final String testId;

  const TestRunnerScreen({
    super.key,
    required this.examId,
    required this.testId,
  });

  @override
  State<TestRunnerScreen> createState() => TestRunnerScreenState();
}

class TestRunnerScreenState extends State<TestRunnerScreen>
    with WidgetsBindingObserver {
  String? attemptId;
  String? testName;
  String? examName;
  List<Map<String, dynamic>> questions = [];
  int currentIndex = 0;
  Map<String, String> answers = {}; // questionId -> selected option id
  Set<String> markedForReview = {};
  Set<String> visited = {};
  Set<String> reported = {};
  Map<String, String> reportedComments = {};

  Timer? _timer;
  int remainingSeconds = 0;

  bool loading = true;
  bool _isSubmittingAttempt = false;
  bool _isHandlingLifecycleViolation = false;
  int _allowedAppSwitch = 1;
  bool _autoSubmitOnViolation = true;
  List<SectionBean> sectionsBeans = [];
  int violationCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _blockScreenshots;
    unawaited(_bootstrapTestRunner());
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !loading && attemptId == null) {
        _startAttempt();
      }
    });
    _loadTestMetadata(); // 👈 add this
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isViolationState(state)) {
      _handleLifecycleViolation();
    }
  }

  bool _isViolationState(AppLifecycleState state) {
    return state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
  }

  void _handleLifecycleViolation() {
    if (!mounted ||
        loading ||
        _isSubmittingAttempt ||
        _isHandlingLifecycleViolation) {
      return;
    }

    _isHandlingLifecycleViolation = true;
    violationCount++;

    if (_shouldAutoSubmitForViolation) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var isSubmitting = false;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text("Test Submitted"),
              content: Text(
                isSubmitting
                    ? "Submitting your test. Please wait..."
                    : "Video/audio overlay or leaving the test screen is not allowed. The test will now be submitted automatically.",
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          Navigator.of(dialogContext).pop();
                          await _submitAttempt();
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("OK"),
                ),
              ],
            ),
          );
        },
      ).whenComplete(() {
        _isHandlingLifecycleViolation = false;
      });
    } else {
      _showWarning().whenComplete(() {
        _isHandlingLifecycleViolation = false;
      });
    }
  }

  bool get _shouldAutoSubmitForViolation {
    if (violationCount <= _allowedAppSwitch) {
      return false;
    }
    return _autoSubmitOnViolation;
  }

  Future<void> _bootstrapTestRunner() async {
    await _loadTestMetadata();
    if (!mounted || attemptId != null) return;
    await _startAttempt();
  }

  Future<void> _showWarning() {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Warning"),
        content: const Text(
          "Switching apps or opening video/audio overlays during the test is not allowed.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text("Continue Test"),
          ),
        ],
      ),
    );
  }

  Future<void> _blockScreenshots() async {
    await ScreenProtector.preventScreenshotOn();
  }

  Future<void> _loadTestMetadata() async {
    final testDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(widget.examId)
        .collection('tests')
        .doc(widget.testId)
        .get();
    final testData = testDoc.data() ?? const <String, dynamic>{};
    final securityConfig = testData['securityConfig'] is Map
        ? Map<String, dynamic>.from(testData['securityConfig'] as Map)
        : const <String, dynamic>{};

    final examDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(widget.examId)
        .get();

    if (!mounted) return;
    setState(() {
      testName = testData['name'] ?? widget.testId;
      examName = examDoc.data()?['name'] ?? widget.examId;
      _allowedAppSwitch = _asInt(securityConfig['allowedAppSwitch']) ?? 1;
      _autoSubmitOnViolation =
          _asBool(securityConfig['autoSubmitOnViolation']) ?? true;
    });
    if (!loading && attemptId == null) {
      unawaited(_startAttempt());
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  bool? _asBool(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return null;
  }

  Future<void> _startAttempt() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be signed in to start a test'),
          ),
        );
      }
      return;
    }

    setState(() => loading = true);

    // create attempt doc
    final ref = FirebaseFirestore.instance
        .collection(ResultSchemaContract.attemptCollection)
        .doc();
    final attemptData = {
      'userId': user.uid,
      'examId': widget.examId,
      'testId': widget.testId,
      'attemptNumber': 1,
      'startedAt': Timestamp.now(),
      'status': 'in_progress',
      'answers': {},
      'reported': <String>[],
      'reportedComments': <String, String>{},
    };
    await ref.set(attemptData);

    // fetch questions - try with orderBy first, fallback without orderBy if that fails
    List<QueryDocumentSnapshot<Map<String, dynamic>>> qdocs = [];
    try {
      final qSnap = await FirebaseFirestore.instance
          .collection('exams')
          .doc(widget.examId)
          .collection('tests')
          .doc(widget.testId)
          .collection('questions')
          .orderBy('createdAt')
          .get();
      qdocs = qSnap.docs;
    } catch (e) {
      // orderBy('createdAt') may fail if field missing or for security rules - retry without order
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not order questions: ${e.toString()} — retrying without order',
            ),
          ),
        );
      }
      try {
        final qSnap = await FirebaseFirestore.instance
            .collection('exams')
            .doc(widget.examId)
            .collection('tests')
            .doc(widget.testId)
            .collection('questions')
            .get();
        qdocs = qSnap.docs;
      } catch (e2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load questions: ${e2.toString()}'),
            ),
          );
        }
        qdocs = [];
      }
    }

    // map to internal structure
    questions = qdocs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['__id'] = d.id;
      return m;
    }).toList();

    // debug logs to help runtime investigation
    // ignore: avoid_print
    print(
      'TestRunner: started attempt for exam=${widget.examId} test=${widget.testId} user=${user.uid} — questions found=${questions.length} ids=${qdocs.map((d) => d.id).toList()}',
    );

    SectionService sectionService = SectionService();
    sectionsBeans = await sectionService.getSections(
      widget.examId,
      widget.testId,
    );
    questions = sectionService.rearrangeQuestionsLikeDrawer(
      questions: questions,
      sections: sectionsBeans,
    );

    setState(() {
      attemptId = ref.id;
      remainingSeconds =
          (SectionService.unlockedTime + SectionService.lockedTime) * 60;
      loading = false;
      currentIndex = 0;
      answers = {};
      markedForReview = {};
      visited = {};
      reported = {};
      reportedComments = {};
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (remainingSeconds <= 0) {
        t.cancel();
        _submitAttempt();
      } else if (remainingSeconds <= SectionService.lockedTime * 60 &&
          SectionService.isLock) {
        SectionService.isLock = false;
        setState(() {
          remainingSeconds -= 1;
          SectionService.isLock = false;
        });
      } else {
        setState(() => remainingSeconds -= 1);
      }
    });
  }

  Future<void> _saveProgress() async {
    if (attemptId == null) return;
    final attemptRef = FirebaseFirestore.instance
        .collection(ResultSchemaContract.attemptCollection)
        .doc(attemptId);
    await attemptRef.update({
      'answers': answers,
      'markedForReview': markedForReview.toList(),
      'reported': reported.toList(),
      'reportedComments': reportedComments,
      'visited': visited.toList(),
      'lastSavedAt': Timestamp.now(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context);
    }
  }

  Future<void> _submitAttempt() async {
    if (attemptId == null || _isSubmittingAttempt) return;

    setState(() {
      _isSubmittingAttempt = true;
    });

    _timer?.cancel();

    try {
      final attemptRef = FirebaseFirestore.instance
          .collection(ResultSchemaContract.attemptCollection)
          .doc(attemptId);
      await attemptRef.update({
        'status': 'completed',
        'submittedAt': Timestamp.now(),
        'answers': answers,
      });

      // compute a simple score for placeholder results
      int correct = 0;
      int answered = 0;
      int total = questions.length;
      for (final q in questions) {
        final qid = q['__id'] as String;
        final selected = answers[qid];
        if (selected != null && selected.isNotEmpty) {
          answered += 1;
          if (q['correctOption'] != null &&
              ExamResultScreenState.optionLetter(q['correctOption']) ==
                  selected) {
            correct += 1;
          }
        }
      }

      final score = correct; // simple 1 point per correct for placeholder

      // Keep result doc id equal to attempt id so analytics/history can resolve
      // the finalized result without timestamp guessing.
      final resRef = FirebaseFirestore.instance
          .collection(ResultSchemaContract.resultCollection)
          .doc(attemptId);
      await resRef.set({
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'examId': widget.examId,
        'testId': widget.testId,
        'score': score,
        'correct': correct,
        'incorrect': answered - correct,
        'unanswered': total - answered,
        'answers': answers,
        'question': questions,
        'percentile': 0,
        'rank': 0,
        'createdAt': Timestamp.now(),
      });
      await _syncLeaderboardMetricsForTest();
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        StartupPrefetchService.invalidateDashboardData(
          userId: currentUser.uid,
          examId: widget.examId,
        );
        unawaited(
          StartupPrefetchService.prefetchDashboardData(
            userId: currentUser.uid,
            examId: widget.examId,
            forceRefresh: true,
          ),
        );
      }

      SectionService.lockedTime = 0;
      SectionService.unlockedSectionLength = 0;
      SectionService.isLock = true;
      SectionService.unlockedTime = 0;
      SectionService.totalQuestionLength = 0;
      Map<String, dynamic> attemptData = (await attemptRef.get()).data()!;
      final Map<String, dynamic> resultData = (await resRef.get()).data()!;

      if (!mounted) return;
      ScaffoldMessenger.of(context);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => TestSolutionScreen(
            attemptId: attemptId!,
            attemptData: attemptData,
            resultData: resultData,
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmittingAttempt = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to submit the test right now. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmAndSubmitTest() async {
    if (_isSubmittingAttempt) return;

    int notVisited = 0;
    int answered = 0;
    int notAnswered = 0;
    int marked = 0;
    int answeredAndMarked = 0;

    for (final q in questions) {
      final qid = q['__id'] as String;
      final isVisited = visited.contains(qid);
      final isAnswered = answers.containsKey(qid);
      final isMarked = markedForReview.contains(qid);

      if (!isVisited) {
        notVisited++;
      } else if (!isAnswered) {
        notAnswered++;
      }

      if (isAnswered) answered++;
      if (isMarked && !isAnswered) marked++;
      if (isMarked && isAnswered) answeredAndMarked++;
    }

    final shouldSubmit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("Submit Test"),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${examName ?? ''} - ${testName ?? ''}",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Questions Overview",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildCounter(notVisited, "Not Visited", Colors.grey),
                    _buildCounter(notAnswered, "Not Answered", Colors.red),
                    _buildCounter(answered, "Answered", Colors.green),
                    _buildCounter(
                      marked,
                      "Marked for Review",
                      Colors.deepPurple,
                    ),
                    _buildCounter(
                      answeredAndMarked,
                      "Answered & Marked",
                      Colors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  "Are you sure you want to submit the test?",
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text("No"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );

    if (shouldSubmit != true) return;
    SectionService.isLock = false;
    await _submitAttempt();
  }

  bool _canOpenQuestion(int index) {
    if (index > SectionService.unlockedSectionLength &&
        SectionService.isLock == true) {
      return false;
    }

    if (index < SectionService.unlockedSectionLength &&
        SectionService.isLock == false) {
      return false;
    }

    return true;
  }

  Future<void> _syncLeaderboardMetricsForTest() async {
    final snap = await FirebaseFirestore.instance
        .collection(ResultSchemaContract.resultCollection)
        .where('examId', isEqualTo: widget.examId)
        .where('testId', isEqualTo: widget.testId)
        .get();

    if (snap.docs.isEmpty) return;

    final docs = snap.docs.toList()
      ..sort((a, b) {
        final aData = a.data();
        final bData = b.data();

        final scoreDiff = _numValue(
          bData['score'],
        ).compareTo(_numValue(aData['score']));
        if (scoreDiff != 0) return scoreDiff;

        final correctDiff = _intValue(
          bData['correct'],
        ).compareTo(_intValue(aData['correct']));
        if (correctDiff != 0) return correctDiff;

        final incorrectDiff = _intValue(
          aData['incorrect'],
        ).compareTo(_intValue(bData['incorrect']));
        if (incorrectDiff != 0) return incorrectDiff;

        final createdAtDiff = _timeMillis(
          aData['createdAt'],
        ).compareTo(_timeMillis(bData['createdAt']));
        if (createdAtDiff != 0) return createdAtDiff;

        return a.id.compareTo(b.id);
      });

    final total = docs.length;
    var lastScore = double.nan;
    var currentRank = 0;
    var batch = FirebaseFirestore.instance.batch();
    var opCount = 0;

    for (int index = 0; index < docs.length; index++) {
      final doc = docs[index];
      final data = doc.data();
      final score = _numValue(data['score']);
      if (index == 0 || score != lastScore) {
        currentRank = index + 1;
        lastScore = score;
      }

      final percentile = _percentileForRank(currentRank, total);
      final existingRank = _intValue(data['rank']);
      final existingPercentile = _numValue(data['percentile']);
      if (existingRank == currentRank &&
          (existingPercentile - percentile).abs() < 0.001) {
        continue;
      }

      batch.update(doc.reference, {
        'rank': currentRank,
        'percentile': percentile,
        'leaderboardUpdatedAt': Timestamp.now(),
      });
      opCount++;

      if (opCount >= 450) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) {
      await batch.commit();
    }

    await LeaderboardBackfillService.syncExamLeaderboardSummary(
      examId: widget.examId,
    );
  }

  double _percentileForRank(int rank, int total) {
    if (total <= 1) return 100;
    final value = ((total - rank) / (total - 1)) * 100;
    return value.clamp(0.0, 100.0).toDouble();
  }

  double _numValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _timeMillis(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    return 0;
  }

  bool _isFirstQuestionOfSection(int index) {
    if (index <= 0 || index >= questions.length) {
      return true;
    }

    final current = questions[index];
    final previous = questions[index - 1];
    return _questionSectionKey(current) != _questionSectionKey(previous);
  }

  String _questionSectionKey(Map<String, dynamic> question) {
    return (question['sectionId'] ??
            question['sectionName'] ??
            question['section'] ??
            question['subject'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
  }

  Future<void> _unlockSectionAndMoveNext({
    bool closeNavigationPanel = false,
  }) async {
    SectionService.isLock = false;
    remainingSeconds = SectionService.lockedTime * 60;
    _saveProgress();
    final nextIndex = currentIndex + 1;
    if (!mounted) return;
    if (nextIndex >= questions.length || !_canOpenQuestion(nextIndex)) {
      setState(() {});
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F5E9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Color(0xFF2E7D32),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Section Submitted',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your section has been submitted successfully. Continue to the next section.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Continue'),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (closeNavigationPanel) {
      Navigator.pop(context);
    }
    setState(() {
      _markCurrentQuestionVisited();
      currentIndex = nextIndex;
    });
  }

  void _showSubmitSectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: true, // allows closing by tapping outside
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("Submit Section"),
          content: const Text(
            "This will submit the current unlocked section, and it will unlock the locked section.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog (Do nothing)
              },
              child: const Text("No"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog first
                _unlockSectionAndMoveNext();
              },
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );
  }

  void _showSubmitSectionNavDialog() {
    showDialog(
      context: context,
      barrierDismissible: true, // allows closing by tapping outside
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("Submit Section"),
          content: const Text(
            "This will submit the current unlocked section, and it will unlock the locked section.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog (Do nothing)
              },
              child: const Text("No"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog first
                _unlockSectionAndMoveNext(closeNavigationPanel: true);
              },
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );
  }

  void _showSubmitTestDialog() {
    _confirmAndSubmitTest();
  }

  void _showAddForReviewQuestionDialog(String qid) {
    final existingComment = reportedComments[qid]?.trim() ?? '';
    final controller = TextEditingController(text: existingComment);
    var errorText = '';
    final isEditing = reported.contains(qid);

    showDialog(
      context: context,
      barrierDismissible: true, // allows closing by tapping outside
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(isEditing ? "Edit Report" : "Report Question"),
                  ),
                  if (isEditing)
                    IconButton(
                      tooltip: 'Undo report',
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        setState(() {
                          reported.remove(qid);
                          reportedComments.remove(qid);
                        });
                        await _saveProgress();
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Report removed successfully.'),
                            backgroundColor: Color(0xFF15803D),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.undo_rounded,
                        color: Color(0xFF64748B),
                      ),
                    ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing
                        ? "Update what is wrong with this question."
                        : "Tell us what is wrong with this question.",
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 4,
                    minLines: 3,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText:
                          'Example: option B is correct, but the marked answer says C.',
                      errorText: errorText.isEmpty ? null : errorText,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (errorText.isNotEmpty) {
                        setDialogState(() => errorText = '');
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final comment = controller.text.trim();
                    if (comment.isEmpty) {
                      setDialogState(() {
                        errorText = 'Please describe what is wrong with the question.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop();
                    setState(() {
                      reported.add(qid);
                      reportedComments[qid] = comment;
                    });
                    await _saveProgress();
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEditing
                              ? 'Report updated successfully.'
                              : 'Question reported successfully.',
                        ),
                        backgroundColor: const Color(0xFF15803D),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Text(isEditing ? "Update" : "Report"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _toggleReview(String qid) {
    setState(() {
      if (markedForReview.contains(qid)) {
        markedForReview.remove(qid);
      } else {
        markedForReview.add(qid);
      }
    });
  }

  void _moveToNextQuestionOrHandleSectionBoundary() {
    final nextIndex = currentIndex + 1;

    if (nextIndex < questions.length && _canOpenQuestion(nextIndex)) {
      setState(() {
        _markCurrentQuestionVisited();
        currentIndex = nextIndex;
      });
      return;
    }

    final isAtLockedSectionBoundary =
        SectionService.isLock &&
        currentIndex == SectionService.unlockedSectionLength;

    if (isAtLockedSectionBoundary) {
      setState(() {
        _markCurrentQuestionVisited();
        currentIndex = 0;
      });
    }
  }

  void _selectOption(String qid, String optionId) {
    setState(() {
      answers[qid] = optionId;
      visited.add(qid);
    });
  }

  void _clearAnswer(String qid) {
    setState(() {
      answers.remove(qid);
      visited.add(qid);
    });
  }

  void _markCurrentQuestionVisited() {
    if (questions.isEmpty ||
        currentIndex < 0 ||
        currentIndex >= questions.length) {
      return;
    }
    final qid = questions[currentIndex]['__id']?.toString();
    if (qid == null || qid.isEmpty || visited.contains(qid)) {
      return;
    }
    visited.add(qid);
  }

  void _openPalette() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        int notVisited = 0;
        int answered = 0;
        int notAnswered = 0;
        int marked = 0;
        int answeredAndMarked = 0;
        for (final q in questions) {
          final qid = q['__id'] as String;

          final isVisited = visited.contains(qid);
          final isAnswered = answers.containsKey(qid);
          final isMarked = markedForReview.contains(qid);

          if (!isVisited) {
            notVisited++;
          } else if (!isAnswered) {
            notAnswered++;
          }

          if (isAnswered) answered++;
          if (isMarked && !isAnswered) marked++;
          if (isMarked && isAnswered) answeredAndMarked++;
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 28, 0, 8),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 55,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            "${examName ?? ''} - ${testName ?? ''}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              await _saveProgress();
                              if (!mounted) return;
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.cloud_upload),
                            label: const Text("Save"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _isSubmittingAttempt
                                ? null
                                : () async {
                                    Navigator.pop(context);
                                    await _confirmAndSubmitTest();
                                  },
                            icon: const Icon(Icons.check_circle),
                            label: const Text("Finish"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      const Text(
                        "Questions Overview",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          _buildCounter(notVisited, "Not Visited", Colors.grey),
                          _buildCounter(
                            notAnswered,
                            "Not Answered",
                            Colors.red,
                          ),
                          _buildCounter(answered, "Answered", Colors.green),
                          _buildCounter(
                            marked,
                            "Marked for Review",
                            Colors.deepPurple,
                          ),
                          _buildCounter(
                            answeredAndMarked,
                            "Answered & Marked",
                            Colors.blue,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      Center(
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _showSubmitSectionNavDialog();
                            },
                            icon: const Icon(Icons.cloud_done),
                            label: const Text(
                              "Submit Current Unlocked Sections",
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey[100],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                    ],
                  ),
                ),

                ExamNavigationDrawer(
                  sections: sectionsBeans,
                  questions: questions,
                  visited: visited,
                  answers: answers,
                  markedForReview: markedForReview,
                  onQuestionTap: (index) {
                    Navigator.pop(context);
                    setState(() {
                      _markCurrentQuestionVisited();
                      currentIndex = index;
                    });
                  },
                  currentSectionTimeLeft: SectionService.isLock
                      ? remainingSeconds - SectionService.lockedTime * 60
                      : remainingSeconds,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildCounter(int count, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  String _questionHtmlWithInlineNumber(int number, String html) {
    final content = html.trim();
    final prefix = '<span style="font-weight:600;">$number. </span>';
    final pOpen = RegExp(r'^<p(\s[^>]*)?>', caseSensitive: false);

    if (pOpen.hasMatch(content)) {
      return content.replaceFirstMapped(pOpen, (m) => '${m.group(0)}$prefix');
    }

    return '$prefix$content';
  }

  List<String> _questionImageUrls(Map<String, dynamic> question) {
    return HtmlHelper.extractImageUrls(
      question,
      preferredKeys: const [
        'questionImageUrl',
        'questionImageUrls',
        'questionImage',
        'questionImages',
        'imageUrl',
        'imageUrls',
        'image',
        'images',
      ],
    );
  }

  List<String> _optionImageUrls(Map<String, dynamic> option) {
    return HtmlHelper.extractImageUrls(
      option,
      preferredKeys: const [
        'optionImageUrl',
        'optionImageUrls',
        'optionImage',
        'optionImages',
        'imageUrl',
        'imageUrls',
        'image',
        'images',
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAttempt = attemptId != null;

    return PopScope(
      canPop: !_isSubmittingAttempt,
      child: Stack(
        children: [
          AbsorbPointer(
            absorbing: _isSubmittingAttempt,
            child: Scaffold(
              backgroundColor: const Color(0xFFF5F6FA),
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      if (hasAttempt) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            InkWell(
                              onTap: _openPalette,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.menu,
                                  color: Color(0xFF2F6FEB),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _formatTime(remainingSeconds),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2F6FEB),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (!hasAttempt)
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                /// AI Animation
                                Container(
                                  height: 220,
                                  width: 220,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFE9F1FF),
                                        Color(0xFFF6F8FF),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(36),
                                  ),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome_rounded,
                                        size: 68,
                                        color: Color(0xFF2F6FEB),
                                      ),
                                      SizedBox(height: 14),
                                      SizedBox(
                                        width: 42,
                                        height: 42,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: Color(0xFF5B3FD6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 20),

                                /// Title
                                const Text(
                                  "AI Exam Engine",
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2F6FEB),
                                  ),
                                ),

                                const SizedBox(height: 8),

                                /// Subtitle
                                const Text(
                                  "Preparing your questions\nAnalyzing difficulty & timer",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 30),
                                const Text(
                                  "Your Test starting in a moment...",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (questions.isEmpty)
                        const Expanded(
                          child: Center(child: Text('No questions')),
                        )
                      else
                        // Question card and options
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Builder(
                                    builder: (context) {
                                      final currentQuestion =
                                          questions[currentIndex];
                                      final questionText =
                                          (currentQuestion['questionText'] ??
                                                  '')
                                              .toString();
                                      final questionImages = _questionImageUrls(
                                        currentQuestion,
                                      );
                                      final opts =
                                          (currentQuestion['options']
                                                      as List? ??
                                                  const [])
                                              .cast<Map<String, dynamic>>();
                                      final qid =
                                          currentQuestion['__id'] as String;

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Card(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                16.0,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      InkWell(
                                                        onTap: () =>
                                                            _clearAnswer(qid),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              20,
                                                            ),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 6,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0xFFEFF8FF,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  20,
                                                                ),
                                                          ),
                                                          child: const Text(
                                                            'Clear Answer',
                                                            style: TextStyle(
                                                              color: Color(
                                                                0xFF2F6FEB,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        onPressed: () {
                                                          _showAddForReviewQuestionDialog(
                                                            qid,
                                                          );
                                                        },
                                                        style: IconButton.styleFrom(
                                                          backgroundColor:
                                                              reported.contains(
                                                                qid,
                                                              )
                                                              ? const Color(
                                                                  0xFFFEE2E2,
                                                                )
                                                              : const Color(
                                                                  0xFFF8FAFC,
                                                                ),
                                                          foregroundColor:
                                                              reported.contains(
                                                                qid,
                                                              )
                                                              ? const Color(
                                                                  0xFFB91C1C,
                                                                )
                                                              : const Color(
                                                                  0xFF64748B,
                                                                ),
                                                        ),
                                                        icon: Icon(
                                                          Icons
                                                              .report_problem_outlined,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  if (questionText
                                                          .trim()
                                                          .isEmpty &&
                                                      questionImages.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 8,
                                                          ),
                                                      child: Text(
                                                        'Q${currentIndex + 1}.',
                                                        style: const TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          height: 1.4,
                                                        ),
                                                      ),
                                                    ),
                                                  HtmlHelper.renderContent(
                                                    html:
                                                        questionText
                                                            .trim()
                                                            .isEmpty
                                                        ? null
                                                        : _questionHtmlWithInlineNumber(
                                                            currentIndex + 1,
                                                            questionText,
                                                          ),
                                                    imageUrls: questionImages,
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ListView.separated(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            itemCount: opts.length,
                                            separatorBuilder: (context, i) =>
                                                const SizedBox(height: 8),
                                            itemBuilder: (context, i) {
                                              final opt = opts[i];
                                              final optId =
                                                  opt['id']?.toString() ??
                                                  String.fromCharCode(65 + i);
                                              final optText = opt['text'] ?? '';
                                              final selected = answers[qid];
                                              final isSelected =
                                                  selected == optId;

                                              return Card(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(0),
                                                ),
                                                child: ListTile(
                                                  leading: CircleAvatar(
                                                    backgroundColor:
                                                        const Color(0xFFEAEFF6),
                                                    child: Text(optId),
                                                  ),
                                                  title:
                                                      HtmlHelper.renderContent(
                                                        html: optText
                                                            .toString(),
                                                        imageUrls:
                                                            _optionImageUrls(
                                                              opt,
                                                            ),
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                  onTap: () =>
                                                      _selectOption(qid, optId),
                                                  tileColor: isSelected
                                                      ? const Color(0x6796C196)
                                                      : null,
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // bottom actions
                              Row(
                                children: [
                                  if (!(currentIndex ==
                                          SectionService
                                              .unlockedSectionLength &&
                                      SectionService.isLock)) ...[
                                    if (!_isFirstQuestionOfSection(
                                      currentIndex,
                                    )) ...[
                                      OutlinedButton(
                                        onPressed: currentIndex > 0
                                            ? () {
                                                setState(() {
                                                  currentIndex -= 1;
                                                });
                                              }
                                            : null,
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFCBD5E1),
                                          ),
                                          minimumSize: const Size(58, 48),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.arrow_back,
                                          size: 18,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                  ],
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        final qid =
                                            questions[currentIndex]['__id']
                                                as String;
                                        _toggleReview(qid);
                                        _moveToNextQuestionOrHandleSectionBoundary();
                                      },
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFF2F6FEB),
                                        ),
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        child: Text(
                                          'Review Later',
                                          style: TextStyle(
                                            color: Color(0xFF2F6FEB),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  currentIndex ==
                                              SectionService
                                                  .unlockedSectionLength &&
                                          SectionService.isLock
                                      ? Expanded(
                                          child: ElevatedButton(
                                            onPressed: _showSubmitSectionDialog,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF1E40AF,
                                              ),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                    horizontal: 16,
                                                  ),
                                            ),
                                            child: const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.lock_open_rounded,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Submit Section',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : currentIndex ==
                                            SectionService.totalQuestionLength
                                      ? Expanded(
                                          child: ElevatedButton(
                                            onPressed: _showSubmitTestDialog,
                                            style: ElevatedButton.styleFrom(
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                vertical: 14,
                                              ),
                                              child: Text(
                                                'Submit Test',
                                                style: TextStyle(fontSize: 16),
                                              ),
                                            ),
                                          ),
                                        )
                                      : ElevatedButton(
                                          onPressed: () {
                                            if (_canOpenQuestion(
                                              currentIndex + 1,
                                            )) {
                                              setState(() {
                                                _markCurrentQuestionVisited();
                                                currentIndex += 1;
                                              });
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            minimumSize: const Size(58, 48),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.zero,
                                            child: Icon(
                                              Icons.arrow_forward,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isSubmittingAttempt)
            Positioned.fill(
              child: ColoredBox(
                color: Color(0x99000000),
                child: Center(
                  child: Container(
                    width: 280,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE3E8F5)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x180E1A33),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF3FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(7),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF2F3E8F),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Submitting your test',
                                style: TextStyle(
                                  color: Color(0xFF172554),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: const LinearProgressIndicator(
                            minHeight: 8,
                            backgroundColor: Color(0xFFE6ECFA),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF2F3E8F),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Saving answers, calculating score, and preparing your result screen.',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                            height: 1.4,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
