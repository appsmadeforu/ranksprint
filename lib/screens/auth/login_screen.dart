import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../services/auth_session_coordinator.dart';
import '../../services/single_device_session_service.dart';
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
  bool _logoutNoticeShown = false;

  void _log(String message) {
    debugPrint('LoginScreen: $message');
  }

  void _showMessage(String message) {
    if (!mounted || message.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logoutNoticeShown) return;
    _logoutNoticeShown = true;
    final pendingMessage =
        SingleDeviceSessionService.consumePendingLogoutMessage();
    if (pendingMessage == null || pendingMessage.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMessage(pendingMessage);
    });
  }

  Future<void> _sendOtp() async {
    if (_phoneController.text.trim().isEmpty) return;

    setState(() => _loading = true);
    final phoneNumber = "+91${_phoneController.text.trim()}";
    _log('sendOtp start phone=$phoneNumber');

    try {
      if (kIsWeb) {
        final confirmationResult = await _auth.signInWithPhoneNumber(
          phoneNumber,
        ).timeout(const Duration(seconds: 30));
        if (!mounted) return;
        setState(() => _loading = false);
        _log('sendOtp web confirmation ready phone=$phoneNumber');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              phoneNumber: phoneNumber,
              confirmationResult: confirmationResult,
            ),
          ),
        );
        return;
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          _log('sendOtp verificationCompleted phone=$phoneNumber');
          final userCredential = await _auth.signInWithCredential(credential);
          final user = userCredential.user;
          if (user != null) {
            await AuthSessionCoordinator.completePostLogin(
              user,
              fallbackPhoneNumber: phoneNumber,
            );
          }
          if (mounted) {
            setState(() => _loading = false);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          _log('sendOtp verificationFailed code=${e.code} message=${e.message}');
          _showMessage(e.message ?? "Verification Failed");
          if (mounted) setState(() => _loading = false);
        },
        codeSent: (String verificationId, int? resendToken) {
          _log('sendOtp codeSent verificationId=$verificationId');
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OtpScreen(
                  verificationId: verificationId,
                  phoneNumber: phoneNumber,
                  resendToken: resendToken,
                ),
              ),
            );
          }
          if (mounted) setState(() => _loading = false);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _log('sendOtp autoRetrievalTimeout verificationId=$verificationId');
          if (mounted) setState(() => _loading = false);
        },
      );
    } on FirebaseAuthException catch (e) {
      _log('sendOtp auth error code=${e.code} message=${e.message}');
      if (mounted) {
        setState(() => _loading = false);
        _showMessage(e.message ?? "Verification Failed");
      }
    } on TimeoutException {
      _log('sendOtp timeout phone=$phoneNumber');
      if (mounted) {
        setState(() => _loading = false);
        _showMessage("OTP request timed out. Please try again.");
      }
    } catch (_) {
      _log('sendOtp unknown failure phone=$phoneNumber');
      if (mounted) {
        setState(() => _loading = false);
        _showMessage("Verification Failed");
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      setState(() => _loading = true);
      _log('google sign-in start');

      late final UserCredential userCredential;
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        provider.addScope('email');
        provider.addScope('profile');
        userCredential = await _auth
            .signInWithPopup(provider)
            .timeout(const Duration(seconds: 45));
      } else {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

        if (googleUser == null) {
          _log('google sign-in cancelled by user');
          setState(() => _loading = false);
          return;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential = await _auth
            .signInWithCredential(credential)
            .timeout(const Duration(seconds: 45));
      }

      final user = userCredential.user;
      if (user != null) {
        _log('google sign-in success uid=${user.uid}');
        await AuthSessionCoordinator.completePostLogin(user);
      }

      if (mounted) setState(() => _loading = false);
    } on FirebaseAuthException catch (e) {
      _log('google sign-in auth error code=${e.code} message=${e.message}');
      if (mounted) {
        setState(() => _loading = false);
        _showMessage(e.message ?? "Google Sign-In failed");
      }
    } on TimeoutException {
      _log('google sign-in timeout');
      if (mounted) {
        setState(() => _loading = false);
        _showMessage("Google Sign-In timed out. Please try again.");
      }
    } catch (_) {
      _log('google sign-in unknown failure');
      if (mounted) {
        setState(() => _loading = false);
        _showMessage("Google Sign-In failed");
      }
    }
  }

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
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          maxLength: 10,
                          decoration: InputDecoration(
                            hintText: "Enter Mobile Number",
                            counterText: "",
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
                              padding: EdgeInsets.symmetric(horizontal: 8),
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
                            onPressed: _loading ? null : _signInWithGoogle,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: Colors.grey),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
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
