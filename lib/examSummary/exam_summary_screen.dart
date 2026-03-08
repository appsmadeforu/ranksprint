import 'package:flutter/material.dart';
import 'package:ranksprint/sections/section_bean.dart';
import 'package:ranksprint/services/html_helper.dart';

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

  const ExamResultScreen({
    super.key,
    required this.questions,
    required this.answers,
    required this.correct,
    required this.incorrect,
    required this.unanswered,
    required this.section,
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
  Color getColor(selected, correct) {
    if (selected == null) return Colors.grey;
    if (selected.toString() == correct.toString()) return Colors.green;
    return Colors.red;
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

    return Column(
      children: [
        Text(
          "$value",
          style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white),
        ),
      ],
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
          padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.blue : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
                color: selected ? Colors.white : Colors.black),
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

    return Card(
      margin:
      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            HtmlHelper.renderHtml(
              '<span style="font-weight:600;">Q$number. </span>${(q['questionText'] ?? '').toString()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            for (int i = 0; i < options.length; i++)
              optionTile(i, options[i]['text'], selected, optionLetter(correct)),

            const SizedBox(height: 10),

            Text(
              "Your Answer: ${selected ?? '-'}",
              style: TextStyle(
                color: getColor(selected, optionLetter(correct)),
                fontWeight: FontWeight.bold,
              ),
            ),

            Text(
              "Correct Answer: ${optionLetter(correct)}",
              style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            Text(
              "Explanation: ${q['explanationText'] ?? ''}",
              style: const TextStyle(color: Colors.black87),
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
      child: Row(
        children: [

          Text(
            "${optionLetter(index)}. ",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color),
          ),

          Expanded(
            child: HtmlHelper.renderHtml(
              text,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// BUILD SECTION TAB
  Widget buildSectionTab(SectionBean sec) {

    final secQuestions = groupedQuestions[sec.id] ?? [];

    final filteredQuestions = applyFilter(secQuestions);

    return Column(
      children: [

        const SizedBox(height: 10),

        buildFilterBar(),

        const SizedBox(height: 10),

        Expanded(
          child: ListView(
            children: filteredQuestions.map((q) {

              final qid = q['__id'];
              final selected = widget.answers[qid];
              final correctOption = q['correctOption'];

              final number =
                  widget.questions.indexOf(q) + 1;

              return questionCard(
                number,
                q,
                selected,
                correctOption,
              );

            }).toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Exam Result"),
        centerTitle: true,
      ),

      body: Column(
        children: [

          //buildSummary(),

          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.blue,
            tabs: widget.section.map((sec) {
              return Tab(
                text: sec.name ?? "Section",
              );
            }).toList(),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: widget.section.map((sec) {
                return buildSectionTab(sec);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}