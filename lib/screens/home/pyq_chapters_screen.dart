import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ranksprint/screens/home/pdf_viewer_screen.dart';

class PyqChaptersScreen extends StatelessWidget {
  final String examId;
  final String subjectId;
  final String subjectName;

  const PyqChaptersScreen({
    super.key,
    required this.examId,
    required this.subjectId,
    required this.subjectName,
  });

  Stream<QuerySnapshot> _chaptersStream() {
    return FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .collection('pyqs')
        .doc(subjectId)
        .collection('chapters')
        .orderBy('createdAt')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(subjectName),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _chaptersStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('No chapters available'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>? ?? {};

              final title =
                  data['name'] ?? data['title'] ?? 'Chapter ${index + 1}';
              final pdfUrl = (data['pdfUrl'] ?? data['notesPdfUrl'] ?? '')
                  .toString();
              final qCount = data['questionCount']?.toString() ?? '';

              /// ✅ FIXED: force List<String>
              final List<String> allPdfUrls = docs
                  .map((document) {
                    final documentData =
                        document.data() as Map<String, dynamic>? ?? {};
                    return (documentData['pdfUrl'] ??
                            documentData['notesPdfUrl'] ??
                            '')
                        .toString();
                  })
                  .where((url) => url.isNotEmpty)
                  .toList();

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFEFF3FF),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Color(0xFF2F3E8F)),
                    ),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: qCount.isNotEmpty
                      ? Text(
                          '$qCount papers available',
                          style: const TextStyle(color: Colors.grey),
                        )
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (pdfUrl.isNotEmpty && allPdfUrls.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfViewerScreen(
                            pdfUrl: pdfUrl,
                            title: title,
                            pdfUrls: allPdfUrls,
                            currentIndex: allPdfUrls.indexOf(pdfUrl),
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PDF not available')),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
