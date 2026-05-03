import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import '../../services/subscription_backend_service.dart';
import '../../services/subscription_access_service.dart';

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
  String? _selectedExamName;
  List<String> _selectedExamPlanIds = const [];
  bool isLoadingPlans = false;
  bool _isPurchasing = false;
  bool _isApplyingCoupon = false;
  bool _isRestoring = false;
  Map<String, dynamic>? _appliedCoupon;
  String? _pendingPurchasePlanId;
  String? _couponFeedback;
  bool _couponFeedbackIsError = false;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  @override
  void initState() {
    super.initState();
    selectedPlanId = widget.initialPlanId ?? '';
    selectedExamId = widget.initialExamId;
    _listenToPurchases();
    _loadSubscriptionPlans();
  }

  Future<void> _loadSelectedExamContext() async {
    if (selectedExamId == null || selectedExamId!.isEmpty) {
      _selectedExamName = null;
      _selectedExamPlanIds = const [];
      return;
    }

    try {
      final examDoc = await FirebaseFirestore.instance
          .collection('exams')
          .doc(selectedExamId)
          .get();
      final examData = examDoc.data() ?? const <String, dynamic>{};
      _selectedExamName = (examData['name'] ?? selectedExamId).toString();
      _selectedExamPlanIds = List<String>.from(
        examData['subscriptionPlanIds'] ?? const <String>[],
      );
    } catch (_) {
      _selectedExamName = selectedExamId;
      _selectedExamPlanIds = const [];
    }
  }

  void _listenToPurchases() {
    _purchaseSubscription = _iap.purchaseStream.listen(
      (purchaseDetailsList) async {
        for (final purchase in purchaseDetailsList) {
          try {
            if (purchase.status == PurchaseStatus.pending) {
              if (mounted) {
                setState(() => _isPurchasing = true);
              }
              continue;
            }

            if (purchase.status == PurchaseStatus.error) {
              if (mounted) {
                setState(() => _isPurchasing = false);
                _showPurchaseErrorDialog(_friendlyBillingError(purchase.error));
              }
            }

            if (purchase.status == PurchaseStatus.purchased ||
                purchase.status == PurchaseStatus.restored) {
              await _finalizeSubscriptionForPurchase(purchase);
              if (mounted) {
                setState(() {
                  _isPurchasing = false;
                  _isRestoring = false;
                });
                _showSuccessAndPop();
              }
            }

            if (purchase.status == PurchaseStatus.canceled && mounted) {
              setState(() {
                _isPurchasing = false;
                _isRestoring = false;
              });
            }
          } catch (error) {
            debugPrint('Subscription finalize error: $error');
            if (mounted) {
              setState(() {
                _isPurchasing = false;
                _isRestoring = false;
              });
              _showPurchaseErrorDialog((
                title: 'Activation Failed',
                body: _friendlyPurchaseError(error),
                code: null,
              ));
            }
          } finally {
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
          }
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _isPurchasing = false;
          _isRestoring = false;
        });
      },
    );
  }

  /// LOAD PLANS FROM FIRESTORE
  Future<void> _loadSubscriptionPlans() async {
    setState(() => isLoadingPlans = true);

    try {
      await _loadSelectedExamContext();
      final snapshot = await FirebaseFirestore.instance
          .collection('subscriptionPlans')
          .get();

      final plans = <Map<String, dynamic>>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final features = _asStringMap(data['features']);
        final isActive = _isPlanActive(data, features);
        if (!isActive) {
          continue;
        }

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
          'name': (features['name'] ?? data['name'] ?? 'Plan').toString(),
          'durationDays': data['durationDays'] ?? 30,
          'duration': _getDurationString(data['durationDays'] ?? 30),
          'price': ((features['price'] ?? data['price'] ?? 0) as num).toInt(),
          'discount':
              ((features['discountPercentage'] ??
                          data['discountPercentage'] ??
                          0)
                      as num)
                  .toInt(),
          'originalPrice': _calculateOriginalPrice(
            ((features['price'] ?? data['price'] ?? 0) as num).toInt(),
            ((features['discountPercentage'] ?? data['discountPercentage'] ?? 0)
                    as num)
                .toInt(),
          ),
          'storeProductId':
              (features['storeProductId'] ??
                      data['storeProductId'] ??
                      data['productId'] ??
                      data['playProductId'] ??
                      data['androidProductId'] ??
                      data['appStoreProductId'] ??
                      data['iosProductId'] ??
                      '')
                  .toString(),
          'playBasePlanId':
              (features['playBasePlanId'] ??
                      features['googlePlayBasePlanId'] ??
                      data['playBasePlanId'] ??
                      data['googlePlayBasePlanId'] ??
                      data['basePlanId'] ??
                      '')
                  .toString(),
          'playOfferId':
              (features['playOfferId'] ??
                      features['googlePlayOfferId'] ??
                      data['playOfferId'] ??
                      data['googlePlayOfferId'] ??
                      '')
                  .toString(),
          'examsIncluded': examsIncluded,
        });
      }

      plans.sort((a, b) => (a['price'] as int).compareTo(b['price'] as int));

      if (plans.isNotEmpty) {
        if (selectedPlanId.isEmpty ||
            !plans.any((plan) => plan['id'] == selectedPlanId)) {
          selectedPlanId = _resolveInitialPlanId(plans);
        }
        selectedExamId ??= _resolveInitialExamId(plans, selectedPlanId);
        await _loadSelectedExamContext();
      }

      setState(() {
        subscriptionPlans = plans;
        if (plans.isNotEmpty) {
          _syncSelectionWithExam();
        }
        isLoadingPlans = false;
      });
    } catch (e) {
      debugPrint("Plan load error: $e");
      setState(() => isLoadingPlans = false);
    }
  }

  bool _isPlanActive(Map<String, dynamic> data, Map<String, dynamic> features) {
    if (features['isActive'] is bool) {
      return features['isActive'] == true;
    }
    if (data['isActive'] is bool) {
      return data['isActive'] == true;
    }
    return true;
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
    final visiblePlans = _visiblePlans();
    if (visiblePlans.isEmpty) return null;
    for (final p in visiblePlans) {
      if (p['id'] == selectedPlanId) return p;
    }
    return visiblePlans.first;
  }

  List<Map<String, dynamic>> _visiblePlans() {
    if (selectedExamId == null || selectedExamId!.isEmpty) {
      return subscriptionPlans;
    }

    return subscriptionPlans.where(_planMatchesSelectedExam).toList();
  }

  bool _planMatchesSelectedExam(Map<String, dynamic> plan) {
    final examId = selectedExamId;
    if (examId == null || examId.isEmpty) {
      return true;
    }

    final planId = plan['id'].toString();
    if (_selectedExamPlanIds.contains(planId)) {
      return true;
    }

    return SubscriptionAccessService.planIncludesExam(
      plan['examsIncluded'],
      examId,
    );
  }

  void _syncSelectionWithExam() {
    final visiblePlans = _visiblePlans();
    if (visiblePlans.isEmpty) {
      selectedPlanId = '';
      return;
    }

    if (selectedPlanId.isNotEmpty &&
        visiblePlans.any((plan) => plan['id'] == selectedPlanId)) {
      return;
    }

    selectedPlanId = visiblePlans.first['id'].toString();
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

    final effectivePrice = _effectivePriceForPlan(plan);
    if (effectivePrice <= 0) {
      await _redeemFreeCoupon(plan);
      return;
    }

    _pendingPurchasePlanId = plan['id'].toString();

    final productId = _productIdForPlan(plan);
    if (productId.isEmpty) {
      if (!mounted) return;
      _showPurchaseErrorDialog((
        title: 'Plan Not Configured',
        body:
            'This plan is not linked to a store product yet. Please contact support.',
        code: 'MISSING_PRODUCT_ID',
      ));
      return;
    }

    final available = await _iap.isAvailable();
    if (!available) {
      if (!mounted) return;
      _showPurchaseErrorDialog((
        title: 'Store Unavailable',
        body:
            'In-app purchases are not available on this device. Please make sure you are signed in to Google Play.',
        code: 'IAP_UNAVAILABLE',
      ));
      return;
    }

    if (mounted) {
      setState(() => _isPurchasing = true);
    }

    final response = await _iap.queryProductDetails({productId});
    if (!mounted) return;

    if (response.error != null) {
      setState(() => _isPurchasing = false);
      _showPurchaseErrorDialog((
        title: 'Store Error',
        body:
            'Could not load product details from Google Play. Please check your internet connection and try again.',
        code: response.error!.code,
      ));
      return;
    }

    if (response.notFoundIDs.contains(productId) ||
        response.productDetails.isEmpty) {
      setState(() => _isPurchasing = false);
      _showPurchaseErrorDialog((
        title: 'Plan Unavailable',
        body:
            'This plan could not be found on Google Play. It may have been removed or is not available in your region.',
        code: 'PRODUCT_NOT_FOUND',
      ));
      return;
    }

    final productSelection = _selectProductDetailsForPlan(
      plan,
      response.productDetails,
    );
    if (!productSelection.isValid) {
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(productSelection.errorMessage)));
      return;
    }

    final purchaseParam = _buildPurchaseParamForPlan(
      plan,
      productSelection.product!,
    );
    final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    if (!started && mounted) {
      _pendingPurchasePlanId = null;
      setState(() => _isPurchasing = false);
      _showPurchaseErrorDialog((
        title: 'Purchase Not Started',
        body: 'Google Play could not start the purchase. Please try again.',
        code: null,
      ));
    }
  }

  Future<void> _finalizeSubscriptionForPurchase(
    PurchaseDetails purchase,
  ) async {
    final pendingPlanId = _pendingPurchasePlanId;
    final plan = pendingPlanId != null
        ? subscriptionPlans.firstWhere(
            (p) => p['id'].toString() == pendingPlanId,
            orElse: () => <String, dynamic>{},
          )
        : subscriptionPlans
              .where((p) {
                return (p['storeProductId'] ?? '').toString() ==
                    purchase.productID;
              })
              .firstWhere(
                (_) => true,
                orElse: () => _selectedPlanOrNull() ?? <String, dynamic>{},
              );
    if (plan.isEmpty) return;

    await SubscriptionBackendService.finalizePurchase(
      planId: plan['id'].toString(),
      examId: selectedExamId ?? '',
      purchase: purchase,
      couponCode: (_appliedCoupon?['id'] ?? '').toString(),
    );
    _pendingPurchasePlanId = null;
    SubscriptionAccessService.clearCache();
  }

  void _showSuccessAndPop() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.check_circle,
          color: Color(0xFF4CAF50),
          size: 56,
        ),
        title: const Text('Subscription Activated!'),
        content: Text(
          widget.lockedItemLabel != null
              ? '"${widget.lockedItemLabel}" is now unlocked. Redirecting you back...'
              : 'Your subscription is now active. Enjoy full access!',
          textAlign: TextAlign.center,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F6FEB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(true);
              },
              child: const Text('Continue', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    ).then((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    });
  }

  String _friendlyPurchaseError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.contains('OR_CSE_05')) {
      return 'Google Play could not open the checkout. Please try again later.';
    }
    if (message.contains('Purchase product does not match the selected plan')) {
      return 'The purchased product does not match the selected plan. Please contact support.';
    }
    if (message.contains('Missing purchase verification data')) {
      return 'Payment completed but verification failed. Please contact support if your plan is not activated.';
    }
    if (message.contains('Subscription plan not found')) {
      return 'This subscription plan is no longer available.';
    }
    if (message.contains('Subscription plan is inactive')) {
      return 'This subscription plan is currently unavailable.';
    }
    if (message.contains('PERMISSION_DENIED') ||
        message.contains('permission-denied')) {
      return 'You do not have permission to complete this action. Please sign in again.';
    }
    if (message.contains('unauthenticated') ||
        message.contains('UNAUTHENTICATED')) {
      return 'Your session has expired. Please sign in again and retry.';
    }
    return 'Something went wrong. Please try again or contact support.';
  }

  ({String title, String body, String? code}) _friendlyBillingError(
    IAPError? error,
  ) {
    final raw = error?.message ?? '';
    final code = error?.code ?? '';

    if (code.contains('developerError') || raw.contains('developerError')) {
      return (
        title: 'Purchase Unavailable',
        body:
            'This plan cannot be purchased right now. This is usually a temporary issue with the store configuration. Please try again later.',
        code: 'DEV_ERROR',
      );
    }
    if (code.contains('itemAlreadyOwned') ||
        raw.contains('itemAlreadyOwned') ||
        raw.contains('already extended')) {
      return (
        title: 'Already Subscribed',
        body:
            'You already own this plan. If your access is not active, try using "Restore Purchases" or contact support.',
        code: 'ALREADY_OWNED',
      );
    }
    if (code.contains('itemUnavailable') || raw.contains('itemUnavailable')) {
      return (
        title: 'Plan Unavailable',
        body:
            'This plan is not available for purchase in your region or on this device.',
        code: 'UNAVAILABLE',
      );
    }
    if (code.contains('userCanceled') || raw.contains('userCanceled')) {
      return (
        title: 'Purchase Cancelled',
        body: 'You cancelled the purchase. No payment was made.',
        code: null,
      );
    }
    if (code.contains('serviceDisconnected') ||
        raw.contains('serviceDisconnected')) {
      return (
        title: 'Connection Lost',
        body:
            'Google Play connection was lost. Please check your internet and try again.',
        code: 'SERVICE_DISCONNECTED',
      );
    }
    if (code.contains('serviceUnavailable') ||
        raw.contains('serviceUnavailable')) {
      return (
        title: 'Store Unavailable',
        body:
            'Google Play is temporarily unavailable. Please try again in a few minutes.',
        code: 'SERVICE_UNAVAILABLE',
      );
    }
    if (code.contains('billingUnavailable') ||
        raw.contains('billingUnavailable')) {
      return (
        title: 'Billing Unavailable',
        body:
            'Google Play billing is not available on this device. Make sure you are signed in to Google Play.',
        code: 'BILLING_UNAVAILABLE',
      );
    }
    if (code.contains('featureNotSupported') ||
        raw.contains('featureNotSupported')) {
      return (
        title: 'Not Supported',
        body:
            'Subscriptions are not supported on this device. Please try on a different device.',
        code: 'NOT_SUPPORTED',
      );
    }
    if (raw.contains('network') ||
        raw.contains('internet') ||
        raw.contains('timeout')) {
      return (
        title: 'Network Error',
        body: 'Please check your internet connection and try again.',
        code: 'NETWORK',
      );
    }

    return (
      title: 'Purchase Failed',
      body:
          'Something went wrong with the purchase. Please try again or contact support.',
      code: code.isNotEmpty ? code : null,
    );
  }

  void _showPurchaseErrorDialog(
    ({String title, String body, String? code}) info,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.error_outline,
          color: Color(0xFFE53935),
          size: 48,
        ),
        title: Text(info.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(info.body, textAlign: TextAlign.center),
            if (info.code != null) ...[
              const SizedBox(height: 12),
              Text(
                'Error code: ${info.code}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F6FEB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  int _effectivePriceForPlan(
    Map<String, dynamic> plan, {
    Map<String, dynamic>? couponOverride,
  }) {
    final basePrice = ((plan['price'] ?? 0) as num).toInt();
    final coupon = couponOverride ?? _appliedCoupon;
    if (coupon == null || !_couponAppliesToPlan(coupon, plan)) {
      return basePrice;
    }

    final type = (coupon['discountType'] ?? '').toString().toLowerCase();
    final value = ((coupon['discountValue'] ?? 0) as num).toInt();

    switch (type) {
      case 'free':
        return 0;
      case 'flat':
      case 'fixed':
        return (basePrice - value).clamp(0, basePrice).toInt();
      case 'percent':
        final discounted = basePrice - ((basePrice * value) / 100).round();
        return discounted.clamp(0, basePrice).toInt();
      default:
        return basePrice;
    }
  }

  String _productIdForPlan(Map<String, dynamic> plan) {
    final coupon = _appliedCoupon;
    if (coupon != null && _couponAppliesToPlan(coupon, plan)) {
      final couponProductId =
          (coupon['googlePlayProductId'] ??
                  coupon['playProductId'] ??
                  coupon['storeProductId'] ??
                  '')
              .toString()
              .trim();
      if (couponProductId.isNotEmpty) {
        return couponProductId;
      }
    }

    return (plan['storeProductId'] ?? '').toString().trim();
  }

  Map<String, dynamic> _asStringMap(Object? value) {
    if (value is Map) {
      return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    }
    return const <String, dynamic>{};
  }

  PurchaseParam _buildPurchaseParamForPlan(
    Map<String, dynamic> plan,
    ProductDetails product,
  ) {
    final basePlanId = (plan['playBasePlanId'] ?? '').toString().trim();
    final offerId = (plan['playOfferId'] ?? '').toString().trim();
    if (product is GooglePlayProductDetails && basePlanId.isNotEmpty) {
      final matchedOffer = _matchGooglePlayOffer(
        product,
        basePlanId,
        offerId: offerId,
      );
      final offerToken = matchedOffer?.offerIdToken ?? product.offerToken;
      if ((offerToken ?? '').isNotEmpty) {
        return GooglePlayPurchaseParam(
          productDetails: product,
          offerToken: offerToken,
        );
      }
    }

    return PurchaseParam(productDetails: product);
  }

  _ProductSelection _selectProductDetailsForPlan(
    Map<String, dynamic> plan,
    List<ProductDetails> products,
  ) {
    final basePlanId = (plan['playBasePlanId'] ?? '').toString().trim();
    final offerId = (plan['playOfferId'] ?? '').toString().trim();
    if (basePlanId.isEmpty) {
      return _ProductSelection.valid(products.first);
    }

    for (final product in products) {
      if (product is! GooglePlayProductDetails) {
        continue;
      }
      final matchedOffer = _matchGooglePlayOffer(
        product,
        basePlanId,
        offerId: offerId,
      );
      if (matchedOffer != null) {
        return _ProductSelection.valid(product);
      }
    }

    final productId = _productIdForPlan(plan);
    return _ProductSelection.invalid(
      offerId.isNotEmpty
          ? 'Google Play offer "$offerId" under base plan "$basePlanId" was not found for product "$productId".'
          : 'Google Play base plan "$basePlanId" was not found for product "$productId".',
    );
  }

  dynamic _matchGooglePlayOffer(
    GooglePlayProductDetails product,
    String basePlanId, {
    String offerId = '',
  }) {
    final offers = product.productDetails.subscriptionOfferDetails;
    if (offers == null || offers.isEmpty) {
      return null;
    }

    for (final offer in offers) {
      final offerMatches = offerId.isEmpty || (offer.offerId ?? '') == offerId;
      if (offer.basePlanId == basePlanId && offerMatches) {
        return offer;
      }
    }

    return null;
  }

  bool _couponAppliesToPlan(
    Map<String, dynamic> coupon,
    Map<String, dynamic> plan,
  ) {
    final applicablePlanIds = List<String>.from(
      coupon['applicablePlanIds'] ?? const <String>[],
    );
    if (applicablePlanIds.isNotEmpty &&
        !applicablePlanIds.contains(plan['id'].toString())) {
      return false;
    }

    final applicableExamIds = List<String>.from(
      coupon['applicableExamIds'] ?? const <String>[],
    );
    if (applicableExamIds.isEmpty) {
      return true;
    }

    final examId = selectedExamId;
    return examId != null && applicableExamIds.contains(examId);
  }

  bool _couponWithinWindow(Map<String, dynamic> coupon) {
    final now = DateTime.now();
    final validFrom = coupon['validFrom'];
    final validUntil = coupon['validUntil'];

    if (validFrom is Timestamp && now.isBefore(validFrom.toDate())) {
      return false;
    }
    if (validUntil is Timestamp && now.isAfter(validUntil.toDate())) {
      return false;
    }
    return true;
  }

  Future<bool> _couponAllowedForUser(Map<String, dynamic> coupon) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final userType = (coupon['userType'] ?? 'all').toString().toLowerCase();
    if (userType.isEmpty || userType == 'all') {
      return true;
    }

    final allowedUserIds = List<String>.from(coupon['userIds'] ?? const []);
    if (userType == 'users') {
      return allowedUserIds.isEmpty || allowedUserIds.contains(user.uid);
    }

    if (userType == 'groups') {
      if (allowedUserIds.contains(user.uid)) {
        return true;
      }

      final allowedGroupIds = List<String>.from(
        coupon['userGroupIds'] ?? const [],
      );
      if (allowedGroupIds.isEmpty) {
        return false;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? const <String, dynamic>{};
      final userGroupIds = <String>{
        ...List<String>.from(userData['userGroupIds'] ?? const []),
        ...List<String>.from(userData['groupIds'] ?? const []),
      };

      for (final groupId in allowedGroupIds) {
        if (userGroupIds.contains(groupId)) {
          return true;
        }
      }
      return false;
    }

    return allowedUserIds.isEmpty || allowedUserIds.contains(user.uid);
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findCouponDocument(
    String code,
  ) async {
    final candidates = <String>{
      code.trim(),
      code.trim().toUpperCase(),
      code.trim().toLowerCase(),
    }.where((value) => value.isNotEmpty);

    for (final candidate in candidates) {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('coupons')
          .where('code', isEqualTo: candidate)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first;
      }
    }

    return null;
  }

  Future<void> _applyCoupon() async {
    final rawCode = _couponController.text.trim();
    final plan = _selectedPlanOrNull();
    if (rawCode.isEmpty || plan == null) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isApplyingCoupon = true;
      _couponFeedback = null;
      _couponFeedbackIsError = false;
    });

    try {
      final result = await SubscriptionBackendService.redeemCoupon(
        planId: plan['id'].toString(),
        examId: selectedExamId ?? '',
        couponCode: rawCode,
      );
      if (!mounted) return;
      final appliedCoupon = <String, dynamic>{
        'id': result.couponCode,
        'googlePlayProductId': result.checkoutProductId,
        'discountType': result.finalPrice == 0 ? 'free' : 'custom',
        'discountValue': 0,
      };
      final finalPrice = result.finalPrice;
      setState(() {
        _appliedCoupon = appliedCoupon;
        _couponFeedback =
            'Coupon ${(appliedCoupon['id'] ?? rawCode).toString()} applied. Final price: Rs. $finalPrice';
        _couponFeedbackIsError = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Coupon ${(appliedCoupon['id'] ?? rawCode).toString()} applied successfully.',
          ),
        ),
      );
      if (result.activated) {
        SubscriptionAccessService.clearCache();
        if (mounted) _showSuccessAndPop();
        return;
      }
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _appliedCoupon = null;
        _couponFeedback = message;
        _couponFeedbackIsError = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isApplyingCoupon = false);
      }
    }
  }

  Future<void> _redeemFreeCoupon(Map<String, dynamic> plan) async {
    if (_appliedCoupon == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apply a valid coupon first.')),
      );
      return;
    }

    if (mounted) {
      setState(() => _isPurchasing = true);
    }

    try {
      final result = await SubscriptionBackendService.redeemCoupon(
        planId: plan['id'].toString(),
        examId: selectedExamId ?? '',
        couponCode: (_appliedCoupon?['id'] ?? '').toString(),
      );
      if (!result.activated) {
        throw Exception('Coupon requires checkout before activation.');
      }
      SubscriptionAccessService.clearCache();
      if (!mounted) return;
      _showSuccessAndPop();
      return;
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _restorePurchases() async {
    final available = await _iap.isAvailable();
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('In-app purchases are not available.')),
      );
      return;
    }

    if (mounted) {
      setState(() => _isRestoring = true);
    }

    try {
      await _iap.restorePurchases();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isRestoring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingPlans) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final visiblePlans = _visiblePlans();
    final selectedPlan = _selectedPlanOrNull() == null
        ? null
        : Map<String, dynamic>.from(_selectedPlanOrNull()!);
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    if (selectedPlan == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: const Text('Subscription'),
          backgroundColor: const Color(0xFF2F3E8F),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
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
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_outlined,
                      size: 36,
                      color: Color(0xFF2F3E8F),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'No Plans Available',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    (selectedExamId ?? '').isNotEmpty
                        ? 'There are no active subscription plans available for ${_selectedExamName ?? selectedExamId} right now.'
                        : 'There are no active subscription plans available right now.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Please check back later or contact support if you expected to see a plan here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final effectivePrice = _effectivePriceForPlan(selectedPlan);
    final hasCoupon =
        _appliedCoupon != null &&
        _couponAppliesToPlan(_appliedCoupon!, selectedPlan);
    if (hasCoupon) {
      selectedPlan['price'] = effectivePrice;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            /// HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
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
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if ((widget.lockedItemLabel ?? '').isNotEmpty)
                      _sectionCard(
                        color: colorScheme.tertiaryContainer,
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color: colorScheme.tertiary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Unlock ${widget.lockedItemType ?? 'content'}: ${widget.lockedItemLabel}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if ((selectedExamId ?? '').isNotEmpty)
                      _sectionCard(
                        color: colorScheme.primaryContainer,
                        child: Row(
                          children: [
                            Icon(
                              Icons.school_outlined,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Showing plans for exam: ${_selectedExamName ?? selectedExamId}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    /// PLAN CARDS
                    ...visiblePlans.map((plan) {
                      final isSelected = plan['id'] == selectedPlanId;
                      final isPopular = plan['durationDays'] == 180;

                      return GestureDetector(
                        onTap: () =>
                            setState(() => selectedPlanId = plan['id']),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant,
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
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
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
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurface,
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
                                              borderRadius:
                                                  BorderRadius.circular(4),
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
                                        color: colorScheme.onSurfaceVariant,
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
                          Text(
                            "Have a Coupon Code?",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _couponController,
                                  decoration: InputDecoration(
                                    hintText: "Enter coupon code",
                                    hintStyle: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    isDense: true,
                                    filled: true,
                                    fillColor:
                                        colorScheme.surfaceContainerLowest,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _isApplyingCoupon
                                    ? null
                                    : _applyCoupon,
                                child: _isApplyingCoupon
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text("Apply"),
                              ),
                            ],
                          ),
                          if (hasCoupon) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Applied: ${_appliedCoupon!['id']}  |  Final price: Rs. $effectivePrice',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              ((_appliedCoupon!['googlePlayProductId'] ?? '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty) ||
                                      effectivePrice == 0
                                  ? 'This coupon is linked to the checkout flow.'
                                  : 'Coupon saved, but add googlePlayProductId in Firebase if you want Play Store discounted billing.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (_couponFeedback != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _couponFeedback!,
                              style: TextStyle(
                                fontSize: 13,
                                color: _couponFeedbackIsError
                                    ? Colors.red.shade700
                                    : Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    /// SECURE
                    _sectionCard(
                      color: colorScheme.primaryContainer,
                      child: Row(
                        children: [
                          Icon(Icons.verified, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "100% Secure Payment",
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _isPurchasing || _isRestoring
                                ? null
                                : _restorePurchases,
                            child: _isRestoring
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Restore'),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 88 + bottomInset),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      /// BOTTOM BAR
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
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
              onPressed: (_isPurchasing || _isRestoring)
                  ? null
                  : _startPurchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                minimumSize: const Size(0, 42),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
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

class _ProductSelection {
  final ProductDetails? product;
  final String errorMessage;
  final bool isValid;

  const _ProductSelection._({
    required this.product,
    required this.errorMessage,
    required this.isValid,
  });

  factory _ProductSelection.valid(ProductDetails product) {
    return _ProductSelection._(
      product: product,
      errorMessage: '',
      isValid: true,
    );
  }

  factory _ProductSelection.invalid(String errorMessage) {
    return _ProductSelection._(
      product: null,
      errorMessage: errorMessage,
      isValid: false,
    );
  }
}

/// FEATURE ROW (OUTSIDE MAIN CLASS)
class _Feature extends StatelessWidget {
  final String text;
  const _Feature(this.text);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}
