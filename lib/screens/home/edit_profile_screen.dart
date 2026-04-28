import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/login_screen.dart';
import '../../services/auth_identity_service.dart';
import 'main_navigation.dart';
import '../../services/single_device_session_service.dart';
import '../../widgets/top_header.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();

  final firstNameController = TextEditingController();
  final middleNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final pincodeController = TextEditingController();
  final cityController = TextEditingController();
  final stateController = TextEditingController();

  String? gender;
  DateTime? dob;
  bool loading = false;
  bool _initialLoadComplete = false;
  bool _emailLocked = false;
  bool _phoneLocked = false;
  bool _isProcessingPhoto = false;
  bool _isResolvingPincode = false;
  String? _pincodeLookupMessage;
  String _authEmail = '';
  String _authPhone = '';
  Timer? _pincodeDebounce;
  String? _photoUrl;
  Uint8List? _selectedPhotoBytes;
  String? _selectedPhotoName;
  bool _removePhoto = false;
  Map<String, dynamic>? _initialProfileSnapshot;
  String? _pendingEmailVerificationEmail;
  bool _showHeaderLogout = false;
  int _activePincodeLookupToken = 0;
  bool _refreshingAfterResume = false;

  static const List<String> _genderOptions = ['Male', 'Female', 'Other'];
  static const int _maxProfilePhotoBytes = 2 * 1024 * 1024;
  static const double _pickedPhotoMaxDimension = 1600;
  static const int _croppedPhotoMaxDimension = 1080;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshVerifiedEmailState());
    }
  }

  Future<void> _refreshVerifiedEmailState() async {
    if (_refreshingAfterResume) return;
    final user = FirebaseAuth.instance.currentUser;
    final pendingEmail = (_pendingEmailVerificationEmail ?? '').trim();
    if (user == null || pendingEmail.isEmpty) return;

    _refreshingAfterResume = true;
    try {
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      final authEmail = (refreshedUser?.email ?? '').trim();
      if (authEmail.isEmpty ||
          authEmail.toLowerCase() != pendingEmail.toLowerCase()) {
        return;
      }

      if (!mounted) return;
      await _loadUserData();
      if (!mounted) return;

      final hasProfileName =
          firstNameController.text.trim().isNotEmpty ||
          lastNameController.text.trim().isNotEmpty;
      final hasContact =
          emailController.text.trim().isNotEmpty ||
          phoneController.text.trim().isNotEmpty;
      final hasSelectedExam = await _hasAnySelectedExam();
      if (!mounted) return;

      if (_showHeaderLogout && hasProfileName && hasContact && hasSelectedExam) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 0)),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email verified for $authEmail')),
        );
      }
    } catch (_) {
      // Ignore resume refresh failures and let the user continue manually.
    } finally {
      _refreshingAfterResume = false;
    }
  }

  Future<bool> _hasAnySelectedExam() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final selectedExams = snapshot.data()?['selectedExams'];
    return selectedExams is List && selectedExams.isNotEmpty;
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);

    final authEmail = (user.email ?? '').trim();
    final authPhone = (user.phoneNumber ?? '').trim();
    final hasPhoneProvider = user.providerData.any(
      (p) => p.providerId == 'phone',
    );
    final hasEmailProvider = user.providerData.any(
      (p) => p.providerId == 'google.com' || p.providerId == 'password',
    );

    final doc = await userDoc.get();

    if (!mounted) return;

    final data = doc.data() ?? <String, dynamic>{};
    final pendingEmail = (data['pendingEmailVerificationEmail'] is String)
        ? (data['pendingEmailVerificationEmail'] as String).trim()
        : '';
    final pendingEmailMatchesAuth =
        pendingEmail.isNotEmpty &&
        authEmail.isNotEmpty &&
        pendingEmail.toLowerCase() == authEmail.toLowerCase();
    if (pendingEmailMatchesAuth) {
      await userDoc.set({
        'pendingEmailVerificationEmail': FieldValue.delete(),
        'pendingEmailVerificationUpdatedAt': FieldValue.delete(),
      }, SetOptions(merge: true));
    }
    final legacyFullName = (data['name'] is String)
        ? (data['name'] as String).trim()
        : '';
    final firstName = (data['firstName'] is String)
        ? (data['firstName'] as String).trim()
        : '';
    final middleName = (data['middleName'] is String)
        ? (data['middleName'] as String).trim()
        : '';
    final lastName = (data['lastName'] is String)
        ? (data['lastName'] as String).trim()
        : '';
    final resolvedNames = _resolveNameParts(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      legacyFullName: legacyFullName,
    );
    final hasProfileName =
        resolvedNames.firstName.isNotEmpty || resolvedNames.lastName.isNotEmpty;
    final hasStoredEmail =
        authEmail.isNotEmpty ||
        ((data['email'] ?? '').toString().trim().isNotEmpty);
    final hasStoredPhone =
        authPhone.isNotEmpty ||
        ((data['phone'] ?? '').toString().trim().isNotEmpty);
    final isProfileIncomplete =
        ((!hasStoredEmail && !hasStoredPhone) || !hasProfileName);

    setState(() {
      firstNameController.text = resolvedNames.firstName;
      middleNameController.text = resolvedNames.middleName;
      lastNameController.text = resolvedNames.lastName;
      emailController.text = authEmail.isNotEmpty
          ? authEmail
          : ((data['email'] is String) ? data['email'] : '');
      phoneController.text = authPhone.isNotEmpty
          ? AuthIdentityService.normalizePhone(authPhone)
          : AuthIdentityService.normalizePhone(
              (data['phone'] is String) ? data['phone'] : '',
            );
      pincodeController.text = (data['pincode'] is String)
          ? data['pincode']
          : '';
      cityController.text = (data['city'] is String) ? data['city'] : '';
      stateController.text = (data['state'] is String) ? data['state'] : '';
      _authEmail = authEmail;
      _authPhone = AuthIdentityService.normalizePhone(authPhone);
      _photoUrl = (data['photoURL'] is String)
          ? (data['photoURL'] as String).trim()
          : '';
      _pendingEmailVerificationEmail = pendingEmailMatchesAuth || pendingEmail.isEmpty
          ? null
          : pendingEmail;
      _showHeaderLogout = isProfileIncomplete;
      _selectedPhotoBytes = null;
      _selectedPhotoName = null;
      _removePhoto = false;
      if (hasPhoneProvider && !hasEmailProvider) {
        _phoneLocked = true;
        _emailLocked = false;
      } else if (hasEmailProvider && !hasPhoneProvider) {
        _emailLocked = true;
        _phoneLocked = false;
      } else {
        _emailLocked = authEmail.isNotEmpty;
        _phoneLocked = authPhone.isNotEmpty;
      }
      gender = (data['gender'] is String) ? data['gender'] : null;
      if (data['dob'] is Timestamp) {
        dob = (data['dob'] as Timestamp).toDate();
      } else {
        dob = null;
      }
      _initialProfileSnapshot = _currentProfileSnapshot();
      _initialLoadComplete = true;
    });
  }

  Map<String, dynamic> _currentProfileSnapshot() {
    return <String, dynamic>{
      'firstName': firstNameController.text.trim(),
      'middleName': middleNameController.text.trim(),
      'lastName': lastNameController.text.trim(),
      'email': emailController.text.trim(),
      'phone': phoneController.text.trim(),
      'pincode': pincodeController.text.trim(),
      'city': cityController.text.trim(),
      'state': stateController.text.trim(),
      'gender': gender ?? '',
      'dob': dob == null
          ? ''
          : DateTime(dob!.year, dob!.month, dob!.day).millisecondsSinceEpoch,
      'photoUrl': (_photoUrl ?? '').trim(),
      'pendingEmailVerificationEmail':
          (_pendingEmailVerificationEmail ?? '').trim(),
      'hasSelectedPhoto': _selectedPhotoBytes != null,
      'selectedPhotoName': (_selectedPhotoName ?? '').trim(),
      'removePhoto': _removePhoto,
    };
  }

  bool get _hasUnsavedChanges {
    final initial = _initialProfileSnapshot;
    if (initial == null) return false;
    return jsonEncode(initial) != jsonEncode(_currentProfileSnapshot());
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasUnsavedChanges) return true;
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Discard changes?'),
          content: const Text(
            'You have unsaved profile changes. Do you want to discard them and leave?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep Editing'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );
    return shouldDiscard ?? false;
  }

  Future<bool> _confirmApplyChanges() async {
    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Apply changes?'),
          content: const Text(
            'Do you want to save these profile updates now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F3E8F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    return shouldApply ?? false;
  }

  Future<void> _handleSavePressed() async {
    if (!_formKey.currentState!.validate()) return;
    if (!await _confirmApplyChanges()) return;
    await _saveProfile();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (dob != null && !_isAllowedDob(dob!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Date of birth must be on or before 01/01/2007.'),
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => loading = true);

    final firstName = firstNameController.text.trim();
    final middleName = middleNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final fullName = [
      firstName,
      middleName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ');
    final requestedEmail = emailController.text.trim();
    final requestedPhone = AuthIdentityService.normalizePhone(
      phoneController.text.trim(),
    );
    final pendingEmail = (_pendingEmailVerificationEmail ?? '').trim();
    final requestMatchesPendingEmail =
        pendingEmail.isNotEmpty &&
        requestedEmail.toLowerCase() == pendingEmail.toLowerCase();
    final emailChanged =
        !_emailLocked &&
        requestedEmail.isNotEmpty &&
        requestedEmail.toLowerCase() != _authEmail.trim().toLowerCase() &&
        !requestMatchesPendingEmail;
    final phoneChanged =
        !_phoneLocked &&
        requestedPhone.isNotEmpty &&
        _normalizePhoneForCompare(requestedPhone) !=
            _normalizePhoneForCompare(_authPhone);

    final Map<String, dynamic> updateData = {
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'name': fullName,
      'email': _authEmail,
      'phone': _phoneLocked
          ? AuthIdentityService.normalizePhone(_authPhone)
          : requestedPhone,
      'normalizedEmail': AuthIdentityService.normalizeEmail(_authEmail),
      'normalizedPhone': _phoneLocked
          ? AuthIdentityService.normalizePhone(_authPhone)
          : requestedPhone,
      'pincode': pincodeController.text.trim(),
      'city': cityController.text.trim(),
      'state': stateController.text.trim(),
      'gender': gender,
      'updatedAt': Timestamp.now(),
    };
    if (pendingEmail.isNotEmpty) {
      updateData['pendingEmailVerificationEmail'] = pendingEmail;
      updateData['pendingEmailVerificationUpdatedAt'] = Timestamp.now();
    }

    if (dob != null) {
      updateData['dob'] = Timestamp.fromDate(dob!);
    } else {
      updateData['dob'] = '';
    }

    try {
      if (emailChanged) {
        if (await _isEmailAlreadyInUse(user: user, email: requestedEmail)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That email address is already being used by another account.'),
            ),
          );
          return;
        }
        final emailFlowResult = await _verifyAndUpdateEmail(
          user: user,
          newEmail: requestedEmail,
        );
        if (emailFlowResult == _EmailUpdateFlowResult.cancelled) return;
        if (emailFlowResult == _EmailUpdateFlowResult.loggedOut) return;
        updateData['pendingEmailVerificationEmail'] = requestedEmail;
        updateData['pendingEmailVerificationUpdatedAt'] = Timestamp.now();
        updateData['normalizedEmail'] = AuthIdentityService.normalizeEmail(
          requestedEmail,
        );
      }

      if (phoneChanged) {
        if (await _isPhoneAlreadyInUse(user: user, phone: requestedPhone)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That phone number is already being used by another account.'),
            ),
          );
          return;
        }
        final phoneVerified = await _verifyAndUpdatePhone(
          user: user,
          newPhone: requestedPhone,
        );
        if (!phoneVerified) return;
        updateData['phone'] = requestedPhone;
        updateData['normalizedPhone'] = requestedPhone;
      }

      if (_selectedPhotoBytes != null) {
        final uploadedPhotoUrl = await _uploadProfilePhoto(
          userId: user.uid,
          bytes: _selectedPhotoBytes!,
          fileName: _selectedPhotoName,
        );
        updateData['photoURL'] = uploadedPhotoUrl;
      } else if (_removePhoto) {
        await _deleteProfilePhoto(user.uid);
        updateData['photoURL'] = '';
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));

      if (updateData.containsKey('photoURL')) {
        final nextPhotoUrl = (updateData['photoURL'] ?? '').toString().trim();
        await user.updatePhotoURL(nextPhotoUrl.isEmpty ? null : nextPhotoUrl);
      }

      if (emailChanged) {
        _pendingEmailVerificationEmail = requestedEmail;
      }
      if (phoneChanged) {
        _authPhone = requestedPhone;
      }

      if (mounted) {
        _initialProfileSnapshot = _currentProfileSnapshot();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text(_profileSaveErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<_EmailUpdateFlowResult> _verifyAndUpdateEmail({
    required User user,
    required String newEmail,
  }) async {
    try {
      await user.verifyBeforeUpdateEmail(newEmail);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'pendingEmailVerificationEmail': newEmail,
        'pendingEmailVerificationUpdatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
      if (!mounted) return _EmailUpdateFlowResult.cancelled;
      final action = await showDialog<_PostVerificationAction>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text('Verify your new email'),
          content: Text(
              'We sent a verification link to $newEmail. The email could be in your SPAM folder. After you verify it, you may need to log out and sign in again before using this new email to log in or changing the email again.',
          ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_PostVerificationAction.stayLoggedIn),
                child: const Text('Stay logged in'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_PostVerificationAction.logOutNow),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F3E8F),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Log out now'),
              ),
            ],
          );
        },
      );
      if (action == _PostVerificationAction.logOutNow) {
        await _forceLogoutAndGoToLogin();
        return _EmailUpdateFlowResult.loggedOut;
      }
      return _EmailUpdateFlowResult.pending;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return _EmailUpdateFlowResult.cancelled;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_emailChangeErrorMessage(e))),
      );
      return _EmailUpdateFlowResult.cancelled;
    } catch (_) {
      if (!mounted) return _EmailUpdateFlowResult.cancelled;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not verify new email.')),
      );
      return _EmailUpdateFlowResult.cancelled;
    }
  }

  String _emailChangeErrorMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'requires-recent-login' ||
      'email-change-needs-verification' =>
        'Please verify the email change you already requested, then log out and sign in again before trying to change your email.',
      'invalid-email' => 'Enter a valid email address.',
      'email-already-in-use' =>
        'That email address is already being used by another account.',
      _ => error.message ?? 'Could not verify new email.',
    };
  }

  String _profileSaveErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'network-request-failed' =>
          'Could not save your profile right now. Please check your internet connection and try again.',
        'requires-recent-login' =>
          'For security reasons, please sign in again and then retry saving your profile.',
        _ => error.message ?? 'Could not save your profile right now. Please try again.',
      };
    }

    if (error is FirebaseException) {
      return switch (error.code) {
        'unavailable' || 'network-request-failed' =>
          'Could not save your profile right now. Please check your internet connection and try again.',
        _ => 'Could not save your profile right now. Please try again.',
      };
    }

    if (error is TimeoutException ||
        error is http.ClientException ||
        error.toString().toLowerCase().contains('connection reset') ||
        error.toString().toLowerCase().contains('network')) {
      return 'Could not save your profile right now. Please check your internet connection and try again.';
    }

    return 'Could not save your profile right now. Please try again.';
  }

  Future<bool> _isEmailAlreadyInUse({
    required User user,
    required String email,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) return false;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isGreaterThanOrEqualTo: '')
        .get();

    for (final doc in snapshot.docs) {
      if (doc.id == user.uid) continue;
      final existingEmail = (doc.data()['email'] ?? '').toString().trim();
      if (existingEmail.toLowerCase() == normalizedEmail) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _isPhoneAlreadyInUse({
    required User user,
    required String phone,
  }) async {
    final normalizedPhone = _normalizePhoneForCompare(phone);
    if (normalizedPhone.isEmpty) return false;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('phone', isGreaterThanOrEqualTo: '')
        .get();

    for (final doc in snapshot.docs) {
      if (doc.id == user.uid) continue;
      final existingPhone = (doc.data()['phone'] ?? '').toString().trim();
      if (_normalizePhoneForCompare(existingPhone) == normalizedPhone) {
        return true;
      }
    }
    return false;
  }

  Future<void> _forceLogoutAndGoToLogin() async {
    await SingleDeviceSessionService.signOutToLogin();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Log out?'),
          content: const Text(
            'You will need to sign in again to continue editing your profile.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F3E8F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await _forceLogoutAndGoToLogin();
    }
  }

  Future<bool> _verifyAndUpdatePhone({
    required User user,
    required String newPhone,
  }) async {
    final phoneNumber = _phoneForVerification(newPhone);
    if (phoneNumber == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid phone number.')),
        );
      }
      return false;
    }

    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Phone number verification from profile update is not supported on web yet.',
            ),
          ),
        );
      }
      return false;
    }

    try {
      final credential = await _requestPhoneUpdateCredential(phoneNumber);
      if (credential == null) return false;
      await user.updatePhoneNumber(credential);
      return true;
    } on _PhoneVerificationCancelled {
      return false;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return false;
      final message = switch (e.code) {
        'invalid-verification-code' => 'Incorrect OTP. Please try again.',
        'session-expired' => 'OTP expired. Please request a new verification.',
        'credential-already-in-use' =>
          'This mobile number is already linked to another account.',
        _ => e.message ?? 'Could not verify phone number.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not verify phone number.')),
      );
      return false;
    }
  }

  Future<PhoneAuthCredential?> _requestPhoneUpdateCredential(
    String phoneNumber,
  ) async {
    final auth = FirebaseAuth.instance;
    final completer = Completer<PhoneAuthCredential?>();
    var cancelledByUser = false;

    await auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) {
        if (!completer.isCompleted) {
          completer.complete(credential);
        }
      },
      verificationFailed: (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
      codeSent: (verificationId, resendToken) async {
        final smsCode = await _promptForOtp(phoneNumber);
        if (smsCode == null || smsCode.length != 6) {
          cancelledByUser = true;
          if (!completer.isCompleted) {
            completer.completeError(const _PhoneVerificationCancelled());
          }
          return;
        }
        if (!completer.isCompleted) {
          completer.complete(
            PhoneAuthProvider.credential(
              verificationId: verificationId,
              smsCode: smsCode,
            ),
          );
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!cancelledByUser && !completer.isCompleted) {
          completer.complete(null);
        }
      },
    );

    return completer.future;
  }

  Future<String?> _promptForOtp(String phoneNumber) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool submitting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Verify Mobile Number'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter the 6-digit OTP sent to $phoneNumber'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    enabled: !submitting,
                    decoration: const InputDecoration(
                      hintText: 'Enter OTP',
                      counterText: '',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () {
                          final otp = controller.text.trim();
                          if (otp.length != 6) return;
                          setDialogState(() => submitting = true);
                          Navigator.of(dialogContext).pop(otp);
                        },
                  child: const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  String _normalizePhoneForCompare(String value) {
    return AuthIdentityService.normalizePhone(value);
  }

  String? _phoneForVerification(String value) {
    final normalized = AuthIdentityService.normalizePhone(value);
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _pickDob() async {
    final latestAllowedDob = _latestAllowedDob;
    final initialDate = dob != null && !dob!.isAfter(latestAllowedDob)
        ? dob!
        : latestAllowedDob;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1950),
      lastDate: latestAllowedDob,
    );

    if (picked != null) {
      setState(() => dob = picked);
    }
  }

  Future<void> _pickProfilePhoto() async {
    if (_isProcessingPhoto) return;
    try {
      if (mounted) {
        setState(() => _isProcessingPhoto = true);
      }
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: _pickedPhotoMaxDimension,
        maxHeight: _pickedPhotoMaxDimension,
      );
      if (image == null) return;

      final croppedImage = await ImageCropper().cropImage(
        sourcePath: image.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 82,
        maxWidth: _croppedPhotoMaxDimension,
        maxHeight: _croppedPhotoMaxDimension,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Photo',
            toolbarColor: const Color(0xFF2F3E8F),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            aspectRatioPresets: const [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.original,
            ],
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Crop Photo',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            aspectRatioPresets: const [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.original,
            ],
          ),
        ],
      );
      if (croppedImage == null) return;

      final bytes = await croppedImage.readAsBytes();
      if (bytes.length > _maxProfilePhotoBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo must be 2 MB or smaller.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _selectedPhotoBytes = bytes;
        _selectedPhotoName = croppedImage.path.split('/').last;
        _removePhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessingPhoto = false);
      }
    }
  }

  void _removeProfilePhoto() {
    setState(() {
      _selectedPhotoBytes = null;
      _selectedPhotoName = null;
      _removePhoto = true;
    });
  }

  Future<String> _uploadProfilePhoto({
    required String userId,
    required Uint8List bytes,
    required String? fileName,
  }) async {
    final extension = _fileExtension(fileName);
    final ref = FirebaseStorage.instance.ref().child(
      'profile_photos/$userId/profile$extension',
    );
    await ref.putData(
      bytes,
      SettableMetadata(contentType: _contentTypeForExtension(extension)),
    );
    return ref.getDownloadURL();
  }

  Future<void> _deleteProfilePhoto(String userId) async {
    try {
      final folderRef = FirebaseStorage.instance.ref().child(
        'profile_photos/$userId',
      );
      final items = await folderRef.listAll();
      for (final item in items.items) {
        await item.delete();
      }
    } catch (_) {
      // Ignore missing storage objects for users without uploaded photos.
    }
  }

  String _fileExtension(String? fileName) {
    final value = (fileName ?? '').toLowerCase();
    if (value.endsWith('.png')) return '.png';
    if (value.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  void _onPincodeChanged(String value) {
    _pincodeDebounce?.cancel();

    if (value.trim().length != 6) {
      if (_pincodeLookupMessage != null || _isResolvingPincode) {
        setState(() {
          _isResolvingPincode = false;
          _pincodeLookupMessage = null;
        });
      }
      return;
    }

    _pincodeDebounce = Timer(
      const Duration(milliseconds: 350),
      _resolvePincode,
    );
  }

  Future<void> _resolvePincode() async {
    final pincode = pincodeController.text.trim();
    if (pincode.length != 6) return;
    final lookupToken = ++_activePincodeLookupToken;
    setState(() {
      _isResolvingPincode = true;
      _pincodeLookupMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('https://api.postalpincode.in/pincode/$pincode'),
      ).timeout(const Duration(seconds: 8));

      if (!mounted ||
          lookupToken != _activePincodeLookupToken ||
          pincodeController.text.trim() != pincode) {
        return;
      }

      if (response.statusCode != 200) {
        throw Exception('Lookup failed');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) {
        throw const FormatException('Unexpected response');
      }

      final result = decoded.first as Map<String, dynamic>;
      final postOfficeList = result['PostOffice'];
      if (result['Status'] != 'Success' ||
          postOfficeList is! List ||
          postOfficeList.isEmpty) {
        setState(() {
          cityController.clear();
          stateController.clear();
          _pincodeLookupMessage = 'Could not find city and state for this PIN.';
        });
        return;
      }

      final firstOffice = postOfficeList.first as Map<String, dynamic>;
      final city = (firstOffice['District'] ?? '').toString().trim();
      final state = (firstOffice['State'] ?? '').toString().trim();

      if (!mounted) return;

      setState(() {
        if (city.isNotEmpty) {
          cityController.text = city;
        }
        if (state.isNotEmpty) {
          stateController.text = state;
        }
        _pincodeLookupMessage = city.isNotEmpty && state.isNotEmpty
            ? 'City and state autofilled from PIN code.'
            : 'PIN found, but address details were incomplete.';
      });
    } on TimeoutException {
      if (!mounted || lookupToken != _activePincodeLookupToken) return;
      setState(() {
        _pincodeLookupMessage =
            'Unable to fetch location now. You can enter city and state manually.';
      });
    } on http.ClientException {
      if (!mounted || lookupToken != _activePincodeLookupToken) return;
      setState(() {
        _pincodeLookupMessage =
            'Unable to fetch location now. You can enter city and state manually.';
      });
    } catch (_) {
      if (!mounted || lookupToken != _activePincodeLookupToken) return;
      setState(() {
        _pincodeLookupMessage =
            'Unable to fetch location now. You can enter city and state manually.';
      });
    } finally {
      if (mounted && lookupToken == _activePincodeLookupToken) {
        setState(() {
          _isResolvingPincode = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pincodeDebounce?.cancel();
    firstNameController.dispose();
    middleNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    pincodeController.dispose();
    cityController.dispose();
    stateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => await _confirmDiscardChanges(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  TopHeader(
                    selectedExamId: null,
                    userExamIds: const [],
                    onExamChanged: (_) {},
                    showExamDropdown: false,
                    showNotificationBell: false,
                    enableTitleNavigation: false,
                    trailingAction: _showHeaderLogout
                        ? TextButton.icon(
                            onPressed: loading ? null : _confirmLogout,
                            icon: const Icon(
                              Icons.logout_rounded,
                              size: 18,
                              color: Color(0xFFB45309),
                            ),
                            label: const Text(
                              'Log out',
                              style: TextStyle(
                                color: Color(0xFFB45309),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 38),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              backgroundColor: const Color(0xFFFFFBEB),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: loading && !_initialLoadComplete
                        ? const Center(child: CircularProgressIndicator())
                        : IgnorePointer(
                            ignoring: loading,
                            child: Opacity(
                              opacity: loading ? 0.72 : 1,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  24,
                                ),
                                child: Form(
                                  key: _formKey,
                                   child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             const Text(
                                'Keep your details accurate so RankSprint can personalize your exam journey.',
                                style: TextStyle(
                                 fontSize: 14,
                                 color: Color(0xFF6B7280),
                                 height: 1.5,
                               ),
                             ),
                             const SizedBox(height: 18),
                             _buildSectionCard(
                               title: 'Profile Photo',
                               subtitle:
                                   'Upload a clear profile image up to 2 MB.',
                               children: [
                                 _buildPhotoEditor(),
                               ],
                             ),
                             const SizedBox(height: 16),
                             _buildSectionCard(
                         title: 'Basic Details',
                        subtitle: 'Your identity and personal information',
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  firstNameController,
                                  'First Name',
                                  required: true,
                                  validator: (value) {
                                    if ((value ?? '').trim().isEmpty) {
                                      return 'First name is required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  middleNameController,
                                  'Middle Name',
                                ),
                              ),
                            ],
                          ),
                          _buildTextField(
                            lastNameController,
                            'Last Name',
                            required: true,
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return 'Last name is required';
                              }
                              return null;
                            },
                          ),
                          _buildTextField(
                            emailController,
                            'Email ID',
                            enabled: !_emailLocked,
                            keyboardType: TextInputType.emailAddress,
                            helperText: _emailLocked
                                ? 'Managed by your sign-in method'
                                : null,
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) return 'Email is required';
                              final emailRegex = RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              );
                              if (!emailRegex.hasMatch(v)) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          if ((_pendingEmailVerificationEmail ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B).withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 1),
                                      child: Icon(
                                        Icons.mark_email_unread_outlined,
                                        size: 18,
                                        color: Color(0xFFB45309),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Verification pending for ${_pendingEmailVerificationEmail!}. After verifying, log out and sign in again if you want to use this email for login or make another email change.',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          height: 1.4,
                                          color: Color(0xFF92400E),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          _buildTextField(
                            phoneController,
                            'Phone Number',
                            enabled: !_phoneLocked,
                            keyboardType: TextInputType.phone,
                            helperText: _phoneLocked
                                ? 'Managed by your sign-in method'
                                : null,
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) return 'Phone number is required';
                              if (v.length < 10) {
                                return 'Enter a valid phone number';
                              }
                              return null;
                            },
                          ),
                          _buildGenderField(),
                          _buildDobField(),
                        ],
                      ),
                            const SizedBox(height: 16),
                            _buildSectionCard(
                        title: 'Location',
                        subtitle:
                            'PIN code can help autofill your city and state',
                        children: [
                          _buildTextField(
                            pincodeController,
                            'Pincode',
                            keyboardType: TextInputType.number,
                            helperText: 'Enter a 6-digit PIN code',
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) return 'Pincode is required';
                              if (v.length != 6) return 'Enter a valid pincode';
                              return null;
                            },
                            onChanged: _onPincodeChanged,
                            suffixIcon: _isResolvingPincode
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.location_searching_rounded,
                                    color: Color(0xFF6B7280),
                                  ),
                          ),
                          if (_pincodeLookupMessage != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _pincodeLookupMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    _pincodeLookupMessage!
                                        .toLowerCase()
                                        .contains('autofilled')
                                    ? const Color(0xFF0F766E)
                                    : const Color(0xFF92400E),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  cityController,
                                  'City',
                                  validator: (value) {
                                    if ((value ?? '').trim().isEmpty) {
                                      return 'City is required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  stateController,
                                  'State',
                                  validator: (value) {
                                    if ((value ?? '').trim().isEmpty) {
                                      return 'State is required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: loading ? null : _handleSavePressed,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2F3E8F),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                child: loading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Text(
                                        'Save Changes',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            if (_isProcessingPhoto)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.12),
                  child: const Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.4),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Processing photo...',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _buildPhotoEditor() {
    final imageProvider = _avatarImageProvider();
    final initials = _profileInitials();

    return Row(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: const Color(0xFF2F3E8F),
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton.icon(
                onPressed: loading || _isProcessingPhoto ? null : _pickProfilePhoto,
                icon: _isProcessingPhoto
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: Text(
                  _isProcessingPhoto ? 'Processing...' : 'Upload Photo',
                ),
              ),
              const SizedBox(height: 8),
              if (_selectedPhotoBytes != null ||
                  ((_photoUrl ?? '').isNotEmpty && !_removePhoto))
                TextButton(
                  onPressed:
                      loading || _isProcessingPhoto ? null : _removeProfilePhoto,
                  child: const Text('Remove Photo'),
                ),
              const SizedBox(height: 4),
              if (_isProcessingPhoto) ...[
                const Text(
                  'Optimizing image for faster cropping...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF2F3E8F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              const Text(
                'JPG, PNG, or WebP. Maximum size 2 MB.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  ImageProvider? _avatarImageProvider() {
    if (_selectedPhotoBytes != null) {
      return MemoryImage(_selectedPhotoBytes!);
    }
    final photoUrl = (_photoUrl ?? '').trim();
    if (photoUrl.isNotEmpty && !_removePhoto) {
      return NetworkImage(photoUrl);
    }
    return null;
  }

  String _profileInitials() {
    final first = firstNameController.text.trim();
    final last = lastNameController.text.trim();
    final firstInitial = first.isNotEmpty ? first.substring(0, 1) : '';
    final lastInitial = last.isNotEmpty ? last.substring(0, 1) : '';
    final value = '$firstInitial$lastInitial'.toUpperCase();
    return value.isEmpty ? 'RS' : value;
  }

  Widget _buildGenderField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: _genderOptions.contains(gender) ? gender : null,
        isExpanded: true,
        menuMaxHeight: 220,
        icon: Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF2FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Color(0xFF2F3E8F),
          ),
        ),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(16),
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF111827),
        ),
        decoration: _inputDecoration(
          'Gender',
          helperText: 'Choose the option that best describes you',
          suffixIcon: const Icon(
            Icons.arrow_drop_down_rounded,
            color: Colors.transparent,
          ),
        ).copyWith(
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 8),
            child: Icon(
              Icons.person_outline_rounded,
              size: 20,
              color: Color(0xFF6B7280),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 20,
          ),
          hintText: 'Select Gender',
          hintStyle: const TextStyle(
            fontSize: 15,
            color: Color(0xFF9CA3AF),
            fontWeight: FontWeight.w500,
          ),
        ),
        items: _genderOptions
            .map(
              (option) => DropdownMenuItem<String>(
                value: option,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: gender == option
                              ? const Color(0xFF2F3E8F)
                              : const Color(0xFFD1D5DB),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          option,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: (val) => setState(() => gender = val),
      ),
    );
  }

  Widget _buildDobField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: _pickDob,
        borderRadius: BorderRadius.circular(16),
        child: InputDecorator(
          decoration: _inputDecoration('Date of Birth').copyWith(
            suffixIcon: const Icon(
              Icons.calendar_today_rounded,
              size: 18,
              color: Color(0xFF6B7280),
            ),
          ),
          child: Text(
            dob != null ? _formatDate(dob!) : 'Select Date of Birth',
            style: TextStyle(
              fontSize: 15,
              color: dob != null
                  ? const Color(0xFF111827)
                  : const Color(0xFF9CA3AF),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool enabled = true,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    String? helperText,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: validator,
        onChanged: onChanged,
        decoration: _inputDecoration(
          required ? '$label *' : label,
          helperText: helperText,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    String? helperText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2F3E8F), width: 1.3),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  DateTime get _latestAllowedDob {
    return DateTime(2007, 1, 1);
  }

  bool _isAllowedDob(DateTime value) {
    return !value.isAfter(_latestAllowedDob);
  }

  _ResolvedNameParts _resolveNameParts({
    required String firstName,
    required String middleName,
    required String lastName,
    required String legacyFullName,
  }) {
    if (firstName.isNotEmpty || middleName.isNotEmpty || lastName.isNotEmpty) {
      return _ResolvedNameParts(
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
      );
    }

    if (legacyFullName.isEmpty) {
      return const _ResolvedNameParts(
        firstName: '',
        middleName: '',
        lastName: '',
      );
    }

    final parts = legacyFullName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return const _ResolvedNameParts(
        firstName: '',
        middleName: '',
        lastName: '',
      );
    }

    if (parts.length == 1) {
      return _ResolvedNameParts(
        firstName: parts.first,
        middleName: '',
        lastName: '',
      );
    }

    if (parts.length == 2) {
      return _ResolvedNameParts(
        firstName: parts.first,
        middleName: '',
        lastName: parts.last,
      );
    }

    return _ResolvedNameParts(
      firstName: parts.first,
      middleName: parts.sublist(1, parts.length - 1).join(' '),
      lastName: parts.last,
    );
  }
}

class _PhoneVerificationCancelled implements Exception {
  const _PhoneVerificationCancelled();
}

enum _PostVerificationAction { stayLoggedIn, logOutNow }

enum _EmailUpdateFlowResult { pending, loggedOut, cancelled }

class _ResolvedNameParts {
  const _ResolvedNameParts({
    required this.firstName,
    required this.middleName,
    required this.lastName,
  });

  final String firstName;
  final String middleName;
  final String lastName;
}
