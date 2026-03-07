const admin = require("firebase-admin");
const functions = require("firebase-functions");
const crypto = require("crypto");
const Razorpay = require("razorpay");

admin.initializeApp();

const db = admin.firestore();

function requireAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentication required."
    );
  }
  return context.auth.uid;
}

function getRazorpayClient() {
  const keyId = functions.config().razorpay?.key_id;
  const keySecret = functions.config().razorpay?.key_secret;
  if (!keyId || !keySecret) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Razorpay keys are not configured."
    );
  }
  return {
    keyId,
    keySecret,
    client: new Razorpay({ key_id: keyId, key_secret: keySecret }),
  };
}

exports.createRazorpayOrder = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const planId = (data?.planId || "").toString();
  const requestedAmount = Number(data?.amountRupees || 0);
  const couponCode = (data?.couponCode || "").toString().trim().toUpperCase();

  if (!planId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing planId.");
  }

  const planSnap = await db.collection("subscriptionPlans").doc(planId).get();
  if (!planSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Plan not found.");
  }

  const plan = planSnap.data() || {};
  const planPrice = Number(plan.price || 0);
  if (!Number.isFinite(planPrice) || planPrice <= 0) {
    throw new functions.https.HttpsError("failed-precondition", "Invalid plan price.");
  }

  let discountPercentage = Number(plan.discountPercentage || 0);
  if (couponCode) {
    const couponSnap = await db.collection("coupons").doc(couponCode).get();
    if (couponSnap.exists) {
      const c = couponSnap.data() || {};
      if (c.isActive === true) {
        discountPercentage = Number(c.discountPercentage || discountPercentage);
      }
    }
  }

  const finalRupees = Math.max(
    1,
    Math.round(planPrice * (1 - discountPercentage / 100))
  );

  if (requestedAmount > 0 && requestedAmount !== finalRupees) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Amount mismatch with server-side plan calculation."
    );
  }

  const { keyId, client } = getRazorpayClient();
  const amountPaise = finalRupees * 100;

  const order = await client.orders.create({
    amount: amountPaise,
    currency: "INR",
    receipt: `rs_${uid.slice(0, 10)}_${Date.now()}`,
    notes: { uid, planId, couponCode },
  });

  await db.collection("paymentOrders").doc(order.id).set(
    {
      uid,
      planId,
      couponCode,
      amountRupees: finalRupees,
      amountPaise,
      status: "created",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return {
    orderId: order.id,
    keyId,
    amountPaise,
    currency: "INR",
    planId,
    amountRupees: finalRupees,
  };
});

exports.verifyRazorpayPayment = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);

  const orderId = (data?.orderId || "").toString();
  const paymentId = (data?.paymentId || "").toString();
  const signature = (data?.signature || "").toString();
  const planId = (data?.planId || "").toString();
  const couponCode = (data?.couponCode || "").toString().trim().toUpperCase();
  const paidAmountRupees = Number(data?.paidAmountRupees || 0);

  if (!orderId || !paymentId || !signature || !planId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "orderId, paymentId, signature and planId are required."
    );
  }

  const { keySecret } = getRazorpayClient();
  const digest = crypto
    .createHmac("sha256", keySecret)
    .update(`${orderId}|${paymentId}`)
    .digest("hex");

  if (digest !== signature) {
    return { verified: false };
  }

  const planSnap = await db.collection("subscriptionPlans").doc(planId).get();
  if (!planSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Plan not found.");
  }

  const plan = planSnap.data() || {};
  const durationDays = Number(plan.durationDays || 30);
  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    now.toMillis() + durationDays * 24 * 60 * 60 * 1000
  );

  const subRef = db.collection("subscriptions").doc();
  const batch = db.batch();

  batch.set(subRef, {
    userId: uid,
    planId,
    status: "active",
    provider: "razorpay",
    orderId,
    paymentId,
    paymentSignature: signature,
    paidAmountRupees,
    couponCode,
    startedAt: now,
    createdAt: now,
    expiresAt,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const userRef = db.collection("users").doc(uid);
  batch.set(
    userRef,
    {
      subscriptionStatus: "paid",
      subscriptionIds: admin.firestore.FieldValue.arrayUnion(subRef.id),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  const orderRef = db.collection("paymentOrders").doc(orderId);
  batch.set(
    orderRef,
    {
      uid,
      planId,
      couponCode,
      status: "verified",
      paymentId,
      paymentSignature: signature,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  await batch.commit();

  return {
    verified: true,
    subscriptionId: subRef.id,
    durationDays,
    expiresAtMs: expiresAt.toMillis(),
  };
});
