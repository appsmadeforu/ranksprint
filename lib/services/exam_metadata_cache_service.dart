import 'package:cloud_firestore/cloud_firestore.dart';

import '../sections/section_bean.dart';
import '../sections/section_service.dart';

class ExamMetadataCacheService {
  ExamMetadataCacheService._();

  static final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>>
      _testDocFutures =
      <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};
  static final Map<String, Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>
      _questionFutures =
      <String, Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>{};
  static final Map<String, Future<Map<String, String>>> _sectionNameFutures =
      <String, Future<Map<String, String>>>{};
  static final Map<String, Future<List<SectionBean>>> _sectionBeansFutures =
      <String, Future<List<SectionBean>>>{};

  static Future<DocumentSnapshot<Map<String, dynamic>>?> getTestDoc(
    String examId,
    String testId,
  ) async {
    if (examId.isEmpty || testId.isEmpty) return null;
    final key = '$examId|$testId';
    try {
      return await _testDocFutures.putIfAbsent(
        key,
        () => FirebaseFirestore.instance
            .collection('exams')
            .doc(examId)
            .collection('tests')
            .doc(testId)
            .get(),
      );
    } catch (_) {
      _testDocFutures.remove(key);
      return null;
    }
  }

  static Future<String?> getTestName(String examId, String testId) async {
    final doc = await getTestDoc(examId, testId);
    return (doc?.data()?['name'] ?? '').toString();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getQuestions(
    String examId,
    String testId,
  ) async {
    if (examId.isEmpty || testId.isEmpty) return const [];
    final key = '$examId|$testId';
    try {
      return await _questionFutures.putIfAbsent(
        key,
        () async {
          final snap = await FirebaseFirestore.instance
              .collection('exams')
              .doc(examId)
              .collection('tests')
              .doc(testId)
              .collection('questions')
              .get();
          return snap.docs;
        },
      );
    } catch (_) {
      _questionFutures.remove(key);
      return const [];
    }
  }

  static Future<Map<String, String>> getSectionNames(
    String examId,
    String testId,
  ) async {
    if (examId.isEmpty || testId.isEmpty) return const {};
    final key = '$examId|$testId';
    try {
      return await _sectionNameFutures.putIfAbsent(
        key,
        () async {
          final snap = await FirebaseFirestore.instance
              .collection('exams')
              .doc(examId)
              .collection('tests')
              .doc(testId)
              .collection('sections')
              .get();
          final names = <String, String>{};
          for (final doc in snap.docs) {
            final name = (doc.data()['name'] ?? '').toString().trim();
            if (name.isNotEmpty) {
              names[doc.id] = name;
            }
          }
          return names;
        },
      );
    } catch (_) {
      _sectionNameFutures.remove(key);
      return const {};
    }
  }

  static Future<List<SectionBean>> getSectionBeans(
    String examId,
    String testId,
  ) async {
    if (examId.isEmpty || testId.isEmpty) return const [];
    final key = '$examId|$testId';
    try {
      return await _sectionBeansFutures.putIfAbsent(
        key,
        () => SectionService().getSections(examId, testId),
      );
    } catch (_) {
      _sectionBeansFutures.remove(key);
      return const [];
    }
  }

  static void invalidate(String examId, String testId) {
    if (examId.isEmpty || testId.isEmpty) return;
    final key = '$examId|$testId';
    _testDocFutures.remove(key);
    _questionFutures.remove(key);
    _sectionNameFutures.remove(key);
    _sectionBeansFutures.remove(key);
  }
}
