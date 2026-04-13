import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ranksprint/sections/section_service.dart';
import 'package:ranksprint/sections/section_split.dart';

import '../../../sections/section_bean.dart';

class ExamNavigationDrawer extends StatefulWidget {
  final List<SectionBean> sections;
  final List<Map<String, dynamic>> questions;
  final Set<String> visited;
  final Map<String, dynamic> answers;
  final Set<String> markedForReview;
  final Function(int) onQuestionTap;
  final int? currentSectionTimeLeft;

  const ExamNavigationDrawer({
    super.key,
    required this.sections,
    required this.questions,
    required this.visited,
    required this.answers,
    required this.markedForReview,
    required this.onQuestionTap,
    required this.currentSectionTimeLeft,
  });

  @override
  State<ExamNavigationDrawer> createState() => _ExamNavigationDrawerState();
}

class _ExamNavigationDrawerState extends State<ExamNavigationDrawer> {
  Timer? _countdownTimer;
  int _liveSectionTimeLeft = 0;

  @override
  void initState() {
    super.initState();
    _syncTimerFromWidget();
  }

  @override
  void didUpdateWidget(covariant ExamNavigationDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSectionTimeLeft != widget.currentSectionTimeLeft) {
      _syncTimerFromWidget();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _syncTimerFromWidget() {
    _countdownTimer?.cancel();
    _liveSectionTimeLeft = widget.currentSectionTimeLeft ?? 0;
    if (_liveSectionTimeLeft <= 0) {
      return;
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _liveSectionTimeLeft <= 0) {
        timer.cancel();
        return;
      }
      setState(() {
        _liveSectionTimeLeft -= 1;
      });
    });
  }

  String formatTime(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final m = safeSeconds ~/ 60;
    final s = safeSeconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final question in widget.questions) {
      final sectionKey = SectionService.questionSectionKey(question);
      if (sectionKey.isEmpty) continue;
      grouped.putIfAbsent(sectionKey, () => []);
      grouped[sectionKey]!.add(question);
    }
    final sectionService = SectionService();
    final sectionSplit = sectionService.getSectionsSplit(widget.sections);
    final unlockedSections = sectionSplit.unlockedSections;
    final lockedSections = sectionSplit.lockedSections;

    if (widget.sections.isEmpty) {
      return SingleChildScrollView(
        child: _buildQuestionGrid(
          context,
          title: 'All Questions',
          sectionQuestions: widget.questions,
          isLocked: false,
          showDivider: false,
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unlockedSections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Unlocked Sections Remaining Time",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      formatTime(_liveSectionTimeLeft),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ...unlockedSections.map(
            (section) => _buildSection(
              context,
              section,
              grouped,
              !SectionService.isLock,
              widget.sections.length > 1,
            ),
          ),
          ...lockedSections.map(
            (section) => _buildSection(
              context,
              section,
              grouped,
              SectionService.isLock,
              widget.sections.length > 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    SectionBean section,
    Map<String, List<Map<String, dynamic>>> grouped,
    bool isLocked,
    bool showDivider,
  ) {
    final sectionQuestions = <Map<String, dynamic>>[];
    final seenQuestionIds = <String>{};
    for (final key in SectionService.sectionKeys(section)) {
      final matches = grouped[key];
      if (matches != null && matches.isNotEmpty) {
        for (final question in matches) {
          final qid = question['__id']?.toString() ?? '';
          if (qid.isEmpty || seenQuestionIds.add(qid)) {
            sectionQuestions.add(question);
          }
        }
      }
    }

    final answeredCount = sectionQuestions
        .where((q) => widget.answers.containsKey(q['__id']))
        .length;

    return _buildQuestionGrid(
      context,
      title: section.name ?? "Section",
      sectionQuestions: sectionQuestions,
      isLocked: isLocked,
      showDivider: showDivider,
      durationMinutes: section.sectionDurationMinutes,
      answeredCount: answeredCount,
    );
  }

  Widget _buildQuestionGrid(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> sectionQuestions,
    required bool isLocked,
    required bool showDivider,
    int? durationMinutes,
    int? answeredCount,
  }) {
    final resolvedAnsweredCount =
        answeredCount ??
        sectionQuestions
            .where((q) => widget.answers.containsKey(q['__id']))
            .length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Opacity(
        opacity: isLocked ? 0.5 : 1,
        child: IgnorePointer(
          ignoring: isLocked,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (durationMinutes != null)
                          Text(
                            formatTime(durationMinutes * 60),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (isLocked) const Icon(Icons.lock, color: Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "Answered: $resolvedAnsweredCount / ${sectionQuestions.length}",
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sectionQuestions.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, i) {
                    final question = sectionQuestions[i];
                    final qid = question['__id']?.toString() ?? "";

                    final isVisited = widget.visited.contains(qid);
                    final isAnswered = widget.answers.containsKey(qid);
                    final isMarked = widget.markedForReview.contains(qid);

                    var bg = const Color(0xFFEAEFF6);
                    var textColor = Colors.black;

                    if (isMarked && isAnswered) {
                      bg = Colors.blue;
                      textColor = Colors.white;
                    } else if (isMarked) {
                      bg = Colors.deepPurple;
                      textColor = Colors.white;
                    } else if (isAnswered) {
                      bg = Colors.green;
                      textColor = Colors.white;
                    } else if (!isVisited) {
                      bg = Colors.grey.shade300;
                    } else {
                      bg = Colors.red;
                      textColor = Colors.white;
                    }

                    return GestureDetector(
                      onTap: () {
                        final globalIndex = widget.questions.indexWhere(
                          (q) => q['__id'] == qid,
                        );

                        if (globalIndex != -1) {
                          widget.onQuestionTap(globalIndex);
                        }
                      },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${i + 1}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (showDivider) const Divider(),
            ],
          ),
        ),
      ),
    );
  }
}
