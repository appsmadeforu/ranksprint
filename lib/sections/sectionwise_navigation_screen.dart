import 'package:flutter/material.dart';
import 'package:ranksprint/sections/section_service.dart';
import 'package:ranksprint/sections/section_split.dart';
import '../../../sections/section_bean.dart';

class ExamNavigationDrawer extends StatelessWidget {
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
    this.currentSectionTimeLeft,
  });

  String formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final question in questions) {
      final sectionId = question['sectionId']?.toString();
      if (sectionId == null) continue;
      grouped.putIfAbsent(sectionId, () => []);
      grouped[sectionId]!.add(question);
    }
    SectionService sectionService  = SectionService();
    SectionSplit sectionSplit = sectionService.getSectionsSplit(sections);
    final unlockedSections = sectionSplit.unlockedSections;
    final lockedSections = sectionSplit.lockedSections;

    final totalUnlockedTime = unlockedSections.fold<int>(
      0,
          (sum, s) => sum + (s.sectionDurationMinutes ?? 0),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          /// ===============================
          /// 🔓 UNLOCKED SECTION SUMMARY
          /// ===============================
          if (unlockedSections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Unlocked Sections Total Time",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      formatTime(totalUnlockedTime),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          /// ===============================
          /// 🔓 UNLOCKED SECTIONS
          /// ===============================
          ...unlockedSections.map(
                  (section) => _buildSection(
                context,
                section,
                grouped,
                false,
              )),

          /// ===============================
          /// 🔒 LOCKED SECTIONS TITLE
          /// ===============================
          if (lockedSections.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Locked Sections",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),

          /// ===============================
          /// 🔒 LOCKED SECTIONS
          /// ===============================
          ...lockedSections.map(
                  (section) => _buildSection(
                context,
                section,
                grouped,
                true,
              )),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context,
      SectionBean section,
      Map<String, List<Map<String, dynamic>>> grouped,
      bool isLocked,
      ) {
    final sectionId = section.id?.toString() ?? "";
    final sectionQuestions =
        grouped[sectionId] ?? <Map<String, dynamic>>[];

    final answeredCount = sectionQuestions
        .where((q) => answers.containsKey(q['__id']))
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

              /// Header
              Padding(
                padding:
                const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        section.name ?? "Section",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (section.sectionDurationMinutes != null)
                          Text(
                            formatTime(section.sectionDurationMinutes!),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (isLocked)
                          const Icon(Icons.lock,
                              color: Colors.red),
                      ],
                    ),
                  ],
                ),
              ),

              /// Answer Count
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "Answered: $answeredCount / ${sectionQuestions.length}",
                  style: const TextStyle(fontSize: 13),
                ),
              ),

              const SizedBox(height: 12),

              /// Grid
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics:
                  const NeverScrollableScrollPhysics(),
                  itemCount: sectionQuestions.length,
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, i) {
                    final question =
                    sectionQuestions[i];
                    final qid =
                        question['__id']?.toString() ?? "";

                    final isVisited =
                    visited.contains(qid);
                    final isAnswered =
                    answers.containsKey(qid);
                    final isMarked =
                    markedForReview.contains(qid);

                    Color bg = const Color(0xFFEAEFF6);
                    Color textColor = Colors.black;

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
                        final globalIndex =
                        questions.indexWhere(
                                (q) =>
                            q['__id'] ==
                                qid);

                        if (globalIndex != -1) {
                          onQuestionTap(globalIndex);
                        }
                      },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius:
                          BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${i + 1}",
                          style: TextStyle(
                            fontWeight:
                            FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const Divider(),
            ],
          ),
        ),
      ),
    );
  }
}