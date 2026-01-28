import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:image_picker/image_picker.dart';

import 'main.dart'; // LoginScreen
import 'services/data_service.dart';

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  String accountType = "merchant";
  DateTime? selectedDate;

  String get year =>
      selectedDate == null ? "Year" : selectedDate!.year.toString();
  String get month =>
      selectedDate == null ? "Month" : _monthName(selectedDate!.month);
  String get day =>
      selectedDate == null ? "Day" : selectedDate!.day.toString();

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  String _monthName(int m) {
    const months = [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December"
    ];
    return months[m - 1];
  }

  final emailController = TextEditingController();
  final usernameController = TextEditingController();
  final nationalIdController = TextEditingController();
  final businessTypeController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  /// PROFILE IMAGE STATE
  Uint8List? _webImageBytes; // Web preview
  File? _mobileImageFile;   // Mobile upload
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF2E9),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Image.asset("assets/images/logo.png", height: 100),
              const SizedBox(height: 30),

              const Text(
                "Create Account",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.deepOrange,
                ),
              ),

              const SizedBox(height: 25),
              _label("National ID"),
              _inputField(
                controller: nationalIdController,
                hint: "National ID",
                icon: Icons.perm_identity,
              ),

              const SizedBox(height: 20),
              _label("Upload profile picture"),
              const SizedBox(height: 8),

              GestureDetector(
                onTap: _pickAndSaveImage,
                child: Container(
                  height: 120,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.deepOrangeAccent),
                  ),
                  child: (_webImageBytes == null && _mobileImageFile == null)
                      ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 36, color: Colors.grey),
                        SizedBox(height: 8),
                        Text("Tap to upload profile picture",
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                      : Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb
                            ? Image.memory(
                          _webImageBytes!,
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        )
                            : Image.file(
                          _mobileImageFile!,
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Profile image selected",
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              _label("Account Type"),
              DropdownButtonFormField<String>(
                value: accountType,
                items: const [
                  DropdownMenuItem(value: "merchant", child: Text("merchant")),
                  DropdownMenuItem(value: "user", child: Text("user")),
                ],
                onChanged: (v) => setState(() => accountType = v!),
              ),

              const SizedBox(height: 20),
              _inputField(
                controller: emailController,
                hint: "Email",
                icon: Icons.email,
              ),
              const SizedBox(height: 20),
              _inputField(
                controller: usernameController,
                hint: "Username",
                icon: Icons.person,
              ),
              const SizedBox(height: 20),
              _inputField(
                controller: phoneController,
                hint: "Phone Number",
                icon: Icons.phone,
              ),
              const SizedBox(height: 20),
              _inputField(
                controller: passwordController,
                hint: "Password",
                icon: Icons.lock,
                obscure: true,
              ),

              const SizedBox(height: 20),
              _label(accountType == "merchant"
                  ? "Date of Creation"
                  : "Date of Birth"),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [_dateBox(year), _dateBox(month), _dateBox(day)],
              ),

              if (accountType == "merchant") ...[
                const SizedBox(height: 12),
                _inputField(
                  controller: businessTypeController,
                  hint: "Business Type",
                  icon: Icons.business,
                ),
              ],

              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _handleCreateAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    "Create account",
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: const Text(
                  "Or sign in",
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// CREATE ACCOUNT
  Future<void> _handleCreateAccount() async {
    try {
      await createUserWithProfile(
        nationalId: nationalIdController.text.trim(),
        email: emailController.text.trim(),
        username: usernameController.text.trim(),
        phoneNumber: phoneController.text.trim(),
        password: passwordController.text.trim(),
        accountType: accountType,
        profileImage: _mobileImageFile, // null on Web
        dateOfBirth: accountType == "user" ? selectedDate : null,
        dateOfCreation: accountType == "merchant" ? selectedDate : null,
        businessType:
        accountType == "merchant" ? businessTypeController.text.trim() : null,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// IMAGE PICKER (WEB + MOBILE)
  Future<void> _pickAndSaveImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    if (kIsWeb) {
      _webImageBytes = await picked.readAsBytes();
      _mobileImageFile = null;
    } else {
      _mobileImageFile = File(picked.path);
      _webImageBytes = null;
    }

    setState(() {});
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }

  Widget _label(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
  );

  Widget _dateBox(String text) => GestureDetector(
    onTap: pickDate,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.deepOrangeAccent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    ),
  );
}
