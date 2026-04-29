import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class SubscriptionBackendService {
  const SubscriptionBackendService._();

  static FirebaseFunctions get _functions => FirebaseFunctions.instance;

  static Future<SubscriptionCouponResult> redeemCoupon({
    required String planId,
    required String examId,
    required String couponCode,
  }) async {
    final callable = _functions.httpsCallable('redeemSubscriptionCoupon');
    final result = await callable.call(<String, dynamic>{
      'planId': planId,
      'examId': examId,
      'couponCode': couponCode.trim(),
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final couponData = data['coupon'];

    return SubscriptionCouponResult(
      activated: data['activated'] == true,
      requiresPurchase: data['requiresPurchase'] == true,
      finalPrice: (data['finalPrice'] as num?)?.toInt() ?? 0,
      checkoutProductId: couponData is Map
          ? (couponData['googlePlayProductId'] ?? '').toString().trim()
          : '',
      couponCode: couponData is Map
          ? (couponData['code'] ?? '').toString().trim()
          : couponCode.trim(),
    );
  }

  static Future<void> finalizePurchase({
    required String planId,
    required String examId,
    required PurchaseDetails purchase,
    String couponCode = '',
  }) async {
    final callable = _functions.httpsCallable('finalizeSubscriptionPurchase');
    await callable.call(<String, dynamic>{
      'planId': planId,
      'examId': examId,
      'couponCode': couponCode.trim(),
      'status': purchase.status.name,
      'verification': <String, dynamic>{
        'productId': purchase.productID,
        'purchaseId': purchase.purchaseID ?? '',
        'source': purchase.verificationData.source,
        'localVerificationData': purchase.verificationData.localVerificationData,
        'serverVerificationData': purchase.verificationData.serverVerificationData,
        'transactionDate': purchase.transactionDate ?? '',
      },
    });
  }

  static Future<SubscriptionRefreshResult> refreshAccess() async {
    final callable = _functions.httpsCallable('refreshSubscriptionAccess');
    final result = await callable.call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return SubscriptionRefreshResult(
      activePlanIds: List<String>.from(data['activePlanIds'] ?? const []),
      subscriptionIds: List<String>.from(data['subscriptionIds'] ?? const []),
      subscriptionStatus: (data['subscriptionStatus'] ?? 'free').toString(),
    );
  }
}

class SubscriptionCouponResult {
  final bool activated;
  final bool requiresPurchase;
  final int finalPrice;
  final String checkoutProductId;
  final String couponCode;

  const SubscriptionCouponResult({
    required this.activated,
    required this.requiresPurchase,
    required this.finalPrice,
    required this.checkoutProductId,
    required this.couponCode,
  });
}

class SubscriptionRefreshResult {
  final List<String> activePlanIds;
  final List<String> subscriptionIds;
  final String subscriptionStatus;

  const SubscriptionRefreshResult({
    required this.activePlanIds,
    required this.subscriptionIds,
    required this.subscriptionStatus,
  });
}
