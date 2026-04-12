import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/content_access_service.dart';
import '../../widgets/offline_state.dart';
import 'pdf_viewer_screen.dart';

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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Set<String> _favoriteLessonIds = <String>{};
  int _reloadTick = 0;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final raw = doc.data()?['favoritePyqLessons'];
      final favorites = raw is Iterable
          ? raw
                .map((value) => value.toString())
                .where((value) => value.isNotEmpty)
                .toSet()
          : <String>{};
      if (!mounted) return;
      setState(() {
        _favoriteLessonIds = favorites;
      });
    } catch (_) {
      if (!mounted) return;
    }
  }

  void _retryLoad() {
    if (!mounted) return;
    setState(() {
      _reloadTick++;
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _chaptersStream() {
    return FirebaseFirestore.instance
        .collection('exams')
        .doc(widget.examId)
        .collection('pyqs')
        .doc(widget.subjectId)
        .collection('chapters')
        .snapshots();
  }

  String _favoriteLessonKey(String lessonId) {
    return '${widget.examId}|${widget.subjectId}|$lessonId';
  }

  String _chapterTitle(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    final name = (data['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final title = (data['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    return fallback;
  }

  bool _isFavoriteLesson(String lessonId) {
    return _favoriteLessonIds.contains(_favoriteLessonKey(lessonId));
  }

  Future<void> _toggleFavorite(String lessonId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to save favourites')),
      );
      return;
    }

    final favoriteKey = _favoriteLessonKey(lessonId);
    final wasFavorite = _favoriteLessonIds.contains(favoriteKey);

    setState(() {
      if (wasFavorite) {
        _favoriteLessonIds.remove(favoriteKey);
      } else {
        _favoriteLessonIds.add(favoriteKey);
      }
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'favoritePyqLessons': wasFavorite
            ? FieldValue.arrayRemove([favoriteKey])
            : FieldValue.arrayUnion([favoriteKey]),
      }, SetOptions(merge: true));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoriteLessonIds.add(favoriteKey);
        } else {
          _favoriteLessonIds.remove(favoriteKey);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update favourite right now')),
      );
    }
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        key: ValueKey('pyq-chapters-${widget.subjectId}-$_reloadTick'),
        stream: _chaptersStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return OfflineState(
              message:
                  'Could not load PYQ details. Please check your connection and try again.',
              onRetry: _retryLoad,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs.toList()
             ..sort(ContentAccessService.compareCreatedAtAsc);

          final filteredDocs = docs.where((doc) {
            if (_searchQuery.trim().isEmpty) return true;
            final data = doc.data();
            final title = _chapterTitle(data, fallback: doc.id);
            return title.toLowerCase().contains(_searchQuery.trim().toLowerCase());
          }).toList()
            ..sort((a, b) {
              final aFavorite = _isFavoriteLesson(a.id);
              final bFavorite = _isFavoriteLesson(b.id);
              if (aFavorite != bFavorite) {
                return aFavorite ? -1 : 1;
              }
              return ContentAccessService.compareCreatedAtAsc(a, b);
            });
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
                  final data = doc.data();

                  final title = _chapterTitle(
                    data,
                    fallback: 'Chapter ${index + 1}',
                  );
                  final pdfUrl = data['pdfUrl'] ?? data['notesPdfUrl'] ?? '';
                  final qCount = data['questionCount']?.toString() ?? '';
                  final isFavorite = _isFavoriteLesson(doc.id);
                  final cardColor = Colors.white;
                  final iconTileColor = const Color(0xFFEFF3FF);
                  final titleColor = const Color(0xFF111827);
                  final metaColor = Colors.grey;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Material(
                      borderRadius: BorderRadius.circular(18),
                      color: cardColor,
                      elevation: isFavorite ? 4 : 3,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        splashColor: const Color(0xFF2F6FEB).withValues(alpha: 0.1),
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
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isFavorite
                                  ? const Color(0xFFD7E3FF)
                                  : const Color(0x00000000),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: iconTileColor,
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
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: titleColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    if (qCount.isNotEmpty)
                                      Text(
                                        '$qCount questions available',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: metaColor,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                child: IconButton(
                                  onPressed: () => _toggleFavorite(doc.id),
                                  tooltip: isFavorite
                                      ? 'Remove from favourites'
                                      : 'Add to favourites',
                                  icon: Icon(
                                    isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: isFavorite
                                        ? const Color(0xFF2F6FEB)
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
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

}