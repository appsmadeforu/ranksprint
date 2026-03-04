import 'package:ranksprint/sections/section_bean.dart';
import 'package:ranksprint/sections/section_dao.dart';
import 'package:ranksprint/sections/section_split.dart';

class SectionService {
  final SectionDao _sectionDao = SectionDao();
  static int unlockedSectionLength = 0;
  static bool isLock = true;

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

  List<Map<String, dynamic>> rearrangeQuestionsLikeDrawer({
    required List<Map<String, dynamic>> questions,
    required List<SectionBean> sections,
  }) {
    final sectionService = SectionService();
    final sectionSplit = sectionService.getSectionsSplit(sections);

    final unlockedSections = sectionSplit.unlockedSections;
    final lockedSections = sectionSplit.lockedSections;

    // Group questions by sectionId
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final q in questions) {
      final sectionId = q['sectionId']?.toString();
      if (sectionId == null) continue;
      grouped.putIfAbsent(sectionId, () => []);
      grouped[sectionId]!.add(q);
    }

    final List<Map<String, dynamic>> arranged = [];

    // 1️⃣ Add unlocked section questions first
    for (final section in unlockedSections) {
      final sectionId = section.id?.toString();
      if (sectionId != null && grouped.containsKey(sectionId)) {
        arranged.addAll(grouped[sectionId]!);
      }
    }
    unlockedSectionLength = arranged.length - 1;

    // 2️⃣ Then add locked section questions
    for (final section in lockedSections) {
      final sectionId = section.id?.toString();
      if (sectionId != null && grouped.containsKey(sectionId)) {
        arranged.addAll(grouped[sectionId]!);
      }
    }

    return arranged;
  }
}
