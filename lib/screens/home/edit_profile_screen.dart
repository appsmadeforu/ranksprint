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

  final Map<String, String> cityStateMap = {
    "Mumbai": "Maharashtra",
    "Pune": "Maharashtra",
    "Bangalore": "Karnataka",
    "Kochi": "Kerala",
    "Chennai": "Tamil Nadu",
    "Hyderabad": "Telangana",
    "Delhi": "Delhi",
    "Ahmedabad": "Gujarat",
    "Jaipur": "Rajasthan",
  };

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

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data() ?? {};

    setState(() {
      nameController.text = data['name'] ?? '';
      emailController.text = authEmail.isNotEmpty
          ? authEmail
          : (data['email'] ?? '');
      phoneController.text = authPhone.isNotEmpty
          ? authPhone
          : (data['phone'] ?? '');

      pincodeController.text = data['pincode'] ?? '';
      cityController.text = data['city'] ?? '';
      stateController.text = data['state'] ?? '';

      gender = data['gender'];

      if (data['dob'] is Timestamp) {
        dob = (data['dob'] as Timestamp).toDate();
      }

      _authEmail = authEmail;
      _authPhone = authPhone;

      _emailLocked = authEmail.isNotEmpty;
      _phoneLocked = authPhone.isNotEmpty;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => loading = true);

    final updateData = {
      'name': nameController.text.trim(),
      'email': _emailLocked ? _authEmail : emailController.text.trim(),
      'phone': _phoneLocked ? _authPhone : phoneController.text.trim(),
      'pincode': pincodeController.text.trim(),
      'city': cityController.text.trim(),
      'state': stateController.text.trim(),
      'gender': gender,
      'updatedAt': Timestamp.now(),
      'dob': dob != null ? Timestamp.fromDate(dob!) : "",
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
    }

    if (mounted) setState(() => loading = false);
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
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        titleSpacing: 0,
        title: Row(
          children: [Image.asset("assets/icons/account_icon.png", height: 180)],
        ),
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
                    ),

                    _buildTextField(
                      phoneController,
                      "Phone Number",
                      enabled: !_phoneLocked,
                      keyboardType: TextInputType.phone,
                    ),

                    _buildTextField(pincodeController, "Pincode"),

                    /// CITY DROPDOWN
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String>(
                        value: cityController.text.isEmpty
                            ? null
                            : cityController.text,
                        decoration: _inputDecoration("City"),
                        items: cityStateMap.keys.map((city) {
                          return DropdownMenuItem(
                            value: city,
                            child: Text(city),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              cityController.text = value;
                              stateController.text = cityStateMap[value] ?? '';
                            });
                          }
                        },
                      ),
                    ),

                    /// STATE (AUTO FILLED)
                    _buildTextField(
                      stateController,
                      "State",
                      enabled: false,
                      helperText: "Auto filled based on city",
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: gender,
                            decoration: _inputDecoration("Gender"),
                            items: const [
                              DropdownMenuItem(
                                value: "Male",
                                child: Text("Male"),
                              ),
                              DropdownMenuItem(
                                value: "Female",
                                child: Text("Female"),
                              ),
                              DropdownMenuItem(
                                value: "Other",
                                child: Text("Other"),
                              ),
                            ],
                            onChanged: (val) {
                              setState(() => gender = val);
                            },
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: GestureDetector(
                            onTap: _pickDob,
                            child: Container(
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
                                    : "Select DOB",
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                      ],
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
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
