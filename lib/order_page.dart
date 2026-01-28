import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_code_tools/qr_code_tools.dart';
import 'package:http/http.dart' as http;
import 'home_page.dart';
import 'pay_page.dart';
import 'wallet_page.dart';
import 'receive_page.dart';
import 'menu.dart';
import 'pay_orders.dart';
import 'see_orders.dart';
import 'profile_overlay.dart';
import 'services/data_service.dart';
import 'credentials.dart';

class OrderPage extends StatefulWidget {
  const OrderPage({super.key});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  int _selectedIndex = 1;
  int _activeTopSegment = 1; // 0: pay orders, 1: scan, 2: see orders

  // QR Scanner
  MobileScannerController? mobileScannerController;
  bool _isScanning = true;
  bool _isLoadingFromCode = false;
  bool _isLoadingGallery = false;
  bool _isLoadingMenu = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;
  bool _showQrDetected = false;
  final ImagePicker _picker = ImagePicker();

  // Animation
  double _scanLinePosition = 0;
  Timer? _scanTimer;
  bool _isTorchOn = false;

  // Merchant data
  final TextEditingController _merchantCodeController = TextEditingController();
  final TextEditingController _merchantNameController = TextEditingController();
  Map<String, dynamic>? _merchantData;
  List<Map<String, dynamic>> _menuItems = [];
  String _menuError = '';

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
    _merchantCodeController.dispose();
    _merchantNameController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> lookupMerchantByPaycode(String paycode) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/find-user-by-paycode/?paycode=$paycode"),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (data['success'] == true && data['type'] == 'merchant') {
          // IMPORTANT: Fetch the full merchant details to get merchantid
          try {
            final merchantDetailsResponse = await http.get(
              Uri.parse("$baseUrl/merchant-details/?email=${data['email']}"),
              headers: {"Content-Type": "application/json"},
            ).timeout(const Duration(seconds: 5));

            if (merchantDetailsResponse.statusCode == 200) {
              final merchantDetails = jsonDecode(merchantDetailsResponse.body);

              print('=== MERCHANT DETAILS FETCHED ===');
              print('Merchant Details: $merchantDetails');
              print('Merchant ID: ${merchantDetails['merchantid']}');
              print('===============================');

              return {
                'username': data['username'] ?? '',
                'email': data['email'] ?? '',
                'phone': data['phone'] ?? '',
                'type': 'merchant',
                'paycode': data['paycode'] ?? paycode,
                'merchantpaycode': data['paycode'] ?? paycode,
                'profile_picture': data['profile_picture'],
                'business_type': data['business_type'] ?? '',
                'merchantid': merchantDetails['merchantid'], // THIS IS CRITICAL
              };
            } else {
              print('Failed to fetch merchant details: ${merchantDetailsResponse.statusCode}');
            }
          } catch (e) {
            print('Error fetching merchant details: $e');
          }
        } else {
          print('Not a merchant or success false: ${data['type']}');
        }
      } else {
        print('Failed to find user by paycode: ${response.statusCode}');
      }
      return null;
    } on TimeoutException {
      print('Timeout in lookupMerchantByPaycode');
      return null;
    } catch (e) {
      print('Error in lookupMerchantByPaycode: $e');
      return null;
    }
  }

  Future<void> fetchMerchantMenu(String merchantPaycode) async {
    try {
      setState(() {
        _isLoadingMenu = true;
        _menuError = '';
        _menuItems.clear();
      });

      final merchantData = await lookupMerchantByPaycode(merchantPaycode);

      // DEBUG: Check what we got
      print('=== FETCHED MERCHANT DATA ===');
      print('Merchant Data: $merchantData');
      print('Has merchantid: ${merchantData != null && merchantData['merchantid'] != null}');
      print('=============================');

      if (merchantData == null) {
        setState(() {
          _menuError = 'Merchant not found';
          _isLoadingMenu = false;
        });
        return;
      }

      // Check if merchantid exists
      if (merchantData['merchantid'] == null) {
        setState(() {
          _menuError = 'Could not get merchant ID. Please try again.';
          _isLoadingMenu = false;
        });
        return;
      }

      final merchantId = merchantData['merchantid'];

      // Fetch menu using the actual merchant ID
      final menuResponse = await http.get(
        Uri.parse("$baseUrl/merchant-menu/?merchant_id=$merchantId"),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      print('Menu response status: ${menuResponse.statusCode}');

      if (menuResponse.statusCode == 200) {
        final menuData = jsonDecode(menuResponse.body);

        print('Menu data received: ${menuData.containsKey('success')}');
        print('Menu success: ${menuData['success']}');

        if (menuData['success'] == true) {
          final menuItems = List<Map<String, dynamic>>.from(menuData['menu'] ?? []);

          print('Number of menu items: ${menuItems.length}');

          if (menuItems.isEmpty) {
            setState(() {
              _menuError = 'NO menu found for "${merchantData['username']}"';
              _merchantData = merchantData;
              _merchantNameController.text = merchantData['username'];
              _isLoadingMenu = false;
            });
          } else {
            setState(() {
              _menuItems = menuItems;
              _merchantData = merchantData;
              _merchantNameController.text = merchantData['username'];
              _isLoadingMenu = false;
            });

            // DEBUG: Print merchant data before navigation
            print('=== MENU LOADED SUCCESSFULLY ===');
            print('Merchant Data for MenuPage: $_merchantData');
            print('Merchant ID: ${_merchantData?['merchantid']}');
            print('Merchant Name: ${_merchantData?['username']}');
            print('Number of menu items: ${_menuItems.length}');
            print('================================');

            // Auto navigate to menu when items are loaded
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _proceedToMenu();
            });
          }
        } else {
          setState(() {
            _menuError = 'NO menu found for "${merchantData['username']}"';
            _merchantData = merchantData;
            _merchantNameController.text = merchantData['username'];
            _isLoadingMenu = false;
          });
        }
      } else {
        print('Menu fetch failed with status: ${menuResponse.statusCode}');
        print('Menu response body: ${menuResponse.body}');
        setState(() {
          _menuError = 'Failed to load menu. Server error: ${menuResponse.statusCode}';
          _isLoadingMenu = false;
        });
      }
    } on TimeoutException {
      print('Menu fetch timeout');
      setState(() {
        _menuError = 'Request timed out';
        _isLoadingMenu = false;
      });
    } catch (e) {
      print('Error fetching menu: $e');
      setState(() {
        _menuError = 'Error: $e';
        _isLoadingMenu = false;
      });
    }
  }

  Future<void> _fetchMerchantDetailsFromPayCode(String payCode) async {
    try {
      setState(() {
        _isLoadingFromCode = true;
        _menuError = '';
        _menuItems.clear();
        _merchantData = null;
      });

      String cleanPayCode = payCode.trim().toUpperCase();
      cleanPayCode = cleanPayCode
          .replaceAll('O', '0')
          .replaceAll('I', '1')
          .replaceAll('l', '1');

      bool isValidMerchantCode = RegExp(r'^MP[0-9A-Z]+$').hasMatch(cleanPayCode);

      if (!isValidMerchantCode) {
        _showSnackbar('Invalid merchant paycode format', Colors.orange);
        setState(() {
          _merchantNameController.text = 'Invalid merchant paycode';
          _merchantCodeController.text = cleanPayCode;
          _isLoadingFromCode = false;
        });
        return;
      }

      await fetchMerchantMenu(cleanPayCode);

      setState(() {
        _isLoadingFromCode = false;
        _merchantCodeController.text = cleanPayCode;
      });

    } on TimeoutException {
      _showSnackbar('Request timed out', Colors.orange);
      setState(() {
        _isLoadingFromCode = false;
      });
    } catch (e) {
      _showSnackbar('Failed to fetch merchant: $e', Colors.red);
      setState(() {
        _isLoadingFromCode = false;
      });
    }
  }

  void _handleQrDetect(BarcodeCapture barcodes) {
    if (!_isScanning || barcodes.barcodes.isEmpty) return;

    final barcode = barcodes.barcodes.first;
    final scannedCode = barcode.rawValue?.trim();
    if (scannedCode == null || scannedCode.isEmpty) return;

    final now = DateTime.now();
    if (_lastScannedCode == scannedCode &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
      return;
    }

    _lastScannedCode = scannedCode;
    _lastScanTime = now;

    setState(() {
      _showQrDetected = true;
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _showQrDetected = false;
        });
      }
    });

    print('QR Code detected: $scannedCode');
    _fetchMerchantDetailsFromPayCode(scannedCode);

    setState(() {
      _isScanning = false;
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isScanning = true;
        });
      }
    });
  }

  Future<void> _searchByCode() async {
    final code = _merchantCodeController.text.trim();
    if (code.isEmpty) {
      _showSnackbar('Please enter a merchant paycode', Colors.orange);
      return;
    }

    print('Manual search for paycode: $code');
    await _fetchMerchantDetailsFromPayCode(code);
  }

  Future<void> _scanFromGallery() async {
    setState(() {
      _isLoadingGallery = true;
    });

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        setState(() {
          _isLoadingGallery = false;
        });
        return;
      }

      final String? qrData = await QrCodeToolsPlugin.decodeFrom(image.path);
      if (qrData != null) {
        _merchantCodeController.text = qrData;
        await _fetchMerchantDetailsFromPayCode(qrData);
      } else {
        _showSnackbar('No QR code found', Colors.red);
      }
    } catch (e) {
      _showSnackbar('Failed to scan QR: $e', Colors.red);
    } finally {
      setState(() {
        _isLoadingGallery = false;
      });
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

  void _proceedToMenu() {
    if (_merchantData == null || _menuItems.isEmpty) {
      _showSnackbar('Please scan a merchant QR code first', Colors.orange);
      return;
    }

    // Final debug check before navigation
    print('=== NAVIGATING TO MENU PAGE ===');
    print('Merchant ID being passed: ${_merchantData!['merchantid']}');
    print('Merchant Name: ${_merchantData!['username']}');
    print('Menu Items count: ${_menuItems.length}');
    print('===============================');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MenuPage(
          merchantData: _merchantData!,
          menuItems: _menuItems,
          isRestaurant: (_merchantData!['business_type']?.toString().toLowerCase() ?? '').contains('restaurant'),
        ),
      ),
    );
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);

    if (index == 0) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } else if (index == 2) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PayPage()));
    } else if (index == 3) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletPage()));
    } else if (index == 4) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceivePage()));
    }
  }

  void _onTopSegmentTap(int index) {
    setState(() => _activeTopSegment = index);

    if (index == 0) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PayOrdersPage()));
    } else if (index == 2) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SeeOrdersPage()));
    }
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

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF2E9),
      body: SafeArea(
        child: Column(
          children: [
            /// ---------------- TOP BAR (Reduced Height) ----------------
            Container(
              height: 70, // Reduced from 100
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [orange, Colors.orange.shade700],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Order",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
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
                                backgroundColor: Colors.white,
                                child: Icon(Icons.person, color: Colors.orange, size: 20),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            /// -------- TOP SEGMENTS (Without Icons) ---------
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [orange, Colors.orange.shade600],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _buildTopSegment("Pay Orders", 0),
                  _buildTopSegment("Scan", 1),
                  _buildTopSegment("See Orders", 2),
                ],
              ),
            ),

            /// -------- TORCH & GALLERY ---------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      _isTorchOn ? "Torch ON" : "Torch",
                      _isTorchOn ? Icons.flash_on : Icons.flash_off,
                      Colors.deepOrange,
                      _toggleTorch,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildActionButton(
                      "Scan from Gallery",
                      Icons.photo_library,
                      Colors.deepOrange,
                      _isLoadingGallery ? null : _scanFromGallery,
                      isLoading: _isLoadingGallery,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    /// -------- QR SCANNER PREVIEW --------
                    Container(
                      width: 260,
                      height: 260,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.black,
                        border: Border.all(
                          color: _showQrDetected ? Colors.green : orange,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
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
                                  borderRadius: BorderRadius.circular(17),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 50,
                                  ),
                                ),
                              ),

                            // Center instruction
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
                                            'Scan Merchant QR',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.7),
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'to view menu',
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

                    /// -------- SCANNER STATUS --------
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
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
                            _showQrDetected ? 'QR Detected!' :
                            _isScanning ? 'Ready to scan...' : 'Processing...',
                            style: TextStyle(
                              color: _showQrDetected ? Colors.green :
                              _isScanning ? Colors.blue : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    /// -------- INPUT FIELDS --------
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                      child: Column(
                        children: [
                          // Merchant Name (read-only)
                          _buildInputField(
                            label: "Merchant Name",
                            controller: _merchantNameController,
                            readOnly: true,
                            suffix: _merchantNameController.text.isNotEmpty &&
                                _merchantNameController.text != 'Invalid merchant paycode'
                                ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                                : null,
                          ),

                          const SizedBox(height: 15),

                          // Merchant Code with search
                          _buildInputField(
                            label: "Merchant Paycode",
                            controller: _merchantCodeController,
                            suffix: GestureDetector(
                              onTap: _isLoadingFromCode ? null : _searchByCode,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _isLoadingFromCode ? Colors.grey : orange,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: _isLoadingFromCode
                                    ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                    : const Icon(Icons.search, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    /// -------- MENU STATUS --------
                    if (_menuError.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange.shade600, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _menuError,
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_isLoadingMenu)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.blue,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Loading menu...',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),

                    /// -------- VIEW MENU BUTTON (Visible even when loading complete) --------
                    if (_merchantData != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                        child: Column(
                          children: [
                            if (_merchantData!['merchantid'] != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.green.shade200),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Merchant ID: ${_merchantData!['merchantid']}',
                                      style: TextStyle(
                                        color: Colors.green.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            GestureDetector(
                              onTap: _proceedToMenu,
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [orange, Colors.orange.shade600],
                                  ),
                                  borderRadius: BorderRadius.circular(25),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.orange.withOpacity(0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    _menuItems.isNotEmpty ? "View Menu & Order" : "View Merchant Details",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
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
          ],
        ),
      ),

        /// -------- BOTTOM NAVIGATION (Fixed Icons) --------
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
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

  Widget _buildTopSegment(String title, int index) {
    final isSelected = _activeTopSegment == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTopSegmentTap(index),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            boxShadow: isSelected ? [
              BoxShadow(
                color: Colors.orange.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              )
            ] : null,
          ),
          child: Center(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: isSelected ? const Color(0xFFFF8A00) : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    bool readOnly = false,
    Widget? suffix,
    bool isLoading = false,
    VoidCallback? onSuffixTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(
            color: readOnly ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: readOnly ? Colors.grey.shade300 : const Color(0xFFFF8A00),
              width: 2,
            ),
            boxShadow: readOnly ? null : const [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  readOnly: readOnly,
                  decoration: InputDecoration(
                    hintText: label == "Merchant Name"
                        ? "Will appear after scan"
                        : "Enter MP code or scan QR",
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 8),
                suffix,
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
      String label,
      IconData icon,
      Color color,
      VoidCallback? onTap, {
        bool isLoading = false,
      }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isLoading ? Colors.grey : color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}