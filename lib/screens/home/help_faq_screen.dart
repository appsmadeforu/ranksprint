import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HelpFaqScreen extends StatelessWidget {
  const HelpFaqScreen({super.key});

  /// Convert HTML → Plain Text
  String htmlToPlainText(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Help & FAQ")),
      body: StreamBuilder<QuerySnapshot>(
        // remove the `where` temporarily for debugging; uncomment once data is confirmed
        stream: FirebaseFirestore.instance
            .collection('helpFaqs')
            //.where('isActive', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('HelpFaqScreen snapshot error: ${snapshot.error}');
            return const Center(child: Text("Error loading FAQs"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docsList = snapshot.data?.docs;
          debugPrint('HelpFaqScreen got ${docsList?.length ?? 0} documents');

          if (docsList == null || docsList.isEmpty) {
            return const Center(child: Text("No FAQs available"));
          }

          /// Convert docs safely
          final docs = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data;
          }).toList();

          /// Sort by priority
          docs.sort(
            (a, b) => ((a['priority'] ?? 0) as num).compareTo(
              (b['priority'] ?? 0) as num,
            ),
          );

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = docs[i];
              final question = data['question'] ?? "";
              final answerHtml = data['answer'] ?? "";
              final answer = htmlToPlainText(answerHtml);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ExpansionTile(
                  title: Text(
                    question,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        answer,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
