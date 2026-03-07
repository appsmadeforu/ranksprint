import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pdf_viewer_screen.dart';

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
      backgroundColor: const Color(0xFFF5F6FA),
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

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>? ?? {};

              final title =
                  data['name'] ?? data['title'] ?? 'Chapter ${index + 1}';
              final pdfUrl = data['pdfUrl'] ?? data['notesPdfUrl'] ?? '';
              final qCount = data['questionCount']?.toString() ?? '';

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

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Material(
                  borderRadius: BorderRadius.circular(18),
                  color: Colors.white,
                  elevation: 3,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    splashColor: const Color(0xFF2F6FEB).withOpacity(0.1),
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
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          // Left icon box
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF3FF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Color(0xFF2F6FEB),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Text content
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (qCount.isNotEmpty)
                                  Text(
                                    "$qCount Questions available",
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          const Icon(Icons.chevron_right, color: Colors.grey),
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
