import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/subscription_access_service.dart';
import '../../services/user_exam_preference_service.dart';
import '../../widgets/top_header.dart';
import 'subscription_screen.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  String? _selectedExamId;
  Future<_PaymentHistoryVm>? _vmFuture;

  @override
  void initState() {
    super.initState();
    _vmFuture = _loadVm();
  }

  void _reload() {
    setState(() {
      _vmFuture = _loadVm();
    });
  }

  Future<_PaymentHistoryVm> _loadVm() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _PaymentHistoryVm(userExamIds: []);
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = userDoc.data() ?? const <String, dynamic>{};
    final userExamIds = List<String>.from(data['selectedExams'] ?? const []);
    final preferredExamId = await UserExamPreferenceService.loadPreferredExamId(
      availableExamIds: userExamIds,
    );
    final effectiveExamId = userExamIds.contains(_selectedExamId)
        ? _selectedExamId
        : (userExamIds.contains(preferredExamId)
              ? preferredExamId
              : (userExamIds.isNotEmpty ? userExamIds.first : null));

    final subscriptionsSnap = await FirebaseFirestore.instance
        .collection('subscriptions')
        .where('userId', isEqualTo: user.uid)
        .get();

    final planIds = <String>{};
    for (final doc in subscriptionsSnap.docs) {
      final planId = (doc.data()['planId'] ?? '').toString().trim();
      if (planId.isNotEmpty) planIds.add(planId);
    }

    final planNames = <String, String>{};
    for (final planId in planIds) {
      try {
        final planDoc = await FirebaseFirestore.instance
            .collection('subscriptionPlans')
            .doc(planId)
            .get();
        if (planDoc.exists) {
          final planData = planDoc.data() ?? {};
          final features = planData['features'];
          final featuresMap = features is Map
              ? features.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          planNames[planId] = (featuresMap['name'] ??
                  planData['name'] ??
                  'Plan')
              .toString();
        }
      } catch (_) {}
    }

    final payments = <_PaymentRecord>[];
    final now = DateTime.now();

    for (final doc in subscriptionsSnap.docs) {
      final d = doc.data();
      final planId = (d['planId'] ?? '').toString().trim();
      final status = (d['status'] ?? '').toString();
      final source = (d['source'] ?? '').toString();
      final originalPrice = ((d['originalPrice'] ?? 0) as num).toInt();
      final finalPrice = ((d['finalPrice'] ?? 0) as num).toInt();
      final couponCode = (d['couponCode'] ?? '').toString();

      DateTime? startedAt;
      final rawStart = d['startedAt'];
      if (rawStart is Timestamp) startedAt = rawStart.toDate();

      DateTime? expiresAt;
      final rawExpiry = d['expiresAt'];
      if (rawExpiry is Timestamp) expiresAt = rawExpiry.toDate();

      final isExpired = expiresAt != null && expiresAt.isBefore(now);
      final effectiveStatus = isExpired && status == 'active' ? 'expired' : status;

      payments.add(_PaymentRecord(
        id: doc.id,
        planId: planId,
        planName: planNames[planId] ?? planId,
        status: effectiveStatus,
        source: source,
        originalPrice: originalPrice,
        finalPrice: finalPrice,
        couponCode: couponCode,
        startedAt: startedAt,
        expiresAt: expiresAt,
      ));
    }

    payments.sort((a, b) {
      final aTime = a.startedAt ?? DateTime(2000);
      final bTime = b.startedAt ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    return _PaymentHistoryVm(
      userExamIds: userExamIds,
      selectedExamId: effectiveExamId,
      payments: payments,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: FutureBuilder<_PaymentHistoryVm>(
        future: _vmFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final vm = snapshot.data!;
          final effectiveSelectedExamId = vm.userExamIds.contains(_selectedExamId)
              ? _selectedExamId
              : vm.selectedExamId;
          _selectedExamId = effectiveSelectedExamId;

          return SafeArea(
            child: Column(
              children: [
                TopHeader(
                  selectedExamId: effectiveSelectedExamId,
                  userExamIds: vm.userExamIds,
                  onExamChanged: (examId) {
                    setState(() => _selectedExamId = examId);
                  },
                  showBackButton: true,
                  enableTitleNavigation: false,
                ),
                Expanded(
                  child: vm.payments.isEmpty
                      ? _buildEmptyState(effectiveSelectedExamId)
                      : _buildPaymentList(vm.payments),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String? examId) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.receipt_long_rounded,
                size: 34,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Payment History',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'No subscriptions taken so far.',
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => SubscriptionScreen(
                        initialExamId: examId,
                      ),
                    ),
                  ).then((subscribed) {
                    if (subscribed == true) {
                      SubscriptionAccessService.clearCache();
                      _reload();
                    }
                  });
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Subscribe Now',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentList(List<_PaymentRecord> payments) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: payments.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          final colorScheme = Theme.of(context).colorScheme;
          return Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Text(
              'Payment History',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
          );
        }
        return _buildPaymentCard(payments[index - 1]);
      },
    );
  }

  Widget _buildPaymentCard(_PaymentRecord record) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _statusColor(record.status);
    final statusLabel = _statusLabel(record.status);
    final sourceLabel = _sourceLabel(record.source);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    record.status == 'active'
                        ? Icons.check_circle_outline
                        : Icons.history,
                    color: statusColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.planName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sourceLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildDetailRow(
                    'Amount Paid',
                    record.finalPrice == 0
                        ? 'Free'
                        : '₹${record.finalPrice}',
                  ),
                  if (record.originalPrice > record.finalPrice) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Original Price',
                      '₹${record.originalPrice}',
                      valueStyle: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                  if (record.couponCode.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow('Coupon', record.couponCode),
                  ],
                  if (record.startedAt != null) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Purchased On',
                      _formatDate(record.startedAt!),
                    ),
                  ],
                  if (record.expiresAt != null) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Valid Until',
                      _formatDate(record.expiresAt!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {TextStyle? valueStyle}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: valueStyle ??
              TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    final year = dt.year;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year, $hour:$minute $period';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF16A34A);
      case 'expired':
        return const Color(0xFFD97706);
      case 'canceled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'expired':
        return 'Expired';
      case 'canceled':
        return 'Cancelled';
      default:
        return status.isNotEmpty
            ? '${status[0].toUpperCase()}${status.substring(1)}'
            : 'Unknown';
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'iap':
        return 'Google Play Purchase';
      case 'coupon':
        return 'Coupon Redemption';
      case 'restore':
        return 'Restored Purchase';
      default:
        return source.isNotEmpty
            ? '${source[0].toUpperCase()}${source.substring(1)}'
            : 'Purchase';
    }
  }
}

class _PaymentHistoryVm {
  const _PaymentHistoryVm({
    required this.userExamIds,
    this.selectedExamId,
    this.payments = const [],
  });

  final List<String> userExamIds;
  final String? selectedExamId;
  final List<_PaymentRecord> payments;
}

class _PaymentRecord {
  const _PaymentRecord({
    required this.id,
    required this.planId,
    required this.planName,
    required this.status,
    required this.source,
    required this.originalPrice,
    required this.finalPrice,
    required this.couponCode,
    this.startedAt,
    this.expiresAt,
  });

  final String id;
  final String planId;
  final String planName;
  final String status;
  final String source;
  final int originalPrice;
  final int finalPrice;
  final String couponCode;
  final DateTime? startedAt;
  final DateTime? expiresAt;
}
