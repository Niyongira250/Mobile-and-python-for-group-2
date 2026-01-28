import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:qr_code_tools/qr_code_tools.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:myapp/receive_page.dart';
import 'package:myapp/wallet_page.dart';
import 'home_page.dart';
import 'order_page.dart';
import 'credentials.dart';
import 'profile_overlay.dart';
import 'services/data_service.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:math';


class PayPage extends StatefulWidget {
  const PayPage({super.key});

  @override
  State<PayPage> createState() => _PayPageState();
}

class _PayPageState extends State<PayPage> {
  int _selectedIndex = 2;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  final TextEditingController amountController = TextEditingController();

  MobileScannerController? mobileScannerController;
  bool _isScanning = true;
  bool _isLoadingFromCode = false;
  bool _isLoadingGallery = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;
  bool _showQrDetected = false;
  final ImagePicker _picker = ImagePicker();

  // Animation for scanning line
  double _scanLinePosition = 0;
  Timer? _scanTimer;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();

    // Initialize QR scanner
    mobileScannerController = MobileScannerController(
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: [BarcodeFormat.qrCode],
      returnImage: false,
    );

    // Start scanning line animation
    _startScanAnimation();
  }

  void _startScanAnimation() {
    _scanTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted) {
        setState(() {
          _scanLinePosition = (_scanLinePosition + 3) % 260;
        });
      }
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    mobileScannerController?.dispose();
    super.dispose();
  }

  /// ===============================
  /// LOOKUP USER BY PAYCODE
  /// ===============================
  Future<Map<String, dynamic>?> lookupByPaycode(String paycode) async {
    try {
      print('🔍 Looking up paycode: $paycode');

      final response = await http.get(
        Uri.parse("$baseUrl/find-user-by-paycode/?paycode=$paycode"),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      print('📡 Response status: ${response.statusCode}');
      print('📄 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (data['success'] == true) {
          print('✅ Paycode lookup successful: ${data['username']}');
          return {
            'username': data['username'] ?? '',
            'email': data['email'] ?? '',
            'phone': data['phone'] ?? '',
            'type': data['type'] ?? 'user',
            'paycode': data['paycode'] ?? paycode,
            'profile_picture': data['profile_picture'],
            'business_type': data['business_type'],
          };
        } else {
          print('❌ Paycode not found: ${data['error']}');
          return null;
        }
      } else {
        debugPrint('❌ lookupByPaycode failed: ${response.statusCode}');
        return null;
      }
    } on TimeoutException {
      debugPrint('⏰ lookupByPaycode request timed out');
      return null;
    } catch (e) {
      debugPrint('🔥 lookupByPaycode error: $e');
      return null;
    }
  }

  Future<void> _fetchUserDetailsFromPayCode(String payCode) async {
    try {
      setState(() {
        _isLoadingFromCode = true;
      });

      print('🔍 Searching for paycode: $payCode');

      // Clean the paycode - remove spaces
      String cleanPayCode = payCode.trim();

      // Convert to uppercase for consistency
      String searchPayCode = cleanPayCode.toUpperCase();

      // Fix common OCR/scanning errors: O -> 0, I -> 1, l -> 1
      searchPayCode = searchPayCode
          .replaceAll('O', '0')
          .replaceAll('I', '1')
          .replaceAll('l', '1');

      // Check if paycode matches expected format for both users and merchants
      // User: UP followed by 6 digits (UP123456)
      // Merchant: MP followed by any alphanumeric characters (MP001, MP20259796, MP20255276, etc.)
      bool isValidUserCode = RegExp(r'^UP\d{6}$').hasMatch(searchPayCode);
      bool isValidMerchantCode = RegExp(r'^MP[0-9A-Z]+$').hasMatch(searchPayCode);

      if (!isValidUserCode && !isValidMerchantCode) {
        _showSnackbar('Invalid paycode format', Colors.orange);
        setState(() {
          nameController.text = 'Invalid paycode format';
          codeController.text = cleanPayCode;
          _isLoadingFromCode = false;
        });
        return;
      }

      // First check if this is the current user's paycode
      final currentUser = getCurrentUser();
      if (currentUser != null) {
        // Check for user paycode
        final userPayCode = currentUser['paycode']?.toString().toUpperCase() ?? '';
        // Check for merchant paycode
        final merchantPayCode = currentUser['merchantpaycode']?.toString().toUpperCase() ?? '';

        // Also apply the same character replacements for comparison
        String cleanUserPayCode = userPayCode
            .replaceAll('O', '0')
            .replaceAll('I', '1')
            .replaceAll('l', '1');
        String cleanMerchantPayCode = merchantPayCode
            .replaceAll('O', '0')
            .replaceAll('I', '1')
            .replaceAll('l', '1');

        if (cleanUserPayCode == searchPayCode || cleanMerchantPayCode == searchPayCode) {
          print('✅ Scanned own paycode');
          setState(() {
            nameController.text = currentUser['username']?.toString() ?? 'Yourself';
            codeController.text = cleanPayCode;
            _isLoadingFromCode = false;
          });
          return;
        }
      }

      // Try lookup with normalized code first
      Map<String, dynamic>? userData = await lookupByPaycode(searchPayCode);

      // If not found with normalized code, try with original uppercase code
      if (userData == null && searchPayCode != cleanPayCode.toUpperCase()) {
        userData = await lookupByPaycode(cleanPayCode.toUpperCase());
      }

      if (userData != null && userData['username'] != null && userData['username'].isNotEmpty) {
        String username = userData['username'];
        String userType = userData['type'] ?? 'user';
        print('✅ Found $userType: $username');

        // Check if it's a merchant
        if (userType == 'merchant') {
          String businessType = userData['business_type'] ?? '';
          if (businessType.isNotEmpty) {
            username = '$username ($businessType)';
          }
        }

        setState(() {
          nameController.text = username;
          codeController.text = cleanPayCode;
          _isLoadingFromCode = false;
        });

        // Show success message
        _showSnackbar('Found $userType: $username', Colors.green);
      } else {
        _handleUserNotFound(cleanPayCode);
      }
    } on TimeoutException {
      print('❌ Request timeout');
      _showSnackbar('Request timed out. Please try again.', Colors.orange);
      setState(() {
        _isLoadingFromCode = false;
      });
    } catch (e) {
      print('❌ Error fetching user details: $e');
      _showSnackbar('Failed to fetch user details: $e', Colors.red);
      setState(() {
        _isLoadingFromCode = false;
      });
    }
  }

  void _handleUserNotFound(String payCode) {
    setState(() {
      nameController.text = 'User not found';
      codeController.text = payCode;
    });

    _showSnackbar('No user or merchant found with paycode: $payCode', Colors.orange);
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleQrDetect(BarcodeCapture barcodes) {
    if (!_isScanning || barcodes.barcodes.isEmpty) return;

    final barcode = barcodes.barcodes.first;
    final scannedCode = barcode.rawValue?.trim();
    if (scannedCode == null || scannedCode.isEmpty) return;

    final now = DateTime.now();
    if (_lastScannedCode == scannedCode &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(seconds: 3)) {
      return;
    }

    _lastScannedCode = scannedCode;
    _lastScanTime = now;

    // Show visual feedback
    setState(() {
      _showQrDetected = true;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showQrDetected = false;
        });
      }
    });

    print('📱 QR Code detected: $scannedCode');

    // Fetch user/merchant details
    _fetchUserDetailsFromPayCode(scannedCode);

    // Pause scanning briefly
    setState(() {
      _isScanning = false;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isScanning = true;
        });
      }
    });
  }

  Future<void> _searchByCode() async {
    final code = codeController.text.trim();
    if (code.isEmpty) {
      _showSnackbar('Please enter a paycode', Colors.orange);
      return;
    }

    await _fetchUserDetailsFromPayCode(code);
  }

  Future<void> _scanFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    try {
      final String? qrData = await QrCodeToolsPlugin.decodeFrom(image.path);
      if (qrData != null) {
        print('✅ QR code data: $qrData');
        codeController.text = qrData;
        await _fetchUserDetailsFromPayCode(qrData);
        _showSnackbar('QR code scanned successfully!', Colors.green);
      } else {
        _showSnackbar('No QR code found', Colors.red);
      }
    } catch (e) {
      _showSnackbar('Failed to scan QR: $e', Colors.red);
    }
  }

  void _toggleTorch() {
    if (mobileScannerController != null) {
      setState(() {
        _isTorchOn = !_isTorchOn;
      });
      mobileScannerController!.toggleTorch();
    }
  }

  void _onTap(int index) {
    setState(() => _selectedIndex = index);

    if (index == 0) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    } else if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const OrderPage()),
      );
    } else if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WalletPage()),
      );
    } else if (index == 4) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ReceivePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF2E9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              /// ---------------- TOP BAR ----------------
              Container(
                height: 110,
                width: double.infinity,
                decoration: const BoxDecoration(color: Color(0xFFFF8A00)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Builder(
                          builder: (context) {
                            final user = getCurrentUser();
                            final username = user?['username']?.toString() ?? 'User';
                            return Text(
                              username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProfileOverlay(
                                  onClose: () => Navigator.pop(context),
                                ),
                              ),
                            );
                            setState(() {});
                          },
                          child: Builder(
                            builder: (context) {
                              final user = getCurrentUser();
                              final imgPath = user?['profilePicturePath'] as String?;
                              final provider = imageProviderFromPath(imgPath);
                              if (provider != null) {
                                return CircleAvatar(
                                  radius: 18,
                                  backgroundImage: provider,
                                );
                              }
                              return const CircleAvatar(
                                radius: 18,
                                backgroundImage: AssetImage(
                                  "assets/images/profile.jpeg",
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 15),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      "SCAN QR CODE",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              /// -------- TORCH & GALLERY ---------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _toggleTorch,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isTorchOn ? Icons.flash_on : Icons.flash_off,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isTorchOn ? "Torch ON" : "Torch",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _isLoadingGallery ? null : _scanFromGallery,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _isLoadingGallery
                                ? Colors.grey
                                : Colors.deepOrange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isLoadingGallery)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                Image.asset(
                                  "assets/images/scan_from_gallery.png",
                                  height: 20,
                                ),
                              const SizedBox(width: 6),
                              Text(
                                _isLoadingGallery ? "Loading..." : "Scan from gallery",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
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

              const SizedBox(height: 15),

              /// -------- QR SCANNER PREVIEW --------
              Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: Colors.black,
                  border: Border.all(
                    color: _showQrDetected ? Colors.green : Colors.blue,
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    children: [
                      // Camera preview with MobileScanner
                      MobileScanner(
                        controller: mobileScannerController,
                        onDetect: _handleQrDetect,
                        fit: BoxFit.cover,
                      ),

                      // Scanning line animation
                      Positioned(
                        top: _scanLinePosition,
                        child: Container(
                          width: 260,
                          height: 4,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.green.withOpacity(0.9),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // QR detection overlay
                      if (_showQrDetected)
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.green.withOpacity(0.5),
                              width: 10,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 50,
                            ),
                          ),
                        ),

                      // Corner guides
                      _buildCornerGuide(Alignment.topLeft),
                      _buildCornerGuide(Alignment.topRight),
                      _buildCornerGuide(Alignment.bottomLeft),
                      _buildCornerGuide(Alignment.bottomRight),

                      // Center instruction with animated arrow
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.qr_code_scanner,
                                      color: Colors.white.withOpacity(0.7),
                                      size: 40,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Place QR code here',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'or enter code manually',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Loading indicator
                      if (_isLoadingFromCode)
                        Container(
                          color: Colors.black.withOpacity(0.7),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.orange,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Scanner status
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _showQrDetected ? Icons.check_circle :
                    _isScanning ? Icons.qr_code_scanner : Icons.pause,
                    color: _showQrDetected ? Colors.green :
                    _isScanning ? Colors.blue : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _showQrDetected ? 'QR Code Detected!' :
                    _isScanning ? 'Ready to scan...' : 'Processing...',
                    style: TextStyle(
                      color: _showQrDetected ? Colors.green :
                      _isScanning ? Colors.blue : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              /// -------- INPUT FIELDS --------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  children: [
                    _inputField(
                      "Name",
                      controller: nameController,
                      readOnly: true,
                    ),
                    const SizedBox(height: 12),
                    _inputFieldWithIcon(
                      "Code",
                      controller: codeController,
                      onIconTap: _searchByCode,
                      isLoading: _isLoadingFromCode,
                    ),
                    const SizedBox(height: 12),
                    _inputField(
                      "Amount",
                      hint: "Enter amount in FRW",
                      controller: amountController,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              /// -------- PROCEED BUTTON --------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: GestureDetector(
                  onTap: () {
                    if (nameController.text.isEmpty ||
                        codeController.text.isEmpty ||
                        amountController.text.isEmpty) {
                      _showSnackbar('Please fill all fields', Colors.orange);
                      return;
                    }

                    if (nameController.text == 'User not found' ||
                        nameController.text == 'Invalid paycode format') {
                      _showSnackbar('Please scan a valid QR code', Colors.red);
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CredentialsPage(
                          name: nameController.text,
                          code: codeController.text,
                          amount: amountController.text,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 50,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8A00),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Center(
                      child: Text(
                        "Proceed",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              /// -------- INSTRUCTIONS --------
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 25),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "How to use:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "1. Point camera at QR code - it will auto-fill details\n"
                          "2. Tap 'Scan from gallery' to select QR image\n"
                          "3. Or enter paycode manually and tap QR icon\n"
                          "4. Enter amount and tap Proceed",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "User Paycode: UP followed by 6 digits (e.g., UP123456)\n"
                          "Merchant Paycode: MP followed by numbers (e.g., MP001, MP20259796, MP20255276)",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_lastScannedCode != null)
                      Text(
                        "Last scanned: $_lastScannedCode",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),

      /// -------- BOTTOM NAV --------
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onTap,
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: Image.asset("assets/images/home.png", height: 24),
            label: "home",
          ),
          BottomNavigationBarItem(
            icon: Image.asset("assets/images/order.png", height: 24),
            label: "order",
          ),
          BottomNavigationBarItem(
            icon: Image.asset("assets/images/pay.png", height: 28),
            label: "pay",
          ),
          BottomNavigationBarItem(
            icon: Image.asset("assets/images/wallet.png", height: 24),
            label: "wallet",
          ),
          BottomNavigationBarItem(
            icon: Image.asset("assets/images/receive.png", height: 24),
            label: "receive",
          ),
        ],
      ),
    );
  }

  Widget _buildCornerGuide(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
                  ? Colors.green
                  : Colors.transparent,
              width: 4,
            ),
            top: BorderSide(
              color: alignment == Alignment.topLeft || alignment == Alignment.topRight
                  ? Colors.green
                  : Colors.transparent,
              width: 4,
            ),
            right: BorderSide(
              color: alignment == Alignment.topRight || alignment == Alignment.bottomRight
                  ? Colors.green
                  : Colors.transparent,
              width: 4,
            ),
            bottom: BorderSide(
              color: alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight
                  ? Colors.green
                  : Colors.transparent,
              width: 4,
            ),
          ),
        ),
      ),
    );
  }

  /// --------------------- COMPONENTS ---------------------
  Widget _inputField(
      String label, {
        String? hint,
        required TextEditingController controller,
        bool readOnly = false,
        TextInputType keyboardType = TextInputType.text,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
      decoration: BoxDecoration(
        color: readOnly ? Colors.grey.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: readOnly ? Colors.grey : Colors.deepOrangeAccent,
        ),
        boxShadow: readOnly ? null : const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint ?? "",
          labelText: label,
          border: InputBorder.none,
          suffixIcon: readOnly &&
              controller.text.isNotEmpty &&
              controller.text != 'User not found' &&
              controller.text != 'Invalid paycode format'
              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
              : null,
        ),
      ),
    );
  }

  Widget _inputFieldWithIcon(
      String label, {
        required TextEditingController controller,
        required VoidCallback onIconTap,
        bool isLoading = false,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.deepOrangeAccent),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                border: InputBorder.none,
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  onIconTap();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: isLoading ? null : onIconTap,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isLoading ? Colors.grey : Colors.deepOrange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}