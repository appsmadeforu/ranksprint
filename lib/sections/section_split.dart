import 'package:ranksprint/sections/section_bean.dart';

class SectionSplit {
  final List<SectionBean> lockedSections;
  final List<SectionBean> unlockedSections;

  SectionSplit({
    required this.lockedSections,
    required this.unlockedSections,
  });
}