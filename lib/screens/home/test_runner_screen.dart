import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ranksprint/screens/home/test_solution_screen.dart';
import 'package:ranksprint/sections/section_bean.dart';
import 'package:ranksprint/sections/section_service.dart';
import 'package:ranksprint/sections/sectionwise_navigation_screen.dart';
import 'package:lottie/lottie.dart';
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

class TestRunnerScreenState extends State<TestRunnerScreen> with WidgetsBindingObserver{
  String? attemptId;
  String? testName;
  String? examName;
  List<Map<String, dynamic>> questions = [];
  int currentIndex = 0;
  Map<String, String> answers = {}; // questionId -> selected option id
  Set<String> markedForReview = {};
  Set<String> visited = {};
  Set<String> reported = {};

  Timer? _timer;
  int remainingSeconds = 0;

  bool loading = false;
  List<SectionBean> sectionsBeans = [];
  int violationCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _blockScreenshots;
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !loading && attemptId == null) {
        _startAttempt();
      }
    });
    _loadTestMetadata(); // 👈 add this
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ) {
      violationCount++;

      if (violationCount >= 2) {
        //print("violations: $violationCount");
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text("Test Submitted"),
            content: const Text(
              "You left the exam screen. The test has been submitted automatically.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _submitAttempt();
                },
                child: const Text("OK"),
              )
            ],
          ),
        );
      } else {
        _showWarning();
      }
    }
  }


  void _showWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Warning"),
        content: const Text(
          "Switching apps during the test is not allowed.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text("Continue Test"),
          )
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

    final examDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(widget.examId)
        .get();

    setState(() {
      testName = testDoc.data()?['name'] ?? widget.testId;
      examName = examDoc.data()?['name'] ?? widget.examId;
    });
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
    final ref = FirebaseFirestore.instance.collection('testAttempts').doc();
    final attemptData = {
      'userId': user.uid,
      'examId': widget.examId,
      'testId': widget.testId,
      'attemptNumber': 1,
      'startedAt': Timestamp.now(),
      'status': 'in_progress',
      'answers': {},
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
    sectionsBeans = await sectionService.getSections(widget.examId, widget.testId);
    questions = sectionService.rearrangeQuestionsLikeDrawer(questions: questions, sections: sectionsBeans);


    setState(() {
      attemptId = ref.id;
      remainingSeconds = (SectionService.unlockedTime + SectionService.lockedTime) * 60;
      loading = false;
      currentIndex = 0;
      answers = {};
      markedForReview = {};
      visited = {};
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (remainingSeconds <= 0) {
        t.cancel();
        _submitAttempt();
      }else if(remainingSeconds <= SectionService.lockedTime * 60 && SectionService.isLock){
        SectionService.isLock = false;
        setState(() {
          remainingSeconds -= 1;
          SectionService.isLock = false;});
      }
      else {
        setState(() => remainingSeconds -= 1);
      }
    });
  }

  Future<void> _saveProgress() async {
    if (attemptId == null) return;
    final attemptRef = FirebaseFirestore.instance
        .collection('testAttempts')
        .doc(attemptId);
    await attemptRef.update({
      'answers': answers,
      'markedForReview': markedForReview.toList(),
      'reported': reported.toList(),
      'visited': visited.toList(),
      'lastSavedAt': Timestamp.now(),
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      );
    }
  }

  Future<void> _submitAttempt() async {
    if (attemptId == null) return;

    _timer?.cancel();

    final attemptRef = FirebaseFirestore.instance
        .collection('testAttempts')
        .doc(attemptId);
    await attemptRef.update({
      'status': 'completed',
      'submittedAt': Timestamp.now(),
      'answers': answers,
    });

    // compute a simple score for placeholder results
    int correct = 0;
    int total = questions.length;
    for (final q in questions) {
      final qid = q['__id'] as String;
      final selected = answers[qid];
      if (selected != null &&
          q['correctOption'] != null &&
          ExamResultScreenState.optionLetter(q['correctOption'] ) == selected) {
        correct += 1;
      }
    }

    final score = correct; // simple 1 point per correct for placeholder

    final resRef = FirebaseFirestore.instance
        .collection('results')
        .doc(attemptId);
    await resRef.set({
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'examId': widget.examId,
      'testId': widget.testId,
      'score': score,
      'correct': correct,
      'incorrect': total - correct,
      'unanswered': total - answers.length,
      'answers': answers,
      'question': questions,
      'percentile': 0,
      'rank': 0,
      'createdAt': Timestamp.now(),
    });

    SectionService.lockedTime = 0;
    SectionService.unlockedSectionLength = 0;
    SectionService.isLock = true;
    SectionService.unlockedTime = 0;
    SectionService.totalQuestionLength = 0;
    Map<String, dynamic> attemptData = (await attemptRef.get()).data()!;
    final Map<String, dynamic> resultData = (await resRef.get()).data()!;

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>  TestSolutionScreen(
            attemptId: attemptId!,
            attemptData: attemptData,
            resultData: resultData,
          ),
        ),
      );
    }
  }

  bool _canOpenQuestion(int index) {
    if (index > SectionService.unlockedSectionLength && SectionService.isLock == true) {
      return false;
    }

    if (index < SectionService.unlockedSectionLength && SectionService.isLock == false) {
      return false;
    }

    return true;
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
                SectionService.isLock = false;
                remainingSeconds = SectionService.lockedTime * 60;
                _saveProgress();
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
                SectionService.isLock = false;
                remainingSeconds = SectionService.lockedTime * 60;
                _saveProgress();
                if (!mounted) return;
                Navigator.pop(context);// Call your method
              },
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );
  }

  void _showSubmitTestDialog() {

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

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
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
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildCounter(notVisited, "Not Visited", Colors.grey),
                    _buildCounter(notAnswered, "Not Answered", Colors.red),
                    _buildCounter(answered, "Answered", Colors.green),
                    _buildCounter(marked, "Marked", Colors.deepPurple),
                    _buildCounter(
                      answeredAndMarked,
                      "Answered & Marked",
                      Colors.blue,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                const Text(
                  "This will finish and submit the test.",
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),

          actions: [

            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("No"),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                SectionService.isLock = false;
                _submitAttempt();
              },
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );
  }

  void _showAddForReviewQuestionDialog(String qid) {
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
            "Are you sure you want to report this question?",
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
                reported.add(qid);
                _saveProgress();
              },
              child: const Text("Yes"),
            ),
          ],
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

  void _selectOption(String qid, String optionId) {
    setState(() {
      answers[qid] = optionId;
      visited.add(qid);
    });
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
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  "${examName ?? ''} - ${testName ?? ''}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                // Save + Finish
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
                      onPressed: () async {
                        Navigator.pop(context);
                        await _submitAttempt();
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text("Finish"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                const Text(
                  "Questions Overview",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                // Overview Counters
                Wrap(
                  spacing: 16,
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

                const SizedBox(height: 24),

                Center(
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                         _showSubmitSectionNavDialog();
                      },
                      icon: const Icon(Icons.cloud_done),
                      label: const Text("Submit Current Unlocked Sections"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[100],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                
                ExamNavigationDrawer(sections: sectionsBeans,
                  questions: questions,
                  visited: visited,
                  answers: answers,
                  markedForReview: markedForReview,
                  onQuestionTap: (index) { Navigator.pop(context); setState(() { currentIndex = index; }); },
                  currentSectionTimeLeft: SectionService.isLock ? remainingSeconds - SectionService.lockedTime * 60 : remainingSeconds ,
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

  @override
  Widget build(BuildContext context) {
    final hasAttempt = attemptId != null;

    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
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
                      child: const Icon(Icons.menu, color: Color(0xFF2F6FEB)),
                    ),
                  ),
                  if (hasAttempt)
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

              if (!hasAttempt)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [

                        /// AI Animation
                        SizedBox(
                          height: 220,
                          child: Lottie.network(
                            "https://assets2.lottiefiles.com/packages/lf20_x62chJ.json",
                            repeat: true,
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
                        const CircularProgressIndicator(),
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
                const Expanded(child: Center(child: Text('No questions')))
              else
                // Question card and options
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF8FF),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Clear Answer',
                                      style: TextStyle(
                                        color: Color(0xFF2F6FEB),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () {
                                          final qid =
                                          questions[currentIndex]['__id'] as String;
                                          _showAddForReviewQuestionDialog(qid);
                                          if (_canOpenQuestion(currentIndex + 1)) {
                                            setState(() {
                                              currentIndex += 1;
                                            });
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.report_problem_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              HtmlHelper.renderHtml(
                                _questionHtmlWithInlineNumber(
                                  currentIndex + 1,
                                  (questions[currentIndex]['questionText'] ?? '')
                                      .toString(),
                                ),
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
                      // Options
                      Expanded(
                        child: ListView.separated(
                          itemCount:
                              (questions[currentIndex]['options'] as List?)
                                  ?.length ??
                              0,
                          separatorBuilder: (context, i) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final opts =
                                (questions[currentIndex]['options'] as List)
                                    .cast<Map<String, dynamic>>();
                            final opt = opts[i];
                            final optId =
                                opt['id']?.toString() ??
                                String.fromCharCode(65 + i);
                            final optText = opt['text'] ?? '';
                            final qid =
                                questions[currentIndex]['__id'] as String;
                            final selected = answers[qid];

                            final bool isSelected = selected == optId;

                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(0),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFEAEFF6),
                                  child: Text(optId),
                                ),
                                title: HtmlHelper.renderHtml(
                                  optText.toString(),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                onTap: () => _selectOption(qid, optId),
                                tileColor: isSelected
                                    ? const Color(0x6796C196)
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      // bottom actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                final qid =
                                    questions[currentIndex]['__id'] as String;
                                _toggleReview(qid);
                                if (_canOpenQuestion(currentIndex + 1)) {
                                  setState(() {
                                    currentIndex += 1;
                                  });
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: const BorderSide(
                                  color: Color(0xFF2F6FEB),
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'Review Later',
                                  style: TextStyle(color: Color(0xFF2F6FEB)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          currentIndex == SectionService.unlockedSectionLength && SectionService.isLock
                              ? Expanded(
                            child: ElevatedButton(
                              onPressed:
                                _showSubmitSectionDialog
                                ,
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'Submit Section',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          )
                              :
                          currentIndex == SectionService.totalQuestionLength ?
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _showSubmitTestDialog,
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'Submit Test',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          ) :
                          ElevatedButton(
                            onPressed: () {
                              if (_canOpenQuestion(currentIndex + 1)) {
                                setState(() {
                                  currentIndex += 1;
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 18,
                              ),
                              child: Icon(Icons.arrow_forward),
                            ),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),);
  }
}
