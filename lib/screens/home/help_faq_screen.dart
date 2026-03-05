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
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2F6FEB),
        centerTitle: true,
        title: const Text(
          "Help & FAQ",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('helpFaqs').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Error loading FAQs"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docsList = snapshot.data?.docs;

          if (docsList == null || docsList.isEmpty) {
            return const Center(child: Text("No FAQs available"));
          }

          final docs = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data;
          }).toList();

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

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    color: Colors.white,
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 6,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          20,
                        ),
                        iconColor: const Color(0xFF2F6FEB),
                        collapsedIconColor: Colors.grey,
                        title: Text(
                          question,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F6FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              answer,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
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
}
