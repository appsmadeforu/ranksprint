import 'package:flutter/material.dart';
import 'package:ranksprint/sections/section_bean.dart';
import 'package:ranksprint/services/html_helper.dart';
import 'package:ranksprint/screens/home/main_navigation.dart';

enum ResultFilter {
  all,
  correct,
  incorrect,
  answered,
  unanswered
}

class ExamResultScreen extends StatefulWidget {
  final List questions;
  final Map answers;
  final int correct;
  final int incorrect;
  final int unanswered;
  final List<SectionBean> section;
  final String? returnToTestsExamId;

  const ExamResultScreen({
    super.key,
    required this.questions,
    required this.answers,
    required this.correct,
    required this.incorrect,
    required this.unanswered,
    required this.section,
    this.returnToTestsExamId,
  });

  @override
  State<ExamResultScreen> createState() => ExamResultScreenState();
}

class ExamResultScreenState extends State<ExamResultScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  Map<String, List> groupedQuestions = {};

  ResultFilter selectedFilter = ResultFilter.all;

  @override
  void initState() {
    super.initState();

    groupedQuestions = groupQuestions();

    _tabController = TabController(
      length: widget.section.length,
      vsync: this,
    );
  }

  /// OPTION LETTER
  static String optionLetter(dynamic index) {
    switch (index.toString()) {
      case '0':
        return 'A';
      case '1':
        return 'B';
      case '2':
        return 'C';
      case '3':
        return 'D';
      default:
        return '-';
    }
  }

  /// COLOR FOR ANSWER
  Color getColor(dynamic selected, dynamic correct) {
    if (selected == null) return Colors.grey;
    if (selected.toString() == correct.toString()) return Colors.green;
    return Colors.red;
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  /// GROUP QUESTIONS BY SECTION
  Map<String, List> groupQuestions() {

    Map<String, List> map = {};

    for (var q in widget.questions) {

      final secId = q['sectionId'] ?? '';

      if (!map.containsKey(secId)) {
        map[secId] = [];
      }

      map[secId]!.add(q);
    }

    return map;
  }

  /// APPLY FILTER
  List applyFilter(List questions) {

    if (selectedFilter == ResultFilter.all) return questions;

    return questions.where((q) {

      final qid = q['__id'];
      final selected = widget.answers[qid];
      final correct = optionLetter(q['correctOption']);

      if (selectedFilter == ResultFilter.correct) {
        return selected != null &&
            selected.toString() == correct.toString();
      }

      if (selectedFilter == ResultFilter.incorrect) {
        return selected != null &&
            selected.toString() != correct.toString();
      }

      if (selectedFilter == ResultFilter.answered) {
        return selected != null;
      }

      if (selectedFilter == ResultFilter.unanswered) {
        return selected == null;
      }

      return true;

    }).toList();
  }

  /// SUMMARY CARD
/*  Widget buildSummary() {

    int total = widget.questions.length;

    double accuracy =
    total == 0 ? 0 : widget.correct / total * 100;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade700],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [

          stat("Correct", widget.correct),

          stat("Incorrect", widget.incorrect),

          stat("Unanswered", widget.unanswered),

          stat("Accuracy", "${accuracy.toStringAsFixed(1)}%"),
        ],
      ),
    );
  }*/

  Widget stat(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$value",
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFD6E1FF), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget buildSummaryCard() {
    final total = widget.questions.length;
    final accuracy = total == 0 ? 0.0 : (widget.correct * 100.0 / total);

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF263D9A), Color(0xFF3049B0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF31479F)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x241F317B),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
          BoxShadow(
            color: Color(0x12FFFFFF),
            blurRadius: 0,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review your answers with section-wise insights',
            style: TextStyle(
              color: Color(0xFFE5ECFF),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: stat('Correct', widget.correct)),
              const SizedBox(width: 8),
              Expanded(child: stat('Incorrect', widget.incorrect)),
              const SizedBox(width: 8),
              Expanded(child: stat('Skipped', widget.unanswered)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Overall Accuracy',
                    style: TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${accuracy.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// FILTER BAR
  Widget buildFilterBar() {
    Widget chip(String label, ResultFilter filter) {
      bool selected = selectedFilter == filter;
      return GestureDetector(
        onTap: () {
          setState(() {
            selectedFilter = filter;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF263D9A) : const Color(0xFFF1F5FF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip("All", ResultFilter.all),
            chip("Correct", ResultFilter.correct),
            chip("Incorrect", ResultFilter.incorrect),
            chip("Answered", ResultFilter.answered),
            chip("Unanswered", ResultFilter.unanswered),
          ],
        ),
      ),
    );
  }

  /// QUESTION CARD
  Widget questionCard(
      int number,
      dynamic q,
      dynamic selected,
      dynamic correct,
      ) {

    final options = q['options'];
    final questionText = (q['questionText'] ?? '').toString();
    final questionImages = _questionImageUrls(Map<String, dynamic>.from(q));

    final isCorrectAnswer = selected != null && selected.toString() == optionLetter(correct);
    final accentColor = selected == null
        ? const Color(0xFF94A3B8)
        : isCorrectAnswer
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Question $number',
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (questionText.trim().isEmpty && questionImages.isNotEmpty)
              Text(
                'Q$number.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            HtmlHelper.renderContent(
              html: questionText.trim().isEmpty
                  ? null
                  : '<span style="font-weight:600;">Q$number. </span>$questionText',
              imageUrls: questionImages,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Color(0xFF111827),
              ),
            ),

            const SizedBox(height: 10),

            for (int i = 0; i < options.length; i++)
              optionTile(
                i,
                options[i]['text'],
                selected,
                optionLetter(correct),
                Map<String, dynamic>.from(options[i] as Map),
              ),

            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Your Answer: ${selected ?? '-'}",
                    style: TextStyle(
                      color: getColor(selected, optionLetter(correct)),
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),
                  Text(
                    "Correct Answer: ${optionLetter(correct)}",
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
              ),
              child: HtmlHelper.renderContent(
                html:
                    '<span style="font-weight:600;">Explanation: </span>${(q['explanationText'] ?? '').toString()}',
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// OPTION TILE
  Widget optionTile(
      int index,
      String text,
      dynamic selected,
      dynamic correct,
      [Map<String, dynamic>? optionData]
      ) {

    Color color = Colors.black;

    if (index.toString() == correct.toString()) {
      color = Colors.green;
    }

    if (selected != null &&
        index.toString() == selected.toString() &&
        selected.toString() != correct.toString()) {
      color = Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: 0.22),
            width: 1.2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${optionLetter(index)}. ",
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
            Expanded(
              child: HtmlHelper.renderContent(
                html: text,
                imageUrls: optionData == null ? const [] : _optionImageUrls(optionData),
                style: TextStyle(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSectionSelector() {
    return SizedBox(
      height: 58,
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: widget.section.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final sec = widget.section[index];
              final isSelected = _tabController.index == index;
              return GestureDetector(
                onTap: () {
                  _tabController.animateTo(index);
                  setState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF263D9A) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF263D9A)
                          : const Color(0xFFDCE3F4),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F0F172A),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      sec.name ?? 'Section',
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF475569),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget buildSectionTab(SectionBean sec) {
    final secQuestions = groupedQuestions[sec.id] ?? [];
    final filteredQuestions = applyFilter(secQuestions);

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const SizedBox(height: 10),
        buildFilterBar(),
        const SizedBox(height: 10),
        if (filteredQuestions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(
              child: Text(
                'No questions match this filter.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
          )
        else
          ...filteredQuestions.map((q) {
            final qid = q['__id'];
            final selected = widget.answers[qid];
            final correctOption = q['correctOption'];
            final number = widget.questions.indexOf(q) + 1;

            return questionCard(
              number,
              q,
              selected,
              correctOption,
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.returnToTestsExamId == null,
      onPopInvokedWithResult: (_, __) {
        if (widget.returnToTestsExamId != null) {
          _goToTestsScreen();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF3F5FC),
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () {
                          if (widget.returnToTestsExamId != null) {
                            _goToTestsScreen();
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 34,
                          width: 34,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFDCE3F4)),
                          ),
                          child: const Icon(
                            Icons.chevron_left_rounded,
                            size: 20,
                            color: Color(0xFF27408B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Exam Result',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF18306B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: buildSummaryCard()),
              SliverToBoxAdapter(child: buildSectionSelector()),
            ];
          },
          body: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TabBarView(
              controller: _tabController,
              children: widget.section.map((sec) {
                return buildSectionTab(sec);
              }).toList(),
            ),
          ),
        ),
      ),
    ));
  }

  void _goToTestsScreen() {
    final examId = widget.returnToTestsExamId;
    if (examId == null || examId.isEmpty) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainNavigation(
          initialIndex: 1,
          initialTestsExamId: examId,
        ),
      ),
      (route) => route.isFirst,
    );
  }
}
