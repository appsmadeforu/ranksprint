import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PaymentOrderPayload {
  final String orderId;
  final String keyId;
  final int amountPaise;
  final String currency;

  const PaymentOrderPayload({
    required this.orderId,
    required this.keyId,
    required this.amountPaise,
    required this.currency,
  });
}

class PaymentService {
  PaymentService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final List<String> _regions = <String>['asia-south1', 'us-central1'];

  static Future<HttpsCallableResult<dynamic>> _callWithRegionFallback({
    required String functionName,
    required Map<String, dynamic> payload,
  }) async {
    FirebaseFunctionsException? lastFnError;
    Object? lastOtherError;

    for (final region in _regions) {
      try {
        final instance = FirebaseFunctions.instanceFor(region: region);
        final callable = instance.httpsCallable(functionName);
        return await callable.call(payload);
      } on FirebaseFunctionsException catch (e) {
        lastFnError = e;
        if (e.code != 'not-found') rethrow;
      } catch (e) {
        lastOtherError = e;
      }
    }

    if (lastFnError != null) throw lastFnError;
    if (lastOtherError != null) throw lastOtherError;
    throw FirebaseFunctionsException(
      code: 'internal',
      message: 'Callable invocation failed.',
    );
  }

  static Future<PaymentOrderPayload> createRazorpayOrder({
    required String planId,
    required int amountRupees,
    String? couponCode,
  }) async {
    final result = await _callWithRegionFallback(
      functionName: 'createRazorpayOrder',
      payload: <String, dynamic>{
      'planId': planId,
      'amountRupees': amountRupees,
      'couponCode': couponCode,
      },
    );

    final data = Map<String, dynamic>.from(result.data as Map);
    return PaymentOrderPayload(
      orderId: (data['orderId'] ?? '').toString(),
      keyId: (data['keyId'] ?? '').toString(),
      amountPaise: (data['amountPaise'] as num?)?.toInt() ?? 0,
      currency: (data['currency'] ?? 'INR').toString(),
    );
  }

  static Future<bool> verifyAndActivateSubscription({
    required String orderId,
    required String paymentId,
    required String signature,
    required String planId,
    required int durationDays,
    required int paidAmountRupees,
    String? couponCode,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'not-authenticated',
        message: 'User not logged in',
      );
    }

    final verifyResult = await _callWithRegionFallback(
      functionName: 'verifyRazorpayPayment',
      payload: <String, dynamic>{
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
        'planId': planId,
        'paidAmountRupees': paidAmountRupees,
        'couponCode': couponCode,
      },
    );

    final verifyData = Map<String, dynamic>.from(verifyResult.data as Map);
    final verified = verifyData['verified'] == true;
    if (!verified) return false;

    final now = DateTime.now();
    final expiresAt = now.add(Duration(days: durationDays));
    final explicitSubscriptionId =
        (verifyData['subscriptionId'] ?? '').toString();
    final subRef = explicitSubscriptionId.isNotEmpty
        ? _db.collection('subscriptions').doc(explicitSubscriptionId)
        : _db.collection('subscriptions').doc();

    final batch = _db.batch();
    batch.set(subRef, {
      'userId': user.uid,
      'planId': planId,
      'status': 'active',
      'provider': 'razorpay',
      'orderId': orderId,
      'paymentId': paymentId,
      'paymentSignature': signature,
      'paidAmountRupees': paidAmountRupees,
      'currency': 'INR',
      'couponCode': couponCode ?? '',
      'createdAt': Timestamp.fromDate(now),
      'startedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final userRef = _db.collection('users').doc(user.uid);
    batch.set(userRef, {
      'subscriptionStatus': 'paid',
      'subscriptionIds': FieldValue.arrayUnion([subRef.id]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
    return true;
  }
}
