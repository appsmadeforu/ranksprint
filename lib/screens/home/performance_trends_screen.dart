import 'package:flutter/material.dart';
import '../../widgets/top_header.dart';
import 'main_navigation.dart';

class PerformanceTrendsScreen extends StatelessWidget {
  const PerformanceTrendsScreen({super.key});

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
                  'Performance Trends (Mockup)',
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
