import 'package:ranksprint/sections/section_bean.dart';
import 'package:ranksprint/sections/section_dao.dart';
import 'package:ranksprint/sections/section_split.dart';

class SectionService {
  final SectionDao _sectionDao = SectionDao();

  Future<List<SectionBean>> getSections(String examId, String testId) {
    return _sectionDao.getSectionsOnce(examId, testId);
  }

  SectionSplit getSectionsSplit(List<SectionBean> sections) {
    List<SectionBean> unlocked = sections.where((s) => s.switchingAllowed == true).toList();
    List<SectionBean> locked = sections.where((s) => s.switchingAllowed == false).toList();

      return SectionSplit(
        lockedSections: locked,
        unlockedSections: unlocked,
      );
    }
}