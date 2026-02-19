import 'package:cloud_firestore/cloud_firestore.dart';

class FullFirestoreSeeder {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> seed() async {
    print("🚀 FULL DATABASE SEED STARTED");

    final batch = _db.batch();

    await _seedAdmin(batch);
    await _seedSubscription(batch);
    await _seedExamStructure(batch);
    await _seedJeePracticeTest(batch); // 👈 NEW PRACTICE TEST
    await _seedUser(batch);

    await batch.commit();

    print("✅ FULL DATABASE SEED COMPLETED");
  }

  // =====================================================
  // ADMIN
  // =====================================================

  static Future<void> _seedAdmin(WriteBatch batch) async {
    batch.set(_db.collection("admins").doc("admin_001"), {
      "name": "Super Admin",
      "email": "admin@ranksprint.ai",
      "role": "super_admin",
      "permissions": [
        "manage_exams",
        "manage_tests",
        "manage_subscriptions"
      ],
      "createdAt": Timestamp.now(),
    });
  }

  // =====================================================
  // SUBSCRIPTION
  // =====================================================

  static Future<void> _seedSubscription(WriteBatch batch) async {
    batch.set(_db.collection("subscriptionPlans").doc("plan_yearly"), {
      "name": "Yearly Plan",
      "durationDays": 365,
      "price": 2999,
      "examsIncluded": ["jee"],
      "isActive": true,
    });
  }

  // =====================================================
  // MULTIPLE EXAMS
  // =====================================================

  static Future<void> _seedExamStructure(WriteBatch batch) async {
    final now = Timestamp.now();

    final List<Map<String, dynamic>> exams = [
      {
        "id": "jee",
        "name": "JEE Main",
        "category": "Engineering"
      },
      {
        "id": "mhtcet",
        "name": "MHT-CET",
        "category": "Engineering"
      },
    ];

    for (Map<String, dynamic> exam in exams) {
      final String examId = exam["id"] as String;
      final String examName = exam["name"] as String;

      final examRef = _db.collection("exams").doc(examId);

      batch.set(examRef, {
        "name": examName,
        "shortCode": examId,
        "description": "$examName Mock Platform",
        "category": exam["category"],
        "year": 2026,
        "isActive": true,
        "subscriptionPlanIds": ["plan_yearly"],
        "createdAt": now,
      });
    }
  }

  // =====================================================
  // JEE PRACTICE TEST (10 QUESTIONS)
  // =====================================================

  static Future<void> _seedJeePracticeTest(WriteBatch batch) async {
    final now = Timestamp.now();
    final examRef = _db.collection("exams").doc("jee");
    final testRef = examRef.collection("tests").doc("jee_practice_01");

    // ---------------- TEST ----------------

    batch.set(testRef, {
      "name": "JEE Main Practice Test 1",
      "type": "practice",
      "status": "published",
      "isDemo": false,
      "isLocked": false,
      "totalQuestions": 10,
      "totalMarks": 40,
      "marksPerQuestion": 4,
      "negativeMarkingEnabled": true,
      "negativeMarks": 1,
      "attemptLimit": 5,
      "randomizeQuestions": false,
      "randomizeOptions": true,
      "timing": {
        "totalDurationMinutes": 30,
        "serverEnforced": true,
      },
      "createdAt": now,
    });

    // ---------------- SECTIONS ----------------

    final List<Map<String, String>> sections = [
      {"id": "physics", "name": "Physics"},
      {"id": "chemistry", "name": "Chemistry"},
      {"id": "maths", "name": "Mathematics"},
    ];

    for (int i = 0; i < sections.length; i++) {
      batch.set(
          testRef.collection("sections").doc(sections[i]["id"]!), {
        "name": sections[i]["name"],
        "order": i + 1,
        "navigationRule": "free",
        "switchingAllowed": true,
      });
    }

    // ---------------- QUESTIONS ----------------

    final List<Map<String, dynamic>> questions = [
      {
        "sectionId": "physics",
        "subject": "Physics",
        "text": "What is the SI unit of force?",
        "options": ["Newton", "Joule", "Pascal", "Watt"],
        "answer": "A"
      },
      {
        "sectionId": "physics",
        "subject": "Physics",
        "text": "Acceleration due to gravity on Earth is?",
        "options": ["9.8 m/s²", "10 m/s²", "8.9 m/s²", "12 m/s²"],
        "answer": "A"
      },
      {
        "sectionId": "chemistry",
        "subject": "Chemistry",
        "text": "Atomic number represents number of?",
        "options": ["Protons", "Neutrons", "Electrons", "Atoms"],
        "answer": "A"
      },
      {
        "sectionId": "chemistry",
        "subject": "Chemistry",
        "text": "pH less than 7 means?",
        "options": ["Acidic", "Basic", "Neutral", "Salt"],
        "answer": "A"
      },
      {
        "sectionId": "maths",
        "subject": "Mathematics",
        "text": "Derivative of x² is?",
        "options": ["2x", "x", "x²", "1"],
        "answer": "A"
      },
      {
        "sectionId": "maths",
        "subject": "Mathematics",
        "text": "sin(90°) equals?",
        "options": ["1", "0", "-1", "0.5"],
        "answer": "A"
      },
      {
        "sectionId": "physics",
        "subject": "Physics",
        "text": "Velocity is a vector because it has?",
        "options": ["Magnitude", "Direction", "Mass", "Speed"],
        "answer": "B"
      },
      {
        "sectionId": "chemistry",
        "subject": "Chemistry",
        "text": "Avogadro number equals?",
        "options": ["6.022×10²³", "3.14", "9.8", "1.6×10⁻¹⁹"],
        "answer": "A"
      },
      {
        "sectionId": "maths",
        "subject": "Mathematics",
        "text": "Value of π is?",
        "options": ["3.14", "2.17", "4.13", "1.41"],
        "answer": "A"
      },
      {
        "sectionId": "maths",
        "subject": "Mathematics",
        "text": "log10(100) equals?",
        "options": ["2", "1", "10", "100"],
        "answer": "A"
      },
    ];

    for (int i = 0; i < questions.length; i++) {
      final Map<String, dynamic> q = questions[i];
      final List<String> options =
          (q["options"] as List<dynamic>).cast<String>();

      batch.set(testRef.collection("questions").doc("q${i + 1}"), {
        "questionText": q["text"],
        "subject": q["subject"],
        "sectionId": q["sectionId"],
        "chapter": "Practice",
        "difficulty": "medium",
        "marks": 4,
        "negativeMarks": 1,
        "options": [
          {"id": "A", "text": options[0]},
          {"id": "B", "text": options[1]},
          {"id": "C", "text": options[2]},
          {"id": "D", "text": options[3]},
        ],
        "correctOption": q["answer"],
        "explanationText": "Basic concept question.",
        "createdAt": now,
      });
    }
  }

  // =====================================================
  // USER
  // =====================================================

  static Future<void> _seedUser(WriteBatch batch) async {
    batch.set(_db.collection("users").doc("user_001"), {
      "name": "Test User",
      "email": "test@ranksprint.ai",
      "activeExam": "jee",
      "selectedExams": ["jee"],
      "createdAt": Timestamp.now(),
    });
  }
}
