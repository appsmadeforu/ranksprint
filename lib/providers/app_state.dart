import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {

  String? _selectedExamId;

  String? get selectedExamId => _selectedExamId;

  void setSelectedExam(String examId) {
    _selectedExamId = examId;
    notifyListeners();
  }

  void clearExam() {
    _selectedExamId = null;
    notifyListeners();
  }
}
