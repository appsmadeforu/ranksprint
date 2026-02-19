import 'package:flutter/material.dart';

class TestRunnerScreen extends StatelessWidget {
  final String examId;
  final String testId;

  const TestRunnerScreen({super.key, required this.examId, required this.testId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Runner')),
      body: const Center(child: Text('Test Runner (placeholder)')),
    );
  }
}
