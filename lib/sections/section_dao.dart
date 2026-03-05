import 'package:ranksprint/sections/section_bean.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SectionDao {
  Stream<List<SectionBean>> streamSections(
      String examId, String testId) {
    return FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .collection('tests')
        .doc(testId)
        .collection('sections')
        .orderBy('order')
        .snapshots()
        .map((querySnapshot) {
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;

        return SectionBean.fromJson(data);
      }).toList();
    });
  }


  Future<List<SectionBean>> getSectionsOnce(
      String examId, String testId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .collection('tests')
        .doc(testId)
        .collection('sections')
        .orderBy('order')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return SectionBean.fromJson(data);
    }).toList();
  }
}