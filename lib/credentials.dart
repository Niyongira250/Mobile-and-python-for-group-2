import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:myapp/wallet_page.dart';
import 'home_page.dart';
import 'order_page.dart';
import 'pay_page.dart';
import 'transaction_result.dart';
import 'receive_page.dart';
import 'profile_overlay.dart';
import 'services/data_service.dart';

class CredentialsPage extends StatefulWidget {
  final String name;
  final String code;
  final String amount;
  final String? receiverType; // Add receiver type parameter

  const CredentialsPage({
    super.key,
    required this.name,
    required this.code,
    required this.amount,
    this.receiverType, // Can be 'user' or 'merchant'
  });

  @override
  State<CredentialsPage> createState() => _CredentialsPageState();
}

class _CredentialsPageState extends State<CredentialsPage> {
  int _selectedIndex = 2;
  final TextEditingController pinCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();
  bool _isProcessing = false;
  String _errorMessage = '';
  String? _receiverType; // Store receiver type

  @override
  void initState() {
    amountCtrl.text = widget.amount;
    _receiverType = widget.receiverType;
    _detectReceiverType(); // Try to detect receiver type if not provided
    super.initState();
  }

  Future<void> _detectReceiverType() async {
    if (_receiverType == null) {
      // Try to detect receiver type by looking up the paycode
      try {
        final receiverInfo = await lookupByPaycode(widget.code.trim());
        if (receiverInfo != null && receiverInfo['type'] != null) {
          setState(() {
            _receiverType = receiverInfo['type'];
          });
          print('✅ Detected receiver type: $_receiverType');
        }
      } catch (e) {
        print('⚠️ Could not detect receiver type: $e');
      }
    }
  }

  Future<void> _processPayment() async {
    // Validate inputs
    if (pinCtrl.text.isEmpty) {
      _showError('Please enter your PIN');
      return;
    }

    if (pinCtrl.text.length != 6) {
      _showError('PIN must be 6 digits');
      return;
    }

    final amount = double.tryParse(amountCtrl.text);
    if (amount == null || amount <= 0) {
      _showError('Please enter a valid amount');
      return;
    }

    if (amount > 1000000) { // Optional: Set a maximum limit
      _showError('Maximum amount is 1,000,000 RWF');
      return;
    }

    // Get current user (sender) details
    final currentUser = getCurrentUser();
    if (currentUser == null) {
      _showError('User not logged in');
      return;
    }

    // Get sender's paycode (user or merchant)
    final senderPaycode = currentUser['paycode'] ?? currentUser['merchantpaycode'];
    if (senderPaycode == null || senderPaycode.isEmpty) {
      _showError('Unable to get your paycode');
      return;
    }

    // Get sender type
    final senderType = currentUser['type'] ?? 'user';

    // Receiver paycode (from scanned QR code)
    final receiverPaycode = widget.code.trim();
    if (receiverPaycode.isEmpty) {
      _showError('Invalid receiver paycode');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = '';
    });

    try {
      print('💰 Processing payment...');
      print('👤 Sender paycode: $senderPaycode (Type: $senderType)');
      print('👥 Receiver paycode: $receiverPaycode (Type: ${_receiverType ?? 'unknown'})');
      print('💵 Amount: $amount');
      print('🔐 PIN entered: ${"*" * pinCtrl.text.length}');

      final response = await http.post(
        Uri.parse('$baseUrl/process-payment/'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'sender_paycode': senderPaycode,
          'receiver_paycode': receiverPaycode,
          'pin': pinCtrl.text,
          'amount': amount,
        }),
      ).timeout(const Duration(seconds: 30));

      print('📡 Response status: ${response.statusCode}');
      print('📄 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          final transactionId = data['transaction_id'];
          final charge = data['charge']?.toDouble() ?? 20.0;
          final total = amount + charge;
          final senderBalance = data['sender_balance']?.toDouble() ?? 0;
          final receiverName = data['receiver_name'] ?? widget.name;
          final receiverType = data['receiver_type'] ?? _receiverType ?? 'user';
          final senderType = data['sender_type'] ?? 'user';

          print('✅ Payment successful!');
          print('   Transaction ID: $transactionId');
          print('   Sender type: $senderType');
          print('   Receiver type: $receiverType');
          print('   New sender balance: $senderBalance');

          // Update local user data with new balance
          updateLocalUserBalance(senderBalance);

          // Navigate to success page with more details
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TransactionResultPage(
                receiverName: receiverName,
                receiverType: receiverType,
                amount: amount,
                charge: charge,
                total: total,
                balance: senderBalance,
                transactionId: transactionId,
                senderType: senderType,
                date: DateTime.now(),
              ),
            ),
          );
        } else {
          final errorMsg = data['error'] ?? 'Payment failed';
          print('❌ Payment failed: $errorMsg');
          _showError(errorMsg);
        }
      } else if (response.statusCode == 400 || response.statusCode == 404) {
        // Handle specific error cases
        try {
          final errorData = json.decode(response.body);
          final errorMsg = errorData['error'] ?? 'Payment failed';
          print('❌ Payment failed: $errorMsg');
          _showError(errorMsg);
        } catch (e) {
          _showError('Payment failed with status ${response.statusCode}');
        }
      } else {
        print('❌ Server error: ${response.statusCode}');
        _showError('Server error: ${response.statusCode}');
        if (response.body.isNotEmpty) {
          try {
            final errorData = json.decode(response.body);
            if (errorData['error'] != null) {
              _showError(errorData['error']);
            }
          } catch (e) {
            // If can't parse error, use generic message
          }
        }
      }
    } on TimeoutException catch (e) {
      print('⏰ Request timeout: $e');
      _showError('Request timed out. Please try again.');
    } on http.ClientException catch (e) {
      print('🌐 Network error: $e');
      _showError('Network error. Please check your connection.');
    } on FormatException catch (e) {
      print('🔣 Format error: $e');
      _showError('Invalid server response');
    } catch (e) {
      print('🔥 Unexpected error: $e');
      _showError('An unexpected error occurred: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);

    switch (index) {
      case 0:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const HomePage()));
        break;
      case 1:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderPage()));
        break;
      case 2:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PayPage()));
        break;
      case 3:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletPage()));
        break;
      case 4:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceivePage()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF2E9),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              // ------------ TOP ORANGE BOX WITH GRADIENT ------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 30,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xFFFFB74D), // lighter orange at bottom
                      Color(0xFFFF8A00), // more intense orange at top
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(35),
                    bottomRight: Radius.circular(35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _headLabel("Name"),
                    _headField(widget.name),

                    const SizedBox(height: 10),

                    _headLabel("Code"),
                    _headField(widget.code),

                    // Show receiver type if known
                    if (_receiverType != null)
                      Column(
                        children: [
                          const SizedBox(height: 8),
                          _headLabel("Account Type"),
                          _headField(_receiverType == 'merchant' ? 'Merchant Account' : 'User Account'),
                        ],
                      ),

                    const SizedBox(height: 25),

                    Center(
                      child: GestureDetector(
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
                                radius: 42,
                                backgroundImage: provider,
                              );
                            }
                            return const CircleAvatar(
                              radius: 42,
                              backgroundImage: AssetImage(
                                "assets/images/profile.jpeg",
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    GestureDetector(
                      onTap: _isProcessing ? null : () => Navigator.pop(context),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_back, color: _isProcessing ? Colors.grey : Colors.black),
                          const SizedBox(width: 6),
                          Text(
                            "Back",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _isProcessing ? Colors.grey : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ---------- AMOUNT ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: _styledInputField(
                  controller: amountCtrl,
                  hint: "Amount to pay in RWF",
                  icon: Icons.attach_money,
                  keyboardType: TextInputType.number,
                  enabled: !_isProcessing,
                ),
              ),

              const SizedBox(height: 30),

              // -------- PIN BOX ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  children: [
                    const Text(
                      "Please enter your PIN",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    // Error message
                    if (_errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    const SizedBox(height: 15),
                    _styledInputField(
                      controller: pinCtrl,
                      hint: "------",
                      obscure: true,
                      centerText: true,
                      letterSpacing: 10,
                      fontSize: 24,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      enabled: !_isProcessing,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Note: A charge of 20 RWF will be applied",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),

                    // Additional info about receiver
                    if (_receiverType != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _receiverType == 'merchant'
                              ? "You are sending money to a merchant account"
                              : "You are sending money to a user account",
                          style: TextStyle(
                            color: _receiverType == 'merchant' ? Colors.orange : Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),

                    const SizedBox(height: 25),

                    // -------- Buttons --------
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _isProcessing ? null : _processPayment,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _isProcessing ? Colors.grey : orange,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: _isProcessing ? null : [
                                  BoxShadow(
                                    color: orange.withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _isProcessing
                                    ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                    : Text(
                                  _receiverType == 'merchant' ? "Pay Merchant" : "Pay",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: _isProcessing ? null : () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _isProcessing ? Colors.grey : Colors.red,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: _isProcessing ? null : [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text(
                                  "Cancel",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),
                    Text(
                      "Default PIN: 123456",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),

      // -------- NAVIGATION BAR --------
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: orange,
        unselectedItemColor: Colors.grey,
        onTap: _onNavTap,
        items: const [
          BottomNavigationBarItem(
            icon: ImageIcon(AssetImage("assets/images/home.png")),
            label: "home",
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(AssetImage("assets/images/order.png")),
            label: "order",
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(AssetImage("assets/images/pay.png")),
            label: "pay",
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(AssetImage("assets/images/wallet.png")),
            label: "wallet",
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(AssetImage("assets/images/receive.png")),
            label: "receive",
          ),
        ],
      ),
    );
  }

  // ----------------------- STYLED INPUT FIELD -----------------------
  Widget _styledInputField({
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
    IconData? icon,
    bool centerText = false,
    double letterSpacing = 0,
    double fontSize = 16,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: enabled ? Colors.white : Colors.grey[100],
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: enabled ? Colors.deepOrangeAccent : Colors.grey,
          width: 1.5,
        ),
        boxShadow: enabled ? const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
        ] : null,
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        textAlign: centerText ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: fontSize,
          letterSpacing: letterSpacing,
          color: enabled ? Colors.black : Colors.grey,
        ),
        keyboardType: keyboardType,
        maxLength: maxLength,
        enabled: enabled,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: enabled ? Colors.grey : Colors.grey[400]),
          border: InputBorder.none,
          prefixIcon: icon != null
              ? Icon(icon, color: enabled ? Colors.deepOrange : Colors.grey)
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          counterText: '', // Hide character counter
        ),
      ),
    );
  }

  Widget _headLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _headField(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Text(
        value,
        style: const TextStyle(fontSize: 16),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}