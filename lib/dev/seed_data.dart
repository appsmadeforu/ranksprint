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
  await _seedAdditionalFreeTests(batch); // 👈 ADDITIONAL FREE/DEMO TESTS
  await _seedUsers(batch);
  await _seedPyqs(batch);

    await batch.commit();

    print("✅ FULL DATABASE SEED COMPLETED");
  }

  // =====================================================
  // ADDITIONAL FREE / DEMO TESTS FOR OTHER EXAMS
  // =====================================================

  static Future<void> _seedAdditionalFreeTests(WriteBatch batch) async {
    final now = Timestamp.now();

    // NEET demo test
    final neetExamRef = _db.collection("exams").doc("neet");
    batch.set(neetExamRef, {
      "name": "NEET",
      "shortCode": "neet",
      "description": "NEET Mock Platform",
      "category": "Medical",
      "year": 2026,
      "isActive": true,
      "subscriptionPlanIds": ["plan_yearly"],
      "createdAt": now,
    });

    final neetTestRef = neetExamRef.collection("tests").doc("neet_demo_01");
    batch.set(neetTestRef, {
      "name": "NEET Demo Test 1",
      "type": "demo",
      "status": "published",
      "isPremium": false,
      "isDemo": true,
      "isLocked": false,
      "totalQuestions": 3,
      "totalMarks": 12,
      "marksPerQuestion": 4,
      "negativeMarkingEnabled": true,
      "negativeMarks": 1,
      "attemptLimit": 5,
      "randomizeQuestions": false,
      "randomizeOptions": true,
      "timing": {"totalDurationMinutes": 10, "serverEnforced": true},
      "createdAt": now,
    });

    final neetQuestions = [
      {
        "text": "Which blood cell carries oxygen?",
        "subject": "Biology",
        "sectionId": "biology",
        "options": ["Red blood cells", "White blood cells", "Platelets", "Plasma"],
        "answer": "A",
      },
      {
        "text": "The basic unit of life is?",
        "subject": "Biology",
        "sectionId": "biology",
        "options": ["Atom", "Cell", "Molecule", "Organ"],
        "answer": "B",
      },
      {
        "text": "Which gas is most abundant in air?",
        "subject": "Chemistry",
        "sectionId": "chemistry",
        "options": ["Oxygen", "Hydrogen", "Nitrogen", "Carbon Dioxide"],
        "answer": "C",
      },
    ];

    for (int i = 0; i < neetQuestions.length; i++) {
      final q = neetQuestions[i];
      final opts = (q["options"] as List<dynamic>).cast<String>();
      batch.set(neetTestRef.collection("questions").doc("q${i + 1}"), {
        "questionText": q["text"],
        "subject": q["subject"],
        "sectionId": q["sectionId"],
        "chapter": "Demo",
        "difficulty": "easy",
        "marks": 4,
        "negativeMarks": 1,
        "options": [
          {"id": "A", "text": opts[0]},
          {"id": "B", "text": opts[1]},
          {"id": "C", "text": opts[2]},
          {"id": "D", "text": opts[3]},
        ],
        "correctOption": q["answer"],
        "explanationText": "Demo question.",
        "createdAt": now,
      });
    }

    // SSC demo test
    final sscExamRef = _db.collection("exams").doc("ssc");
    batch.set(sscExamRef, {
      "name": "SSC CGL",
      "shortCode": "ssc",
      "description": "SSC Mock Platform",
      "category": "Government",
      "year": 2026,
      "isActive": true,
      "subscriptionPlanIds": ["plan_yearly"],
      "createdAt": now,
    });

    final sscTestRef = sscExamRef.collection("tests").doc("ssc_demo_01");
    batch.set(sscTestRef, {
      "name": "SSC Demo Test 1",
      "type": "demo",
      "status": "published",
      "isPremium": false,
      "isDemo": true,
      "isLocked": false,
      "totalQuestions": 3,
      "totalMarks": 30,
      "marksPerQuestion": 10,
      "negativeMarkingEnabled": false,
      "attemptLimit": 5,
      "randomizeQuestions": false,
      "randomizeOptions": true,
      "timing": {"totalDurationMinutes": 15, "serverEnforced": true},
      "createdAt": now,
    });

    final sscQuestions = [
      {
        "text": "The capital of India is?",
        "subject": "General Knowledge",
        "sectionId": "gk",
        "options": ["New Delhi", "Mumbai", "Kolkata", "Chennai"],
        "answer": "A",
      },
      {
        "text": "2 + 2 * 2 = ?",
        "subject": "Quant",
        "sectionId": "maths",
        "options": ["6", "8", "4", "2"],
        "answer": "A",
      },
      {
        "text": "Who wrote 'Bhagavad Gita'?",
        "subject": "English",
        "sectionId": "history",
        "options": ["Vyasa", "Valmiki", "Kalidasa", "Tulsidas"],
        "answer": "A",
      },
    ];

    for (int i = 0; i < sscQuestions.length; i++) {
      final q = sscQuestions[i];
      final opts = (q["options"] as List<dynamic>).cast<String>();
      batch.set(sscTestRef.collection("questions").doc("q${i + 1}"), {
        "questionText": q["text"],
        "subject": q["subject"],
        "sectionId": q["sectionId"],
        "chapter": "Demo",
        "difficulty": "easy",
        "marks": 10,
        "negativeMarks": 0,
        "options": [
          {"id": "A", "text": opts[0]},
          {"id": "B", "text": opts[1]},
          {"id": "C", "text": opts[2]},
          {"id": "D", "text": opts[3]},
        ],
        "correctOption": q["answer"],
        "explanationText": "Demo question.",
        "createdAt": now,
      });
    }
  }

  // =====================================================
  // ADMIN
  // =====================================================

  static Future<void> _seedAdmin(WriteBatch batch) async {
    final now = Timestamp.now();
    batch.set(_db.collection("admins").doc("admin_001"), {
      "name": "Super Admin",
      "email": "admin@ranksprint.ai",
      "role": "super_admin",
      "permissions": [
        "manage_exams",
        "manage_tests",
        "manage_subscriptions"
      ],
      "createdAt": now,
    });

    batch.set(_db.collection("admins").doc("admin_002"), {
      "name": "Content Admin",
      "email": "content@ranksprint.ai",
      "role": "content_admin",
      "permissions": ["manage_tests", "publish_tests"],
      "createdAt": now,
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
      "isPremium": false,
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

  static Future<void> _seedUsers(WriteBatch batch) async {
    final now = Timestamp.now();

    final users = [
      {
        "id": "user_001",
        "name": "Alice",
        "email": "alice@example.com",
        "photoURL": null,
        "selectedExams": ["jee", "neet"],
        "activeExam": "jee",
        "subscriptionStatus": "free",
        "subscriptionIds": [],
        "deviceId": "device_a1",
        "isBlocked": false,
      },
      {
        "id": "user_002",
        "name": "Bob",
        "email": "bob@example.com",
        "photoURL": null,
        "selectedExams": ["ssc"],
        "activeExam": "ssc",
        "subscriptionStatus": "paid",
        "subscriptionIds": ["sub_001"],
        "deviceId": "device_b2",
        "isBlocked": false,
      },
      {
        "id": "user_003",
        "name": "Carlos",
        "email": "carlos@example.com",
        "photoURL": null,
        "selectedExams": ["mhtcet"],
        "activeExam": "mhtcet",
        "subscriptionStatus": "free",
        "subscriptionIds": [],
        "deviceId": "device_c3",
        "isBlocked": false,
      },
      {
        "id": "user_004",
        "name": "Deepa",
        "email": "deepa@example.com",
        "photoURL": null,
        "selectedExams": ["neet", "jee"],
        "activeExam": "neet",
        "subscriptionStatus": "paid",
        "subscriptionIds": ["sub_002"],
        "deviceId": "device_d4",
        "isBlocked": false,
      },
      {
        "id": "user_005",
        "name": "Esha",
        "email": "esha@example.com",
        "photoURL": null,
        "selectedExams": ["jee"],
        "activeExam": "jee",
        "subscriptionStatus": "free",
        "subscriptionIds": [],
        "deviceId": "device_e5",
        "isBlocked": false,
      },
      {
        "id": "user_006",
        "name": "Farhan",
        "email": "farhan@example.com",
        "photoURL": null,
        "selectedExams": ["ssc"],
        "activeExam": "ssc",
        "subscriptionStatus": "free",
        "subscriptionIds": [],
        "deviceId": "device_f6",
        "isBlocked": false,
      },
      {
        "id": "user_007",
        "name": "Geeta",
        "email": "geeta@example.com",
        "photoURL": null,
        "selectedExams": ["mhtcet", "jee"],
        "activeExam": "mhtcet",
        "subscriptionStatus": "paid",
        "subscriptionIds": ["sub_003"],
        "deviceId": "device_g7",
        "isBlocked": false,
      },
      {
        "id": "user_008",
        "name": "Harish",
        "email": "harish@example.com",
        "photoURL": null,
        "selectedExams": ["neet"],
        "activeExam": "neet",
        "subscriptionStatus": "free",
        "subscriptionIds": [],
        "deviceId": "device_h8",
        "isBlocked": false,
      },
    ];

    for (final u in users) {
      batch.set(_db.collection("users").doc(u["id"] as String), {
        "name": u["name"],
        "email": u["email"],
        "photoURL": u["photoURL"],
        "selectedExams": u["selectedExams"],
        "activeExam": u["activeExam"],
        "subscriptionStatus": u["subscriptionStatus"],
        "subscriptionIds": u["subscriptionIds"],
        "deviceId": u["deviceId"],
        "isBlocked": u["isBlocked"],
        "createdAt": now,
        "lastLoginAt": now,
      });
    }
  }

  // =====================================================
  // PYQ (Previous Year Questions) SEEDER
  // =====================================================

  static Future<void> _seedPyqs(WriteBatch batch) async {
    final now = Timestamp.now();

    // helper to add chapters for a subject
    void addChapters(CollectionReference<Map<String, dynamic>> chaptersRef, List<Map<String, dynamic>> chapters) {
      for (int i = 0; i < chapters.length; i++) {
        final ch = chapters[i];
        chaptersRef.doc('ch_${i + 1}').set({
          'name': ch['name'],
          'pdfUrl': ch['pdfUrl'] ?? '',
          'questionCount': ch['questionCount'] ?? 0,
          'isLocked': ch['isLocked'] ?? false,
          'status': ch['status'] ?? 'published',
          'createdAt': now,
        });
      }
    }

    // JEE subjects
    final jeeRef = _db.collection('exams').doc('jee');
    final jeePyq = jeeRef.collection('pyqs');
    final jeeSubjects = {
      'physics': [
        {'name': 'Mechanics', 'pdfUrl': 'https://example.com/jee/physics/mechanics.pdf', 'questionCount': 12, 'isLocked': false},
        {'name': 'Optics', 'pdfUrl': 'https://example.com/jee/physics/optics.pdf', 'questionCount': 8, 'isLocked': false},
      ],
      'chemistry': [
        {'name': 'Organic Chemistry', 'pdfUrl': 'https://example.com/jee/chem/org.pdf', 'questionCount': 10, 'isLocked': false},
        {'name': 'Physical Chemistry', 'pdfUrl': 'https://example.com/jee/chem/phys.pdf', 'questionCount': 9, 'isLocked': false},
      ],
      'maths': [
        {'name': 'Calculus', 'pdfUrl': 'https://example.com/jee/math/calculus.pdf', 'questionCount': 15, 'isLocked': false},
        {'name': 'Algebra', 'pdfUrl': 'https://example.com/jee/math/algebra.pdf', 'questionCount': 10, 'isLocked': false},
      ],
    };

    jeeSubjects.forEach((subjectId, chapters) {
      final subjRef = jeePyq.doc(subjectId);
      batch.set(subjRef, {'name': '${subjectId[0].toUpperCase()}${subjectId.substring(1)}'});
      addChapters(subjRef.collection('chapters'), List<Map<String, dynamic>>.from(chapters));
    });

    // NEET subjects
    final neetRef = _db.collection('exams').doc('neet');
    final neetPyq = neetRef.collection('pyqs');
    final neetSubjects = {
      'biology': [
        {'name': 'Human Physiology', 'pdfUrl': 'https://example.com/neet/bio/physiology.pdf', 'questionCount': 20, 'isLocked': false},
        {'name': 'Genetics', 'pdfUrl': 'https://example.com/neet/bio/genetics.pdf', 'questionCount': 12, 'isLocked': false},
      ],
      'chemistry': [
        {'name': 'Inorganic Chemistry', 'pdfUrl': 'https://example.com/neet/chem/inorg.pdf', 'questionCount': 10, 'isLocked': false},
      ],
      'physics': [
        {'name': 'Electrostatics', 'pdfUrl': 'https://example.com/neet/phys/electro.pdf', 'questionCount': 8, 'isLocked': false},
      ],
    };

    neetSubjects.forEach((subjectId, chapters) {
      final subjRef = neetPyq.doc(subjectId);
      batch.set(subjRef, {'name': '${subjectId[0].toUpperCase()}${subjectId.substring(1)}'});
      addChapters(subjRef.collection('chapters'), List<Map<String, dynamic>>.from(chapters));
    });

    // SSC subjects
    final sscRef = _db.collection('exams').doc('ssc');
    final sscPyq = sscRef.collection('pyqs');
    final sscSubjects = {
      'gk': [
        {'name': 'Indian Polity', 'pdfUrl': 'https://example.com/ssc/gk/polity.pdf', 'questionCount': 10, 'isLocked': false},
      ],
      'maths': [
        {'name': 'Arithmetic', 'pdfUrl': 'https://example.com/ssc/math/arithmetic.pdf', 'questionCount': 12, 'isLocked': false},
      ],
    };

    sscSubjects.forEach((subjectId, chapters) {
      final subjRef = sscPyq.doc(subjectId);
      batch.set(subjRef, {'name': '${subjectId[0].toUpperCase()}${subjectId.substring(1)}'});
      addChapters(subjRef.collection('chapters'), List<Map<String, dynamic>>.from(chapters));
    });

    // MHTCET subjects
    final mhtRef = _db.collection('exams').doc('mhtcet');
    final mhtPyq = mhtRef.collection('pyqs');
    final mhtSubjects = {
      'physics': [
        {'name': 'Thermodynamics', 'pdfUrl': 'https://example.com/mht/phys/thermo.pdf', 'questionCount': 8, 'isLocked': false},
      ],
      'chemistry': [
        {'name': 'Physical Chemistry', 'pdfUrl': 'https://example.com/mht/chem/phys.pdf', 'questionCount': 7, 'isLocked': false},
      ],
    };

    mhtSubjects.forEach((subjectId, chapters) {
      final subjRef = mhtPyq.doc(subjectId);
      batch.set(subjRef, {'name': '${subjectId[0].toUpperCase()}${subjectId.substring(1)}'});
      addChapters(subjRef.collection('chapters'), List<Map<String, dynamic>>.from(chapters));
    });
  }
}
