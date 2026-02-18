import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Account"),
        content: const Text(
          "This action is permanent. Are you sure you want to delete your account?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.currentUser?.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("User not logged in")),
      );
    }

    return Scaffold(
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("User data not found"));
          }

          final data =
              snapshot.data!.data() as Map<String, dynamic>;

          final phone = data['phone'] ?? "";
          final selectedExams =
              List<String>.from(data['selectedExams'] ?? []);
          final subscription =
              data['subscription'] ?? {};
          final subType =
              subscription['type'] ?? "free";

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [

                  const SizedBox(height: 20),

                  const Text(
                    "Profile",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // User Info
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundColor:
                            const Color(0xFF1F3A8A),
                        child: Text(
                          phone.isNotEmpty
                              ? phone.substring(
                                  phone.length - 2)
                              : "RS",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            const Text(
                              "Rank Sprint User",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              phone,
                              style:
                                  const TextStyle(
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // Subscription Card
                  Container(
                    padding:
                        const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF1F3A8A),
                      borderRadius:
                          BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons
                                  .workspace_premium,
                              color: Colors.orange,
                            ),
                            const SizedBox(
                                width: 8),
                            Text(
                              subType == "premium"
                                  ? "Premium Plan"
                                  : "Free Plan",
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                                fontSize: 16,
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                            height: 8),
                        Text(
                          subType ==
                                  "premium"
                              ? "You have full access"
                              : "Upgrade to unlock all features",
                          style:
                              const TextStyle(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  const Text(
                    "Selected Exams",
                    style: TextStyle(
                        fontWeight:
                            FontWeight.bold),
                  ),

                  const SizedBox(height: 10),

                  selectedExams.isEmpty
                      ? const Text(
                          "No exams selected",
                          style: TextStyle(
                              color:
                                  Colors.grey),
                        )
                      : Wrap(
                          spacing: 8,
                          children:
                              selectedExams
                                  .map(
                                    (exam) =>
                                        Chip(
                                      label: Text(
                                          exam),
                                      backgroundColor:
                                          const Color(
                                              0xFF1F3A8A),
                                      labelStyle:
                                          const TextStyle(
                                              color: Colors
                                                  .white),
                                    ),
                                  )
                                  .toList(),
                        ),

                  const SizedBox(height: 40),

                  const Divider(),

                  const SizedBox(height: 20),

                  ListTile(
                    leading: const Icon(
                      Icons.logout,
                      color: Colors.orange,
                    ),
                    title: const Text(
                      "Logout",
                      style: TextStyle(
                          color: Colors.orange),
                    ),
                    onTap: () =>
                        _logout(context),
                  ),

                  ListTile(
                    leading: const Icon(
                      Icons.delete,
                      color: Colors.red,
                    ),
                    title: const Text(
                      "Delete Account",
                      style: TextStyle(
                          color: Colors.red),
                    ),
                    onTap: () =>
                        _deleteAccount(
                            context),
                  ),

                  const SizedBox(height: 40),

                  const Center(
                    child: Text(
                      "Rank Sprint v1.0.0\n© 2026 Rank Sprint",
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                          color:
                              Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
