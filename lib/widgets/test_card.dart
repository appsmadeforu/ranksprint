import 'package:flutter/material.dart';

class TestCard extends StatelessWidget {
  final String title;
  final String duration;
  final String marks;
  final String attempts;
  final String buttonText;

  const TestCard({
    super.key,
    required this.title,
    required this.duration,
    required this.marks,
    required this.attempts,
    required this.buttonText,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("$duration • $marks marks"),
            const SizedBox(height: 8),
            Text("Attempts: $attempts"),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () {},
                child: Text(buttonText),
              ),
            )
          ],
        ),
      ),
    );
  }
}
