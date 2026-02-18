import 'package:flutter/material.dart';
import '../../widgets/test_card.dart';

class TestsScreen extends StatelessWidget {
  const TestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("UPSC CSE")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          TestCard(
            title: "UPSC Prelims Mock Test #45",
            duration: "120 min",
            marks: "200",
            attempts: "2/3",
            buttonText: "Attempt",
          ),
          TestCard(
            title: "General Studies Paper I",
            duration: "150 min",
            marks: "250",
            attempts: "1/2",
            buttonText: "Reattempt",
          ),
        ],
      ),
    );
  }
}
