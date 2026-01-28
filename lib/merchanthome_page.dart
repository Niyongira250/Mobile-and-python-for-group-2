import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'package:intl/intl.dart';
import 'home_page.dart';
import 'order_page.dart';
import 'pay_page.dart';
import 'receive_page.dart';
import 'merchant_wallet.dart';
import 'profile_overlay.dart';
import 'product_entry.dart';
import 'dart:math';
import 'services/data_service.dart';
import 'dart:async';

class MerchantHomePage extends StatefulWidget {
  const MerchantHomePage({super.key});

  @override
  State<MerchantHomePage> createState() => _MerchantHomePageState();
}

class _MerchantHomePageState extends State<MerchantHomePage> {
  int _selectedIndex = 0;
  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;
  DateTime? selectedDay = DateTime.now();

  // Merchant data
  String _merchantUsername = 'Merchant';
  double? _merchantBalance = 0.0;

  // Statistics data
  List<Map<String, dynamic>> _bestSellers = [];
  List<Map<String, dynamic>> _recentOrders = [];
  List<Map<String, dynamic>> _receivedTransactions = [];
  List<Map<String, dynamic>> _sentTransactions = [];

  double _todayReceived = 0.0;
  double _todaySent = 0.0;

  // Notification variables
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = true;
  bool _isLoadingStats = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    final u = getCurrentUser();
    if (u == null || u['type'] != 'merchant') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Merchant dashboard is for merchants only'),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      });
    } else {
      _merchantUsername = u['username']?.toString() ?? 'Merchant';
      _merchantBalance = u['balance'] != null
          ? double.tryParse(u['balance'].toString()) ?? 0.0
          : 0.0;

      _loadNotifications();
      _loadMerchantStats();
    }
  }

  // Navigation handler - FIXED: This method exists but was called _onItemTapped
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
      // Already on home page
        break;
      case 1:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderPage()));
        break;
      case 2:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PayPage()));
        break;
      case 3:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MerchantWallet()));
        break;
      case 4:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceivePage()));
        break;
    }
  }

  // Load merchant statistics
  Future<void> _loadMerchantStats() async {
    try {
      setState(() {
        _isLoadingStats = true;
      });

      final user = getCurrentUser();
      if (user == null) return;

      final merchantId = user['id']?.toString();
      if (merchantId == null) return;

      print('📊 Loading merchant statistics...');

      // Load best sellers from orders
      await _loadBestSellers(merchantId);

      // Load today's transactions
      await _loadTodayTransactions(merchantId);

      // Load recent orders
      await _loadRecentOrders(merchantId);

      setState(() {
        _isLoadingStats = false;
      });

      print('✅ Merchant stats loaded successfully');
    } catch (e) {
      print('❌ Error loading merchant stats: $e');
      setState(() {
        _isLoadingStats = false;
        _setMockData();
      });
    }
  }

  // Load best sellers from orders
  Future<void> _loadBestSellers(String merchantId) async {
    try {
      final uri = Uri.parse("http://localhost:8000/api/get-merchant-orders/")
          .replace(queryParameters: {
        'merchant_id': merchantId,
      });

      final response = await http.get(
        uri,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final orders = data['orders'] ?? [];

        // Process all orders to get product quantities
        Map<String, int> productQuantities = {};

        for (var order in orders) {
          final items = order['items'] ?? [];
          if (items is List && items.isNotEmpty) {
            for (var item in items) {
              if (item is Map) {
                final productName = item['productname']?.toString() ?? 'Unknown';
                final quantity = item['quantity'] is int
                    ? item['quantity'] as int
                    : int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

                productQuantities.update(
                  productName,
                      (value) => value + quantity,
                  ifAbsent: () => quantity,
                );
              }
            }
          }
        }

        // Sort by quantity and get top 5
        final sortedProducts = productQuantities.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        // Prepare best sellers data
        List<Map<String, dynamic>> bestSellers = [];
        final maxSales = sortedProducts.isNotEmpty ? sortedProducts[0].value : 1;

        // Colors from green (most bought) to red (5th most bought)
        final colors = [
          const Color(0xFF155703),
          const Color(0xFFFFA726),
          const Color(0xFFFFB74D),
          const Color(0xFFFFCC80),
          const Color(0xFFFFE0B2),
        ];

        for (int i = 0; i < min(5, sortedProducts.length); i++) {
          final entry = sortedProducts[i];
          bestSellers.add({
            'name': entry.key,
            'sales': entry.value,
            'color': colors[i % colors.length],
            'height': (entry.value / maxSales) * 150 + 20,
          });
        }

        // If we don't have enough products, fill with placeholders
        while (bestSellers.length < 5) {
          bestSellers.add({
            'name': 'Product ${bestSellers.length + 1}',
            'sales': 0,
            'color': Colors.green.shade300,
            'height': 20,
          });
        }

        setState(() {
          _bestSellers = bestSellers;
        });

        print('✅ Loaded ${bestSellers.length} best sellers');
      }
    } catch (e) {
      print('❌ Error loading best sellers: $e');
      _setMockBestSellers();
    }
  }

  // Mock best sellers for fallback
  void _setMockBestSellers() {
    setState(() {
      _bestSellers = [
        {'name': 'Chicken Burger', 'sales': 25, 'color': const Color(0xB300D069), 'height': 150.0},
        {'name': 'French Fries', 'sales': 18, 'color': const Color(0xFFFFA726), 'height': 120.0},
        {'name': 'Coca Cola', 'sales': 15, 'color': const Color(0xFFFFB74D), 'height': 110.0},
        {'name': 'Cheese Pizza', 'sales': 12, 'color': const Color(0xFFFFCC80), 'height': 95.0},
        {'name': 'Chocolate Cake', 'sales': 8, 'color': const Color(0xFFFFE0B2), 'height': 75.0},
      ];
    });
  }

  // Load today's transactions - FIXED VERSION
  Future<void> _loadTodayTransactions(String merchantId) async {
    try {
      final user = getCurrentUser();
      if (user == null) return;

      final email = user['email']?.toString();
      if (email == null) return;

      print('💰 Loading transactions for merchant: $merchantId, email: $email');

      // Get transactions for this merchant
      final uri = Uri.parse("http://localhost:8000/api/get-user-transactions/")
          .replace(queryParameters: {
        'email': email, // Use email to get transactions
      });

      final response = await http.get(
        uri,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final transactions = data['transactions'] ?? [];

        print('📊 Found ${transactions.length} total transactions');

        // Filter for today's transactions
        final today = DateTime.now();
        List<Map<String, dynamic>> todayTransactions = [];

        for (var trans in transactions) {
          if (trans is Map) {
            try {
              final dateStr = trans['date']?.toString();
              if (dateStr != null) {
                // Parse date string
                DateTime? transDate;
                if (dateStr.contains(' ')) {
                  // Format: "01 January 2024 14:30"
                  final parts = dateStr.split(' ');
                  if (parts.length >= 3) {
                    transDate = DateFormat('dd MMMM yyyy HH:mm').parse(dateStr);
                  }
                } else {
                  // Try ISO format
                  transDate = DateTime.tryParse(dateStr);
                }

                if (transDate != null &&
                    transDate.year == today.year &&
                    transDate.month == today.month &&
                    transDate.day == today.day) {

                  final amount = double.tryParse(trans['amount']?.toString() ?? '0') ?? 0.0;
                  final type = trans['type']?.toString();
                  final otherParty = trans['other_party']?.toString() ?? 'Unknown';

                  todayTransactions.add({
                    'other_party': otherParty,
                    'amount': amount,
                    'date': _formatTransactionTime(transDate),
                    'type': type,
                    'full_date': transDate,
                  });
                }
              }
            } catch (e) {
              print('⚠️ Error parsing transaction date: $e');
            }
          }
        }

        // Separate received and sent transactions
        List<Map<String, dynamic>> received = [];
        List<Map<String, dynamic>> sent = [];
        double receivedTotal = 0.0;
        double sentTotal = 0.0;

        for (var trans in todayTransactions) {
          final type = trans['type']?.toString();
          final amount = trans['amount'] as double;

          if (type == 'received') {
            receivedTotal += amount;
            received.add({
              'other_party': trans['other_party'],
              'amount': amount,
              'date': trans['date'],
            });
          } else if (type == 'sent') {
            sentTotal += amount;
            sent.add({
              'other_party': trans['other_party'],
              'amount': amount,
              'date': trans['date'],
            });
          }
        }

        // Sort by date (most recent first) and limit to 3 each
        received.sort((a, b) {
          final dateA = a['full_date'];
          final dateB = b['full_date'];
          if (dateA is DateTime && dateB is DateTime) {
            return dateB.compareTo(dateA);
          }
          return 0;
        });

        sent.sort((a, b) {
          final dateA = a['full_date'];
          final dateB = b['full_date'];
          if (dateA is DateTime && dateB is DateTime) {
            return dateB.compareTo(dateA);
          }
          return 0;
        });

        setState(() {
          _receivedTransactions = received.take(3).toList();
          _sentTransactions = sent.take(3).toList();
          _todayReceived = receivedTotal;
          _todaySent = sentTotal;
        });

        print('✅ Today stats: Received ${_receivedTransactions.length} transactions ($receivedTotal RWF), Sent ${_sentTransactions.length} transactions ($sentTotal RWF)');
      } else {
        print('❌ Failed to load transactions: ${response.statusCode}');
        _setMockTransactions();
      }
    } catch (e) {
      print('❌ Error loading today transactions: $e');
      _setMockTransactions();
    }
  }

  // Helper to format transaction time
  String _formatTransactionTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hr ago';
    } else {
      return DateFormat('hh:mm a').format(date);
    }
  }

  // Mock transactions for fallback
  void _setMockTransactions() {
    setState(() {
      _receivedTransactions = [
        {
          'other_party': 'John Doe',
          'amount': 15000.0,
          'date': 'Just now',
        },
        {
          'other_party': 'Jane Smith',
          'amount': 25000.0,
          'date': '30 min ago',
        },
        {
          'other_party': 'Robert Johnson',
          'amount': 18000.0,
          'date': '1 hr ago',
        },
      ];

      _sentTransactions = [
        {
          'other_party': 'Supplier Co.',
          'amount': 45000.0,
          'date': 'Just now',
        },
        {
          'other_party': 'Delivery Service',
          'amount': 12000.0,
          'date': '45 min ago',
        },
        {
          'other_party': 'Utility Company',
          'amount': 8000.0,
          'date': '2 hrs ago',
        },
      ];

      _todayReceived = 95000.0;
      _todaySent = 120000.0;
    });
  }

  // Load recent orders
  Future<void> _loadRecentOrders(String merchantId) async {
    try {
      final uri = Uri.parse("http://localhost:8000/api/get-merchant-orders/")
          .replace(queryParameters: {
        'merchant_id': merchantId,
      });

      final response = await http.get(
        uri,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final orders = data['orders'] ?? [];

        // Sort orders by creation date (most recent first)
        orders.sort((a, b) {
          try {
            final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '');
            final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '');
            if (dateA != null && dateB != null) {
              return dateB.compareTo(dateA);
            }
            return 0;
          } catch (e) {
            return 0;
          }
        });

        // Process orders to get product details (4 recent orders)
        List<Map<String, dynamic>> recentProducts = [];

        for (var order in orders.take(4)) {
          final items = order['items'] ?? [];
          if (items is List && items.isNotEmpty) {
            for (var item in items.take(2)) {
              if (item is Map) {
                recentProducts.add({
                  'productname': item['productname']?.toString() ?? 'Unknown',
                  'quantity': item['quantity']?.toString() ?? '1',
                  'price': double.tryParse(item['price']?.toString() ?? '0') ?? 0.0,
                  'order_date': order['created_at']?.toString() ?? 'Today',
                  'customer': order['customer_name']?.toString() ?? 'Customer',
                  'order_number': order['order_number']?.toString() ?? '',
                });
              }
            }
          }
          if (recentProducts.length >= 4) break;
        }

        setState(() {
          _recentOrders = recentProducts.take(4).toList();
        });

        print('✅ Loaded ${recentProducts.length} recent orders');
      }
    } catch (e) {
      print('❌ Error loading recent orders: $e');
      _setMockRecentOrders();
    }
  }

  // Mock recent orders for fallback
  void _setMockRecentOrders() {
    setState(() {
      _recentOrders = [
        {
          'productname': 'Chicken Burger',
          'quantity': '2',
          'price': 8000.0,
          'order_date': 'Today',
          'customer': 'John Doe',
          'order_number': 'ORD-123',
        },
        {
          'productname': 'French Fries',
          'quantity': '3',
          'price': 6000.0,
          'order_date': 'Today',
          'customer': 'Jane Smith',
          'order_number': 'ORD-124',
        },
        {
          'productname': 'Coca Cola',
          'quantity': '4',
          'price': 4000.0,
          'order_date': 'Today',
          'customer': 'Robert Johnson',
          'order_number': 'ORD-125',
        },
        {
          'productname': 'Cheese Pizza',
          'quantity': '1',
          'price': 12000.0,
          'order_date': 'Today',
          'customer': 'Mary Williams',
          'order_number': 'ORD-126',
        },
      ];
    });
  }

  // Mock all data
  void _setMockData() {
    _setMockBestSellers();
    _setMockTransactions();
    _setMockRecentOrders();
  }

  // Format currency
  String _formatCurrency(double amount) {
    return '${NumberFormat('#,##0').format(amount)} FRW';
  }

  // Format date
  String _formatDate(String dateString) {
    try {
      final date = DateTime.tryParse(dateString);
      if (date == null) return 'Today';

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));

      if (date.isAfter(today)) {
        return 'Today';
      } else if (date.isAfter(yesterday)) {
        return 'Yesterday';
      } else {
        return DateFormat('MMM dd').format(date);
      }
    } catch (e) {
      return 'Today';
    }
  }

  // Get initials for avatar
  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, min(2, name.length)).toUpperCase();
  }

  // PDF Download function
  Future<void> _downloadReport() async {
    try {
      final user = getCurrentUser();
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Merchant not logged in'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final merchantId = user['id']?.toString();
      if (merchantId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Merchant ID not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final uri = Uri.parse("http://localhost:8000/api/generate-merchant-report/")
          .replace(queryParameters: {
        'merchant_id': merchantId,
        'year': selectedYear.toString(),
        'month': selectedMonth.toString(),
        if (selectedDay != null) 'day': selectedDay!.day.toString(),
      });

      print('📥 Downloading report from: $uri');

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generating PDF report...'),
            ],
          ),
        ),
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      Navigator.pop(context);

      if (response.statusCode == 200) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final safeUsername = _merchantUsername.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
        final filename = 'merchant_report_${safeUsername}_$timestamp.pdf';

        if (kIsWeb) {
          await _downloadFileWeb(response.bodyBytes, filename);
        } else {
          await _downloadFileMobile(response.bodyBytes, filename);
        }
      } else {
        print('❌ Failed to download report: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on TimeoutException {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report generation timed out'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      print('🔥 Error downloading report: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadFileWeb(Uint8List bytes, String filename) async {
    try {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();

      html.Url.revokeObjectUrl(url);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report downloaded: $filename'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ Web download error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadFileMobile(Uint8List bytes, String filename) async {
    try {
      Directory? directory;
      try {
        if (Platform.isAndroid || Platform.isIOS) {
          directory = await getExternalStorageDirectory();
        }
        if (directory == null) {
          directory = await getApplicationDocumentsDirectory();
        }
      } catch (e) {
        directory = await getTemporaryDirectory();
      }

      final reportsDir = Directory('${directory!.path}/Merchant_Reports');
      if (!await reportsDir.exists()) {
        await reportsDir.create(recursive: true);
      }

      final file = File('${reportsDir.path}/$filename');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report saved: $filename'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      print('❌ Mobile download error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving file: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Load notifications
  Future<void> _loadNotifications() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = '';
      });

      final user = getCurrentUser();
      if (user == null) {
        print('❌ No merchant logged in');
        setState(() {
          _notifications = [];
          _unreadCount = 0;
          _isLoading = false;
        });
        return;
      }

      final merchantId = user['id']?.toString();
      if (merchantId == null) {
        print('❌ Merchant ID not found');
        setState(() {
          _notifications = [];
          _unreadCount = 0;
          _isLoading = false;
        });
        return;
      }

      // Load merchant-specific order notifications
      final uri = Uri.parse("http://localhost:8000/api/get-merchant-order-notifications/?merchant_id=$merchantId");

      final response = await http.get(
        uri,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (data.containsKey('error')) {
          print('❌ Merchant order notifications error: ${data['error']}');
          setState(() {
            _hasError = true;
            _isLoading = false;
            _errorMessage = data['error'].toString();
          });
          return;
        }

        // Safely extract notifications
        final dynamic notificationsData = data['notifications'] ?? [];
        List<Map<String, dynamic>> parsedNotifications = [];

        if (notificationsData is List) {
          for (var item in notificationsData) {
            if (item is Map<String, dynamic>) {
              parsedNotifications.add(item);
            } else if (item is Map) {
              parsedNotifications.add(Map<String, dynamic>.from(item));
            }
          }
        }

        setState(() {
          _notifications = parsedNotifications;
          _unreadCount = parsedNotifications.length;
          _isLoading = false;
          _hasError = false;
        });

        print('✅ Loaded ${_notifications.length} order notifications');
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
        await _loadGeneralMerchantNotifications(user);
      }
    } on TimeoutException {
      print('⏰ Merchant request timed out');
      setState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage = 'Request timed out. Make sure Django server is running.';
      });
    } catch (e) {
      print('🔥 Error loading merchant order notifications: $e');
      setState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage = 'Error loading notifications: $e';
      });
    }
  }

  // Fallback to general merchant notifications
  Future<void> _loadGeneralMerchantNotifications(Map<String, dynamic> user) async {
    try {
      final email = user['email'] as String?;
      if (email == null) {
        _loadMockNotifications();
        return;
      }

      final uri = Uri.parse("http://localhost:8000/api/notifications/?email=$email");

      final response = await http.get(
        uri,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final dynamic notificationsData = data['notifications'] ?? [];

        List<Map<String, dynamic>> parsedNotifications = [];

        if (notificationsData is List) {
          for (var item in notificationsData) {
            if (item is Map<String, dynamic>) {
              parsedNotifications.add(item);
            } else if (item is Map) {
              parsedNotifications.add(Map<String, dynamic>.from(item));
            }
          }
        }

        setState(() {
          _notifications = parsedNotifications;
          _unreadCount = parsedNotifications.length;
          _isLoading = false;
          _hasError = false;
        });
      } else {
        throw Exception('Failed to load general notifications');
      }
    } catch (e) {
      print('❌ Error loading general notifications: $e');
      _loadMockNotifications();
    }
  }

  // Mock notifications fallback
  void _loadMockNotifications() {
    final merchantUsername = _merchantUsername.isNotEmpty ? _merchantUsername : 'Merchant';

    setState(() {
      _notifications = [
        {
          'title': 'Welcome to Merchant Dashboard!',
          'content': 'You can manage your products and orders here.',
          'urgency': 'low',
          'date': DateTime.now().subtract(const Duration(hours: 2)).toString(),
          'designated_to': 'merchant'
        },
        {
          'title': 'Order Alert',
          'content': 'New order received from customer.',
          'urgency': 'high',
          'date': DateTime.now().subtract(const Duration(minutes: 30)).toString(),
          'designated_to': 'merchant',
          'order_id': '12345',
          'order_status': 'pending',
          'customer_name': 'John Doe'
        },
      ];
      _unreadCount = _notifications.length;
      _isLoading = false;
      _hasError = false;
    });
  }

  // Keep your existing notification helper methods
  String _formatNotificationTime(dynamic dateTime) {
    try {
      String dateString;

      if (dateTime is String) {
        dateString = dateTime;
      } else if (dateTime is Map && dateTime['date'] is String) {
        dateString = dateTime['date'];
      } else {
        return 'Recent';
      }

      final parsedDate = DateTime.tryParse(dateString);
      if (parsedDate == null) return 'Recent';

      final now = DateTime.now();
      final difference = now.difference(parsedDate);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} min ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hr ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else {
        return '${parsedDate.day}/${parsedDate.month}/${parsedDate.year}';
      }
    } catch (e) {
      return 'Recent';
    }
  }

  Color _getUrgencyColor(String urgency) {
    switch (urgency.toLowerCase()) {
      case 'high':
        return const Color(0xFFFF8A00);
      case 'medium':
        return Colors.orange.shade600;
      case 'low':
        return Colors.blue.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  Color _getUrgencyBackgroundColor(String urgency) {
    switch (urgency.toLowerCase()) {
      case 'high':
        return const Color(0xFFFF8A00).withOpacity(0.1);
      case 'medium':
        return Colors.orange.shade50;
      case 'low':
        return Colors.blue.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  IconData _getNotificationIcon(String urgency) {
    switch (urgency.toLowerCase()) {
      case 'high':
        return Icons.error;
      case 'medium':
        return Icons.warning;
      case 'low':
        return Icons.info;
      default:
        return Icons.notifications;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFFF8A00);
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

  String _getActionButtonLabel(String? currentStatus, String? defaultLabel) {
    if (currentStatus == null) return defaultLabel ?? 'Take Action';

    switch (currentStatus.toLowerCase()) {
      case 'pending':
        return 'Confirm Order';
      case 'confirmed':
        return 'Start Preparing';
      case 'preparing':
        return 'Mark as Ready';
      case 'ready':
        return 'Mark as Delivered';
      default:
        return defaultLabel ?? 'Take Action';
    }
  }

  String _getNextStatus(String currentStatus) {
    switch (currentStatus.toLowerCase()) {
      case 'pending':
        return 'confirmed';
      case 'confirmed':
        return 'preparing';
      case 'preparing':
        return 'ready';
      case 'ready':
        return 'delivered';
      default:
        return currentStatus;
    }
  }

  void _handleOrderAction(String orderId, String currentStatus, String title) {
    final nextStatus = _getNextStatus(currentStatus);
    final actionLabel = _getActionButtonLabel(currentStatus, null);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Order Status'),
        content: Text('Are you sure you want to $actionLabel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateOrderStatus(orderId, nextStatus, title);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _getStatusColor(nextStatus),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus, String notificationTitle) async {
    try {
      final user = getCurrentUser();
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Merchant not logged in'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final merchantId = user['id']?.toString();
      if (merchantId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Merchant ID not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final response = await http.post(
        Uri.parse("http://localhost:8000/api/update-order-status/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'order_id': orderId,
          'status': newStatus,
          'merchant_id': merchantId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Order status updated successfully'),
              backgroundColor: Colors.green,
            ),
          );

          _loadNotifications();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['error']?.toString() ?? 'Failed to update order status'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server error: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ Error updating order status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // BAR ITEM WIDGET with visible gradients
  Widget barItem(Map<String, dynamic> item) {
    try {
      if (_bestSellers.isEmpty) {
        return Container(
          width: 30,
          height: 50,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.grey.shade300,
                Colors.grey.shade400,
              ],
              stops: [0.0, 1.0],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(child: Icon(Icons.bar_chart, size: 16, color: Colors.white)),
        );
      }

      // Find max sales safely
      int maxSales = 0;
      for (var element in _bestSellers) {
        final sales = element['sales'];
        if (sales is int) {
          if (sales > maxSales) maxSales = sales;
        } else if (sales is double) {
          final intSales = sales.toInt();
          if (intSales > maxSales) maxSales = intSales;
        }
      }

      // Get current item sales
      final sales = item['sales'];
      double salesValue = 0;

      if (sales is int) {
        salesValue = sales.toDouble();
      } else if (sales is double) {
        salesValue = sales;
      }

      // Calculate height with safeguard
      final double height = maxSales > 0 ? (salesValue / maxSales) * 130 + 20 : 20;

      // Get color safely
      Color color = const Color(0xFFFF8A00);
      final itemColor = item['color'];
      if (itemColor is Color) {
        color = itemColor;
      }

      return Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 30,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color,
                  color.withOpacity(0.7),
                  color.withOpacity(0.4),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            item['name']?.toString() ?? 'Item',
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
          const SizedBox(height: 2),
          Text(
            salesValue.toInt().toString(),
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ],
      );
    } catch (e) {
      print('Error in barItem: $e');
      return Container(
        width: 30,
        height: 50,
        color: Colors.grey,
        child: const Center(child: Icon(Icons.error, size: 16)),
      );
    }
  }

  // TRANSACTION ITEM WIDGET
  Widget _transactionItem(Map<String, dynamic> trans, bool isReceived) {
    final otherParty = trans['other_party']?.toString() ?? 'Unknown';
    final amount = double.tryParse(trans['amount']?.toString() ?? '0') ?? 0.0;
    final date = trans['date']?.toString() ?? 'Today';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isReceived
              ? [
            Colors.green.shade50,
            Colors.green.shade100,
          ]
              : [
            const Color(0xFFFF8A00).withOpacity(0.1),
            const Color(0xFFFF8A00).withOpacity(0.05),
          ],
          stops: [0.0, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar with gradient
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isReceived
                    ? [Colors.green.shade300, Colors.green.shade600]
                    : [const Color(0xFFFF8A00), const Color(0xFFFFA726)],
                stops: [0.0, 1.0],
              ),
            ),
            child: Center(
              child: Text(
                _getInitials(otherParty),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  otherParty,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  date,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Amount with gradient background
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isReceived
                    ? [Colors.green.shade100, Colors.green.shade200]
                    : [const Color(0xFFFF8A00).withOpacity(0.1), const Color(0xFFFFA726).withOpacity(0.1)],
                stops: [0.0, 1.0],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _formatCurrency(amount),
              style: TextStyle(
                color: isReceived ? Colors.green.shade800 : const Color(0xFFFF8A00),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ORDER ITEM WIDGET
  Widget _orderItem(Map<String, dynamic> order) {
    final productName = order['productname']?.toString() ?? 'Unknown';
    final quantity = order['quantity']?.toString() ?? '1';
    final price = double.tryParse(order['price']?.toString() ?? '0') ?? 0.0;
    final total = price * (int.tryParse(quantity) ?? 1);
    final customer = order['customer']?.toString() ?? 'Customer';
    final orderNumber = order['order_number']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFFFF8A00).withOpacity(0.1),
          ],
          stops: [0.0, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Customer: $customer',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                if (orderNumber.isNotEmpty)
                  Text(
                    'Order: $orderNumber',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Qty: $quantity',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF8A00), Color(0xFFFFA726)],
                    stops: [0.0, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatCurrency(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: orange,
        automaticallyImplyLeading: false,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _merchantUsername,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 3),
            const Text(
              "Merchant Dashboard",
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
        actions: [
          // Balance display with gradient
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF8A00), Color(0xFFFFA726)],
                  stops: [0.0, 1.0],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: orange.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '${_merchantBalance?.toStringAsFixed(0) ?? '0'} FRW',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          // Notification icon with badge
          Stack(
            children: [
              IconButton(
                onPressed: _loadNotifications,
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Colors.white70],
                      stops: [0.0, 1.0],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.notifications, color: orange),
                ),
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.red, Colors.redAccent],
                        stops: [0.0, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          // Profile avatar with gradient border
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileOverlay(onClose: () => Navigator.pop(context)),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF8A00), Color(0xFFFFA726)],
                    stops: [0.0, 1.0],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Builder(
                  builder: (context) {
                    final user = getCurrentUser();
                    final imgPath = user?['profilePicturePath'] as String?;
                    final provider = imageProviderFromPath(imgPath);
                    if (provider != null) {
                      return CircleAvatar(
                        radius: 18,
                        backgroundImage: provider,
                        backgroundColor: Colors.transparent,
                      );
                    }
                    return CircleAvatar(
                      radius: 18,
                      backgroundColor: orange.withOpacity(0.8),
                      child: Text(
                        _getInitials(_merchantUsername),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            // TODAY'S BEST SELLERS with visible gradient
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF8A00),
                    Color(0xFFFFA726),
                    Color(0xFFFFB74D),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: orange.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bar_chart, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Best Selling from stock",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      if (_isLoadingStats)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      else
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.refresh, size: 18, color: Colors.white),
                          ),
                          onPressed: _loadMerchantStats,
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  SizedBox(
                    height: 200,
                    child: Row(
                      children: [
                        // Y-Axis (Quantity)
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (int i = 5; i >= 1; i--)
                              Text(
                                '${(i * 20)}',
                                style: const TextStyle(fontSize: 10, color: Colors.white),
                              ),
                            const SizedBox(height: 20),
                            const Text("0", style: TextStyle(fontSize: 10, color: Colors.white)),
                          ],
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: _isLoadingStats
                              ? const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                              : _bestSellers.isEmpty
                              ? const Center(
                            child: Text(
                              'No sales data available',
                              style: TextStyle(color: Colors.white),
                            ),
                          )
                              : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: _bestSellers.map(barItem).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Top 5 products by quantity sold',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // TODAY'S STATISTICS with visible gradient
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Color(0xFFFFF3E0),
                    Colors.white,
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: orange.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: orange.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.trending_up, color: orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Today's Statistics",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      // Received
                      Expanded(
                        child: _statCard(
                          title: 'Received',
                          amount: _formatCurrency(_todayReceived),
                          color: Colors.green,
                          transactions: _receivedTransactions,
                          isReceived: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Sent
                      Expanded(
                        child: _statCard(
                          title: 'Sent',
                          amount: _formatCurrency(_todaySent),
                          color: orange,
                          transactions: _sentTransactions,
                          isReceived: false,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  const Row(
                    children: [
                      Icon(Icons.receipt, color: orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Recent Sales Report",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  if (_isLoadingStats)
                    const Center(child: CircularProgressIndicator(color: orange))
                  else if (_recentOrders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.grey.shade50,
                            Colors.white,
                            Colors.grey.shade50,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'No recent sales',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        ..._recentOrders.map(_orderItem).toList(),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () {
                            // Navigate to all sales page
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const OrderPage()),
                            );
                          },
                          child: Container(
                            height: 35,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFF8A00), Color(0xFFFFA726)],
                                stops: [0.0, 1.0],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: orange.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Text(
                              "View All Sales",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // MANAGE PRODUCTS CARD with visible gradient
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProductEntryPage()),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF8A00), Color(0xFF27AE60)],
                    stops: [0.0, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.storefront, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Manage Products',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Add, edit or remove products',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Download Reports",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(child: _yearPicker()),
                const SizedBox(width: 8),
                Expanded(child: _monthPicker()),
                const SizedBox(width: 8),
                Expanded(child: _dayPicker()),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _downloadReport,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFF8A00), Color(0xFFFFA726)],
                        stops: [0.0, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: orange.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.download, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          "Download PDF",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 5),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                'Generates a comprehensive business report including transactions, orders, customers, and financial analysis.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),

            const SizedBox(height: 20),

            // NOTIFICATIONS SECTION with visible gradient
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF8A00), Color(0xFFFFA726)],
                  stops: [0.0, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: orange.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.notifications, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Order Notifications (${_notifications.length})",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loadNotifications,
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isLoading ? Icons.refresh : Icons.refresh,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Dynamic Notification cards
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(color: orange),
                ),
              )
            else if (_hasError)
              _errorCard()
            else if (_notifications.isEmpty)
                _emptyNotificationsCard()
              else
                ..._notifications.map((notification) {
                  final title = notification['title']?.toString() ?? 'Notification';
                  final content = notification['content']?.toString() ?? '';
                  final urgency = notification['urgency']?.toString() ?? 'low';
                  final date = notification['date'];
                  final orderId = notification['order_id']?.toString();
                  final orderStatus = notification['order_status']?.toString();
                  final customerName = notification['customer_name']?.toString();

                  return Column(
                    children: [
                      _notificationCard(
                        title: title,
                        subtitle: content,
                        urgency: urgency,
                        time: _formatNotificationTime(date),
                        buttonLabel: 'Take Action',
                        orderId: orderId,
                        orderStatus: orderStatus,
                        customerName: customerName,
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }).toList(),

            const SizedBox(height: 35),
          ],
        ),
      ),

      /// -------- BOTTOM NAV --------
      /// FIXED: Changed onTap to use _onItemTapped instead of _onTap
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped, // Fixed this line
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

  // STAT CARD WIDGET with visible gradient
  Widget _statCard({
    required String title,
    required String amount,
    required Color color,
    required List<Map<String, dynamic>> transactions,
    required bool isReceived,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.05),
            Colors.white,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color,
                      color.withOpacity(0.7),
                    ],
                    stops: [0.0, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isReceived ? Icons.arrow_downward : Icons.arrow_upward,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.1),
                      color.withOpacity(0.2),
                    ],
                    stops: [0.0, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  amount,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (transactions.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Colors.grey.shade50,
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  'No ${title.toLowerCase()} yet',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            Column(
              children: transactions.map((trans) => _transactionItem(trans, isReceived)).toList(),
            ),
        ],
      ),
    );
  }

  // NOTIFICATION CARD WIDGET with visible gradient
  Widget _notificationCard({
    required String title,
    required String subtitle,
    required String urgency,
    required String time,
    String? buttonLabel,
    String? orderId,
    String? orderStatus,
    String? customerName,
  }) {
    final bgColor = _getUrgencyBackgroundColor(urgency);
    final iColor = _getUrgencyColor(urgency);
    final icon = _getNotificationIcon(urgency);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bgColor,
            Colors.white,
            bgColor.withOpacity(0.5),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      iColor.withOpacity(0.3),
                      iColor.withOpacity(0.1),
                    ],
                    stops: [0.0, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: iColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.grey.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customerName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Customer: $customerName',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.grey.shade100,
                      Colors.white,
                    ],
                    stops: [0.0, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  time,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 13,
              height: 1.4,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),

          if (orderStatus != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _getStatusColor(orderStatus).withOpacity(0.1),
                    Colors.white,
                    _getStatusColor(orderStatus).withOpacity(0.1),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                orderStatus.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _getStatusColor(orderStatus),
                ),
              ),
            ),
          ],

          if (buttonLabel != null || (orderId != null && orderStatus != null && orderStatus != 'delivered' && orderStatus != 'cancelled')) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: iColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                onPressed: () {
                  if (orderId != null) {
                    _handleOrderAction(orderId, orderStatus ?? 'pending', title);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Action triggered for: $title'),
                        backgroundColor: iColor,
                      ),
                    );
                  }
                },
                child: Text(
                  _getActionButtonLabel(orderStatus, buttonLabel),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // EMPTY NOTIFICATIONS CARD with gradient
  Widget _emptyNotificationsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Color(0xFFFFF3E0),
            Colors.white,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: const Color(0xFFFF8A00).withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF8A00), Color(0xFFFFA726)],
                stops: [0.0, 1.0],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_off,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'No notifications yet',
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'You\'re all caught up!',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _loadNotifications,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A00),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Refresh',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ERROR CARD with gradient
  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Color(0xFFFFEBEE),
            Colors.white,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: Colors.red.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.red, Colors.redAccent],
                stops: [0.0, 1.0],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Failed to load notifications',
            style: TextStyle(
              color: Colors.red,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _errorMessage.isNotEmpty
                ? _errorMessage
                : 'Please check your connection and try again',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _loadNotifications,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Retry',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // DATE PICKERS with visible gradients
  Widget _yearPicker() {
    final current = DateTime.now().year;
    final years = List.generate(5, (i) => current - i);

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Color(0xFFFFF3E0),
            Colors.white,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A00).withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFFF8A00).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: DropdownButton<int>(
        value: selectedYear,
        isExpanded: true,
        underline: Container(),
        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFFF8A00)),
        items: years
            .map((y) => DropdownMenuItem(
          value: y,
          child: Text(
            y.toString(),
            style: const TextStyle(color: Colors.black87),
          ),
        ))
            .toList(),
        onChanged: (v) => setState(() {
          selectedYear = v ?? selectedYear;
        }),
      ),
    );
  }

  Widget _monthPicker() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Color(0xFFFFF3E0),
            Colors.white,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A00).withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFFF8A00).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: DropdownButton<int>(
        value: selectedMonth,
        isExpanded: true,
        underline: Container(),
        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFFF8A00)),
        items: List.generate(12, (i) => i + 1)
            .map((m) => DropdownMenuItem(
          value: m,
          child: Text(
            months[m - 1],
            style: const TextStyle(color: Colors.black87),
          ),
        ))
            .toList(),
        onChanged: (v) => setState(() {
          selectedMonth = v ?? selectedMonth;
        }),
      ),
    );
  }

  Widget _dayPicker() {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDay ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFFFF8A00),
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black,
                ),
                dialogBackgroundColor: Colors.white,
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          setState(() {
            selectedDay = picked;
            selectedYear = picked.year;
            selectedMonth = picked.month;
          });
        }
      },
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Color(0xFFFFF3E0),
              Colors.white,
            ],
            stops: [0.0, 0.5, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF8A00).withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: const Color(0xFFFF8A00).withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF8A00), Color(0xFFFFA726)],
                  stops: [0.0, 1.0],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.calendar_today, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedDay == null
                    ? 'Choose day'
                    : '${selectedDay!.day} ${DateFormat('MMM').format(selectedDay!)} ${selectedDay!.year}',
                style: TextStyle(
                  color: selectedDay == null ? Colors.grey.shade600 : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}