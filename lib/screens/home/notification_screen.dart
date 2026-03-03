import 'package:flutter/material.dart';
import '../../services/html_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/top_header.dart';
import 'package:rxdart/rxdart.dart';

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

  String selectedFilter = 'All';

  String _timeAgo(Timestamp timestamp) {
    final diff = DateTime.now().difference(timestamp.toDate());

    if (diff.inMinutes < 60) {
      return "${diff.inMinutes}m ago";
    } else if (diff.inHours < 24) {
      return "${diff.inHours}h ago";
    } else {
      return "${diff.inDays}d ago";
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
                      if (selectedFilter == 'All') return true;
                      if (selectedFilter == 'Unread') {
                        return !(data['isRead'] ?? false);
                      }
                      if (selectedFilter == 'Test Alerts') {
                        return (data['type'] ?? '') == 'exam';
                      }
                      if (selectedFilter == 'Results') {
                        return (data['type'] ?? '') == 'result';
                      }
                      if (selectedFilter == 'Offers') {
                        return (data['type'] ?? '') == 'offer';
                      }
                      return true;
                    }).toList();

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _buildChip('All'),
                                _buildChip('Unread'),
                                _buildChip('Test Alerts'),
                                _buildChip('Offers'),
                              ],
                            ),
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
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Material(
                                    borderRadius: BorderRadius.circular(16),
                                    color: Colors.white,
                                    elevation: 2,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 16,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF3FF),
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
                                                            Icons.notifications,
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
                                                    color: Color(0xFF2F6FEB),
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
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w600,
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
                                                  child: HtmlHelper.renderHtml(
                                                    message,
                                                    style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 14,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      createdAt != null
                                                          ? createdAt.toString()
                                                          : '',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                    if (!isRead)
                                                      TextButton(
                                                        style: TextButton.styleFrom(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 0,
                                                              ),
                                                          minimumSize:
                                                              const Size(0, 28),
                                                        ),
                                                        onPressed: () =>
                                                            _markAsRead(id),
                                                        child: const Text(
                                                          "Mark read",
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
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }
}
