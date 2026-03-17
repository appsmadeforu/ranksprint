import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

    final paymentsQuery = await FirebaseFirestore.instance
        .collection('subscriptions')
        .where('userId', isEqualTo: user.uid)
        .limit(1)
        .get();

    return _PaymentHistoryVm(
      userExamIds: userExamIds,
      selectedExamId: effectiveExamId,
      hasPayments: paymentsQuery.docs.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: FutureBuilder<_PaymentHistoryVm>(
        future: _loadVm(),
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
                    UserExamPreferenceService.savePreferredExamId(examId);
                    setState(() => _selectedExamId = examId);
                  },
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 520),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
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
                                color: const Color(0xFFEAF1FF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.receipt_long_rounded,
                                size: 34,
                                color: Color(0xFF2F3E8F),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Payment History',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              vm.hasPayments
                                  ? 'Your payment records will appear here.'
                                  : 'No subscriptions taken so far.',
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            if (!vm.hasPayments) ...[
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => SubscriptionScreen(
                                          initialExamId: effectiveSelectedExamId,
                                        ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2F3E8F),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text(
                                    'Subscribe Now',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                        ],
                      ),
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

class _PaymentHistoryVm {
  const _PaymentHistoryVm({
    required this.userExamIds,
    this.selectedExamId,
    this.hasPayments = false,
  });

  final List<String> userExamIds;
  final String? selectedExamId;
  final bool hasPayments;
}
