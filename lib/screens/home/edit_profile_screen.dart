import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../widgets/top_header.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
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
  bool _isResolvingPincode = false;
  String? _pincodeLookupMessage;
  String _authEmail = '';
  String _authPhone = '';
  Timer? _pincodeDebounce;
  String? _photoUrl;
  Uint8List? _selectedPhotoBytes;
  String? _selectedPhotoName;
  bool _removePhoto = false;

  static const List<String> _genderOptions = ['Male', 'Female', 'Other'];
  static const int _maxProfilePhotoBytes = 2 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final authEmail = (user.email ?? '').trim();
    final authPhone = (user.phoneNumber ?? '').trim();
    final hasPhoneProvider = user.providerData.any(
      (p) => p.providerId == 'phone',
    );
    final hasEmailProvider = user.providerData.any(
      (p) => p.providerId == 'google.com' || p.providerId == 'password',
    );

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!mounted) return;

    final data = doc.data() ?? <String, dynamic>{};
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

    setState(() {
      firstNameController.text = resolvedNames.firstName;
      middleNameController.text = resolvedNames.middleName;
      lastNameController.text = resolvedNames.lastName;
      emailController.text = authEmail.isNotEmpty
          ? authEmail
          : ((data['email'] is String) ? data['email'] : '');
      phoneController.text = authPhone.isNotEmpty
          ? authPhone
          : ((data['phone'] is String) ? data['phone'] : '');
      pincodeController.text = (data['pincode'] is String)
          ? data['pincode']
          : '';
      cityController.text = (data['city'] is String) ? data['city'] : '';
      stateController.text = (data['state'] is String) ? data['state'] : '';
      _authEmail = authEmail;
      _authPhone = authPhone;
      _photoUrl = (data['photoURL'] is String)
          ? (data['photoURL'] as String).trim()
          : '';
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
      _initialLoadComplete = true;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (dob != null && !_isAtLeast13YearsOld(dob!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User must be at least 16 years old.')),
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

    final Map<String, dynamic> updateData = {
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'name': fullName,
      'email': _emailLocked ? _authEmail : emailController.text.trim(),
      'phone': _phoneLocked ? _authPhone : phoneController.text.trim(),
      'pincode': pincodeController.text.trim(),
      'city': cityController.text.trim(),
      'state': stateController.text.trim(),
      'gender': gender,
      'updatedAt': Timestamp.now(),
    };

    if (dob != null) {
      updateData['dob'] = Timestamp.fromDate(dob!);
    } else {
      updateData['dob'] = '';
    }

    try {
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

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
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
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null) return;

      final croppedImage = await ImageCropper().cropImage(
        sourcePath: image.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Photo',
            toolbarColor: const Color(0xFF2F3E8F),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            aspectRatioPresets: const [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
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
              CropAspectRatioPreset.ratio4x3,
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
    setState(() {
      _isResolvingPincode = true;
      _pincodeLookupMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('https://api.postalpincode.in/pincode/$pincode'),
      );

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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        cityController.clear();
        stateController.clear();
        _pincodeLookupMessage =
            'Unable to fetch location now. You can enter city and state manually.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingPincode = false;
        });
      }
    }
  }

  @override
  void dispose() {
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            TopHeader(
              selectedExamId: null,
              userExamIds: const [],
              onExamChanged: (_) {},
              showExamDropdown: false,
              showNotificationBell: false,
              enableTitleNavigation: false,
            ),
            Expanded(
              child: loading && !_initialLoadComplete
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                                onPressed: loading ? null : _saveProfile,
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
                onPressed: loading ? null : _pickProfilePhoto,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Upload Photo'),
              ),
              const SizedBox(height: 8),
              if (_selectedPhotoBytes != null ||
                  ((_photoUrl ?? '').isNotEmpty && !_removePhoto))
                TextButton(
                  onPressed: loading ? null : _removeProfilePhoto,
                  child: const Text('Remove Photo'),
                ),
              const SizedBox(height: 4),
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
        decoration: _inputDecoration('Gender'),
        items: _genderOptions
            .map(
              (option) => DropdownMenuItem<String>(
                value: option,
                child: SizedBox(
                  width: double.infinity,
                  child: Text(option, overflow: TextOverflow.ellipsis),
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
    final now = DateTime.now();
    return DateTime(now.year - 13, now.month, now.day);
  }

  bool _isAtLeast13YearsOld(DateTime value) {
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
