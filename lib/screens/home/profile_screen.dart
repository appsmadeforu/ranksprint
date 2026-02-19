import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
      'December'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('User not logged in')),
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
            return const Center(child: Text('User data not found'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final name = data['name'] ?? '';
          final email = data['email'] ?? '';
          final phone = data['phone'] ?? '';
          final selectedExams = List<String>.from(data['selectedExams'] ?? []);
          final subscriptionIds = List<String>.from(data['subscriptionIds'] ?? []);

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Top header: exam selector + notifications
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Text(
                                selectedExams.isNotEmpty ? selectedExams.first.toUpperCase() : 'SELECT',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.keyboard_arrow_down, size: 20),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Stack(
                          children: [
                            const Icon(Icons.notifications_none, size: 28),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // User card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: const Color(0xFF2F3E8F),
                          child: Text(
                            name.isNotEmpty ? (name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase()) : 'RS',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name.isNotEmpty ? name : 'Rank Sprint User', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(email, style: const TextStyle(color: Colors.grey)),
                              if (phone != '') ...[
                                const SizedBox(height: 6),
                                Text(phone, style: const TextStyle(color: Colors.grey)),
                              ]
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.edit_outlined),
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Subscription card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FutureBuilder<DocumentSnapshot?>(
                      future: subscriptionIds.isNotEmpty
                          ? FirebaseFirestore.instance.collection('subscriptions').doc(subscriptionIds.first).get()
                          : Future.value(null),
                      builder: (context, subSnap) {
                        DateTime? expires;
                        if (subSnap.hasData && subSnap.data != null && subSnap.data!.exists) {
                          final sdata = subSnap.data!.data() as Map<String, dynamic>? ?? {};
                          if (sdata['expiresAt'] is Timestamp) {
                            expires = (sdata['expiresAt'] as Timestamp).toDate().toLocal();
                          }
                        }

                        final isPremium = expires != null;
                        final expiryText = expires != null ? 'Valid until ${_formatDate(expires)}' : '';

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF3A53B7), Color(0xFF1F3A8A)]),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                                    child: const Icon(Icons.workspace_premium, color: Colors.orange),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(isPremium ? 'Premium Plan' : 'Free Plan', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      Text(isPremium ? expiryText : 'Upgrade to unlock all features', style: const TextStyle(color: Colors.white70)),
                                    ]),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                    onPressed: () async {
                                      // Construct a management URL (fallback).
                                      String manageUrl = 'https://ranksprint.ai/manage-subscription';
                                      if (subSnap.hasData && subSnap.data != null && subSnap.data!.exists) {
                                        final sdata = subSnap.data!.data() as Map<String, dynamic>? ?? {};
                                        if (sdata['manageUrl'] is String && (sdata['manageUrl'] as String).isNotEmpty) {
                                          manageUrl = sdata['manageUrl'];
                                        } else if (subscriptionIds.isNotEmpty) {
                                          manageUrl = 'https://ranksprint.ai/manage-subscription?sub=${subscriptionIds.first}';
                                        }
                                      } else if (subscriptionIds.isNotEmpty) {
                                        manageUrl = 'https://ranksprint.ai/manage-subscription?sub=${subscriptionIds.first}';
                                      }

                                      // Copy without awaiting to avoid using BuildContext after an async gap.
                                      Clipboard.setData(ClipboardData(text: manageUrl));
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manage subscription URL copied to clipboard')));
                                    },
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.white24),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text('Manage Subscription', style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Account section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ACCOUNT', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.settings_outlined),
                                title: const Text('Account Settings'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {},
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.credit_card_outlined),
                                title: const Text('Payment History'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {},
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.notifications_none),
                                title: const Text('Notifications'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {},
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Support
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('SUPPORT', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.help_outline),
                                title: const Text('Help & FAQ'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {},
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.description_outlined),
                                title: const Text('Terms & Conditions'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {},
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.lock_outline),
                                title: const Text('Privacy Policy'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {},
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
                    child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.logout, color: Colors.orange),
                        title: const Text('Logout', style: TextStyle(color: Colors.orange)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _logout(context),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                  const Center(child: Text('Rank Sprint v1.0.0\n© 2026 Rank Sprint', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
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
