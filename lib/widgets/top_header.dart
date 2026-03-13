import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/content_access_service.dart';
import '../screens/home/main_navigation.dart';
import 'notification_bell.dart';

class TopHeader extends StatelessWidget {
  final String? selectedExamId;
  final List<String> userExamIds;
  final Function(String) onExamChanged;
  final bool showExamDropdown;
  final VoidCallback? onBellTap;
  final bool enableTitleNavigation;

  const TopHeader({
    super.key,
    required this.selectedExamId,
    required this.userExamIds,
    required this.onExamChanged,
    this.showExamDropdown = true,
    this.onBellTap,
    this.enableTitleNavigation = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(minHeight: 55),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE5E7EB), // light grey
            width: 1, // thin line
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // App name on left
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: enableTitleNavigation
                    ? () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const MainNavigation(
                              initialIndex: 1,
                            ),
                          ),
                          (route) => false,
                        );
                      }
                    : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text(
                    'RankSprintAI',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            // Dropdown and bell icon on right
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                if (showExamDropdown)
                  FutureBuilder<QuerySnapshot>(
                    future: ContentAccessService.activeExamsQuery().get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox();
                      }

                      final exams = snapshot.data!.docs;
                      final unlockedExamIds = exams
                          .where((exam) => userExamIds.contains(exam.id))
                          .map((exam) => exam.id)
                          .toList();
                      final validSelectedExamId =
                          unlockedExamIds.contains(selectedExamId)
                          ? selectedExamId
                          : (unlockedExamIds.isNotEmpty
                                ? unlockedExamIds.first
                                : null);

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        constraints: const BoxConstraints(maxHeight: 45),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: validSelectedExamId,
                            icon: const Icon(Icons.keyboard_arrow_down),
                            items: exams.map((exam) {
                              final isUnlocked = userExamIds.contains(exam.id);
                              return DropdownMenuItem<String>(
                                value: exam.id,
                                enabled: isUnlocked,
                                child: Row(
                                  children: [
                                    Text(
                                      exam['name'] ?? exam.id,
                                      style: TextStyle(
                                        color: isUnlocked
                                            ? Colors.black
                                            : Colors.grey,
                                      ),
                                    ),
                                    if (!isUnlocked)
                                      const Icon(
                                        Icons.lock_outline,
                                        size: 18,
                                        color: Colors.grey,
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null &&
                                  userExamIds.contains(value)) {
                                onExamChanged(value);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                // Bell Icon with unread badge and navigation
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseAuth.instance.currentUser == null
                      ? const Stream.empty()
                      : FirebaseFirestore.instance
                            .collection('notification')
                            .snapshots(),
                  builder: (context, notifSnap) {
                    final user = FirebaseAuth.instance.currentUser;
                    if (!notifSnap.hasData || user == null) {
                      return const Icon(Icons.notifications_none, size: 28);
                    }
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('notifications')
                          .snapshots(),
                      builder: (context, metaSnap) {
                        int unread = 0;
                        final notifications = notifSnap.data!.docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final userIds = data['userId'] as List<dynamic>?;
                          return userIds == null ||
                              userIds.isEmpty ||
                              userIds.contains(user.uid);
                        }).toList();
                        for (var doc in notifications) {
                          final notifId = doc.id;
                          final metaDocs = metaSnap.data?.docs ?? [];
                          final metaDocList = metaDocs
                              .cast<QueryDocumentSnapshot>()
                              .where((m) => m.id == notifId);
                          final metaDoc = metaDocList.isNotEmpty
                              ? metaDocList.first
                              : null;
                          if (metaDoc == null || metaDoc['isRead'] == false) {
                            unread++;
                          }
                        }
                        return NotificationBell(
                          unread: unread,
                          onBellTap: onBellTap,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
