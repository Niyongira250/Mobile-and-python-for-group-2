import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:myapp/home_page.dart';
import 'profile_overlay.dart';
import 'services/data_service.dart';
import 'credentials.dart';
import 'transaction_result.dart';

class ConfirmOrderPayPage extends StatefulWidget {
  final Map<String, dynamic> order;

  const ConfirmOrderPayPage({super.key, required this.order});

  @override
  State<ConfirmOrderPayPage> createState() => _ConfirmOrderPayPageState();
}

class _ConfirmOrderPayPageState extends State<ConfirmOrderPayPage> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _tipController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  bool _isProcessing = false;
  String _errorMessage = '';
  Map<String, dynamic>? _merchantPaymentDetails;
  bool _isLoadingMerchant = false;

  @override
  void initState() {
    super.initState();
    _loadMerchantPaymentDetails();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _tipController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMerchantPaymentDetails() async {
    try {
      setState(() {
        _isLoadingMerchant = true;
      });

      final merchantId = widget.order['merchant_id'];
      if (merchantId == null) {
        setState(() {
          _isLoadingMerchant = false;
          _errorMessage = 'Merchant ID not found in order';
        });
        return;
      }

      // Try to get merchant payment details
      final endpoint = "$baseUrl/merchant-payment-details/?merchant_id=$merchantId";

      print('🔍 Loading merchant payment details from: $endpoint');

      final response = await http.get(
        Uri.parse(endpoint),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _merchantPaymentDetails = data;
            _isLoadingMerchant = false;
          });
          print('✅ Merchant payment details loaded: ${data['merchant_paycode']}');
        } else {
          // Try fallback to merchant-details
          await _loadMerchantDetailsFallback(merchantId);
        }
      } else {
        // Try fallback to merchant-details
        await _loadMerchantDetailsFallback(merchantId);
      }
    } catch (e) {
      print('❌ Error loading merchant details: $e');
      setState(() {
        _isLoadingMerchant = false;
        // Continue with payment - we'll use fallback paycode
      });
    }
  }

  Future<void> _loadMerchantDetailsFallback(int merchantId) async {
    try {
      // Try to get merchant by email from order or by ID
      final merchantEmail = widget.order['merchant_email'];
      String? endpoint;

      if (merchantEmail != null && merchantEmail.isNotEmpty) {
        endpoint = "$baseUrl/merchant-details/?email=$merchantEmail";
      } else {
        // Use the updated merchant-details endpoint that accepts merchant_id
        endpoint = "$baseUrl/merchant-details/?merchant_id=$merchantId";
      }

      print('🔍 Trying fallback endpoint: $endpoint');

      final response = await http.get(
        Uri.parse(endpoint),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _merchantPaymentDetails = {
            'merchant_paycode': data['merchantpaycode'] ?? '',
            'merchant_name': data['username'] ?? 'Merchant',
            'merchant_email': data['email'] ?? '',
          };
          _isLoadingMerchant = false;
        });
        print('✅ Fallback merchant details loaded');
      } else {
        setState(() {
          _isLoadingMerchant = false;
          // Use whatever we have from the order
        });
      }
    } catch (e) {
      print('❌ Error in fallback: $e');
      setState(() {
        _isLoadingMerchant = false;
      });
    }
  }

  Future<void> _processPayment() async {
    // Validate PIN
    if (_pinController.text.isEmpty) {
      _showError('Please enter your PIN');
      return;
    }

    if (_pinController.text.length != 6) {
      _showError('PIN must be 6 digits');
      return;
    }

    // Get tip amount - handle empty string
    double tipAmount = 0;
    if (_tipController.text.isNotEmpty && _tipController.text.trim().isNotEmpty) {
      tipAmount = double.tryParse(_tipController.text.trim()) ?? 0;
      if (tipAmount < 0) {
        _showError('Tip amount cannot be negative');
        return;
      }
    }

    // Get current user
    final currentUser = getCurrentUser();
    if (currentUser == null) {
      _showError('User not logged in');
      return;
    }

    // Get order details with proper type conversion
    final orderId = widget.order['orderid']?.toString() ?? '';
    final totalAmount = _parseAmount(widget.order['total_amount']);
    final merchantId = widget.order['merchant_id']?.toString() ?? '';
    final merchantName = widget.order['merchant_name']?.toString() ?? 'Merchant';

    // Get merchant paycode - try multiple sources
    String merchantPaycode = '';
    if (_merchantPaymentDetails != null && _merchantPaymentDetails!['merchant_paycode'] != null) {
      merchantPaycode = _merchantPaymentDetails!['merchant_paycode'].toString();
    } else if (widget.order['merchant_paycode'] != null) {
      merchantPaycode = widget.order['merchant_paycode'].toString();
    } else if (widget.order['merchantpaycode'] != null) {
      merchantPaycode = widget.order['merchantpaycode'].toString();
    }

    if (merchantPaycode.isEmpty) {
      _showError('Unable to get merchant payment details. Please try again.');
      return;
    }

    // Get sender paycode with proper type conversion
    final String senderPaycode;
    final userType = currentUser['type'] ?? 'user';
    if (userType == 'user') {
      senderPaycode = currentUser['paycode']?.toString() ?? '';
    } else {
      senderPaycode = currentUser['merchantpaycode']?.toString() ?? '';
    }

    if (senderPaycode.isEmpty) {
      _showError('Unable to get your paycode');
      return;
    }

    // Calculate total payment (order amount + tip)
    final paymentAmount = totalAmount + tipAmount;

    if (paymentAmount <= 0) {
      _showError('Payment amount must be greater than 0');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = '';
    });

    try {
      print('💰 Processing order payment...');
      print('📦 Order ID: $orderId');
      print('👤 User Type: $userType');
      print('👤 Sender paycode: $senderPaycode');
      print('🏪 Receiver paycode: $merchantPaycode');
      print('💵 Amount: $paymentAmount (Order: $totalAmount + Tip: $tipAmount)');
      print('💬 Message: ${_messageController.text}');

      // Step 1: Process the payment
      final paymentResponse = await http.post(
        Uri.parse('$baseUrl/process-payment/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'sender_paycode': senderPaycode,
          'receiver_paycode': merchantPaycode,
          'pin': _pinController.text,
          'amount': paymentAmount.toString(), // Ensure string for JSON
        }),
      ).timeout(const Duration(seconds: 30));

      print('📡 Payment response status: ${paymentResponse.statusCode}');
      print('📄 Payment response body: ${paymentResponse.body}');

      if (paymentResponse.statusCode == 200) {
        final paymentData = json.decode(paymentResponse.body);

        if (paymentData['success'] == true) {
          final transactionId = paymentData['transaction_id'];
          final charge = _parseAmount(paymentData['charge'] ?? 20.0);
          final total = paymentAmount + charge;
          final senderBalance = _parseAmount(paymentData['sender_balance'] ?? 0);
          final receiverName = merchantName;
          final receiverType = 'merchant';

          print('✅ Payment successful! Transaction ID: $transactionId');

          // Step 2: Mark order as paid
          final markPaidResponse = await http.post(
            Uri.parse('$baseUrl/mark-order-paid/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'order_id': orderId,
              'transaction_id': transactionId?.toString() ?? '',
              'tip_amount': tipAmount.toString(),
              'message': _messageController.text.trim(),
            }),
          );

          print('📡 Mark paid response: ${markPaidResponse.statusCode}');
          print('📄 Mark paid body: ${markPaidResponse.body}');

          if (markPaidResponse.statusCode == 200) {
            final markPaidData = json.decode(markPaidResponse.body);

            if (markPaidData['success'] == true) {
              print('✅ Order marked as paid');

              // Update local user balance
              updateLocalUserBalance(senderBalance);

              // Navigate to success page
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionResultPage(
                    receiverName: receiverName,
                    receiverType: receiverType,
                    amount: paymentAmount,
                    charge: charge,
                    total: total,
                    balance: senderBalance,
                    transactionId: transactionId ?? 0,
                    senderType: userType,
                    date: DateTime.now(),
                  ),
                ),
              );
            } else {
              _showError(markPaidData['error']?.toString() ?? 'Failed to mark order as paid');
            }
          } else {
            _showError('Failed to update order status: ${markPaidResponse.statusCode}');
          }
        } else {
          final errorMsg = paymentData['error']?.toString() ?? 'Payment failed';
          _showError(errorMsg);
        }
      } else {
        _showError('Payment failed with status ${paymentResponse.statusCode}');
      }
    } on http.ClientException catch (e) {
      _showError('Network error. Please check your connection.');
    } catch (e) {
      print('❌ Payment error: $e');
      _showError('An unexpected error occurred: ${e.toString()}');
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

  double _parseAmount(dynamic amount) {
    if (amount == null) return 0.0;

    if (amount is double) return amount;
    if (amount is int) return amount.toDouble();
    if (amount is String) {
      final cleaned = amount.replaceAll(RegExp(r'[^0-9\.]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }

    try {
      return double.parse(amount.toString());
    } catch (e) {
      return 0.0;
    }
  }

  String _formatAmount(dynamic amount) {
    final numAmount = _parseAmount(amount);
    return '${numAmount.toStringAsFixed(0)} RWF';
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }

  List<Map<String, dynamic>> _parseItems() {
    List<Map<String, dynamic>> items = [];
    try {
      if (widget.order['items'] is String) {
        items = List<Map<String, dynamic>>.from(jsonDecode(widget.order['items']));
      } else if (widget.order['items'] is List) {
        items = List<Map<String, dynamic>>.from(widget.order['items']);
      }
    } catch (e) {
      print('Error parsing items: $e');
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);

    final currentUser = getCurrentUser();
    final userName = currentUser?['username'] ?? 'User';

    final orderNumber = widget.order['order_number']?.toString() ?? 'N/A';
    final merchantName = widget.order['merchant_name']?.toString() ?? 'N/A';
    final totalAmount = widget.order['total_amount'];
    final createdAt = widget.order['created_at']?.toString() ?? '';
    final status = widget.order['status']?.toString() ?? 'delivered';

    final items = _parseItems();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            Container(
              height: 110,
              padding: const EdgeInsets.only(top: 35, left: 12, right: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFF8A00),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFFFF8A00),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Spacer(),
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
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
                ],
              ),
            ),

            const SizedBox(height: 16),

            // BACK
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text(
                  "< Back",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF8A00),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // GREEN BANNER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF8A00), Color(0xFF27AE60)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (_isLoadingMerchant)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(Icons.shopping_bag, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Paying Order #$orderNumber",
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ORDER STATUS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 18,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8A00),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      "Order status",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 18,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF27AE60),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ORDER TABLE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF8A00), Color(0xFF27AE60)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Merchant info
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.store, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              merchantName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Text(
                      "Date: ${_formatDate(createdAt)}",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: const [
                          Expanded(
                            flex: 2,
                            child: Text(
                              "Item",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Price",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              "Qty",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    ...items.map(
                          (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                item['productname']?.toString() ?? 'Unknown',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _formatAmount(item['price']),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                (item['quantity'] ?? 1).toString(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Total:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            _formatAmount(totalAmount),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // TIP
            _inputField(_tipController, "Add tip (optional)", TextInputType.number),

            // MESSAGE
            _inputField(_messageController, "Message to merchant (optional)", TextInputType.text),

            const SizedBox(height: 20),

            // PIN BOX
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Enter your 6-digit PIN",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),

                  if (_errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: orange,
                        width: 2,
                      ),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      enabled: !_isProcessing,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "******",
                        hintStyle: TextStyle(color: Colors.grey),
                        counterText: "",
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Note: A transaction fee of 20 RWF will be applied",
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // PAY / CANCEL BUTTONS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: (_isProcessing || _isLoadingMerchant) ? null : _processPayment,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: (_isProcessing || _isLoadingMerchant) ? Colors.grey : orange,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: (_isProcessing || _isLoadingMerchant) ? null : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: (_isProcessing || _isLoadingMerchant)
                              ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Text(
                            "Pay Now",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: InkWell(
                      onTap: (_isProcessing || _isLoadingMerchant) ? null : () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: (_isProcessing || _isLoadingMerchant) ? Colors.grey : Colors.red.shade500,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: (_isProcessing || _isLoadingMerchant) ? null : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            "Cancel",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController controller, String label, TextInputType keyboardType) {
    const orange = Color(0xFFFF8A00);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),

          const SizedBox(height: 5),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: orange, width: 2),
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              enabled: !_isProcessing,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: label.contains("tip") ? "Enter amount" : "Enter message...",
              ),
            ),
          ),
        ],
      ),
    );
  }
}