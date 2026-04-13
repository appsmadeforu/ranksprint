import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'dart:async';

import '../../services/auth_session_coordinator.dart';

class OtpScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final int? resendToken;
  final ConfirmationResult? confirmationResult;

  const OtpScreen({
    super.key,
    this.verificationId = '',
    this.phoneNumber = '',
    this.resendToken,
    this.confirmationResult,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with CodeAutoFill {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  late String _verificationId;
  int? _resendToken;
  ConfirmationResult? _confirmationResult;
  _OtpStage _stage = _OtpStage.idle;
  bool _autofillListening = false;
  int _resendSeconds = 30;
  Timer? _timer;
  StreamSubscription<User?>? _authStateSub;

  void _log(String message) {
    debugPrint('OtpScreen: $message');
  }

  String get _otp => _controllers.map((c) => c.text).join();
  bool get _loading => _stage == _OtpStage.verifying || _stage == _OtpStage.syncing;
  bool get _resending => _stage == _OtpStage.resending;

  void _setStage(_OtpStage stage) {
    if (!mounted) return;
    setState(() => _stage = stage);
  }

  void _showMessage(String message) {
    if (!mounted || message.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _completePostLogin(User user) async {
    await AuthSessionCoordinator.completePostLogin(
      user,
      fallbackPhoneNumber: widget.phoneNumber,
    );
  }

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _confirmationResult = widget.confirmationResult;
    _authStateSub = _auth.authStateChanges().listen((user) {
      if (!mounted || user != null || !_loading) return;
      _setStage(_OtpStage.idle);
    });
    _startResendTimer();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _verifyOtp() async {
    if (_otp.length != 6) return;
    if (_verificationId.isEmpty) {
      _showMessage("OTP session expired. Please retry.");
      return;
    }

    _setStage(_OtpStage.verifying);
    _log('verifyOtp start phone=${widget.phoneNumber}');

    try {
      final user = await _signInWithEnteredOtp();
      if (user == null) {
        throw FirebaseAuthException(
          code: 'missing-user',
          message: 'Could not verify OTP. Please try again.',
        );
      }
      _setStage(_OtpStage.syncing);
      _log('verifyOtp signed in uid=${user.uid}');
      await _completePostLogin(user).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      _setStage(_OtpStage.idle);
      _log('verifyOtp complete uid=${user.uid}');
      Navigator.popUntil(context, (route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      _log('verifyOtp auth error code=${e.code} message=${e.message}');
      _setStage(_OtpStage.idle);
      _showMessage(e.message ?? "Invalid OTP");
    } on TimeoutException {
      _log('verifyOtp timeout');
      _setStage(_OtpStage.idle);
      _showMessage("This is taking longer than expected. Please try again.");
    } catch (_) {
      _log('verifyOtp unknown failure');
      _setStage(_OtpStage.idle);
      _showMessage("Invalid OTP");
    }
  }

  Future<User?> _signInWithEnteredOtp() async {
    if (kIsWeb) {
      final confirmationResult = _confirmationResult;
      if (confirmationResult == null) {
        throw FirebaseAuthException(
          code: 'missing-confirmation-result',
          message: 'OTP session expired. Please retry.',
        );
      }
      final credential = await confirmationResult.confirm(
        _otp,
      ).timeout(const Duration(seconds: 30));
      return credential.user;
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: _otp,
    );
    final userCredential = await _auth
        .signInWithCredential(credential)
        .timeout(const Duration(seconds: 30));
    return userCredential.user;
  }

  @override
  void codeUpdated() {
    final incomingCode = code?.trim() ?? '';
    if (incomingCode.isEmpty) return;

    final digits = incomingCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) return;

    _applyOtpCode(digits.substring(0, 6));
  }

  Future<void> _startSmsAutofill() async {
    if (kIsWeb || _loading || _autofillListening) return;

    setState(() => _autofillListening = true);
    try {
      listenForCode();
      if (!mounted) return;
      _showMessage('Waiting for OTP SMS...');
    } catch (_) {
      if (!mounted) return;
      setState(() => _autofillListening = false);
      _showMessage('Could not start OTP autofill');
    }
  }

  Future<void> _resendOtp() async {
    if (_resendSeconds > 0 || _resending || _loading) return;
    if (widget.phoneNumber.isEmpty) {
      _showMessage("Phone number missing. Go back and retry.");
      return;
    }

    _setStage(_OtpStage.resending);
    _log('resendOtp start phone=${widget.phoneNumber}');
    for (final controller in _controllers) {
      controller.clear();
    }

    try {
      if (kIsWeb) {
        final confirmationResult = await _auth.signInWithPhoneNumber(
          widget.phoneNumber,
        );
        if (!mounted) return;
        setState(() {
          _confirmationResult = confirmationResult;
        });
        _startResendTimer();
        _log('resendOtp web success');
        _showMessage("OTP resent");
      } else {
        await _auth.verifyPhoneNumber(
          phoneNumber: widget.phoneNumber,
          forceResendingToken: _resendToken,
          verificationCompleted: (PhoneAuthCredential credential) async {
            try {
              _log('resendOtp verificationCompleted');
              final userCredential = await _auth
                  .signInWithCredential(credential)
                  .timeout(const Duration(seconds: 30));
              final user = userCredential.user;
              if (user == null) return;
              _setStage(_OtpStage.syncing);
              await _completePostLogin(user).timeout(const Duration(seconds: 15));
              if (mounted) {
                _setStage(_OtpStage.idle);
                _log('resendOtp auto verification complete uid=${user.uid}');
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            } catch (_) {
              _log('resendOtp auto verification failed');
              _setStage(_OtpStage.idle);
              _showMessage("Could not verify OTP automatically. Please enter it manually.");
            }
          },
          verificationFailed: (FirebaseAuthException e) {
            if (mounted) {
              _log('resendOtp verificationFailed code=${e.code} message=${e.message}');
              _setStage(_OtpStage.idle);
              _showMessage(e.message ?? "Failed to resend OTP");
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            if (!mounted) return;
            _log('resendOtp codeSent verificationId=$verificationId');
            setState(() {
              _verificationId = verificationId;
              _resendToken = resendToken;
              _stage = _OtpStage.idle;
            });
            _startResendTimer();
            _showMessage("OTP resent");
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            if (!mounted) return;
            _log('resendOtp autoRetrievalTimeout verificationId=$verificationId');
            setState(() {
              _verificationId = verificationId;
              _autofillListening = false;
            });
          },
        );
      }
    } on FirebaseAuthException catch (e) {
      _log('resendOtp auth error code=${e.code} message=${e.message}');
      _setStage(_OtpStage.idle);
      _showMessage(e.message ?? "Failed to resend OTP");
    } on TimeoutException {
      _log('resendOtp timeout');
      _setStage(_OtpStage.idle);
      _showMessage("Resend OTP timed out. Please try again.");
    } catch (_) {
      _log('resendOtp unknown failure');
      _setStage(_OtpStage.idle);
      _showMessage("Failed to resend OTP");
    }

    if (mounted && kIsWeb && _resending) {
      _setStage(_OtpStage.idle);
    }
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 45,
      child: TextField(
        controller: _controllers[index],
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        textAlign: TextAlign.center,
        maxLength: 1,
        decoration: InputDecoration(
          counterText: "",
          filled: true,
          fillColor: Colors.grey[200],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          if (value.length > 1) {
            _applyOtpCode(value);
            return;
          }

          if (value.isNotEmpty && index < 5) {
            FocusScope.of(context).nextFocus();
          } else if (value.isEmpty && index > 0) {
            FocusScope.of(context).previousFocus();
          }
        },
      ),
    );
  }

  void _applyOtpCode(String rawCode) {
    final digits = rawCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;

    final otp = digits.substring(0, digits.length > 6 ? 6 : digits.length);
    for (var i = 0; i < _controllers.length; i++) {
      _controllers[i].text = i < otp.length ? otp[i] : '';
    }

    if (!mounted) return;

    FocusScope.of(context).unfocus();
    if (_autofillListening) {
      setState(() => _autofillListening = false);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      cancel();
    }
    _authStateSub?.cancel();
    _timer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
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
                left: 24,
                right: 24,
                top: 24,
                bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 400,
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      SizedBox(
                        width: 250,
                        // height: 250,
                        child: Image.asset(
                          "assets/icons/app_icon.png",
                          fit: BoxFit.contain,
                        ),
                      ),

                      const Icon(
                        Icons.mail_outline,
                        size: 40,
                        color: Color(0xFF1F3A8A),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        "Verify OTP",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F3A8A),
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        "Enter the 6-digit code sent to your phone",
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, _buildOtpBox),
                      ),

                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _verifyOtp,
                          style: ElevatedButton.styleFrom(
                            textStyle: const TextStyle(color: Colors.white),
                            backgroundColor: const Color(0xFF1F3A8A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  "Verify & Continue",
                                  style: TextStyle(color: Colors.white),
                                ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      if (!kIsWeb)
                        TextButton(
                          onPressed: (_loading || _autofillListening)
                              ? null
                              : _startSmsAutofill,
                          child: Text(
                            _autofillListening
                                ? 'Waiting for OTP SMS...'
                                : 'Autofill from SMS',
                            style: const TextStyle(color: Color(0xFF1F3A8A)),
                          ),
                        ),

                      if (!kIsWeb) const SizedBox(height: 8),

                      TextButton(
                        onPressed:
                            (_resendSeconds == 0 && !_resending && !_loading)
                            ? _resendOtp
                            : null,
                        child: Text(
                          _resendSeconds == 0
                              ? (_resending ? "Resending..." : "Resend OTP")
                              : "Resend OTP in 00:${_resendSeconds.toString().padLeft(2, '0')}",
                          style: const TextStyle(color: Color(0xFF1F3A8A)),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Policy Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    "Single Device Policy",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  SizedBox(height: 6),

                                  Text(
                                    "Your account can only be active on one device at a time. Logging in on a new device will automatically log you out from other devices.",
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),
                    ],
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

enum _OtpStage { idle, verifying, syncing, resending }
