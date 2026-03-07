import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;

  String selectedPlanId = '';
  final TextEditingController _couponController = TextEditingController();

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  List<Map<String, dynamic>> subscriptionPlans = [];
  bool isLoadingPlans = false;
  bool isStoreAvailable = false;
  bool isPurchasing = false;
  String? purchaseError;
  final Map<String, ProductDetails> _productsById = {};

  @override
  void initState() {
    super.initState();
    _initInAppPurchase();
    _loadSubscriptionPlans();
  }

  Future<void> _initInAppPurchase() async {
    if (kIsWeb) {
      setState(() {
        isStoreAvailable = false;
        purchaseError = 'In-app purchases are available only on Android/iOS.';
      });
      return;
    }

    final available = await _inAppPurchase.isAvailable();
    if (!mounted) return;

    setState(() {
      isStoreAvailable = available;
      if (!available) {
        purchaseError = 'Store is unavailable. Please try again later.';
      }
    });

    if (!available) return;

    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdated,
      onDone: () => _purchaseSubscription?.cancel(),
      onError: (error) {
        if (!mounted) return;
        setState(() {
          isPurchasing = false;
          purchaseError = 'Purchase stream error: $error';
        });
      },
    );
  }

  Future<void> _loadSubscriptionPlans() async {
    setState(() => isLoadingPlans = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('subscriptionPlans')
          .where('isActive', isEqualTo: true)
          .get();

      final plans = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();

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
          'productId': data['productId'] ?? '',
          'androidProductId': '1:860899860233:android:b9b9f1c4b77504be633dd8',
          'iosProductId': data['iosProductId'] ?? '',
        });
      }

      plans.sort((a, b) => (a['price'] as int).compareTo(b['price'] as int));

      setState(() {
        subscriptionPlans = plans;
        if (plans.isNotEmpty) selectedPlanId = plans.first['id'];
        isLoadingPlans = false;
      });

      await _loadStoreProducts(plans);
    } catch (e) {
      debugPrint('Plan load error: $e');
      setState(() => isLoadingPlans = false);
    }
  }

  String _productIdForPlan(Map<String, dynamic> plan) {
    final platformKey = _isIOS ? 'iosProductId' : 'androidProductId';
    return (plan[platformKey] ?? plan['productId'] ?? '').toString();
  }

  Future<void> _loadStoreProducts(List<Map<String, dynamic>> plans) async {
    if (!isStoreAvailable || kIsWeb) return;

    final ids = plans
        .map(_productIdForPlan)
        .where((id) => id.isNotEmpty)
        .toSet();

    if (ids.isEmpty) {
      if (!mounted) return;
      setState(() {
        purchaseError =
            'No in-app product IDs found in plans. Add productId/androidProductId/iosProductId in Firestore.';
      });
      return;
    }

    final response = await _inAppPurchase.queryProductDetails(ids);
    if (!mounted) return;

    if (response.error != null) {
      setState(() {
        purchaseError = response.error!.message;
      });
      return;
    }

    final products = <String, ProductDetails>{};
    for (final p in response.productDetails) {
      products[p.id] = p;
    }

    setState(() {
      _productsById
        ..clear()
        ..addAll(products);
      if (response.notFoundIDs.isNotEmpty) {
        purchaseError =
            'Products not found: ${response.notFoundIDs.join(', ')}';
      }
    });
  }

  Future<void> _subscribeSelectedPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('Please login to subscribe.');
      return;
    }

    if (selectedPlanId.isEmpty) {
      _showSnack('Please select a plan.');
      return;
    }

    if (!isStoreAvailable || kIsWeb) {
      _showSnack('In-app purchases are not available on this device.');
      return;
    }

    final plan = subscriptionPlans.firstWhere((p) => p['id'] == selectedPlanId);
    final productId = _productIdForPlan(plan);
    final product = _productsById[productId];

    if (product == null) {
      _showSnack('Product not available in store. Please try later.');
      return;
    }

    setState(() {
      isPurchasing = true;
      purchaseError = null;
    });

    final purchaseParam = PurchaseParam(
      productDetails: product,
      applicationUserName: user.uid,
    );

    final started = await _inAppPurchase.buyNonConsumable(
      purchaseParam: purchaseParam,
    );

    if (!started && mounted) {
      setState(() => isPurchasing = false);
      _showSnack('Could not start purchase flow.');
    }
  }

  Future<void> _restorePurchases() async {
    if (!isStoreAvailable || kIsWeb) {
      _showSnack('Restore not available on this platform.');
      return;
    }
    await _inAppPurchase.restorePurchases();
    _showSnack('Restore request sent. Processing...');
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) {
          setState(() => isPurchasing = true);
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() {
            isPurchasing = false;
            purchaseError = purchase.error?.message ?? 'Purchase failed.';
          });
        }
        _showSnack(purchaseError ?? 'Purchase failed.');
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final activated = await _activatePurchasedPlan(purchase);
        if (mounted) {
          setState(() => isPurchasing = false);
        }
        if (activated) {
          _showSnack('Subscription activated successfully.');
        } else {
          _showSnack('Purchase received but plan activation failed.');
        }
      }

      if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
      }
    }
  }

  Future<bool> _activatePurchasedPlan(PurchaseDetails purchase) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      Map<String, dynamic>? plan;
      for (final p in subscriptionPlans) {
        if (_productIdForPlan(p) == purchase.productID) {
          plan = p;
          break;
        }
      }

      if (plan == null) return false;

      final durationDays = (plan['durationDays'] as int?) ?? 30;
      final now = DateTime.now();
      final expiresAt = now.add(Duration(days: durationDays));

      final subRef = FirebaseFirestore.instance
          .collection('subscriptions')
          .doc();
      final batch = FirebaseFirestore.instance.batch();

      batch.set(subRef, {
        'userId': user.uid,
        'planId': plan['id'],
        'status': 'active',
        'provider': _isIOS ? 'app_store' : 'google_play',
        'productId': purchase.productID,
        'purchaseId': purchase.purchaseID ?? '',
        'transactionDate': purchase.transactionDate ?? '',
        'verificationData': purchase.verificationData.serverVerificationData,
        'localVerificationData':
            purchase.verificationData.localVerificationData,
        'source': purchase.verificationData.source,
        'couponCode': _couponController.text.trim(),
        'createdAt': Timestamp.fromDate(now),
        'startedAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      batch.set(userRef, {
        'subscriptionStatus': 'paid',
        'subscriptionIds': FieldValue.arrayUnion([subRef.id]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('Activate purchase error: $e');
      return false;
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingPlans) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (subscriptionPlans.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No subscription plans available right now.')),
      );
    }

    final selectedPlan = subscriptionPlans.firstWhere(
      (p) => p['id'] == selectedPlanId,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
            color: const Color(0xFF2F3E8F),
            child: Column(
              children: const [
                Icon(Icons.workspace_premium, color: Colors.orange, size: 40),
                SizedBox(height: 8),
                Text(
                  'Unlock Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Get unlimited access to all features',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
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
                                            'Most Popular',
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "Rs ${plan['originalPrice']}",
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
                                      "Rs ${plan['price']}",
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
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "What's Included",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 10),
                        _Feature('Access to all mock tests'),
                        _Feature('Unlimited test attempts'),
                        _Feature('Previous year questions'),
                        _Feature('Detailed analytics'),
                        _Feature('National rank comparison'),
                        _Feature('Live doubt solving'),
                        _Feature('Study materials'),
                        _Feature('Ad-free experience'),
                      ],
                    ),
                  ),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Have a Coupon Code?',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _couponController,
                                decoration: InputDecoration(
                                  hintText: 'Enter coupon code',
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
                              child: const Text('Apply'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _sectionCard(
                    color: const Color(0xFFEAF4FF),
                    child: Row(
                      children: const [
                        Icon(Icons.verified, color: Colors.green),
                        SizedBox(width: 8),
                        Text('100% Secure Payment'),
                      ],
                    ),
                  ),
                  if (purchaseError != null)
                    _sectionCard(
                      color: const Color(0xFFFFF4F4),
                      child: Text(
                        purchaseError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: Text(
                "Rs ${selectedPlan['price']}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: isPurchasing ? null : _restorePurchases,
              child: const Text('Restore'),
            ),
            ElevatedButton(
              onPressed: isPurchasing ? null : _subscribeSelectedPlan,
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
              child: isPurchasing
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Subscribe Now'),
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
