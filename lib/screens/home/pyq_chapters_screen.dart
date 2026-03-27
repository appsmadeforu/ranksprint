import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/content_access_service.dart';
import '../../services/subscription_access_service.dart';
import 'pdf_viewer_screen.dart';
import 'subscription_screen.dart';

class PyqChaptersScreen extends StatefulWidget {
  final String examId;
  final String subjectId;
  final String subjectName;

  const PyqChaptersScreen({
    super.key,
    required this.examId,
    required this.subjectId,
    required this.subjectName,
  });

  @override
  State<PyqChaptersScreen> createState() => _PyqChaptersScreenState();
}

class _PyqChaptersScreenState extends State<PyqChaptersScreen> {
  Set<String> _activePlanIds = <String>{};
  List<String> _examSubscriptionPlanIds = const [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAccess() async {
    final activePlanIds =
        await SubscriptionAccessService.getCurrentUserActivePlanIds();
    final examDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(widget.examId)
        .get();

    if (!mounted) return;

    setState(() {
      _activePlanIds = activePlanIds;
      _examSubscriptionPlanIds =
          SubscriptionAccessService.readPlanIds(examDoc.data());
    });
  }

  Stream<QuerySnapshot> _chaptersStream() {
    return ContentAccessService.publishedPyqChaptersQuery(
      examId: widget.examId,
      subjectId: widget.subjectId,
    ).snapshots();
  }

  void _openSubscription({
    required List<String> requiredPlanIds,
    required String itemLabel,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubscriptionScreen(
          initialExamId: widget.examId,
          initialPlanId: requiredPlanIds.isNotEmpty ? requiredPlanIds.first : null,
          lockedItemLabel: itemLabel,
          lockedItemType: 'pyq',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(widget.subjectName),
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

          final docs = snapshot.data!.docs
              .cast<QueryDocumentSnapshot<Map<String, dynamic>>>()
              .where(_isPublishedChapter)
              .toList()
            ..sort(ContentAccessService.compareCreatedAtAsc);

          final filteredDocs = docs.where((doc) {
            if (_searchQuery.trim().isEmpty) return true;
            final data = doc.data();
            final title = (data['name'] ?? data['title'] ?? '').toString();
            return title.toLowerCase().contains(_searchQuery.trim().toLowerCase());
          }).toList();
          final allPdfUrls = filteredDocs
              .map((document) {
                final data = document.data();
                return (data['pdfUrl'] ?? data['notesPdfUrl'] ?? '').toString();
              })
              .where((url) => url.isNotEmpty)
              .toList(growable: false);

          if (docs.isEmpty) {
            return const Center(child: Text('No chapters available'));
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCE4F5)),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search lessons...',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF64748B),
                    ),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF64748B),
                            ),
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              if (filteredDocs.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: Text('No lessons found')),
                )
              else
                ...List.generate(filteredDocs.length, (index) {
                  final doc = filteredDocs[index];
              final data = doc.data() as Map<String, dynamic>? ?? {};

              final title =
                  data['name'] ?? data['title'] ?? 'Chapter ${index + 1}';
              final pdfUrl = data['pdfUrl'] ?? data['notesPdfUrl'] ?? '';
              final qCount = data['questionCount']?.toString() ?? '';
              final access = ContentAccessService.resolveAccess(
                itemData: data,
                examPlanIds: _examSubscriptionPlanIds,
                activePlanIds: _activePlanIds,
              );
              final requiredPlanIds = access.requiredPlanIds;
              final isLocked = access.isLocked;

                   return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Material(
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.white,
                      elevation: 3,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        splashColor: const Color(0xFF2F6FEB).withValues(alpha: 0.1),
                        onTap: () {
                          if (isLocked) {
                            _openSubscription(
                              requiredPlanIds: requiredPlanIds,
                              itemLabel: title.toString(),
                            );
                            return;
                          }

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
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: isLocked
                                      ? Colors.grey.shade200
                                      : const Color(0xFFEFF3FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: isLocked
                                      ? const Icon(
                                          Icons.lock_outline,
                                          color: Colors.grey,
                                        )
                                      : Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: Color(0xFF2F6FEB),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 16),
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
                                        '$qCount papers available',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                isLocked ? Icons.lock_outline : Icons.chevron_right,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  bool _isPublishedChapter(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return ContentAccessService.isVisibleNow(data);
  }
}
