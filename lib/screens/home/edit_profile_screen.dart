import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final pincodeController = TextEditingController();
  final cityController = TextEditingController();
  final stateController = TextEditingController();

  String? gender;
  DateTime? dob;
  bool loading = false;
  bool _emailLocked = false;
  bool _phoneLocked = false;
  String _authEmail = '';
  String _authPhone = '';

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

    final data = doc.data() ?? <String, dynamic>{};

    setState(() {
      nameController.text = (data['name'] is String) ? data['name'] : '';
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
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => loading = true);

    final Map<String, dynamic> updateData = {
      'name': nameController.text.trim(),
      'email': _emailLocked ? _authEmail : emailController.text.trim(),
      'phone': _phoneLocked ? _authPhone : phoneController.text.trim(),
      'pincode': pincodeController.text.trim(),
      'city': cityController.text.trim(),
      'state': stateController.text.trim(),
      'gender': gender,
      'updatedAt': Timestamp.now(),
    };

    // Only add dob if selected
    if (dob != null) {
      updateData['dob'] = Timestamp.fromDate(dob!);
    } else {
      updateData['dob'] = ""; // Clear dob if not selected
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            updateData,
            SetOptions(merge: true),
          );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dob ?? DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => dob = picked);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
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
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildTextField(nameController, "Full Name"),
                    _buildTextField(
                      emailController,
                      "Email ID",
                      enabled: !_emailLocked,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return "Email is required";
                        final emailRegex = RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        );
                        if (!emailRegex.hasMatch(v)) {
                          return "Enter a valid email";
                        }
                        return null;
                      },
                    ),
                    _buildTextField(
                      phoneController,
                      "Phone Number",
                      enabled: !_phoneLocked,
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return "Phone number is required";
                        if (v.length < 10) return "Enter a valid phone number";
                        return null;
                      },
                    ),
                    _buildTextField(pincodeController, "Pincode"),
                    _buildTextField(cityController, "City"),
                    _buildTextField(stateController, "State"),

                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: gender,
                      decoration: _inputDecoration("Gender"),
                      items: const [
                        DropdownMenuItem(value: "Male", child: Text("Male")),
                        DropdownMenuItem(
                          value: "Female",
                          child: Text("Female"),
                        ),
                        DropdownMenuItem(value: "Other", child: Text("Other")),
                      ],
                      onChanged: (val) => setState(() => gender = val),
                    ),

                    const SizedBox(height: 12),

                    GestureDetector(
                      onTap: _pickDob,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          dob != null
                              ? "${dob!.day}/${dob!.month}/${dob!.year}"
                              : "Select Date of Birth",
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2F3E8F),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Save Changes",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        validator: validator,
        decoration: _inputDecoration(label, helperText: helperText),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {String? helperText}) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
