import 'package:flutter/material.dart';
import '../../widgets/top_header.dart';
import 'main_navigation.dart';

class TestHistoryScreen extends StatelessWidget {
  const TestHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: null,
              userExamIds: const [],
              onExamChanged: (_) {},
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Test History (Mockup)',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
      // bottomNavigationBar removed
    );
  }
}
