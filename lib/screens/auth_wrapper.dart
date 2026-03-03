import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth/login_screen.dart';
import 'onboarding/select_exam_screen.dart';
import 'home/main_navigation.dart';
import 'home/edit_profile_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // 🔄 Waiting for auth
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ❌ Not logged in
        if (!authSnapshot.hasData) {
          return const LoginScreen();
        }

        final user = authSnapshot.data!;

        // 🔍 Check user document
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // ❌ No user document yet
            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              // Show edit profile first
              return const EditProfileScreen();
            }

            final data = userSnapshot.data!.data() as Map<String, dynamic>?;

            // If profile fields are missing, force edit profile
            if (data == null ||
                ((data['email'] == null || data['email'].toString().isEmpty) &&
                        (data['phone'] == null ||
                            data['phone'].toString().isEmpty) ||
                    (data['name'] == null || data['name'].toString().isEmpty) ||
                    (data['pincode'] == null) ||
                    (data['dob'] == null))) {
              return const EditProfileScreen();
            }

            final selectedExams = data['selectedExams'];

            // ❌ No exams selected
            if (selectedExams == null ||
                selectedExams is! List ||
                selectedExams.isEmpty) {
              return const SelectExamScreen();
            }

            // ✅ Everything good → go to tests screen
            return const MainNavigation(initialIndex: 1);
          },
        );
      },
    );
  }
}
