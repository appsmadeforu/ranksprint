import 'package:ranksprint/sections/section_bean.dart';
import 'package:ranksprint/sections/section_dao.dart';
import 'package:ranksprint/sections/section_split.dart';

class SectionService {
  final SectionDao _sectionDao = SectionDao();
  static int unlockedSectionLength = 0;
  static int totalQuestionLength = 0;
  static bool isLock = true;
  static int unlockedTime = 0;
  static int lockedTime = 0;

  Future<List<SectionBean>> getSections(String examId, String testId) {
    return _sectionDao.getSectionsOnce(examId, testId);
  }

  SectionSplit getSectionsSplit(List<SectionBean> sections) {
    List<SectionBean> unlocked = sections
        .where((s) => s.switchingAllowed == true)
        .toList();
    List<SectionBean> locked = sections
        .where((s) => s.switchingAllowed == false)
        .toList();

    return SectionSplit(lockedSections: locked, unlockedSections: unlocked);
  }

  static String questionSectionKey(Map<String, dynamic> question) {
    return (question['sectionId'] ??
            question['sectionName'] ??
            question['section'] ??
            question['subject'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
  }

  static List<String> sectionKeys(SectionBean section) {
    final keys = <String>{};
    final rawId = (section.id ?? '').toString().trim().toLowerCase();
    final rawName = (section.name ?? '').toString().trim().toLowerCase();

    if (rawId.isNotEmpty) {
      keys.add(rawId);
    }
    if (rawName.isNotEmpty) {
      keys.add(rawName);
      for (final part in rawName.split(RegExp(r'\s*(?:&|,|/|\band\b)\s*'))) {
        final normalized = part.trim();
        if (normalized.isNotEmpty) {
          keys.add(normalized);
        }
      }
    }

    return keys.toList();
  }

  List<Map<String, dynamic>> rearrangeQuestionsLikeDrawer({
    required List<Map<String, dynamic>> questions,
    required List<SectionBean> sections,
  }) {
    unlockedSectionLength = 0;
    totalQuestionLength = questions.isEmpty ? 0 : questions.length - 1;
    unlockedTime = 0;
    lockedTime = 0;
    isLock = true;

    if (questions.isEmpty) {
      return questions;
    }

    if (sections.isEmpty) {
      unlockedSectionLength = questions.length - 1;
      return questions;
    }

    final sectionService = SectionService();
    final sectionSplit = sectionService.getSectionsSplit(sections);

    final unlockedSections = sectionSplit.unlockedSections;
    final lockedSections = sectionSplit.lockedSections;

    // Group questions by sectionId
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final q in questions) {
      final sectionKey = questionSectionKey(q);
      if (sectionKey.isEmpty) continue;
      grouped.putIfAbsent(sectionKey, () => []);
      grouped[sectionKey]!.add(q);
    }

    final List<Map<String, dynamic>> arranged = [];

    // 1️⃣ Add unlocked section questions first
    for (final section in unlockedSections) {
      final keys = sectionKeys(section);
      unlockedTime += section.sectionDurationMinutes ?? 0;
      for (final key in keys) {
        if (grouped.containsKey(key)) {
          arranged.addAll(grouped.remove(key)!);
        }
      }
    }
    unlockedSectionLength = arranged.isEmpty ? questions.length - 1 : arranged.length - 1;

    // 2️⃣ Then add locked section questions
    for (final section in lockedSections) {
      final keys = sectionKeys(section);
      lockedTime += section.sectionDurationMinutes ?? 0;
      for (final key in keys) {
        if (grouped.containsKey(key)) {
          arranged.addAll(grouped.remove(key)!);
        }
      }
    }
    if (grouped.isNotEmpty) {
      for (final leftovers in grouped.values) {
        arranged.addAll(leftovers);
      }
    }
    if (arranged.isEmpty) {
      unlockedSectionLength = questions.length - 1;
      totalQuestionLength = questions.length - 1;
      return questions;
    }

    totalQuestionLength = arranged.length - 1;

    return arranged;
  }
}
