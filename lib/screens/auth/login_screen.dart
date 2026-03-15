import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _loading = false;

  // =========================
  // PHONE OTP
  // =========================

  Future<void> _sendOtp() async {
    if (_phoneController.text.trim().isEmpty) return;

    setState(() => _loading = true);

    await _auth.verifyPhoneNumber(
      phoneNumber: "+91${_phoneController.text.trim()}",
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);

        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final userDoc = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid);

          final snapshot = await userDoc.get();

          if (!snapshot.exists) {
            await userDoc.set({
              'email': user.email ?? '',
              'selectedExams': [],
              'activePlanIds': [],
              'subscriptionIds': [],
              'createdAt': Timestamp.now(),
            });
          }
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? "Verification Failed")),
          );
        }
        if (mounted) setState(() => _loading = false);
      },
      codeSent: (String verificationId, int? resendToken) {
        if (mounted) {
          final phone = "+91${_phoneController.text.trim()}";
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpScreen(
                verificationId: verificationId,
                phoneNumber: phone,
                resendToken: resendToken,
              ),
            ),
          );
        }
        if (mounted) setState(() => _loading = false);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  // =========================
  // GOOGLE SIGN IN
  // =========================

  Future<void> _signInWithGoogle() async {
    try {
      setState(() => _loading = true);

      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) {
        setState(() => _loading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      final user = userCredential.user;

      if (user != null) {
        final userDoc = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);

        final docSnapshot = await userDoc.get();

        // If new user → create document
        if (!docSnapshot.exists) {
          await userDoc.set({
            'name': user.displayName ?? '',
            'email': user.email ?? '',
            'phone': user.phoneNumber ?? '',
            'selectedExams': [],
            'activePlanIds': [],
            'subscriptionIds': [],
            'createdAt': Timestamp.now(),
          });
        } else {
          // Existing user → update email if missing
          await userDoc.update({
            'email': user.email ?? '',
            'name': user.displayName ?? '',
            'updatedAt': Timestamp.now(),
          });
        }
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Google Sign-In failed")));
      }
    }
  }
  // =========================
  // UI
  // =========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Container(
                    width: 420,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                                SizedBox(
                                  width: 250,
                                  child: Image.asset(
                                    "assets/icons/app_icon.png",
                                    fit: BoxFit.contain,
                                  ),
                                ),

                                TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    hintText: "Enter Mobile Number",
                                    filled: true,
                                    fillColor: Colors.grey[200],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 10),

                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _sendOtp,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1F3A8A),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: _loading
                                        ? const CircularProgressIndicator(
                                            color: Colors.white,
                                          )
                                        : const Text(
                                            "Send OTP",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),

                                const SizedBox(height: 30),

                                const Row(
                                  children: [
                                    Expanded(child: Divider()),
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text("OR"),
                                    ),
                                    Expanded(child: Divider()),
                                  ],
                                ),

                                const SizedBox(height: 20),

                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: OutlinedButton(
                                    onPressed: _loading
                                        ? null
                                        : _signInWithGoogle,
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      side: BorderSide(color: Colors.grey),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Image.asset(
                                          "assets/images/google.png",
                                          height: 22,
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          "Continue with Google",
                                          style: TextStyle(
                                            color: Colors.black87,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 30),

                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E0),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange),
                                  ),
                                  child: const Text(
                                    "Single Device Policy\n"
                                    "Your account can only be active on one device at a time. "
                                    "Logging in on a new device will automatically log you out from other devices.",
                                    style: TextStyle(fontSize: 12),
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
    );
  }
}
