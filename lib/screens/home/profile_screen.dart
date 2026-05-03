import 'package:flutter/material.dart';
import 'help_faq_screen.dart';

import 'privacy_policy_screen.dart';
import 'terms_conditions_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'subscription_screen.dart';
import 'payment_history_screen.dart';
import '../../services/subscription_access_service.dart';
import '../../services/auth_account_deletion_service.dart';
import '../../services/auth_account_cleanup_service.dart';
import '../../services/single_device_session_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/offline_state.dart';
import '../../widgets/theme_mode_tile.dart';
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
  String _appVersionLabel = 'Rank Sprint';
  bool _showDeferredSubscriptionCard = false;
  final Map<String, Future<_ProfileSubscriptionVm>> _subscriptionVmCache = {};

  Future<void> _clearAppCache() async {
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  Future<void> _forceLogoutAndGoToLogin(BuildContext context) async {
    await SingleDeviceSessionService.signOutToLogin();
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
    UserExamPreferenceService.preferredExamNotifier.addListener(
      _handlePreferredExamChanged,
    );
    _loadUserExams();
    _loadAppVersion();
    _scheduleDeferredSections();
  }

  @override
  void dispose() {
    UserExamPreferenceService.preferredExamNotifier.removeListener(
      _handlePreferredExamChanged,
    );
    super.dispose();
  }

  void _scheduleDeferredSections() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        setState(() {
          _showDeferredSubscriptionCard = true;
        });
      });
    });
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
    final preferredExamId = await UserExamPreferenceService.loadPreferredExamId(
      availableExamIds: exams,
    );
    if (!mounted) return;
    setState(() {
      userExamIds = exams;
      selectedExamId = preferredExamId;
    });
  }

  void _handlePreferredExamChanged() {
    final preferredExamId =
        UserExamPreferenceService.preferredExamNotifier.value;
    if (!mounted ||
        preferredExamId == null ||
        preferredExamId == selectedExamId ||
        !userExamIds.contains(preferredExamId)) {
      return;
    }

    setState(() {
      selectedExamId = preferredExamId;
    });
  }

  Future<_ProfileSubscriptionVm> _getSubscriptionVm({
    required String? examId,
    required List<String> activePlanIds,
    required List<String> subscriptionIds,
  }) {
    final cacheKey =
        '${examId ?? ''}|${activePlanIds.join(',')}|${subscriptionIds.join(',')}';
    return _subscriptionVmCache.putIfAbsent(
      cacheKey,
      () => _loadSubscriptionVm(
        examId: examId,
        activePlanIds: activePlanIds,
        subscriptionIds: subscriptionIds,
      ),
    );
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        final buildNumber = info.buildNumber.trim();
        _appVersionLabel = buildNumber.isEmpty
            ? 'Rank Sprint v${info.version}'
            : 'Rank Sprint v${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      // Keep fallback label if package metadata is unavailable.
    }
  }

  void _showProfilePhotoPreview(String photoUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  photoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Could not load profile photo'),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EditProfileScreen()));
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: !isDeletingAccount,
      builder: (dialogContext) {
        var isSubmitting = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => PopScope(
            canPop: !isSubmitting,
            child: AlertDialog(
              title: const Text('Delete Account'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Do you want to delete your account?\n\n'
                    'This will permanently remove your profile, exam selections, saved progress, recommendations, notifications, and related account data. '
                    'You may also lose access to active app data tied to this account.\n\n'
                    'This action cannot be undone.',
                  ),
                  if (isSubmitting) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: const [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text('Deleting account... Please wait.'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                          });

                          await _deleteAccount(context);

                          if (mounted && Navigator.of(dialogContext).canPop()) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text(
                          'Yes, Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    AuthAccountCleanupService.beginAccountDeletion();
    setState(() {
      isDeletingAccount = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        await AuthAccountDeletionService.deleteCurrentAccount();
      }

      await _forceLogoutAndGoToLogin(context);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final msg = e.code == 'requires-recent-login'
            ? 'For security, please log in again and retry account deletion.'
            : 'Error deleting account: ${e.message ?? e.code}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }

      if (e.code == 'requires-recent-login') {
        await _forceLogoutAndGoToLogin(context);
      }
    } on Exception catch (e) {
      final message = e.toString().contains('requires-recent-login')
          ? 'For security, please log in again and retry account deletion.'
          : 'Error deleting account: $e';
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      AuthAccountCleanupService.clearAccountDeletionFlag();
      if (mounted) {
        setState(() {
          isDeletingAccount = false;
        });
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    await SingleDeviceSessionService.signOutToLogin();
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _logout(context);
            },
            child: const Text('Logout', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
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

  String _profileInitials(Map<String, dynamic> data) {
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final firstInitial = firstName.isNotEmpty ? firstName.substring(0, 1) : '';
    final lastInitial = lastName.isNotEmpty ? lastName.substring(0, 1) : '';
    final directInitials = '$firstInitial$lastInitial'.toUpperCase();
    if (directInitials.isNotEmpty) {
      return directInitials;
    }

    final fullName = (data['name'] ?? '').toString().trim();
    final parts = fullName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
          .toUpperCase();
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return 'RS';
  }

  String? _effectiveSelectedExamId(List<String> selectedExams) {
    if (selectedExamId != null && selectedExams.contains(selectedExamId)) {
      return selectedExamId;
    }
    return selectedExams.isNotEmpty ? selectedExams.first : null;
  }

  Future<_ProfileSubscriptionVm> _loadSubscriptionVm({
    required String? examId,
    required List<String> activePlanIds,
    required List<String> subscriptionIds,
  }) async {
    if (examId == null || examId.isEmpty) {
      return const _ProfileSubscriptionVm(
        title: 'Free Plan',
        subtitle: 'Select an exam to manage subscriptions',
      );
    }

    final planSnap = await FirebaseFirestore.instance
        .collection('subscriptionPlans')
        .where('isActive', isEqualTo: true)
        .get();

    final examDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(examId)
        .get();
    final examData = examDoc.data() ?? const <String, dynamic>{};
    final examName = (examData['name'] ?? examId).toString();
    final examPlanIds = List<String>.from(
      examData['subscriptionPlanIds'] ?? const <String>[],
    );

    final plans = planSnap.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList();

    final examPlans = plans.where((plan) {
      final planId = plan['id'].toString();
      if (examPlanIds.contains(planId)) {
        return true;
      }

      final examsIncluded = plan['examsIncluded'];
      if (examsIncluded is Map) {
        return examsIncluded.keys
            .map((value) => value.toString())
            .contains(examId);
      }
      if (examsIncluded is Iterable) {
        return examsIncluded.map((value) => value.toString()).contains(examId);
      }
      return false;
    }).toList();

    if (examPlans.isEmpty) {
      return _ProfileSubscriptionVm(
        title: 'Free Plan',
        subtitle: 'No subscription plans available for $examName',
      );
    }

    final recommendedPlanId = examPlans.first['id']?.toString();
    final matchingActivePlans = examPlans.where((plan) {
      return activePlanIds.contains(plan['id'].toString());
    }).toList();

    DateTime? expiresAt;
    String? activePlanId;
    if (matchingActivePlans.isNotEmpty && subscriptionIds.isNotEmpty) {
      for (final subscriptionId in subscriptionIds) {
        final doc = await FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(subscriptionId)
            .get();
        if (!doc.exists) continue;
        final data = doc.data() ?? <String, dynamic>{};
        final planId = (data['planId'] ?? '').toString();
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status != 'active') continue;
        if (!matchingActivePlans.any(
          (plan) => plan['id'].toString() == planId,
        )) {
          continue;
        }
        final rawExpiry = data['expiresAt'];
        final expiry = rawExpiry is Timestamp
            ? rawExpiry.toDate().toLocal()
            : null;
        if (expiry == null || expiry.isBefore(DateTime.now())) continue;
        activePlanId = planId;
        expiresAt = expiry;
        break;
      }
    }

    if (activePlanId != null) {
      final activePlan = matchingActivePlans.firstWhere(
        (plan) => plan['id'].toString() == activePlanId,
        orElse: () => matchingActivePlans.first,
      );
      return _ProfileSubscriptionVm(
        title: activePlan['name']?.toString() ?? 'Premium Plan',
        subtitle: expiresAt != null
            ? 'Valid until ${_formatDate(expiresAt)}'
            : 'Active for $examName',
        initialPlanId: activePlanId,
      );
    }

    return _ProfileSubscriptionVm(
      title: 'Free Plan',
      subtitle:
          'Upgrade to unlock ${examPlans.first['name'] ?? 'premium access'} for $examName',
      initialPlanId: recommendedPlanId,
    );
  }

  Widget _buildSubscriptionCardPlaceholder({bool showLoader = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3A53B7), Color(0xFF1F3A8A)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              showLoader
                  ? Icons.hourglass_top_rounded
                  : Icons.workspace_premium,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showLoader
                      ? 'Loading subscription details...'
                      : 'Subscription',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  showLoader
                      ? 'Fetching your plan info for the selected exam'
                      : 'Plan details will appear here shortly',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          if (showLoader)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
          if (snapshot.hasError) {
            return const OfflineState(
              message:
                  'Could not load your profile. Please check your connection and try again.',
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('User data not found'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final name = data['name'] ?? '';
          final photoUrl = (data['photoURL'] ?? '').toString().trim();
          final email = data['email'] ?? '';
          final phone = data['phone'] ?? '';
          final selectedExams = List<String>.from(data['selectedExams'] ?? []);
          final activePlanIds = List<String>.from(data['activePlanIds'] ?? []);
          final subscriptionIds = List<String>.from(
            data['subscriptionIds'] ?? [],
          );
          final effectiveSelectedExamId = _effectiveSelectedExamId(
            selectedExams,
          );

          return SafeArea(
            child: Column(
              children: [
                TopHeader(
                  selectedExamId: effectiveSelectedExamId,
                  userExamIds: selectedExams,
                  onExamChanged: (examId) {
                    if (!mounted) return;
                    setState(() {
                      selectedExamId = examId;
                    });
                  },
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      GestureDetector(
                                        onTap: photoUrl.isNotEmpty
                                            ? () => _showProfilePhotoPreview(
                                                photoUrl,
                                              )
                                            : _openEditProfile,
                                        child: Container(
                                          width: 72,
                                          height: 72,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: colorScheme.primary,
                                          ),
                                          alignment: Alignment.center,
                                          clipBehavior: Clip.antiAlias,
                                          child: photoUrl.isNotEmpty
                                              ? Image.network(
                                                  photoUrl,
                                                  width: 72,
                                                  height: 72,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) {
                                                        return Center(
                                                          child: Text(
                                                            _profileInitials(
                                                              data,
                                                            ),
                                                            style: TextStyle(
                                                              color: colorScheme
                                                                  .onPrimary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 20,
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                )
                                              : Text(
                                                  _profileInitials(data),
                                                  style: TextStyle(
                                                    color:
                                                        colorScheme.onPrimary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 20,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      Positioned(
                                        right: -2,
                                        bottom: -2,
                                        child: Material(
                                          color: colorScheme.surface,
                                          elevation: 3,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: _openEditProfile,
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: colorScheme
                                                    .primaryContainer,
                                              ),
                                              child: Icon(
                                                photoUrl.isNotEmpty
                                                    ? Icons.edit_outlined
                                                    : Icons
                                                          .add_a_photo_outlined,
                                                size: 16,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    photoUrl.isNotEmpty
                                        ? 'Edit Photo'
                                        : 'Add Photo',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
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
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        if (!isDeletingAccount)
                                          InkWell(
                                            onTap: () {
                                              _openEditProfile();
                                            },
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: colorScheme
                                                      .outlineVariant,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (email.isNotEmpty)
                                      Text(
                                        email,
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: 14,
                                        ),
                                      ),
                                    if (phone.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        phone,
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
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
                          child: !_showDeferredSubscriptionCard
                              ? _buildSubscriptionCardPlaceholder()
                              : FutureBuilder<_ProfileSubscriptionVm>(
                                  key: ValueKey<String?>(
                                    'subscription-${effectiveSelectedExamId ?? 'none'}',
                                  ),
                                  future: _getSubscriptionVm(
                                    examId: effectiveSelectedExamId,
                                    activePlanIds: activePlanIds,
                                    subscriptionIds: subscriptionIds,
                                  ),
                                  builder: (context, subSnap) {
                                    if (!subSnap.hasData) {
                                      return _buildSubscriptionCardPlaceholder(
                                        showLoader: true,
                                      );
                                    }

                                    final vm = subSnap.data!;

                                    return Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF3A53B7),
                                            Color(0xFF1F3A8A),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white24,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
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
                                                      vm.title,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      vm.subtitle,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (vm.initialPlanId != null) ...[
                                            const SizedBox(height: 14),
                                            SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton(
                                                onPressed: () {
                                                  Navigator.push<bool>(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          SubscriptionScreen(
                                                            initialExamId:
                                                                effectiveSelectedExamId,
                                                            initialPlanId: vm
                                                                .initialPlanId,
                                                          ),
                                                    ),
                                                  ).then((subscribed) {
                                                    if (subscribed == true) {
                                                      SubscriptionAccessService.clearCache();
                                                    }
                                                  });
                                                },
                                                style: OutlinedButton.styleFrom(
                                                  side: const BorderSide(
                                                    color: Colors.white24,
                                                  ),
                                                  minimumSize: const Size(
                                                    0,
                                                    40,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                                child: const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    vertical: 10,
                                                  ),
                                                  child: Text(
                                                    'Manage Subscription',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
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
                              Text(
                                'PERFORMANCE',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
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
                                            builder: (_) => TestHistoryScreen(
                                              initialExamId:
                                                  effectiveSelectedExamId,
                                            ),
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
                                                PerformanceTrendsScreen(
                                                  initialExamId:
                                                      effectiveSelectedExamId,
                                                ),
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
                              Text(
                                'ACCOUNT',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
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
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                        ),
                                        onTap: () {
                                          _openEditProfile();
                                        },
                                      ),
                                    const Divider(height: 1),
                                    const ThemeModeTile(),
                                    const Divider(height: 1),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.credit_card_outlined,
                                      ),
                                      title: const Text('Payment History'),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const PaymentHistoryScreen(),
                                          ),
                                        );
                                      },
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
                              Text(
                                'SUPPORT',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
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
                                      leading: const Icon(
                                        Icons.description_outlined,
                                      ),
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
                                      // trailing: const Icon(Icons.chevron_right),
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
                              Text(
                                'ACTIONS',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
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
                                      // trailing: const Icon(Icons.chevron_right),
                                      onTap: () => _confirmLogout(context),
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
                                      // trailing: const Icon(Icons.chevron_right),
                                      onTap: () =>
                                          _confirmDeleteAccount(context),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 30),
                        Center(
                          child: Text(
                            '$_appVersionLabel\n© 2026 Rank Sprint',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileSubscriptionVm {
  final String title;
  final String subtitle;
  final String? initialPlanId;

  const _ProfileSubscriptionVm({
    required this.title,
    required this.subtitle,
    this.initialPlanId,
  });
}
