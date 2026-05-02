import 'package:flutter/material.dart';
import '../../services/html_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../examSummary/exam_summary_screen.dart';
import '../../sections/section_bean.dart';
import '../../sections/section_service.dart';
import '../../services/result_data_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/top_header.dart';
import 'package:rxdart/rxdart.dart';
import '../../services/subscription_access_service.dart';
import 'subscription_screen.dart';
import 'test_history_screen.dart';
import 'tests_screen.dart';

class NotificationScreen extends StatefulWidget {
  final VoidCallback? onBellTap;
  const NotificationScreen({super.key, this.onBellTap});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  void refreshNotifications() {
    setState(() {});
  }

  final user = FirebaseAuth.instance.currentUser;

  Stream<List<Map<String, dynamic>>> _notificationStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value([]);
    }
    final notifStream = FirebaseFirestore.instance
        .collection('notification')
        .snapshots();
    final metaStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .snapshots();
    return Rx.combineLatest2<
      QuerySnapshot<Map<String, dynamic>>,
      QuerySnapshot<Map<String, dynamic>>,
      List<Map<String, dynamic>>
    >(notifStream, metaStream, (notifSnap, metaSnap) {
      final metaMap = {for (var doc in metaSnap.docs) doc.id: doc.data()};
      List<Map<String, dynamic>> notifications = [];
      for (var doc in notifSnap.docs) {
        final data = doc.data();
        final userIds = data['userId'] as List<dynamic>?;
        if (userIds == null || userIds.isEmpty || userIds.contains(user.uid)) {
          final meta = metaMap[doc.id] ?? {};
          notifications.add({
            ...data,
            'id': doc.id,
            'isRead': meta['isRead'] ?? false,
            'seenAt': meta['seenAt'],
          });
        }
      }
      notifications.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });
      return notifications;
    });
  }

  Future<void> _markAsRead(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc(id)
        .set({
          'isRead': true,
          'seenAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _markAsUnread(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc(id)
        .set({'isRead': false, 'seenAt': null}, SetOptions(merge: true));
  }

  void _showMarkedReadMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Notification marked as read'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  void _showMarkedUnreadMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Notification marked as unread'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _markAllRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('notification')
        .get();
    for (var doc in snap.docs) {
      final data = doc.data();
      final userIds = data['userId'] as List<dynamic>?;
      if (userIds == null || userIds.isEmpty || userIds.contains(user.uid)) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('notifications')
            .doc(doc.id)
            .set({
              'isRead': true,
              'seenAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    }
  }

  String selectedFilter = 'Unread';

  String _timeAgo(Timestamp timestamp) {
    final diff = DateTime.now().difference(timestamp.toDate());

    if (diff.inMinutes < 1) {
      return "Just now";
    } else if (diff.inMinutes < 60) {
      return "${diff.inMinutes}m ago";
    } else if (diff.inHours < 24) {
      return "${diff.inHours}h ago";
    } else if (diff.inDays < 7) {
      return "${diff.inDays}d ago";
    } else {
      final date = timestamp.toDate();
      const monthNames = <String>[
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${date.day} ${monthNames[date.month - 1]}';
    }
  }

  Future<void> _ensureExamContext(String examId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || examId.isEmpty) return;

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final userSnap = await userRef.get();
    final selectedExams = List<String>.from(
      userSnap.data()?['selectedExams'] ?? const <String>[],
    );

    if (!selectedExams.contains(examId)) {
      selectedExams.add(examId);
      await userRef.set({
        'selectedExams': selectedExams,
      }, SetOptions(merge: true));
    }

    await UserExamPreferenceService.savePreferredExamId(examId);
  }

  String _notificationExamId(Map<String, dynamic> data) {
    const candidateKeys = <String>[
      'examId',
      'selectedExamId',
      'targetExamId',
      'initialExamId',
    ];

    for (final key in candidateKeys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }

  Future<String> _resolveNotificationExamId(Map<String, dynamic> data) async {
    final directExamId = _notificationExamId(data);
    if (directExamId.isNotEmpty) {
      return directExamId;
    }

    final preferredExamId = UserExamPreferenceService.preferredExamNotifier.value;
    if (preferredExamId != null && preferredExamId.trim().isNotEmpty) {
      return preferredExamId.trim();
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';

    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userSnap.data() ?? const <String, dynamic>{};

      final lastSelectedExamId =
          (userData['lastSelectedExamId'] ?? '').toString().trim();
      if (lastSelectedExamId.isNotEmpty) {
        return lastSelectedExamId;
      }

      final selectedExams = List<String>.from(
        userData['selectedExams'] ?? const <String>[],
      );
      for (final examId in selectedExams) {
        final normalized = examId.trim();
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    } catch (_) {
      // Keep notification taps resilient even if the user profile read fails.
    }

    return '';
  }

  String _normalizeNotificationType(
    dynamic rawType, {
    Map<String, dynamic>? data,
  }) {
    final value = (rawType ?? '').toString().trim().toLowerCase();
    final title = (data?['title'] ?? '').toString().trim().toLowerCase();
    final message = (data?['message'] ?? data?['msg'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final combined = '$value $title $message';

    if (value == 'exam' || value == 'test alerts' || value == 'test_alerts') {
      return 'exam';
    }
    if (value == 'result' || value == 'results') {
      return 'result';
    }
    if (value == 'offer' ||
        value == 'offers' ||
        value == 'subscription' ||
        value == 'subscriptions' ||
        value == 'plan' ||
        value == 'plans' ||
        combined.contains('subscription') ||
        combined.contains('subscribe') ||
        combined.contains('plan renewal') ||
        combined.contains('renewal')) {
      return 'offer';
    }
    return value;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadLatestAttemptsForExam(
    String userId,
    String examId,
  ) async {
    final attempts = FirebaseFirestore.instance.collection('testAttempts');
    try {
      return await attempts
          .where('userId', isEqualTo: userId)
          .where('examId', isEqualTo: examId)
          .orderBy('submittedAt', descending: true)
          .limit(10)
          .get();
    } catch (_) {
      try {
        return await attempts
            .where('userId', isEqualTo: userId)
            .where('examId', isEqualTo: examId)
            .orderBy('startedAt', descending: true)
            .limit(10)
            .get();
      } catch (_) {
        return attempts
            .where('userId', isEqualTo: userId)
            .where('examId', isEqualTo: examId)
            .limit(25)
            .get();
      }
    }
  }

  DateTime _attemptSortDate(Map<String, dynamic> data) {
    final submittedAt = data['submittedAt'];
    if (submittedAt is Timestamp) return submittedAt.toDate();
    final startedAt = data['startedAt'];
    if (startedAt is Timestamp) return startedAt.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _openLatestResultForExam(String examId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || examId.isEmpty) return;

    final attemptsSnap = await _loadLatestAttemptsForExam(user.uid, examId);
    if (attemptsSnap.docs.isEmpty) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TestHistoryScreen(initialExamId: examId),
        ),
      );
      return;
    }

    final sortedAttempts = attemptsSnap.docs.toList()
      ..sort(
        (a, b) =>
            _attemptSortDate(b.data()).compareTo(_attemptSortDate(a.data())),
      );

    final latestAttempt = sortedAttempts.first;
    final latestAttemptData = latestAttempt.data();
    final resultData = await ResultDataService.resolveResultForAttempt(
      attemptId: latestAttempt.id,
      attemptData: latestAttemptData,
      initialResultData: const <String, dynamic>{},
    );

    final testId = (latestAttemptData['testId'] ?? '').toString();
    final sections = testId.isEmpty
        ? <SectionBean>[]
        : await SectionService().getSections(examId, testId);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExamResultScreen(
          questions: resultData['question'] ?? const [],
          answers: resultData['answers'] ?? const <String, dynamic>{},
          correct: _toInt(resultData['correct']) ?? 0,
          section: sections,
          incorrect: _toInt(resultData['incorrect']) ?? 0,
          unanswered: _toInt(resultData['unanswered']) ?? 0,
        ),
      ),
    );
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> data) async {
    final examId = await _resolveNotificationExamId(data);
    final type = _normalizeNotificationType(data['type'], data: data);
    final notificationId = (data['id'] ?? '').toString();

    if (!(data['isRead'] ?? false) && notificationId.isNotEmpty) {
      await _markAsRead(notificationId);
    }

    if (examId.isNotEmpty) {
      await _ensureExamContext(examId);
    }

    if (!mounted) return;

    switch (type) {
      case 'exam':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TestsScreen(selectedExam: examId)),
        );
        return;
      case 'result':
        await _openLatestResultForExam(examId);
        return;
      case 'offer':
        Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => SubscriptionScreen(initialExamId: examId),
          ),
        ).then((subscribed) {
          if (subscribed == true) {
            SubscriptionAccessService.clearCache();
          }
        });
        return;
      default:
        if (!(data['isRead'] ?? false)) {
          await _markAsRead((data['id'] ?? '').toString());
        }
        return;
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _filterSummary(int count) {
    switch (selectedFilter) {
      case 'Unread':
        return '$count unread';
      case 'Test Alerts':
        return '$count test alerts';
      case 'Offers':
        return '$count offers';
      default:
        return '$count notifications';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: WillPopScope(
          onWillPop: () async {
            Navigator.of(context).pop();
            return false;
          },
          child: Column(
            children: [
              TopHeader(
                selectedExamId: null,
                userExamIds: const [],
                onExamChanged: (_) {},
                showExamDropdown: false,
                showBackButton: true,
                enableTitleNavigation: false,
                onBellTap: () {
                  if (widget.onBellTap != null) {
                    widget.onBellTap!();
                  } else {
                    refreshNotifications();
                  }
                },
              ),
              const SizedBox(height: 2),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _notificationStream(),
                  builder: (context, snapshot) {
                    // ...existing code for notification list rendering...
                    // Ensure a Widget is always returned
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading notifications:\n${snapshot.error}',
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!;
                    if (docs.isEmpty) {
                      return const Center(child: Text("No notifications"));
                    }
                    // Apply client-side filtering based on selectedFilter
                    final filtered = docs.where((data) {
                      final type =
                          _normalizeNotificationType(data['type'], data: data);
                      if (selectedFilter == 'All') return true;
                      if (selectedFilter == 'Unread') {
                        return !(data['isRead'] ?? false);
                      }
                      if (selectedFilter == 'Test Alerts') {
                        return type == 'exam';
                      }
                      if (selectedFilter == 'Results') {
                        return type == 'result';
                      }
                      if (selectedFilter == 'Offers') {
                        return type == 'offer';
                      }
                      return true;
                    }).toList();

                    final unreadCount = docs.where((data) {
                      return !(data['isRead'] ?? false);
                    }).length;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _filterSummary(filtered.length),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (unreadCount > 0)
                                    TextButton(
                                      onPressed: _markAllRead,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        minimumSize: const Size(0, 32),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('Mark all read'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildChip('Unread'),
                                    _buildChip('All'),
                                    _buildChip('Test Alerts'),
                                    _buildChip('Offers'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final data = filtered[index];
                              final id = data['id'];
                              final title = data['title'] ?? '';
                              final message =
                                  data['message'] ?? data['msg'] ?? '';
                              final isRead = data['isRead'] ?? false;
                              final createdAt = data['createdAt'];
                              final imageUrl =
                                  (data['imageUrl'] ?? '') as String;
                              final createdLabel = createdAt is Timestamp
                                  ? _timeAgo(createdAt)
                                  : '';
                              return TweenAnimationBuilder<Offset>(
                                tween: Tween(
                                  begin: const Offset(0, 0.2),
                                  end: Offset.zero,
                                ),
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                                builder: (context, offset, child) {
                                  return Transform.translate(
                                    offset: offset,
                                    child: Opacity(opacity: 1.0, child: child),
                                  );
                                },
                                child: Dismissible(
                                  key: ValueKey('notification-$id'),
                                  direction: DismissDirection.horizontal,
                                  confirmDismiss: (_) async {
                                    if (isRead) {
                                      await _markAsUnread(id);
                                      _showMarkedUnreadMessage();
                                    } else {
                                      await _markAsRead(id);
                                      _showMarkedReadMessage();
                                    }
                                    return false;
                                  },
                                  background: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF16A34A),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: const Row(
                                      children: [
                                        Icon(Icons.done, color: Colors.white),
                                        SizedBox(width: 10),
                                        Text(
                                          'Mark as read',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  secondaryBackground: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    alignment: Alignment.centerRight,
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Mark as unread',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Icon(
                                          Icons.mark_email_unread_outlined,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: Material(
                                      borderRadius: BorderRadius.circular(16),
                                      color: Colors.white,
                                      elevation: 2,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () =>
                                            _handleNotificationTap(data),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            14,
                                            16,
                                            12,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFEFF3FF,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: imageUrl.isNotEmpty
                                                    ? ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                        child: Image.network(
                                                          imageUrl,
                                                          fit: BoxFit.cover,
                                                          errorBuilder:
                                                              (
                                                                context,
                                                                error,
                                                                stackTrace,
                                                              ) => const Icon(
                                                                Icons
                                                                    .notifications,
                                                                size: 24,
                                                                color: Color(
                                                                  0xFF2F6FEB,
                                                                ),
                                                              ),
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons.notifications,
                                                        size: 24,
                                                        color: Color(
                                                          0xFF2F6FEB,
                                                        ),
                                                      ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            title,
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 16,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                          ),
                                                        ),
                                                        if (!isRead)
                                                          const Icon(
                                                            Icons.circle,
                                                            size: 10,
                                                            color: Colors.blue,
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 1.0,
                                                          ),
                                                      child:
                                                          HtmlHelper.renderHtml(
                                                            message,
                                                            style:
                                                                const TextStyle(
                                                                  color: Color(
                                                                    0xFF667085,
                                                                  ),
                                                                  fontSize: 14,
                                                                  height: 1.35,
                                                                ),
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                    ),
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Text(
                                                          createdLabel,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color: Color(
                                                                  0xFF98A2B3,
                                                                ),
                                                              ),
                                                        ),
                                                        TextButton(
                                                          style: TextButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 0,
                                                                ),
                                                            minimumSize:
                                                                const Size(
                                                                  0,
                                                                  28,
                                                                ),
                                                          ),
                                                          onPressed: () async {
                                                            if (isRead) {
                                                              await _markAsUnread(
                                                                id,
                                                              );
                                                              _showMarkedUnreadMessage();
                                                            } else {
                                                              await _markAsRead(
                                                                id,
                                                              );
                                                              _showMarkedReadMessage();
                                                            }
                                                          },
                                                          child: Text(
                                                            isRead
                                                                ? "Mark as unread"
                                                                : "Mark as read",
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    final selected = selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            selectedFilter = label;
          });
        },
        selectedColor: const Color(0xFF2F6FEB),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        showCheckmark: true,
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }
}
