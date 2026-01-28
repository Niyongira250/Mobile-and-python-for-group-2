import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// Import navigation pages
import 'home_page.dart';
import 'pay_page.dart';
import 'wallet_page.dart';
import 'receive_page.dart';
import 'order_page.dart';
import 'pay_orders.dart';
import 'profile_overlay.dart';
import 'services/data_service.dart';
import 'credentials.dart';

class SeeOrdersPage extends StatefulWidget {
  const SeeOrdersPage({super.key});

  @override
  State<SeeOrdersPage> createState() => _SeeOrdersPageState();
}

class _SeeOrdersPageState extends State<SeeOrdersPage> {
  int _selectedIndex = 1;
  String selectedLanguage = "Eng";

  // Order data
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  String _errorMessage = '';

  // Filters
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, pending, confirmed, preparing, ready, delivered, cancelled

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

      print('Loading orders for: $userId ($userType)');

      // Determine which endpoint to call based on user type
      String endpoint;
      if (userType == 'merchant') {
        endpoint = "$baseUrl/get-merchant-orders/?merchant_id=$userId";
      } else {
        endpoint = "$baseUrl/get-customer-orders/?customer_id=$userId&customer_type=$userType";
      }

      print('Calling endpoint: $endpoint');

      final response = await http.get(
        Uri.parse(endpoint),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      print('Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final orders = List<Map<String, dynamic>>.from(data['orders'] ?? []);

          // Sort by creation date (newest first)
          orders.sort((a, b) {
            final dateA = DateTime.parse(a['created_at'] ?? '');
            final dateB = DateTime.parse(b['created_at'] ?? '');
            return dateB.compareTo(dateA);
          });

          setState(() {
            _orders = orders;
            _isLoading = false;
          });

          print('Loaded ${orders.length} orders');
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = data['error'] ?? 'Failed to load orders';
            _orders = [];
          });
        }
      } else {
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

  List<Map<String, dynamic>> get _filteredOrders {
    var filtered = _orders;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((order) {
        final orderId = order['order_number']?.toString().toLowerCase() ?? '';
        final merchantName = order['merchant_name']?.toString().toLowerCase() ?? '';
        final customerName = order['customer_name']?.toString().toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();

        return orderId.contains(query) ||
            merchantName.contains(query) ||
            customerName.contains(query);
      }).toList();
    }

    // Apply status filter
    if (_statusFilter != 'all') {
      filtered = filtered.where((order) {
        final status = order['status']?.toString().toLowerCase() ?? '';
        return status == _statusFilter;
      }).toList();
    }

    return filtered;
  }

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

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd MMM yyyy, HH:mm').format(date);
    } catch (e) {
      return dateString;
    }
  }

  // FIXED: Safe conversion to double
  double _parseAmount(dynamic amount) {
    if (amount == null) return 0.0;

    if (amount is double) return amount;
    if (amount is int) return amount.toDouble();
    if (amount is String) {
      // Remove any non-numeric characters except decimal point
      final cleaned = amount.replaceAll(RegExp(r'[^0-9\.]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }

    try {
      return double.parse(amount.toString());
    } catch (e) {
      print('Error parsing amount $amount: $e');
      return 0.0;
    }
  }

  String _formatAmount(dynamic amount) {
    final numAmount = _parseAmount(amount);
    return '${numAmount.toStringAsFixed(0)} RWF';
  }

  void _refreshOrders() {
    _loadOrders();
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => OrderDetailsBottomSheet(order: order),
    );
  }

  // ------------------- NAV BAR ----------------------
  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);

    if (index == 0) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PayPage()),
      );
    } else if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WalletPage()),
      );
    } else if (index == 4) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReceivePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);

    final currentUser = getCurrentUser();
    final userName = currentUser?['username'] ?? 'User';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: orange,
        elevation: 2,
        title: Row(
          children: [
            const Spacer(),
            Text(
              userName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
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

      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10),

            /// SEGMENT BAR
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
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
                    _topSegment(context, "pay orders", false),
                    _topSegment(context, "scan", false),
                    _topSegment(context, "see orders", true),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            /// HEADER WITH REFRESH BUTTON
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Orders (${_filteredOrders.length})',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  IconButton(
                    onPressed: _refreshOrders,
                    icon: const Icon(Icons.refresh, color: orange),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),

            /// SEARCH AND FILTER BAR
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: "Search by order ID, merchant, or customer...",
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(color: orange, width: 2),
                            ),
                            prefixIcon: const Icon(Icons.search, color: orange),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                                : null,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      PopupMenuButton<String>(
                        icon: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: orange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.filter_list, color: Colors.white),
                        ),
                        onSelected: (value) {
                          setState(() {
                            _statusFilter = value;
                          });
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'all',
                            child: Text('All Orders'),
                          ),
                          const PopupMenuItem(
                            value: 'pending',
                            child: Text('Pending'),
                          ),
                          const PopupMenuItem(
                            value: 'confirmed',
                            child: Text('Confirmed'),
                          ),
                          const PopupMenuItem(
                            value: 'preparing',
                            child: Text('Preparing'),
                          ),
                          const PopupMenuItem(
                            value: 'ready',
                            child: Text('Ready'),
                          ),
                          const PopupMenuItem(
                            value: 'delivered',
                            child: Text('Delivered'),
                          ),
                          const PopupMenuItem(
                            value: 'cancelled',
                            child: Text('Cancelled'),
                          ),
                        ],
                      ),
                    ],
                  ),

                  /// Status Filter Chips
                  if (_statusFilter != 'all')
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Chip(
                            label: Text(
                              _statusFilter.toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: _getStatusColor(_statusFilter),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              setState(() {
                                _statusFilter = 'all';
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            /// LOADING / ERROR / ORDERS DISPLAY
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: orange),
                    const SizedBox(height: 16),
                    const Text(
                      "Loading your orders...",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else if (_errorMessage.isNotEmpty)
              Padding(
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
                      onPressed: _refreshOrders,
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
              )
            else if (_filteredOrders.isEmpty)
                Padding(
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
                        "No orders found",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.isNotEmpty || _statusFilter != 'all'
                            ? "Try different search criteria"
                            : "You haven't placed any orders yet",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (_searchQuery.isNotEmpty || _statusFilter != 'all')
                        ElevatedButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _statusFilter = 'all';
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.clear_all, color: Colors.white),
                          label: const Text(
                            "Clear Filters",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    /// ORDERS LIST
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.orange, width: 2),
                        ),
                        child: Column(
                          children: [
                            /// ----- TABLE HEADER -----
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: orange.withOpacity(0.1),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: const [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      "Order ID",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      "Merchant",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      "Status",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      "Amount",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            /// ----- ORDER ROWS -----
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredOrders.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: Colors.grey.shade300,
                              ),
                              itemBuilder: (context, index) {
                                final order = _filteredOrders[index];
                                final orderNumber = order['order_number']?.toString() ?? 'N/A';
                                final merchantName = order['merchant_name']?.toString() ?? 'N/A';
                                final status = order['status']?.toString() ?? 'pending';
                                final totalAmount = order['total_amount'];
                                final createdAt = order['created_at']?.toString() ?? '';
                                final isUser = getCurrentUser()?['type'] == 'user';
                                final otherParty = isUser ? merchantName : order['customer_name'] ?? 'N/A';

                                return InkWell(
                                  onTap: () => _showOrderDetails(order),
                                  child: Container(
                                    color: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '#$orderNumber',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatDate(createdAt),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            otherParty,
                                            style: const TextStyle(fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(status).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: _getStatusColor(status),
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              status.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: _getStatusColor(status),
                                              ),
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            _formatAmount(totalAmount),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    /// SUMMARY CARD
                    if (_filteredOrders.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: orange.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: orange.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Orders: ${_filteredOrders.length}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Pending: ${_filteredOrders.where((o) => o['status'] == 'pending').length}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Total Amount',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatAmount(
                                      _filteredOrders.fold<double>(
                                        0,
                                            (sum, order) => sum + _parseAmount(order['total_amount']),
                                      ),
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    /// FOOTER BOX
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC4D4),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Order Tracking",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "• Tap on any order to view details\n"
                                  "• Search by order ID, merchant or customer name\n"
                                  "• Filter by status using the filter button\n"
                                  "• Pull down to refresh the list",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 50),
                  ],
                ),
          ],
        ),
      ),

      /// BOTTOM NAV BAR
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

  Widget _topSegment(BuildContext context, String title, bool isSelected) {
    return Expanded(
      child: InkWell(
        onTap: () {
          if (title == "pay orders") {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PayOrdersPage()),
            );
          } else if (title == "scan") {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrderPage()),
            );
          } else if (title == "see orders") {
            // stay here
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? null
                : Border.all(color: Colors.white24, width: 1),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFF8A00) : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Order Details Bottom Sheet
class OrderDetailsBottomSheet extends StatelessWidget {
  final Map<String, dynamic> order;

  const OrderDetailsBottomSheet({super.key, required this.order});

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd MMM yyyy, HH:mm:ss').format(date);
    } catch (e) {
      return dateString;
    }
  }

  // FIXED: Safe conversion to double
  double _parseAmount(dynamic amount) {
    if (amount == null) return 0.0;

    if (amount is double) return amount;
    if (amount is int) return amount.toDouble();
    if (amount is String) {
      // Remove any non-numeric characters except decimal point
      final cleaned = amount.replaceAll(RegExp(r'[^0-9\.]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }

    try {
      return double.parse(amount.toString());
    } catch (e) {
      print('Error parsing amount $amount: $e');
      return 0.0;
    }
  }

  String _formatAmount(dynamic amount) {
    final numAmount = _parseAmount(amount);
    return '${numAmount.toStringAsFixed(0)} RWF';
  }

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

  // FIXED: Safe item parsing
  List<Map<String, dynamic>> _parseItems() {
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
    return items;
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);

    final orderNumber = order['order_number']?.toString() ?? 'N/A';
    final merchantName = order['merchant_name']?.toString() ?? 'N/A';
    final customerName = order['customer_name']?.toString() ?? 'N/A';
    final status = order['status']?.toString() ?? 'pending';
    final totalAmount = order['total_amount'];
    final createdAt = order['created_at']?.toString() ?? '';
    final updatedAt = order['updated_at']?.toString() ?? '';
    final tableName = order['table_name']?.toString();
    final customFields = order['custom_fields'] ?? {};

    final items = _parseItems();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order #$orderNumber',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _getStatusColor(status), width: 2),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(status),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  /// Order Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.store, color: orange, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Merchant',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    merchantName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.person, color: orange, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Customer',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    customerName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  /// Dates
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Order Date',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              _formatDate(createdAt),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Last Updated',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              _formatDate(updatedAt),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  /// Table Name (if restaurant)
                  if (tableName != null && tableName.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Table Name',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          tableName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),

                  /// Custom Fields
                  if (customFields is Map && customFields.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Additional Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...customFields.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${entry.key}:',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  entry.value.toString(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 20),
                      ],
                    ),

                  /// Order Items
                  if (items.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Order Items',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...items.map((item) {
                          final productName = item['productname']?.toString() ?? 'Unknown';
                          final price = _parseAmount(item['price']);
                          final quantity = (item['quantity'] is int)
                              ? (item['quantity'] as int)
                              : (int.tryParse(item['quantity']?.toString() ?? '1') ?? 1);
                          final subtotal = price * quantity;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        productName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${price.toStringAsFixed(0)} RWF × $quantity',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${subtotal.toStringAsFixed(0)} RWF',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: orange,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 20),
                      ],
                    ),

                  /// Total Amount
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: orange.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatAmount(totalAmount),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: orange,
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
        ],
      ),
    );
  }
}