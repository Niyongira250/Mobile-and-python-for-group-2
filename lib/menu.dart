import 'package:flutter/material.dart';
import 'dart:convert';
import 'credentials.dart';
import 'package:http/http.dart' as http;
import 'home_page.dart';
import 'pay_page.dart';
import 'wallet_page.dart';
import 'receive_page.dart';
import 'order_page.dart';
import 'profile_overlay.dart';
import 'services/data_service.dart';
import 'merchanthome_page.dart';

class MenuPage extends StatefulWidget {
  final Map<String, dynamic> merchantData;
  final List<Map<String, dynamic>> menuItems;
  final bool isRestaurant;

  const MenuPage({
    super.key,
    required this.merchantData,
    required this.menuItems,
    this.isRestaurant = true,
  });

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  int orderNumber = DateTime.now().millisecondsSinceEpoch % 1000000;
  final Map<int, Map<String, dynamic>> _cartItems = {};
  String tableName = "";
  final Map<String, TextEditingController> _customFieldControllers = {};
  bool _isPlacingOrder = false;

  @override
  void initState() {
    super.initState();

    for (var menuItem in widget.menuItems) {
      final productId = menuItem['productid'];
      if (productId != null) {
        _cartItems[productId] = {
          'productid': productId,
          'productname': menuItem['productname'] ?? 'Unknown',
          'price': menuItem['price'] ?? 0.0,
          'qty': 0,
          'img': menuItem['productpicture'] ?? '',
          'availability': menuItem['availability'] ?? true,
        };
      }
    }

    if (widget.isRestaurant) {
      _fetchCustomFields();
    }
  }

  @override
  void dispose() {
    for (var controller in _customFieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int get total {
    int totalPrice = 0;
    _cartItems.forEach((key, item) {
      final price = (item["price"] as num?)?.toDouble() ?? 0.0;
      final qty = item["qty"] as int;
      totalPrice += (price * qty).toInt();
    });
    return totalPrice;
  }

  Future<void> _fetchCustomFields() async {
    try {
      final merchantId = widget.merchantData['merchantid'];
      if (merchantId == null) return;

      final response = await http.get(
        Uri.parse("$baseUrl/merchant-custom-fields/?merchant_id=$merchantId"),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final fields = List<String>.from(data['custom_fields'] ?? []);

          setState(() {
            for (var controller in _customFieldControllers.values) {
              controller.dispose();
            }
            _customFieldControllers.clear();

            for (var field in fields) {
              _customFieldControllers[field] = TextEditingController();
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching custom fields: $e');
    }
  }

  Future<void> _placeOrder() async {
    if (_isPlacingOrder) return;

    final orderItems = _cartItems.entries
        .where((entry) => entry.value['qty'] as int > 0)
        .map((entry) {
      final item = entry.value;
      return {
        'productid': item['productid'],
        'productname': item['productname'],
        'price': item['price'],
        'quantity': item['qty'],
      };
    })
        .toList();

    if (orderItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add items to your order'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final Map<String, dynamic> customFieldsData = {};
    for (var entry in _customFieldControllers.entries) {
      if (entry.value.text.isNotEmpty) {
        customFieldsData[entry.key] = entry.value.text;
      }
    }

    if (widget.isRestaurant && tableName.isEmpty) {
      if (_customFieldControllers.containsKey('Table Name') &&
          _customFieldControllers['Table Name']!.text.isNotEmpty) {
        tableName = _customFieldControllers['Table Name']!.text;
      }
    }

    setState(() {
      _isPlacingOrder = true;
    });

    try {
      // Submit order to database
      final result = await _submitOrderToDatabase(
        orderItems: orderItems,
        customFields: customFieldsData,
      );

      if (result['success']) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderConfirmationPage(
              merchantData: widget.merchantData,
              orderItems: orderItems,
              tableName: tableName,
              customFields: customFieldsData,
              total: total,
              orderNumber: orderNumber,
              actualOrderId: result['order_id'],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to place order: ${result['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error placing order: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isPlacingOrder = false;
      });
    }
  }

  Future<Map<String, dynamic>> _submitOrderToDatabase({
    required List<Map<String, dynamic>> orderItems,
    required Map<String, dynamic> customFields,
  }) async {
    try {
      final currentUser = getCurrentUser();
      if (currentUser == null) {
        return {'success': false, 'error': 'User not logged in'};
      }

      // Prepare order data
      final orderData = {
        'order_number': orderNumber,
        'customer_id': currentUser['id'],
        'customer_type': currentUser['type'],
        'customer_name': currentUser['username'],
        'merchant_id': widget.merchantData['merchantid'],
        'merchant_name': widget.merchantData['username'],
        'table_name': tableName,
        'items': orderItems,
        'custom_fields': customFields,
        'total_amount': total,
        'status': 'pending',
      };

      print('Submitting order: ${jsonEncode(orderData)}');

      final response = await http.post(
        Uri.parse("$baseUrl/create-order/"),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode(orderData),
      ).timeout(const Duration(seconds: 10));

      print('Order submission response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {'success': true, 'order_id': data['order_id']};
      } else {
        final error = jsonDecode(response.body);
        return {'success': false, 'error': error['error'] ?? 'Unknown error'};
      }
    } catch (e) {
      print('Error submitting order: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Order #$orderNumber",
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            Text(
              widget.merchantData['username']?.toString() ?? 'Merchant',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
        leading: InkWell(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_ios, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Merchant Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 6,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      color: Colors.grey.shade200,
                    ),
                    child: widget.merchantData['profile_picture'] != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: Image.network(
                        widget.merchantData['profile_picture'].toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.store,
                            color: Colors.grey.shade400,
                          );
                        },
                      ),
                    )
                        : Icon(
                      Icons.store,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.merchantData['username']?.toString() ?? 'Merchant',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (widget.merchantData['business_type'] != null &&
                            widget.merchantData['business_type'].toString().isNotEmpty)
                          Text(
                            widget.merchantData['business_type'].toString(),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        Text(
                          '${widget.menuItems.length} items available',
                          style: TextStyle(
                            color: Colors.green.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.merchantData['paycode'] != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.merchantData['paycode'].toString(),
                        style: TextStyle(
                          color: orange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Custom Fields
            if (widget.isRestaurant || _customFieldControllers.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Order Details",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 10),

                  if (widget.isRestaurant)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Table Name / Number",
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: "Enter table name...",
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onChanged: (v) => setState(() => tableName = v),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  ..._customFieldControllers.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: TextField(
                              controller: entry.value,
                              decoration: InputDecoration(
                                hintText: "Enter ${entry.key.toLowerCase()}...",
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),

                  const SizedBox(height: 20),
                ],
              ),

            // Menu Items
            const Text(
              "Menu Items",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (widget.menuItems.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.restaurant_menu,
                      size: 60,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "No menu items available",
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Please check back later",
                      style: TextStyle(
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              )
            else
              GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.menuItems.length,
                itemBuilder: (context, index) {
                  final menuItem = widget.menuItems[index];
                  final productId = menuItem['productid'];
                  final cartItem = _cartItems[productId];
                  final isAvailable = menuItem['availability'] == true ||
                      menuItem['availability'] == 'true' ||
                      (menuItem['availability'] == null &&
                          (menuItem['amountinstock'] ?? 0) > 0);

                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.15),
                          blurRadius: 6,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 120,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(14),
                              topRight: Radius.circular(14),
                            ),
                            child: _buildProductImage(
                              menuItem['productpicture']?.toString() ?? '',
                              menuItem['productname']?.toString() ?? '',
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                menuItem['productname']?.toString() ?? 'Unknown',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${(menuItem['price'] ?? 0).toStringAsFixed(0)} RWF",
                                style: const TextStyle(
                                  color: Color(0xFFFF8A00),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),

                              if (!isAvailable)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Out of Stock',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),

                              if (isAvailable)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _qtyBtn("-", () {
                                      setState(() {
                                        if (cartItem != null && cartItem['qty'] > 0) {
                                          cartItem['qty']--;
                                        }
                                      });
                                    }),
                                    Text(
                                      cartItem != null ? "${cartItem['qty']}" : "0",
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    _qtyBtn("+", () {
                                      setState(() {
                                        if (cartItem != null) {
                                          cartItem['qty']++;
                                        }
                                      });
                                    }),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: 25),

            // Order Summary
            if (_cartItems.values.any((item) => item['qty'] as int > 0))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: Column(
                  children: [
                    const Text(
                      "Order Summary",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1),
                        2: FlexColumnWidth(1),
                      },
                      children: [
                        const TableRow(children: [
                          Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              "Item",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              "Price",
                              style: TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              "Qty",
                              style: TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ]),
                        ..._cartItems.entries
                            .where((e) => e.value['qty'] as int > 0)
                            .map((e) => TableRow(children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              e.value['productname'].toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              "${(e.value['price'] as num?)?.toInt() ?? 0}",
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              "${e.value['qty']}",
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ])),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Total:",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "$total RWF",
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF8A00),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Place Order Button
            GestureDetector(
              onTap: _isPlacingOrder ? null : _placeOrder,
              child: Container(
                height: 55,
                decoration: BoxDecoration(
                  color: _cartItems.values.any((item) => item['qty'] as int > 0) && !_isPlacingOrder
                      ? orange
                      : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: _isPlacingOrder
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Text(
                    _cartItems.values.any((item) => item['qty'] as int > 0)
                        ? "Place Order ($total RWF)"
                        : "Add Items to Order",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage(String imageUrl, String productName) {
    if (imageUrl != null && imageUrl.isNotEmpty && imageUrl != 'null') {
      try {
        String fullImageUrl;
        if (imageUrl.startsWith('http')) {
          fullImageUrl = imageUrl;
        } else if (imageUrl.startsWith('/media/')) {
          fullImageUrl = 'http://localhost:8000$imageUrl';
        } else if (imageUrl.startsWith('media/')) {
          fullImageUrl = 'http://localhost:8000/$imageUrl';
        } else if (imageUrl.contains('/media/')) {
          fullImageUrl = 'http://localhost:8000$imageUrl';
        } else {
          fullImageUrl = 'http://localhost:8000/media/$imageUrl';
        }

        return Image.network(
          fullImageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey.shade200,
              child: Center(
                child: Icon(
                  Icons.fastfood,
                  color: Colors.grey.shade400,
                  size: 40,
                ),
              ),
            );
          },
        );
      } catch (e) {
        return Container(
          color: Colors.grey.shade200,
          child: Center(
            child: Icon(
              Icons.fastfood,
              color: Colors.grey.shade400,
              size: 40,
            ),
          ),
        );
      }
    } else {
      return Container(
        color: Colors.grey.shade200,
        child: Center(
          child: Icon(
            Icons.fastfood,
            color: Colors.grey.shade400,
            size: 40,
          ),
        ),
      );
    }
  }

  Widget _qtyBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 28,
        width: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.orange,
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class OrderConfirmationPage extends StatelessWidget {
  final Map<String, dynamic> merchantData;
  final List<Map<String, dynamic>> orderItems;
  final String tableName;
  final Map<String, dynamic> customFields;
  final int total;
  final int orderNumber;
  final int? actualOrderId;

  const OrderConfirmationPage({
    super.key,
    required this.merchantData,
    required this.orderItems,
    required this.tableName,
    required this.customFields,
    required this.total,
    required this.orderNumber,
    this.actualOrderId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Order Confirmation #$orderNumber"),
        backgroundColor: const Color(0xFFFF8A00),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Success Message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Order Placed Successfully!",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (actualOrderId != null)
                          Text(
                            "Order ID: $actualOrderId",
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 14,
                            ),
                          ),
                        Text(
                          "Thank you for your order",
                          style: TextStyle(
                            color: Colors.green.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Merchant Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 6,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      color: Colors.grey.shade200,
                    ),
                    child: merchantData['profile_picture'] != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: Image.network(
                        merchantData['profile_picture'].toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.store,
                            color: Colors.grey.shade400,
                          );
                        },
                      ),
                    )
                        : const Icon(Icons.store),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          merchantData['username']?.toString() ?? 'Merchant',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (merchantData['business_type'] != null &&
                            merchantData['business_type'].toString().isNotEmpty)
                          Text(
                            merchantData['business_type'].toString(),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Order Details
            if (tableName.isNotEmpty || customFields.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 6,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Order Details",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (tableName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Table Name:"),
                            Text(
                              tableName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),

                    ...customFields.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("${entry.key}:"),
                            Text(
                              entry.value.toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Order Items
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 6,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Order Items",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  ...orderItems.map((item) {
                    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                    final quantity = item['quantity'] as int;
                    final subtotal = price * quantity;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              "${item['quantity']}x ${item['productname']}",
                            ),
                          ),
                          Text(
                            "${subtotal.toInt()} RWF",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }).toList(),

                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Total:",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "$total RWF",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF8A00),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text("Back to Home"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OrderPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A00),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text("New Order"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}