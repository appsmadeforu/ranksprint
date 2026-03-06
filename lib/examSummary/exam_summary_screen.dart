import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ExamResultScreen extends StatelessWidget {
  final List questions;
  final Map answers;
  final int correct;
  final int incorrect;
  final int unanswered;

  const ExamResultScreen({
    super.key,
    required this.questions,
    required this.answers,
    required this.correct,
    required this.incorrect,
    required this.unanswered,
  });

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

  Color getColor(selected, correct) {
    if (selected == null) return Colors.grey;
    if (selected.toString() == correct.toString()) return Colors.green;
    return Colors.red;
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

          /// SUMMARY CARD
          _buildSummary(),

          const SizedBox(height: 10),

          /// QUESTION LIST
          Expanded(
            child: ListView.builder(
              itemCount: questions.length,
              itemBuilder: (context, index) {

                final q = questions[index];
                final qid = q['__id'];

                final selected = answers[qid];
                final correctOption = q['correctOption'];

                return _questionCard(
                  index + 1,
                  q,
                  selected,
                  correctOption,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [

          _stat("Correct", correct, Colors.green),

          _stat("Incorrect", incorrect, Colors.red),

          _stat("Unanswered", unanswered, Colors.grey),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          "$value",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label),
      ],
    );
  }

  Widget _questionCard(
      int number,
      dynamic q,
      dynamic selected,
      dynamic correct,
      ) {

    final options = q['options'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            /// QUESTION
            Text(
              "Q$number. ${q['questionText']}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            /// OPTIONS
            for (int i = 0; i < options.length; i++)
              _optionTile(
                i,
                options[i]['text'],
                selected,
                correct,
              ),

            const SizedBox(height: 10),

            /// ANSWER SUMMARY
            Text(
              "Your Answer: ${selected}",
              style: TextStyle(
                color: getColor(selected, optionLetter(correct)),
                fontWeight: FontWeight.bold,
              ),
            ),

            Text(
              "Correct Answer: ${optionLetter(correct)}",
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),

            Text(
              "Explanation:  ${q['explanationText']}",
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(
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
              color: color,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}