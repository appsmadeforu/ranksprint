import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/content_access_service.dart';
import '../services/user_exam_preference_service.dart';
import '../screens/onboarding/select_exam_screen.dart';
import '../screens/home/main_navigation.dart';
import 'notification_bell.dart';

class TopHeader extends StatefulWidget {
  final String? selectedExamId;
  final List<String> userExamIds;
  final Function(String) onExamChanged;
  final bool showExamDropdown;
  final bool showNotificationBell;
  final VoidCallback? onBellTap;
  final bool enableTitleNavigation;
  final Widget? trailingAction;

  const TopHeader({
    super.key,
    required this.selectedExamId,
    required this.userExamIds,
    required this.onExamChanged,
    this.showExamDropdown = true,
    this.showNotificationBell = true,
    this.onBellTap,
    this.enableTitleNavigation = true,
    this.trailingAction,
  });

  @override
  State<TopHeader> createState() => _TopHeaderState();
}

class _TopHeaderState extends State<TopHeader> {
  static const String _addExamMenuValue = '__add_exam__';
  late final Future<QuerySnapshot<Map<String, dynamic>>> _activeExamsFuture;
  String? _pendingSelectedExamId;
  String? _lastSyncedExamId;

  void _goHome(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 0)),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _activeExamsFuture = ContentAccessService.activeExamsQuery().get();
  }

  @override
  void didUpdateWidget(covariant TopHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedExamId == _pendingSelectedExamId) {
      _pendingSelectedExamId = null;
    }
    if (oldWidget.selectedExamId != widget.selectedExamId &&
        widget.selectedExamId != null) {
      _lastSyncedExamId = widget.selectedExamId;
    }
  }

  Future<void> _handleExamChanged(String examId) async {
    if (examId.isEmpty) return;
    setState(() {
      _pendingSelectedExamId = examId;
      _lastSyncedExamId = examId;
    });
    await UserExamPreferenceService.savePreferredExamId(examId);
    if (!mounted) return;
    widget.onExamChanged(examId);
  }

  Future<void> _openAddExamScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SelectExamScreen()));
  }

  void _syncResolvedExam(String examId) {
    if (examId.isEmpty || examId == _lastSyncedExamId) return;
    _lastSyncedExamId = examId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      UserExamPreferenceService.syncPreferredExamId(examId);
      widget.onExamChanged(examId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
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
               onTap: widget.enableTitleNavigation ? () => _goHome(context) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'RankSprintAI',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            color: Color(0xFF3A53B7),
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
                   if (widget.showExamDropdown)
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: currentUser == null
                              ? null
                              : FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(currentUser.uid)
                                    .snapshots(),
                          builder: (context, userSnap) {
                            final liveUserExamIds =
                                userSnap.data?.data()?['selectedExams'] is List
                                ? List<String>.from(
                                    userSnap.data?.data()?['selectedExams'] ??
                                        const [],
                                  )
                                : widget.userExamIds;

                            return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              future: _activeExamsFuture,
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const SizedBox();
                                }

                                final exams = snapshot.data!.docs;
                                final unlockedExams = exams
                                    .where(
                                      (exam) =>
                                          liveUserExamIds.contains(exam.id),
                                    )
                                    .toList();
                                final unlockedExamIds = unlockedExams
                                    .map((exam) => exam.id)
                                    .toList();
                                final dropdownItems = <DropdownMenuItem<String>>[
                                  ...unlockedExams.map((exam) {
                                    final label =
                                        (exam['name'] ?? exam.id).toString();
                                    return DropdownMenuItem<String>(
                                      value: exam.id,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              label,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF1F2937),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const DropdownMenuItem<String>(
                                    value: _addExamMenuValue,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.add_circle_outline_rounded,
                                          size: 18,
                                          color: Color(0xFF31459B),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Add exam',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF31459B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ];
                                final requestedExamId =
                                    _pendingSelectedExamId ?? widget.selectedExamId;
                                final validSelectedExamId =
                                    unlockedExamIds.contains(requestedExamId)
                                    ? requestedExamId
                                    : (unlockedExamIds.isNotEmpty
                                          ? unlockedExamIds.first
                                          : null);

                                if (validSelectedExamId != null &&
                                    validSelectedExamId != requestedExamId) {
                                  _syncResolvedExam(validSelectedExamId);
                                }

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
                                      key: ValueKey(
                                        '${validSelectedExamId ?? 'none'}-${unlockedExamIds.join(',')}',
                                      ),
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
                                        return <Widget>[
                                          ...unlockedExams.map((exam) {
                                            final label =
                                                (exam['name'] ?? exam.id)
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
                                          }),
                                          const Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'Add exam',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1F2937),
                                              ),
                                            ),
                                          ),
                                        ];
                                      },
                                      items: dropdownItems,
                                      onChanged: (value) {
                                        if (value == _addExamMenuValue) {
                                          _openAddExamScreen();
                                          return;
                                        }
                                        if (value != null) {
                                          _handleExamChanged(value);
                                        }
                                      },
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                   if (widget.showExamDropdown) const SizedBox(width: 12),
                   if (widget.trailingAction != null) ...[
                     widget.trailingAction!,
                     const SizedBox(width: 8),
                   ],
                   if (widget.showNotificationBell)
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseAuth.instance.currentUser == null
                          ? const Stream.empty()
                          : FirebaseFirestore.instance
                                .collection('notification')
                                .limit(40)
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
                              .limit(40)
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
                              if (metaDoc == null ||
                                  metaDoc['isRead'] == false) {
                                unread++;
                              }
                            }
                            return NotificationBell(
                              unread: unread,
                              onBellTap: widget.onBellTap,
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
