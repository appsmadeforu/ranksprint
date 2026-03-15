import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/content_access_service.dart';
import '../services/user_exam_preference_service.dart';
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
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enableTitleNavigation
                  ? () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const MainNavigation(initialIndex: 1),
                        ),
                        (route) => false,
                      );
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'R',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            color: Color(0xFF2F6FEB),
                          ),
                        ),
                        TextSpan(
                          text: 'ank',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: 'S',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            color: Color(0xFF2F6FEB),
                          ),
                        ),
                        TextSpan(
                          text: 'print',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: 'AI',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            color: Color(0xFF2F6FEB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showExamDropdown)
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: FutureBuilder<QuerySnapshot>(
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
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFDCE4F5),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: validSelectedExamId,
                                  isExpanded: true,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Color(0xFF64748B),
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  dropdownColor: Colors.white,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F2937),
                                  ),
                                  selectedItemBuilder: (context) {
                                    return exams.map((exam) {
                                      final label = (exam['name'] ?? exam.id)
                                          .toString();
                                      return Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                      );
                                    }).toList();
                                  },
                                  items: exams.map((exam) {
                                    final isUnlocked = userExamIds.contains(
                                      exam.id,
                                    );
                                    final label = (exam['name'] ?? exam.id)
                                        .toString();
                                    return DropdownMenuItem<String>(
                                      value: exam.id,
                                      enabled: isUnlocked,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              label,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: isUnlocked
                                                    ? const Color(0xFF1F2937)
                                                    : const Color(0xFF9CA3AF),
                                              ),
                                            ),
                                          ),
                                          if (!isUnlocked)
                                            const Padding(
                                              padding: EdgeInsets.only(left: 8),
                                              child: Icon(
                                                Icons.lock_outline_rounded,
                                                size: 16,
                                                color: Color(0xFF9CA3AF),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null &&
                                        userExamIds.contains(value)) {
                                      UserExamPreferenceService.savePreferredExamId(
                                        value,
                                      );
                                      onExamChanged(value);
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  if (showExamDropdown) const SizedBox(width: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseAuth.instance.currentUser == null
                        ? const Stream.empty()
                        : FirebaseFirestore.instance
                              .collection('notification')
                              .snapshots(),
                    builder: (context, notifSnap) {
                      final user = FirebaseAuth.instance.currentUser;
                      if (!notifSnap.hasData || user == null) {
                        return const SizedBox(
                          width: 28,
                          child: Icon(Icons.notifications_none, size: 28),
                        );
                      }
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .collection('notifications')
                            .snapshots(),
                        builder: (context, metaSnap) {
                          int unread = 0;
                          final notifications = notifSnap.data!.docs.where((
                            doc,
                          ) {
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
            ),
          ),
        ],
      ),
    );
  }
}
