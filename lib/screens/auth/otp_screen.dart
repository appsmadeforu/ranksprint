import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'dart:async';

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
  bool _loading = false;
  bool _resending = false;
  int _resendSeconds = 30;
  Timer? _timer;

  String get _otp => _controllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _confirmationResult = widget.confirmationResult;
    _startResendTimer();
    if (!kIsWeb) {
      listenForCode();
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("OTP session expired. Please retry.")),
        );
      }
      return;
    }

    setState(() => _loading = true);

    try {
      if (kIsWeb) {
        final confirmationResult = _confirmationResult;
        if (confirmationResult == null) {
          throw FirebaseAuthException(
            code: 'missing-confirmation-result',
            message: 'OTP session expired. Please retry.',
          );
        }
        await confirmationResult.confirm(_otp);
      } else {
        final credential = PhoneAuthProvider.credential(
          verificationId: _verificationId,
          smsCode: _otp,
        );

        await _auth.signInWithCredential(credential);
      }

      if (mounted) {
        setState(() => _loading = false);
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text(e.message ?? "Invalid OTP")),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Invalid OTP")));
      }
    }
  }

  @override
  void codeUpdated() {
    final incomingCode = code?.trim() ?? '';
    if (incomingCode.isEmpty) return;

    final digits = incomingCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) return;

    _applyOtpCode(digits.substring(0, 6));
  }

  Future<void> _resendOtp() async {
    if (_resendSeconds > 0 || _resending || _loading) return;
    if (widget.phoneNumber.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Phone number missing. Go back and retry.")),
        );
      }
      return;
    }

    setState(() => _resending = true);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("OTP resent")));
      } else {
        await _auth.verifyPhoneNumber(
          phoneNumber: widget.phoneNumber,
          forceResendingToken: _resendToken,
          verificationCompleted: (PhoneAuthCredential credential) async {
            await _auth.signInWithCredential(credential);
            if (mounted) {
              Navigator.popUntil(context, (route) => route.isFirst);
            }
          },
          verificationFailed: (FirebaseAuthException e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.message ?? "Failed to resend OTP")),
              );
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            if (!mounted) return;
            setState(() {
              _verificationId = verificationId;
              _resendToken = resendToken;
            });
            _startResendTimer();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("OTP resent")));
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            if (!mounted) return;
            setState(() => _verificationId = verificationId);
          },
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "Failed to resend OTP")),
        );
      }
    }

    if (mounted) {
      setState(() => _resending = false);
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

    if (otp.length == 6 && !_loading) {
      _verifyOtp();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      cancel();
    }
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
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Verify & Continue",
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              TextButton(
                onPressed: (_resendSeconds == 0 && !_resending && !_loading)
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
                    const Icon(Icons.info_outline, color: Colors.orange),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Single Device Policy",
                            style: TextStyle(fontWeight: FontWeight.bold),
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
