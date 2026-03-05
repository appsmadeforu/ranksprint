import 'package:flutter/material.dart';
import 'help_faq_screen.dart';

import 'privacy_policy_screen.dart';
import 'terms_conditions_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'subscription_screen.dart';
import '../../widgets/top_header.dart';
import 'edit_profile_screen.dart';
import '../auth/login_screen.dart';
import 'test_history_screen.dart';
import 'performance_trends_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? selectedExamId;
  List<String> userExamIds = [];
  bool isDeletingAccount = false;

  Future<void> _clearAppCache() async {
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  Future<void> _forceLogoutAndGoToLogin(BuildContext context) async {
    try {
      await GoogleSignIn().signOut().timeout(const Duration(seconds: 3));
      await GoogleSignIn().disconnect().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Ignore Google session cleanup errors on devices without stable GMS.
    }
    await FirebaseAuth.instance.signOut();
    await _clearAppCache();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUserExams();
  }

  Future<void> _loadUserExams() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();
    if (data == null) return;

    final exams = List<String>.from(data['selectedExams'] ?? []);
    setState(() {
      userExamIds = exams;
      selectedExamId = exams.isNotEmpty ? exams.first : null;
    });
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(), // Cancel
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _deleteAccount(context);
            },
            child: const Text(
              'Yes, Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    setState(() {
      isDeletingAccount = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;

      if (user != null && uid != null) {
        // Deleting the Firebase Auth user removes all linked sign-in methods
        // (email/password, phone, Google, etc.) for this account.
        await user.delete();
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      }

      await _forceLogoutAndGoToLogin(context);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final msg = e.code == 'requires-recent-login'
            ? 'For security, please log in again and retry account deletion.'
            : 'Error deleting account: ${e.message ?? e.code}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }

      if (e.code == 'requires-recent-login') {
        await _forceLogoutAndGoToLogin(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error deleting account: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          isDeletingAccount = false;
        });
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
  }

  String _formatDate(DateTime d) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('User not logged in')));
    }

    return Scaffold(
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (FirebaseAuth.instance.currentUser == null) {
            Future.microtask(() {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            });
            return const SizedBox();
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('User data not found'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final name = data['name'] ?? '';
          final email = data['email'] ?? '';
          final phone = data['phone'] ?? '';
          final selectedExams = List<String>.from(data['selectedExams'] ?? []);
          final subscriptionIds = List<String>.from(
            data['subscriptionIds'] ?? [],
          );

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Top header with functional dropdown
                  TopHeader(
                    selectedExamId:
                        selectedExamId ??
                        (selectedExams.isNotEmpty ? selectedExams.first : null),
                    userExamIds: selectedExams,
                    onExamChanged: (examId) {
                      setState(() {
                        selectedExamId = examId;
                      });
                    },
                  ),

                  const SizedBox(height: 8),

                  // User card
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF2F3E8F),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            name.isNotEmpty
                                ? (name.length >= 2
                                      ? name.substring(0, 2).toUpperCase()
                                      : name.toUpperCase())
                                : 'RS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Name + Email + Phone
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name.isNotEmpty
                                          ? name
                                          : 'Rank Sprint User',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (!isDeletingAccount)
                                    InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const EditProfileScreen(),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                              const SizedBox(height: 6),

                              if (email.isNotEmpty)
                                Text(
                                  email,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),

                              if (phone.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  phone,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Subscription card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FutureBuilder<DocumentSnapshot?>(
                      future: subscriptionIds.isNotEmpty
                          ? FirebaseFirestore.instance
                                .collection('subscriptions')
                                .doc(subscriptionIds.first)
                                .get()
                          : Future.value(null),
                      builder: (context, subSnap) {
                        DateTime? expires;
                        if (subSnap.hasData &&
                            subSnap.data != null &&
                            subSnap.data!.exists) {
                          final sdata =
                              subSnap.data!.data() as Map<String, dynamic>? ??
                              {};
                          if (sdata['expiresAt'] is Timestamp) {
                            expires = (sdata['expiresAt'] as Timestamp)
                                .toDate()
                                .toLocal();
                          }
                        }

                        final isPremium = expires != null;
                        final expiryText = expires != null
                            ? 'Valid until ${_formatDate(expires)}'
                            : '';

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3A53B7), Color(0xFF1F3A8A)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.workspace_premium,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isPremium
                                              ? 'Premium Plan'
                                              : 'Free Plan',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          isPremium
                                              ? expiryText
                                              : 'Upgrade to unlock all features',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () {
                                    // Navigate to subscription screen
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const SubscriptionScreen(),
                                      ),
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text(
                                      'Manage Subscription',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Performance section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PERFORMANCE',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.history),
                                title: const Text('Test History'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const TestHistoryScreen(),
                                    ),
                                  );
                                },
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.trending_up),
                                title: const Text('Performance Trends'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PerformanceTrendsScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Account section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ACCOUNT',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              if (!isDeletingAccount)
                                ListTile(
                                  leading: Icon(Icons.settings),
                                  title: Text('Account Settings'),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const EditProfileScreen(),
                                      ),
                                    );
                                  },
                                ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.credit_card_outlined),
                                title: const Text('Payment History'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {},
                              ),
                              // Notifications option removed as requested
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Support
                  // Support
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SUPPORT',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              // Help & FAQ
                              ListTile(
                                leading: const Icon(Icons.help_outline),
                                title: const Text("Help & FAQ"),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => HelpFaqScreen(),
                                    ),
                                  );
                                },
                              ),
                              const Divider(height: 1),

                              // Terms
                              ListTile(
                                leading: const Icon(Icons.description_outlined),
                                title: const Text("Terms & Conditions"),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const TermsConditionsScreen(),
                                    ),
                                  );
                                },
                              ),
                              const Divider(height: 1),

                              // Privacy
                              ListTile(
                                leading: const Icon(Icons.lock_outline),
                                title: const Text("Privacy Policy"),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PrivacyPolicyScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ACTIONS',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              // Logout
                              ListTile(
                                leading: const Icon(
                                  Icons.logout,
                                  color: Colors.orange,
                                ),
                                title: const Text(
                                  'Logout',
                                  style: TextStyle(color: Colors.orange),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _logout(context),
                              ),
                              const Divider(height: 1),

                              // Delete Account
                              ListTile(
                                leading: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                title: const Text(
                                  'Delete Account',
                                  style: TextStyle(color: Colors.red),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _confirmDeleteAccount(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                  const Center(
                    child: Text(
                      'Rank Sprint v1.0.0\n© 2026 Rank Sprint',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
