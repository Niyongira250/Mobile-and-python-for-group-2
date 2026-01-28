import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;

import 'home_page.dart';
import 'order_page.dart';
import 'pay_page.dart';
import 'wallet_page.dart';
import 'services/data_service.dart';

class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  String? _payCode;
  bool _isLoading = true;
  String _errorMessage = '';
  int _selectedIndex = 4;

  @override
  void initState() {
    super.initState();
    _fetchPayCodeFromDatabase();
  }

  Future<void> _fetchPayCodeFromDatabase() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

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
          _isLoading = false;
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
          user['paycode'] = paycode;
          user['merchantpaycode'] = paycode;
          setCurrentUser(user);

          setState(() {
            _payCode = paycode.toString();
            _isLoading = false;
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
    // Simple fallback if database fetch fails
    final user = getCurrentUser();
    final userType = user?['type'] ?? 'user';
    final prefix = userType == 'merchant' ? 'MERCHANT-' : 'USER-';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    final code = '$prefix$timestamp';

    setState(() {
      _payCode = code;
      _isLoading = false;
    });
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    }
    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OrderPage()),
      );
    }
    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PayPage()),
      );
    }
    if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WalletPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFFDF2E9),

          /// -------- BODY --------
          body: Column(
            children: [
              /// -------- TOP FIXED "Payment Accepted" --------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 40,
                  horizontal: 16,
                ),
                color: orange,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: const [
                    Text(
                      "Receive Payments",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "Share your paycode to receive money",
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              /// -------- SCROLLABLE MIDDLE CONTENT --------
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 25,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_isLoading) ...[
                        const SizedBox(height: 100),
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Color(0xFFFF8A00)),
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "Loading your paycode...",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ] else if (_payCode != null && _payCode!.isNotEmpty) ...[
                        /// QR CODE BOX with Logo (same as ProfileOverlay)
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
                              color: orange.withOpacity(0.3),
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
                                    color: orange.withOpacity(0.4),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 35),

                        /// Paycode Display
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                orange.withOpacity(0.1),
                                orange.withOpacity(0.05),
                                orange.withOpacity(0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: orange.withOpacity(0.3),
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
                                  color: orange,
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
                        const SizedBox(height: 25),

                        /// Instructions
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
                                    color: orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'How to Receive Payments',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1a3250),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Share this QR code or paycode with others. They can scan or enter this code to send you money instantly.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 100),
                        const Icon(
                          Icons.error_outline,
                          size: 70,
                          color: Colors.orange,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _errorMessage,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _fetchPayCodeFromDatabase,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: orange,
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
              ),
            ],
          ),

          /// -------- BOTTOM NAVIGATION --------
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onNavTap,
            selectedItemColor: orange,
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
            items: [
              BottomNavigationBarItem(
                icon: Image.asset("assets/images/home.png", height: 26),
                label: "Home",
              ),
              BottomNavigationBarItem(
                icon: Image.asset("assets/images/order.png", height: 26),
                label: "Order",
              ),
              BottomNavigationBarItem(
                icon: Image.asset("assets/images/pay.png", height: 26),
                label: "Pay",
              ),
              BottomNavigationBarItem(
                icon: Image.asset("assets/images/wallet.png", height: 26),
                label: "Wallet",
              ),
              BottomNavigationBarItem(
                icon: Image.asset("assets/images/receive.png", height: 26),
                label: "Receive",
              ),
            ],
          ),
        ),
      ],
    );
  }
}