import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'main.dart';
import 'services/data_service.dart';

class ProfileOverlay extends StatefulWidget {
  final Function() onClose;

  const ProfileOverlay({required this.onClose, super.key});

  @override
  State<ProfileOverlay> createState() => _ProfileOverlayState();
}

class _ProfileOverlayState extends State<ProfileOverlay> {
  // User data
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isSaving = false;
  String _errorMessage = '';
  String _successMessage = '';

  // Editable fields
  TextEditingController _usernameController = TextEditingController();
  TextEditingController _emailController = TextEditingController();
  TextEditingController _phoneController = TextEditingController();
  TextEditingController _nationalIdController = TextEditingController();
  TextEditingController _currentPasswordController = TextEditingController();
  TextEditingController _newPasswordController = TextEditingController();
  TextEditingController _confirmPasswordController = TextEditingController();
  TextEditingController _businessTypeController = TextEditingController();

  // Image handling
  Uint8List? _webImageBytes;
  File? _mobileImageFile;
  String? _currentImagePath;
  final ImagePicker _picker = ImagePicker();

  // QR Code
  String? _payCode;
  String? _qrValue;

  // Current section
  String selectedSection = 'profile';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final user = getCurrentUser();
      if (user == null) {
        setState(() {
          _errorMessage = 'No user logged in';
          _isLoading = false;
        });
        return;
      }

      _userData = user;

      // Initialize controllers with current data
      _usernameController.text = user['username']?.toString() ?? '';
      _emailController.text = user['email']?.toString() ?? '';
      _phoneController.text = user['phoneNumber']?.toString() ?? user['phone']?.toString() ?? '';
      _nationalIdController.text = user['nationalId']?.toString() ?? user['national_id']?.toString() ?? '';
      _businessTypeController.text = user['businessType']?.toString() ?? user['business_type']?.toString() ?? '';

      // Get paycode from database
      await _fetchPayCode();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load user data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchPayCode() async {
    try {
      final user = getCurrentUser();
      if (user == null) {
        _generateFallbackPayCode();
        return;
      }

      // First check if we already have paycode in user data
      String? paycode = user['paycode'] ?? user['merchantpaycode'];

      if (paycode != null && paycode.isNotEmpty) {
        setState(() {
          _payCode = paycode;
          _qrValue = paycode;
        });
        return;
      }

      // If not in cache, fetch from API
      final email = user['email']?.toString();
      if (email == null || email.isEmpty) {
        _generateFallbackPayCode();
        return;
      }

      final response = await http.get(
        Uri.parse("http://localhost:8000/api/user-details/?email=$email"),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final paycode = data['paycode'] ?? data['merchantpaycode'];

        if (paycode != null && paycode.isNotEmpty) {
          // Update local user data with paycode
          if (_userData != null) {
            _userData!['paycode'] = paycode;
            _userData!['merchantpaycode'] = paycode;
            setCurrentUser(_userData);
          }

          setState(() {
            _payCode = paycode.toString();
            _qrValue = paycode.toString();
          });
        } else {
          _generateFallbackPayCode();
        }
      } else {
        _generateFallbackPayCode();
      }
    } on TimeoutException {
      _generateFallbackPayCode();
    } catch (e) {
      _generateFallbackPayCode();
    }
  }

  void _generateFallbackPayCode() {
    final rnd = Random();
    final userType = _userData?['type'] ?? 'user';
    final prefix = userType == 'merchant' ? 'MERCHANT-' : 'USER-';
    final code = '$prefix${rnd.nextInt(900000) + 100000}';

    setState(() {
      _payCode = code;
      _qrValue = code;
    });
  }

  Future<void> _pickAndSaveImage() async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      if (kIsWeb) {
        _webImageBytes = await picked.readAsBytes();
        _mobileImageFile = null;
      } else {
        final bytes = await picked.readAsBytes();
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory(path.join(docs.path, 'profile_pics'));
        if (!await dir.exists()) await dir.create(recursive: true);

        final user = getCurrentUser();
        String base = (user?['username'] ?? user?['email'] ?? 'user')
            .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

        final file = File(path.join(dir.path, 'profile_$base.jpg'));
        await file.writeAsBytes(bytes);

        _mobileImageFile = file;
        _webImageBytes = null;
      }

      setState(() {});
      _showSuccess('Profile picture updated locally');

      await _uploadProfilePicture();
    } on MissingPluginException {
      _showError('Image picker not supported on this platform');
    } catch (e) {
      _showError('Failed to update image: $e');
    }
  }

  Future<void> _uploadProfilePicture() async {
    try {
      final user = getCurrentUser();
      if (user == null || user['email'] == null) return;

      final uri = Uri.parse("http://localhost:8000/api/update-profile-picture/");
      final request = http.MultipartRequest('PUT', uri);

      request.fields['email'] = user['email'];

      if (kIsWeb) {
        if (_webImageBytes == null) {
          _showError('No image selected');
          return;
        }
        request.files.add(
          http.MultipartFile.fromBytes(
            'profilePicture',
            _webImageBytes!,
            filename: 'profile.jpg',
          ),
        );
      } else {
        if (_mobileImageFile == null) {
          _showError('No image selected');
          return;
        }
        request.files.add(
          await http.MultipartFile.fromPath(
            'profilePicture',
            _mobileImageFile!.path,
            filename: 'profile.jpg',
          ),
        );
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        _userData?['profilePicture'] = data['profilePicture'];
        setCurrentUser(_userData);

        _showSuccess('Profile picture updated successfully');
      } else {
        _showError('Failed to upload profile picture: ${response.body}');
      }
    } catch (e) {
      _showError('Error uploading profile picture: $e');
    }
  }

  Future<void> _updateProfile() async {
    try {
      if (_isSaving) return;

      setState(() {
        _isSaving = true;
        _errorMessage = '';
        _successMessage = '';
      });

      final user = getCurrentUser();
      if (user == null) {
        _showError('No user logged in');
        setState(() { _isSaving = false; });
        return;
      }

      final uri = Uri.parse("http://localhost:8000/api/update-profile/");
      final response = await http.put(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'email': user['email'],
          'username': _usernameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'national_id': _nationalIdController.text.trim(),
          'current_password': _currentPasswordController.text.isNotEmpty
              ? _currentPasswordController.text
              : null,
          'new_password': _newPasswordController.text.isNotEmpty
              ? _newPasswordController.text
              : null,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        _userData?['username'] = _usernameController.text.trim();
        _userData?['phoneNumber'] = _phoneController.text.trim();
        setCurrentUser(_userData);

        _showSuccess('Profile updated successfully');

        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      } else {
        final errorData = jsonDecode(response.body);
        _showError(errorData['error']?.toString() ?? 'Failed to update profile');
      }
    } on TimeoutException {
      _showError('Request timed out. Please try again.');
    } catch (e) {
      _showError('Error updating profile: $e');
    } finally {
      setState(() { _isSaving = false; });
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performLogout();
            },
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _performLogout() {
    setCurrentUser(null);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
      _successMessage = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    setState(() {
      _successMessage = message;
      _errorMessage = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildSectionContainer({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFF8A00), width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            enabled: enabled,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildProfileSection() {
    final userType = _userData?['type'] ?? 'user';
    final isMerchant = userType == 'merchant';

    ImageProvider avatarProvider;
    if (kIsWeb && _webImageBytes != null) {
      avatarProvider = MemoryImage(_webImageBytes!);
    } else if (!kIsWeb && _mobileImageFile != null) {
      avatarProvider = FileImage(_mobileImageFile!);
    } else if (_currentImagePath != null &&
        _currentImagePath!.isNotEmpty &&
        File(_currentImagePath!).existsSync()) {
      avatarProvider = FileImage(File(_currentImagePath!));
    } else {
      avatarProvider = const AssetImage('assets/images/profile.jpeg');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Profile Settings',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        _buildSectionContainer(
          title: 'Profile Picture',
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickAndSaveImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundImage: avatarProvider,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF8A00),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        _buildSectionContainer(
          title: 'Personal Information',
          children: [
            _buildInputField(
              label: 'Username',
              controller: _usernameController,
            ),
            _buildInputField(
              label: 'Email',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: false,
            ),
            _buildInputField(
              label: 'Phone Number',
              controller: _phoneController,
              keyboardType: TextInputType.phone,
            ),
            _buildInputField(
              label: 'National ID',
              controller: _nationalIdController,
              enabled: false,
            ),
            if (isMerchant)
              _buildInputField(
                label: 'Business Type',
                controller: _businessTypeController,
                enabled: false,
              ),
          ],
        ),

        const SizedBox(height: 20),

        _buildSectionContainer(
          title: 'Change Password',
          children: [
            _buildInputField(
              label: 'Current Password',
              controller: _currentPasswordController,
              obscureText: true,
            ),
            _buildInputField(
              label: 'New Password',
              controller: _newPasswordController,
              obscureText: true,
            ),
            _buildInputField(
              label: 'Confirm New Password',
              controller: _confirmPasswordController,
              obscureText: true,
            ),
            const SizedBox(height: 10),
            Text(
              'Note: Leave password fields empty if you don\'t want to change password',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _updateProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A00),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Text(
              'Save Changes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPayCodeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Code',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        _buildSectionContainer(
          title: 'Your Payment Code',
          children: [
            Center(
              child: Column(
                children: [
                  if (_payCode != null && _payCode!.isNotEmpty) ...[
                    // Elegant QR Code Container with Logo
                    Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            blurRadius: 15,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: const Color(0xFFFF8A00).withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // QR Code with Logo embedded
                          QrImageView(
                            data: _payCode!,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                            // Add your company logo in the center
                            embeddedImage: const AssetImage('images/logo1.png'),
                            embeddedImageStyle: const QrEmbeddedImageStyle(
                              size: Size(50, 50),
                            ),
                            // High error correction to ensure QR still scans with logo
                            errorCorrectionLevel: QrErrorCorrectLevel.H,
                            // Custom styling for better appearance
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF1a3250),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF1a3250),
                            ),
                          ),
                          // Additional decorative border around logo
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFFF8A00).withOpacity(0.4),
                                width: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),

                    // Paycode Display with elegant styling
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            const Color(0xFFFF8A00).withOpacity(0.1),
                            const Color(0xFFFF8A00).withOpacity(0.05),
                            const Color(0xFFFF8A00).withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFFF8A00).withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'YOUR PAYCODE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFF8A00),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _payCode!,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1a3250),
                              letterSpacing: 2.5,
                              fontFamily: 'Monospace',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Instructions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code_scanner,
                                color: const Color(0xFFFF8A00),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'How to Use',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1a3250),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Scan the QR code or share the paycode above to receive payments. Our company logo ensures authenticity.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_isLoading) ...[
                    const SizedBox(height: 60),
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Color(0xFFFF8A00)),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Loading payment code...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 60),
                    const Icon(
                      Icons.error_outline,
                      size: 70,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Unable to load payment code',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _fetchPayCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A00),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.refresh, size: 20),
                      label: const Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 25),

        _buildSectionContainer(
          title: 'Payment Instructions',
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A00).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.qr_code,
                  color: Color(0xFFFF8A00),
                  size: 22,
                ),
              ),
              title: const Text(
                'QR Code with Logo',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              subtitle: const Text(
                'Our company logo is embedded to show authenticity',
              ),
            ),
            const Divider(height: 1, color: Colors.grey),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A00).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.share,
                  color: Color(0xFFFF8A00),
                  size: 22,
                ),
              ),
              title: const Text(
                'Share Your Code',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              subtitle: const Text(
                'Share QR code or text code with customers',
              ),
            ),
            const Divider(height: 1, color: Colors.grey),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A00).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.security,
                  color: Color(0xFFFF8A00),
                  size: 22,
                ),
              ),
              title: const Text(
                'Secure & Verified',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                _userData?['type'] == 'merchant'
                    ? 'Merchant Verified Payment Code'
                    : 'User Verified Payment Code',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSecuritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Security & Privacy',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        _buildSectionContainer(
          title: 'Security Settings',
          children: const [
            ListTile(
              leading: Icon(Icons.fingerprint, color: Color(0xFFFF8A00)),
              title: Text('Biometric Authentication'),
              trailing: Switch(value: false, onChanged: null),
            ),
            ListTile(
              leading: Icon(Icons.notifications, color: Color(0xFFFF8A00)),
              title: Text('Push Notifications'),
              trailing: Switch(value: true, onChanged: null),
            ),
            ListTile(
              leading: Icon(Icons.email, color: Color(0xFFFF8A00)),
              title: Text('Email Notifications'),
              trailing: Switch(value: true, onChanged: null),
            ),
          ],
        ),

        const SizedBox(height: 20),

        _buildSectionContainer(
          title: 'Privacy',
          children: const [
            ListTile(
              leading: Icon(Icons.visibility, color: Color(0xFFFF8A00)),
              title: Text('Profile Visibility'),
              subtitle: Text('Control who can see your profile'),
            ),
            ListTile(
              leading: Icon(Icons.history, color: Color(0xFFFF8A00)),
              title: Text('Transaction History'),
              subtitle: Text('View your transaction privacy settings'),
            ),
          ],
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _logout,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFF8A00),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onClose,
        ),
        title: const Text('Account Settings'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Color(0xFFFF8A00)),
          strokeWidth: 3,
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Navigation Panel
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.grey.shade200,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavButton('Profile', Icons.person_outline, 'profile'),
                  _buildNavButton('Payment Code', Icons.qr_code_2, 'paycode'),
                  _buildNavButton('Security', Icons.security, 'security'),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // Error/Success Messages
            if (_errorMessage.isNotEmpty)
              _buildMessageCard(
                message: _errorMessage,
                isError: true,
                onClose: () => setState(() { _errorMessage = ''; }),
              ),

            if (_successMessage.isNotEmpty)
              _buildMessageCard(
                message: _successMessage,
                isError: false,
                onClose: () => setState(() { _successMessage = ''; }),
              ),

            if (_errorMessage.isNotEmpty || _successMessage.isNotEmpty)
              const SizedBox(height: 20),

            // Selected Section Content
            if (selectedSection == 'profile') _buildProfileSection(),
            if (selectedSection == 'paycode') _buildPayCodeSection(),
            if (selectedSection == 'security') _buildSecuritySection(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard({
    required String message,
    required bool isError,
    required VoidCallback onClose,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? Colors.red.shade200 : Colors.green.shade200,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle,
            color: isError ? Colors.red.shade600 : Colors.green.shade600,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.red.shade800 : Colors.green.shade800,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 18,
              color: isError ? Colors.red.shade600 : Colors.green.shade600,
            ),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(String title, IconData icon, String sectionKey) {
    final isSelected = selectedSection == sectionKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedSection = sectionKey;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF8A00) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey.shade600,
              size: 26,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _businessTypeController.dispose();
    super.dispose();
  }
}