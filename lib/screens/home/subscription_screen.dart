import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class SubscriptionScreen extends StatefulWidget {
  final String? initialPlanId;
  final String? initialExamId;
  final String? lockedItemLabel;
  final String? lockedItemType;

  const SubscriptionScreen({
    super.key,
    this.initialPlanId,
    this.initialExamId,
    this.lockedItemLabel,
    this.lockedItemType,
  });

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String selectedPlanId = '';
  final TextEditingController _couponController = TextEditingController();
  final InAppPurchase _iap = InAppPurchase.instance;

  List<Map<String, dynamic>> subscriptionPlans = [];
  String? selectedExamId;
  bool isLoadingPlans = false;
  bool _isPurchasing = false;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  @override
  void initState() {
    super.initState();
    selectedPlanId = widget.initialPlanId ?? '';
    selectedExamId = widget.initialExamId;
    _listenToPurchases();
    _loadSubscriptionPlans();
  }

  void _listenToPurchases() {
    _purchaseSubscription = _iap.purchaseStream.listen(
      (purchaseDetailsList) async {
        for (final purchase in purchaseDetailsList) {
          if (purchase.status == PurchaseStatus.pending) {
            if (mounted) {
              setState(() => _isPurchasing = true);
            }
            continue;
          }

          if (purchase.status == PurchaseStatus.error) {
            if (mounted) {
              setState(() => _isPurchasing = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    purchase.error?.message ?? 'Purchase failed. Try again.',
                  ),
                ),
              );
            }
          }

          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            await _grantSubscriptionForPurchase(purchase);
            if (mounted) {
              setState(() => _isPurchasing = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Subscription activated.')),
              );
            }
          }

          if (purchase.status == PurchaseStatus.canceled && mounted) {
            setState(() => _isPurchasing = false);
          }

          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isPurchasing = false);
      },
    );
  }

  /// LOAD PLANS FROM FIRESTORE
  Future<void> _loadSubscriptionPlans() async {
    setState(() => isLoadingPlans = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('subscriptionPlans')
          .where('isActive', isEqualTo: true)
          .get();

      final plans = <Map<String, dynamic>>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();

        final rawExamsIncluded = data['examsIncluded'];
        final examsIncluded = <String, dynamic>{};

        if (rawExamsIncluded is Map) {
          examsIncluded.addAll(
            rawExamsIncluded.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
        } else if (rawExamsIncluded is Iterable) {
          for (final examId in rawExamsIncluded) {
            final id = examId.toString();
            if (id.isNotEmpty) {
              examsIncluded[id] = const <String, dynamic>{};
            }
          }
        }

        plans.add({
          'id': doc.id,
          'name': data['name'] ?? 'Plan',
          'durationDays': data['durationDays'] ?? 30,
          'duration': _getDurationString(data['durationDays'] ?? 30),
          'price': (data['price'] ?? 0).toInt(),
          'discount': data['discountPercentage'] ?? 0,
          'originalPrice': _calculateOriginalPrice(
            (data['price'] ?? 0).toInt(),
            (data['discountPercentage'] ?? 0).toInt(),
          ),
          'storeProductId':
              (data['storeProductId'] ??
                      data['productId'] ??
                      data['playProductId'] ??
                      data['androidProductId'] ??
                      data['appStoreProductId'] ??
                      data['iosProductId'] ??
                      '')
                  .toString(),
          'examsIncluded': examsIncluded,
        });
      }

      plans.sort((a, b) => (a['price'] as int).compareTo(b['price'] as int));

      setState(() {
        subscriptionPlans = plans;
        if (plans.isNotEmpty) {
          if (selectedPlanId.isEmpty ||
              !plans.any((plan) => plan['id'] == selectedPlanId)) {
            selectedPlanId = _resolveInitialPlanId(plans);
          }
          selectedExamId ??= _resolveInitialExamId(plans, selectedPlanId);
        }
        isLoadingPlans = false;
      });
    } catch (e) {
      debugPrint("Plan load error: $e");
      setState(() => isLoadingPlans = false);
    }
  }

  String _getDurationString(int days) {
    if (days == 30) return '1 Month';
    if (days == 90) return '3 Months';
    if (days == 180) return '6 Months';
    if (days == 365) return '12 Months';
    return '$days Days';
  }

  int _calculateOriginalPrice(int price, int discount) {
    if (discount == 0) return price;
    return (price / (1 - discount / 100)).toInt();
  }

  Map<String, dynamic>? _selectedPlanOrNull() {
    if (subscriptionPlans.isEmpty) return null;
    for (final p in subscriptionPlans) {
      if (p['id'] == selectedPlanId) return p;
    }
    return subscriptionPlans.first;
  }

  String _resolveInitialPlanId(List<Map<String, dynamic>> plans) {
    if (widget.initialPlanId != null &&
        plans.any((plan) => plan['id'] == widget.initialPlanId)) {
      return widget.initialPlanId!;
    }

    if (widget.initialExamId != null) {
      for (final plan in plans) {
        final examsIncluded = Map<String, dynamic>.from(
          plan['examsIncluded'] ?? const <String, dynamic>{},
        );
        if (examsIncluded.containsKey(widget.initialExamId)) {
          return plan['id'].toString();
        }
      }
    }

    return plans.first['id'].toString();
  }

  String? _resolveInitialExamId(
    List<Map<String, dynamic>> plans,
    String planId,
  ) {
    for (final plan in plans) {
      if (plan['id'] != planId) continue;

      final examsIncluded = Map<String, dynamic>.from(
        plan['examsIncluded'] ?? const <String, dynamic>{},
      );

      if (widget.initialExamId != null &&
          examsIncluded.containsKey(widget.initialExamId)) {
        return widget.initialExamId;
      }

      if (examsIncluded.isNotEmpty) {
        return examsIncluded.keys.first;
      }
    }

    return widget.initialExamId;
  }

  Future<void> _startPurchase() async {
    final plan = _selectedPlanOrNull();
    if (plan == null) return;

    final productId = (plan['storeProductId'] ?? '').toString().trim();
    if (productId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing storeProductId in selected subscription plan.'),
        ),
      );
      return;
    }

    final available = await _iap.isAvailable();
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('In-app purchases are not available.')),
      );
      return;
    }

    if (mounted) {
      setState(() => _isPurchasing = true);
    }

    final response = await _iap.queryProductDetails({productId});
    if (!mounted) return;

    if (response.error != null) {
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.error!.message.isNotEmpty
                ? response.error!.message
                : 'Unable to load product details.',
          ),
        ),
      );
      return;
    }

    if (response.notFoundIDs.contains(productId) ||
        response.productDetails.isEmpty) {
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Product not found in store: $productId')),
      );
      return;
    }

    final product = response.productDetails.first;
    final purchaseParam = PurchaseParam(productDetails: product);
    final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    if (!started && mounted) {
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start purchase flow.')),
      );
    }
  }

  Future<void> _grantSubscriptionForPurchase(PurchaseDetails purchase) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final plan = subscriptionPlans.where((p) {
      return (p['storeProductId'] ?? '').toString() == purchase.productID;
    }).firstWhere(
      (_) => true,
      orElse: () => _selectedPlanOrNull() ?? <String, dynamic>{},
    );
    if (plan.isEmpty) return;

    final durationDays = (plan['durationDays'] ?? 30) as int;
    final now = DateTime.now();
    final expiresAt = now.add(Duration(days: durationDays));
    final subRef = FirebaseFirestore.instance.collection('subscriptions').doc();

    await subRef.set({
      'userId': user.uid,
      'planId': plan['id'],
      'status': 'active',
      'source': 'iap',
      'productId': purchase.productID,
      'purchaseId': purchase.purchaseID ?? '',
      'startedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'subscriptionStatus': 'paid',
      'subscriptionIds': FieldValue.arrayUnion([subRef.id]),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingPlans) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedPlan = _selectedPlanOrNull();
    if (selectedPlan == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: const Text('Subscription'),
          backgroundColor: const Color(0xFF2F3E8F),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('No active subscription plans available right now.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Column(
        children: [
          /// HEADER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
            color: const Color(0xFF2F3E8F),
            child: Column(
              children: const [
                Icon(Icons.workspace_premium, color: Colors.orange, size: 40),
                SizedBox(height: 8),
                Text(
                  "Unlock Premium",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Get unlimited access to all features",
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),

          /// CONTENT
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if ((widget.lockedItemLabel ?? '').isNotEmpty)
                    _sectionCard(
                      color: const Color(0xFFFFF4E8),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline, color: Colors.orange),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Unlock ${widget.lockedItemType ?? 'content'}: ${widget.lockedItemLabel}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  /// PLAN CARDS
                  ...subscriptionPlans.map((plan) {
                    final isSelected = plan['id'] == selectedPlanId;
                    final isPopular = plan['durationDays'] == 180;

                    return GestureDetector(
                      onTap: () => setState(() => selectedPlanId = plan['id']),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF2F3E8F)
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: isSelected
                                  ? const Color(0xFF2F3E8F)
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 12),

                            /// TEXT
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        plan['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (isPopular) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            "Most Popular",
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    plan['duration'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            /// PRICE
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "₹${plan['originalPrice']}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    decoration: TextDecoration.lineThrough,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      "₹${plan['price']}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${plan['discount']}% OFF",
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  /// INCLUDED
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "What's Included",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 10),
                        _Feature("Access to all mock tests"),
                        _Feature("Unlimited test attempts"),
                        _Feature("Previous year questions"),
                        _Feature("Detailed analytics"),
                        _Feature("National rank comparison"),
                        _Feature("Live doubt solving"),
                        _Feature("Study materials"),
                        _Feature("Ad-free experience"),
                      ],
                    ),
                  ),

                  /// COUPON
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Have a Coupon Code?",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _couponController,
                                decoration: InputDecoration(
                                  hintText: "Enter coupon code",
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () {},
                              child: const Text("Apply"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  /// SECURE
                  _sectionCard(
                    color: const Color(0xFFEAF4FF),
                    child: Row(
                      children: const [
                        Icon(Icons.verified, color: Colors.green),
                        SizedBox(width: 8),
                        Text("100% Secure Payment"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),

      /// BOTTOM BAR
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: Text(
                "₹${selectedPlan['price']}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _isPurchasing ? null : _startPurchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isPurchasing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text("Subscribe Now"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required Widget child, Color? color}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _couponController.dispose();
    super.dispose();
  }
}

/// FEATURE ROW (OUTSIDE MAIN CLASS)
class _Feature extends StatelessWidget {
  final String text;
  const _Feature(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
