import 'package:cloud_firestore/cloud_firestore.dart';

class SectionBean {
  String? id;
  DateTime? createdAt;
  String? name;
  String? navigationRule;
  double? negativeMarksOverride;
  int? order;
  int? sectionDurationMinutes;
  bool? switchingAllowed;
  int? totalMarks;
  int? totalQuestion;

  SectionBean({
    this.id,
    this.createdAt,
    this.name,
    this.navigationRule,
    this.negativeMarksOverride,
    this.order,
    this.sectionDurationMinutes,
    this.switchingAllowed,
    this.totalMarks,
    this.totalQuestion,
  });

  /// Create object from JSON
  factory SectionBean.fromJson(Map<String, dynamic> json) {
    return SectionBean(
      id: json['id'],
      createdAt: json['createdAt'] != null
          ? json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.parse(json['createdAt'])
          : null,
      name: json['name'],
      navigationRule: json['navigationRule'],
      negativeMarksOverride: json['negativeMarksOverride'],
      order: json['order'],
      sectionDurationMinutes: json['sectionDurationMinutes'],
      switchingAllowed: json['switchingAllowed'],
      totalMarks: json['totalMarks'],
      totalQuestion: json['totalQuestion'],
    );
  }

  /// Convert object to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt?.toIso8601String(),
      'name': name,
      'navigationRule': navigationRule,
      'negativeMarksOverride': negativeMarksOverride,
      'order': order,
      'sectionDurationMinutes': sectionDurationMinutes,
      'switchingAllowed': switchingAllowed,
      'totalMarks': totalMarks,
      'totalQuestion': totalQuestion,
    };
  }

  /// Copy with modification (very useful in state management)
  SectionBean copyWith({
    String? id,
    DateTime? createdAt,
    String? name,
    String? navigationRule,
    double? negativeMarksOverride,
    int? order,
    int? sectionDurationMinutes,
    bool? switchingAllowed,
    int? totalMarks,
    int? totalQuestion,
  }) {
    return SectionBean(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      name: name ?? this.name,
      navigationRule: navigationRule ?? this.navigationRule,
      negativeMarksOverride:
      negativeMarksOverride ?? this.negativeMarksOverride,
      order: order ?? this.order,
      sectionDurationMinutes:
      sectionDurationMinutes ?? this.sectionDurationMinutes,
      switchingAllowed: switchingAllowed ?? this.switchingAllowed,
      totalMarks: totalMarks ?? this.totalMarks,
      totalQuestion: totalQuestion ?? this.totalQuestion,
    );
  }

  @override
  String toString() {
    return '''
SectionBean(
  id: $id,
  createdAt: $createdAt,
  name: $name,
  navigationRule: $navigationRule,
  negativeMarksOverride: $negativeMarksOverride,
  order: $order,
  sectionDurationMinutes: $sectionDurationMinutes,
  switchingAllowed: $switchingAllowed,
  totalMarks: $totalMarks,
  totalQuestion: $totalQuestion
)
''';
  }
}