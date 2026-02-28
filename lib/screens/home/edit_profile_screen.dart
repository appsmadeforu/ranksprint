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
  final phoneController = TextEditingController();
  final pincodeController = TextEditingController();
  final cityController = TextEditingController();
  final stateController = TextEditingController();

  String? gender;
  DateTime? dob;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data();
    if (data == null) return;

    setState(() {
      nameController.text = data['name'] ?? '';
      phoneController.text = data['phone'] ?? '';
      pincodeController.text = data['pincode'] ?? '';
      cityController.text = data['city'] ?? '';
      stateController.text = data['state'] ?? '';
      gender = data['gender'];
      if (data['dob'] is Timestamp) {
        dob = (data['dob'] as Timestamp).toDate();
      }
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => loading = true);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'name': nameController.text.trim(),
      'phone': phoneController.text.trim(),
      'pincode': pincodeController.text.trim(),
      'city': cityController.text.trim(),
      'state': stateController.text.trim(),
      'gender': gender,
      'dob': dob != null ? Timestamp.fromDate(dob!) : null,
      'updatedAt': Timestamp.now(),
    });

    setState(() => loading = false);

    if (mounted) {
      Navigator.pop(context);
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
                    _buildTextField(phoneController, "Phone Number"),
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

  Widget _buildTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: _inputDecoration(label),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
