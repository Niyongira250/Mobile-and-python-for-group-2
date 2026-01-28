import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'order_page.dart';
import 'see_orders.dart';
import 'confirm_orderpay.dart';
import 'profile_overlay.dart';
import 'services/data_service.dart';
import 'credentials.dart';

class PayOrdersPage extends StatefulWidget {
  const PayOrdersPage({super.key});

  @override
  State<PayOrdersPage> createState() => _PayOrdersPageState();
}

class _PayOrdersPageState extends State<PayOrdersPage> {
  bool showProfileMenu = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Order data
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, int> _statusSummary = {};
  bool _usePayableEndpoint = true; // Switch between endpoints if needed

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _statusSummary = {};
      });

      final currentUser = getCurrentUser();
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'User not logged in';
          _orders = [];
        });
        return;
      }

      final userId = currentUser['id'];
      final userType = currentUser['type'];

      // Use payable orders endpoint which shows all statuses
      final endpoint = _usePayableEndpoint
          ? "$baseUrl/get-payable-orders/?customer_id=$userId&customer_type=$userType"
          : "$baseUrl/get-unpaid-orders/?customer_id=$userId&customer_type=$userType";

      print('Loading payable orders for: $userId ($userType)');
      print('Endpoint: $endpoint');

      final response = await http.get(
        Uri.parse(endpoint),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final orders = List<Map<String, dynamic>>.from(data['orders'] ?? []);

          // Get status summary
          if (data['status_summary'] != null) {
            _statusSummary = Map<String, int>.from(data['status_summary']);
          } else if (data['status_breakdown'] != null) {
            _statusSummary = Map<String, int>.from(data['status_breakdown']);
          }

          print('✅ Successfully loaded ${orders.length} orders from API');
          print('📊 Status summary: $_statusSummary');

          // IMPORTANT: Don't filter by status here - let the API do it
          // The API already returns orders that are is_paid = false and status != 'cancelled'

          // Sort by creation date (newest first)
          orders.sort((a, b) {
            try {
              final dateA = DateTime.parse(a['created_at']?.toString() ?? DateTime.now().toString());
              final dateB = DateTime.parse(b['created_at']?.toString() ?? DateTime.now().toString());
              return dateB.compareTo(dateA);
            } catch (e) {
              return 0;
            }
          });

          // Print statuses for debugging
          print('📊 Order status breakdown:');
          for (var order in orders) {
            print('   - Order ${order['order_number']}: ${order['status']} (paid: ${order['is_paid']})');
          }

          setState(() {
            _orders = orders;
            _isLoading = false;
          });

          print('Loaded ${orders.length} payable orders');
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = data['error'] ?? 'Failed to load orders';
            _orders = [];
          });
        }
      } else {
        // Try the other endpoint if one fails
        if (_usePayableEndpoint) {
          print('⚠️ Payable orders endpoint failed, trying unpaid orders endpoint...');
          _usePayableEndpoint = false;
          await _loadOrders(); // Retry with other endpoint
          return;
        }

        setState(() {
          _isLoading = false;
          _errorMessage = 'Server error: ${response.statusCode}';
          _orders = [];
        });
      }
    } catch (e) {
      print('Error loading orders: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load orders: $e';
        _orders = [];
      });
    }
  }

  Future<void> _cancelOrder(String orderId) async {
    try {
      final currentUser = getCurrentUser();
      if (currentUser == null) {
        _showError('User not logged in');
        return;
      }

      final endpoint = "$baseUrl/cancel-order/";

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          'order_id': orderId,
          'customer_id': currentUser['id'],
          'customer_type': currentUser['type'],
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Remove the order from the list
          setState(() {
            _orders.removeWhere((order) => order['orderid'].toString() == orderId);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order cancelled successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          _showError(data['error'] ?? 'Failed to cancel order');
        }
      } else {
        _showError('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error cancelling order: $e');
      _showError('Failed to cancel order: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '0 RWF';
    final numAmount = amount is String ? double.tryParse(amount) ?? 0 : amount.toDouble();
    return '${numAmount.toStringAsFixed(0)} RWF';
  }

  // Get status color for badges
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'preparing':
        return Colors.purple;
      case 'ready':
        return Colors.green;
      case 'delivered':
        return Colors.teal;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Get status display text
  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'PENDING';
      case 'confirmed':
        return 'CONFIRMED';
      case 'preparing':
        return 'PREPARING';
      case 'ready':
        return 'READY';
      case 'delivered':
        return 'DELIVERED';
      default:
        return status.toUpperCase();
    }
  }

  // Check if order can be cancelled
  bool _canCancelOrder(String status) {
    return status.toLowerCase() == 'pending' || status.toLowerCase() == 'delivered';
  }

  List<Map<String, dynamic>> get _filteredOrders {
    if (_searchQuery.isEmpty) return _orders;

    return _orders.where((order) {
      final orderNumber = order['order_number']?.toString().toLowerCase() ?? '';
      final merchantName = order['merchant_name']?.toString().toLowerCase() ?? '';
      final status = order['status']?.toString().toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();

      return orderNumber.contains(query) ||
          merchantName.contains(query) ||
          status.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = getCurrentUser();
    final userName = currentUser?['username'] ?? 'User';

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),

          appBar: AppBar(
            backgroundColor: const Color(0xFFFF8A00),
            elevation: 2,
            title: Row(
              children: [
                IconButton(
                  onPressed: _loadOrders,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: 'Refresh orders',
                ),
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

          body: _buildBody(),
        ),

        if (showProfileMenu)
          ProfileOverlay(
            onClose: () => setState(() => showProfileMenu = false),
          ),
      ],
    );
  }

  Widget _buildBody() {
    const orange = Color(0xFFFF8A00);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SEGMENT BAR
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: orange,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                _segment(context, "pay orders", true),
                _segment(context, "scan", false),
                _segment(context, "see orders", false),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // STATUS SUMMARY CHIPS
          if (_statusSummary.isNotEmpty && !_isLoading && _orders.isNotEmpty)
            _buildStatusChips(),

          const SizedBox(height: 12),

          // SEARCH BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: orange,
                width: 2,
              ),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: "Search orders by number, merchant, or status...",
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                const Icon(Icons.search, color: Color(0xFFFF8A00)),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ORDER COUNT AND REFRESH
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Orders to Pay (${_filteredOrders.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              TextButton.icon(
                onPressed: _loadOrders,
                icon: Icon(Icons.refresh, color: orange, size: 18),
                label: Text(
                  'Refresh',
                  style: TextStyle(color: orange, fontSize: 14),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // LOADING / ERROR / ORDERS DISPLAY
          if (_isLoading)
            _buildLoading()
          else if (_errorMessage.isNotEmpty)
            _buildError()
          else if (_filteredOrders.isEmpty)
              _buildEmptyOrders()
            else
              _buildOrdersList()
        ],
      ),
    );
  }

  Widget _buildStatusChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _statusSummary.entries.map((entry) {
          final status = entry.key;
          final count = entry.value;

          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: Chip(
              backgroundColor: _getStatusColor(status).withOpacity(0.1),
              label: Text(
                '${_getStatusText(status)}: $count',
                style: TextStyle(
                  color: _getStatusColor(status),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              side: BorderSide(color: _getStatusColor(status)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLoading() {
    const orange = Color(0xFFFF8A00);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const CircularProgressIndicator(color: orange),
          const SizedBox(height: 16),
          const Text(
            "Loading orders to pay...",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    const orange = Color(0xFFFF8A00);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade400, size: 60),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            style: TextStyle(
              fontSize: 16,
              color: Colors.red.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadOrders,
            style: ElevatedButton.styleFrom(
              backgroundColor: orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text(
              "Try Again",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyOrders() {
    const orange = Color(0xFFFF8A00);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Column(
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            color: Colors.grey.shade400,
            size: 80,
          ),
          const SizedBox(height: 16),
          const Text(
            "No orders to pay",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "All your orders have been paid or are still being processed",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SeeOrdersPage()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.list, color: Colors.white),
            label: const Text(
              "View All Orders",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    return Column(
      children: [
        ..._filteredOrders.map((order) {
          return _orderCard(context, order: order);
        }).toList(),
      ],
    );
  }

  // SEGMENT BUTTONS
  Widget _segment(BuildContext context, String text, bool selected) {
    return Expanded(
      child: InkWell(
        onTap: () {
          if (text == "scan") {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrderPage()),
            );
          } else if (text == "see orders") {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SeeOrdersPage()),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? null
                : Border.all(color: Colors.white24, width: 1),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                color: selected ? const Color(0xFFFF8A00) : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ORDER CARD UI
  Widget _orderCard(BuildContext context, {required Map<String, dynamic> order}) {
    const orange = Color(0xFFFF8A00);

    final orderNumber = order['order_number']?.toString() ?? 'N/A';
    final merchantName = order['merchant_name']?.toString() ?? 'N/A';
    final totalAmount = order['total_amount'];
    final createdAt = order['created_at']?.toString() ?? '';
    final status = order['status']?.toString() ?? 'pending';

    // Parse items
    List<Map<String, dynamic>> items = [];
    try {
      if (order['items'] is String) {
        items = List<Map<String, dynamic>>.from(jsonDecode(order['items']));
      } else if (order['items'] is List) {
        items = List<Map<String, dynamic>>.from(order['items']);
      }
    } catch (e) {
      print('Error parsing items: $e');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Status header with colored background
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _getStatusColor(status).withOpacity(0.2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Order #$orderNumber",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Merchant: $merchantName",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getStatusText(status),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Order details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Date: ${_formatDate(createdAt)}",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),

                const SizedBox(height: 14),

                // HEADERS
                if (items.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            "Item",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            "Price",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            "Qty",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (items.isNotEmpty) const SizedBox(height: 8),

                // ITEMS
                if (items.isNotEmpty)
                  ...items.map(
                        (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              item['productname']?.toString() ?? 'Unknown',
                              style: const TextStyle(color: Colors.black87, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _formatAmount(item['price']),
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              (item['quantity'] ?? 1).toString(),
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // TOTAL
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Total Amount:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        _formatAmount(totalAmount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: orange,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Status info message
                if (status.toLowerCase() != 'pending')
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _getStatusColor(status).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: _getStatusColor(status),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _getStatusMessage(status),
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),

                // BUTTONS
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ConfirmOrderPayPage(order: order),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: orange,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: orange.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              "Pay Now",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (_canCancelOrder(status)) {
                            _showCancelConfirmation(order['orderid'].toString());
                          } else {
                            _showError('Orders that are ${status.toLowerCase()} cannot be cancelled');
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              "Cancel",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusMessage(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return 'Your order has been confirmed by the merchant. You can still pay for it.';
      case 'preparing':
        return 'Your order is being prepared. You can pay for it now.';
      case 'ready':
        return 'Your order is ready for pickup. Please pay before collecting.';
      case 'delivered':
        return 'Your order has been delivered. Please pay for it now.';
      default:
        return 'Order is ready for payment.';
    }
  }

  void _showCancelConfirmation(String orderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Order"),
        content: const Text("Are you sure you want to cancel this order?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelOrder(orderId);
            },
            child: const Text("Yes", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}