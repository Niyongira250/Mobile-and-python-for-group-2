import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'order_page.dart';
import 'pay_page.dart';
import 'wallet_page.dart';
import 'receive_page.dart';
import 'profile_overlay.dart';
import 'services/data_service.dart';
import 'merchanthome_page.dart';
import 'package:intl/intl.dart';
import 'dart:math';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isBalanceVisible = false;
  late TextEditingController _pinController;
  bool _isPinLoading = false;
  String _pinError = '';
  double? _userBalance;

  // NEW: Weekly spending data
  List<Map<String, dynamic>> _weeklySpending = [];
  bool _isLoadingSpending = false;

  final Map<String, Map<String, String>> _languages = {
    'Eng': {'name': 'English', 'asset': 'assets/images/usa.png'},
    'Fra': {'name': 'Français', 'asset': 'assets/images/france.png'},
    'Kiny': {'name': 'Kinyarwanda', 'asset': 'assets/images/rwanda.png'},
  };

  String _selectedLanguage = 'Eng';

  @override
  void initState() {
    super.initState();
    _pinController = TextEditingController();
    _checkUserAndLoadData();
    // Fetch balance in background but don't show it yet
    _fetchUserBalance();
    // Load weekly spending data
    _loadWeeklySpending();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  // NEW: Load weekly spending data
  Future<void> _loadWeeklySpending() async {
    try {
      setState(() {
        _isLoadingSpending = true;
      });

      final user = getCurrentUser();
      if (user == null || user['email'] == null) {
        _setMockSpendingData();
        return;
      }

      final email = user['email'] as String;
      print('💰 Loading spending data for: $email');

      // Get user transactions
      final uri = Uri.parse("http://localhost:8000/api/get-user-transactions/")
          .replace(queryParameters: {
        'email': email,
      });

      final response = await http.get(
        uri,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> transactions = data['transactions'] ?? [];

        print('📊 Found ${transactions.length} transactions for spending analysis');

        // Process transactions for last 5 days
        final now = DateTime.now();
        final Map<String, double> dayAmounts = {};

        // Initialize last 5 days with 0 amounts
        for (int i = 0; i < 5; i++) {
          final date = now.subtract(Duration(days: i));
          final dayKey = _getDayOfWeek(date);
          dayAmounts[dayKey] = 0.0;
        }

        // Calculate amounts for each day
        for (var trans in transactions) {
          if (trans is Map) {
            try {
              final dateStr = trans['date']?.toString();
              if (dateStr != null) {
                DateTime? transDate;

                // Parse date string
                if (dateStr.contains(' ')) {
                  // Format: "01 January 2024 14:30"
                  try {
                    transDate = DateFormat('dd MMMM yyyy HH:mm').parse(dateStr);
                  } catch (e) {
                    transDate = DateTime.tryParse(dateStr);
                  }
                } else {
                  transDate = DateTime.tryParse(dateStr);
                }

                if (transDate != null) {
                  // Check if transaction is within last 5 days
                  final difference = now.difference(transDate);
                  if (difference.inDays <= 5) {
                    final dayKey = _getDayOfWeek(transDate);
                    final type = trans['type']?.toString();
                    final amount = double.tryParse(trans['amount']?.toString() ?? '0') ?? 0.0;

                    // Only count "sent" transactions (money spent)
                    if (type == 'sent') {
                      dayAmounts.update(dayKey, (value) => value + amount, ifAbsent: () => amount);
                    }
                  }
                }
              }
            } catch (e) {
              print('⚠️ Error parsing transaction for spending: $e');
            }
          }
        }

        // Calculate average
        double total = 0.0;
        int count = 0;

        final spendingList = [];

        // Get the last 5 days in chronological order (oldest to newest)
        for (int i = 4; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final dayKey = _getDayOfWeek(date);
          final dayName = _getShortDayName(date);
          final amount = dayAmounts[dayKey] ?? 0.0;

          total += amount;
          if (amount > 0) count++;

          spendingList.add({
            'day': dayName,
            'amount': amount,
            'date': date,
          });
        }

        final average = count > 0 ? total / count : 0.0;

        // Calculate max amount for scaling
        double maxAmount = 0.0;
        for (var item in spendingList) {
          final double amount = item['amount'] as double;
          if (amount > maxAmount) maxAmount = amount;
        }

        // If maxAmount is 0 (no spending), set to average to avoid division by zero
        if (maxAmount == 0) maxAmount = average > 0 ? average : 1.0;

        // Add height based on comparison to average
        final List<Map<String, dynamic>> weeklyData = [];
        for (var item in spendingList) {
          final double amount = item['amount'] as double;
          final String day = item['day'] as String;
          final DateTime date = item['date'] as DateTime;

          // Calculate height based on amount relative to max amount
          final double heightPercentage = maxAmount > 0 ? (amount / maxAmount) : 0.0;
          // Height between 20 and 150
          final double height = (heightPercentage * 130) + 20;

          // Determine color based on comparison to average
          Color color;
          if (amount == 0) {
            color = Colors.grey.shade400;
          } else if (amount > average * 1.5) {
            color = Colors.red.shade400; // Much higher than average
          } else if (amount > average) {
            color = Colors.orange; // Higher than average
          } else if (amount > average * 0.5) {
            color = Colors.yellow.shade700; // Close to average
          } else {
            color = Colors.green.shade400; // Lower than average
          }

          weeklyData.add({
            'day': day,
            'fullDay': _getFullDayName(date),
            'amount': amount,
            'formattedAmount': _formatCurrency(amount),
            'height': height,
            'color': color,
            'isAboveAverage': amount > average,
            'date': date,
          });
        }

        setState(() {
          _weeklySpending = weeklyData;
          _isLoadingSpending = false;
        });

        print('✅ Loaded ${_weeklySpending.length} days of spending data');
        print('📈 Average spending: ${_formatCurrency(average)}');
      } else {
        print('❌ Failed to load spending data: ${response.statusCode}');
        _setMockSpendingData();
      }
    } catch (e) {
      print('❌ Error loading weekly spending: $e');
      _setMockSpendingData();
    }
  }

  // Helper to get day of week as string (Monday, Tuesday, etc.)
  String _getDayOfWeek(DateTime date) {
    return DateFormat('EEEE').format(date); // Returns "Monday", "Tuesday", etc.
  }

  // Helper to get short day name (Mon, Tue, etc.)
  String _getShortDayName(DateTime date) {
    return DateFormat('EEE').format(date); // Returns "Mon", "Tue", etc.
  }

  // Helper to get full day name (Monday, Tuesday, etc.)
  String _getFullDayName(DateTime date) {
    return DateFormat('EEEE').format(date); // Returns "Monday", "Tuesday", etc.
  }

  // Mock spending data for fallback
  void _setMockSpendingData() {
    final List<Map<String, dynamic>> mockData = [];
    final now = DateTime.now();
    final random = Random();

    // Generate mock data for last 5 days
    for (int i = 4; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayName = _getShortDayName(date);
      final amount = (random.nextInt(40) + 1) * 1000.0; // Random amount between 1000-40000

      mockData.add({
        'day': dayName,
        'fullDay': _getFullDayName(date),
        'amount': amount,
        'formattedAmount': _formatCurrency(amount),
        'height': 50.0 + (amount / 40000 * 100), // Scale height
        'color': Colors.orange,
        'isAboveAverage': amount > 20000,
        'date': date,
      });
    }

    setState(() {
      _weeklySpending = mockData;
      _isLoadingSpending = false;
    });
  }

  // Format currency helper
  String _formatCurrency(double amount) {
    return '${NumberFormat('#,##0').format(amount)} FRW';
  }

  // NEW: Helper method to format currency in compact form
  String _formatCompactCurrency(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M FRW';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K FRW';
    }
    return '${amount.toInt()} FRW';
  }

  // NEW: Calculate total spent
  double _calculateTotalSpent() {
    double total = 0.0;
    for (var item in _weeklySpending) {
      final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
      total += amount;
    }
    return total;
  }

  // NEW: Calculate average spent
  double _calculateAverageSpent() {
    if (_weeklySpending.isEmpty) return 0.0;

    double total = 0.0;
    int count = 0;
    for (var item in _weeklySpending) {
      final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
      total += amount;
      if (amount > 0) count++;
    }

    return count > 0 ? total / count : 0.0;
  }

  // NEW: Get peak day amount
  double _getPeakDayAmount() {
    if (_weeklySpending.isEmpty) return 0.0;

    double peak = 0.0;
    for (var item in _weeklySpending) {
      final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
      if (amount > peak) {
        peak = amount;
      }
    }
    return peak;
  }

  // NEW: Build stat item widget
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: color,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // NEW: Build legend item widget
  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color orange = Color(0xFFFF8A00);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: orange,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                'assets/images/logo.png',
                height: 32,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedLanguage,
                icon: const Icon(
                  Icons.arrow_drop_down,
                  color: Colors.white,
                ),
                dropdownColor: orange,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedLanguage = value);
                  }
                },
                items: _languages.keys.map((key) {
                  final lang = _languages[key]!;
                  return DropdownMenuItem<String>(
                    value: key,
                    child: Row(
                      children: [
                        Image.asset(lang['asset']!, width: 22, height: 22),
                        const SizedBox(width: 10),
                        Text(
                          lang['name']!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                selectedItemBuilder: (BuildContext context) {
                  return _languages.keys.map((key) {
                    final lang = _languages[key]!;
                    return Row(
                      children: [
                        Image.asset(lang['asset']!, width: 28, height: 28),
                        const SizedBox(width: 8),
                        Text(
                          lang['name']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
              ),
            ),
            const Spacer(),
            Stack(
              children: [
                IconButton(
                  onPressed: () async {
                    await _loadNotifications();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Notifications refreshed'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.notifications,
                    color: Colors.white,
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
                setState(() {}); // Refresh profile image
              },
              child: Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 8, right: 12),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(30),
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
                          );
                        }
                        return const CircleAvatar(
                          radius: 18,
                          backgroundImage: AssetImage(
                            'assets/images/profile.jpeg',
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 8,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF8A00), Color(0xFFFFA500)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _getGreetingData()['icon'],
                                    color: _getGreetingData()['iconColor'],
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  Builder(
                                    builder: (context) {
                                      final user = getCurrentUser();
                                      final username = user?['username']?.toString() ?? 'User';
                                      return Text(
                                        '${_getGreetingData()['greeting']}, $username',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${DateTime.now().day} ${_getMonthName(DateTime.now().month)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Balance',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () {
                          if (!_isBalanceVisible) {
                            _showBalancePinDialog();
                          }
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _isBalanceVisible
                                    ? (_userBalance != null
                                    ? '${_userBalance!.toInt().toStringAsFixed(0)} FRW'
                                    : '0 FRW')
                                    : '•••••• FRW',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (!_isBalanceVisible)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.visibility,
                                        color: Colors.white, size: 16),
                                    SizedBox(width: 4),
                                    Text(
                                      'View',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_isBalanceVisible)
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _isBalanceVisible = false;
                                  });
                                },
                                icon:
                                const Icon(Icons.visibility_off, color: Colors.white),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                iconSize: 20,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // UPDATED: Weekly Transactions Header (Horizontal)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Weekly Spending Trend',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Last 5 days spending overview',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: _loadWeeklySpending,
                      icon: Icon(
                        _isLoadingSpending ? Icons.refresh : Icons.refresh,
                        color: _isLoadingSpending ? Colors.grey : orange,
                      ),
                      tooltip: 'Refresh spending data',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // UPDATED: HORIZONTAL Spending Card - FIXED OVERFLOW
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (_isLoadingSpending)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_weeklySpending.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text(
                            'No spending data available',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                      // HORIZONTAL BARS CONTAINER - FIXED LAYOUT
                        Column(
                          children: [
                            // Bars Container with fixed height
                            SizedBox(
                              height: 220, // Increased height to prevent overflow
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: _weeklySpending.map((data) {
                                  try {
                                    final day = data['day'] as String? ?? '--';
                                    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                                    final formattedAmount = data['formattedAmount'] as String? ?? '0 FRW';
                                    final height = (data['height'] as num?)?.toDouble() ?? 0.0;
                                    final color = data['color'] as Color? ?? Colors.grey;
                                    final isAboveAverage = data['isAboveAverage'] as bool? ?? false;
                                    final fullDay = data['fullDay'] as String? ?? '--';

                                    // Calculate actual bar height (capped at 100 to prevent overflow)
                                    final double barHeight = (height.clamp(20.0, 100.0));

                                    return Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                        child: SizedBox(
                                          height: 220, // Fixed container height
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              // Amount label above bar - FIXED: Limited space
                                              if (amount > 0)
                                                Container(
                                                  constraints: const BoxConstraints(
                                                    maxHeight: 40, // Limit height
                                                  ),
                                                  child: Padding(
                                                    padding: const EdgeInsets.only(bottom: 4.0),
                                                    child: Text(
                                                      _formatCompactCurrency(amount),
                                                      style: TextStyle(
                                                        fontSize: 9, // Smaller font
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.grey.shade700,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                              // The bar itself
                                              Container(
                                                width: 36, // Slightly smaller width
                                                height: barHeight,
                                                decoration: BoxDecoration(
                                                  borderRadius: const BorderRadius.only(
                                                    topLeft: Radius.circular(6),
                                                    topRight: Radius.circular(6),
                                                  ),
                                                  gradient: LinearGradient(
                                                    begin: Alignment.bottomCenter,
                                                    end: Alignment.topCenter,
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
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  children: [
                                                    // Day label inside bar (top) - FIXED: Smaller font
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 4.0),
                                                      child: Text(
                                                        day,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    // Average indicator line - MOVED: Inside bar only when needed
                                                    if (isAboveAverage && amount > 0 && barHeight > 40)
                                                      Container(
                                                        margin: const EdgeInsets.only(top: 16),
                                                        height: 2,
                                                        width: 40,
                                                        color: Colors.white.withOpacity(0.8),
                                                        child: const Center(
                                                          child: Icon(
                                                            Icons.arrow_drop_up,
                                                            size: 10,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              // Full day name below bar - FIXED: Limited space
                                              Container(
                                                constraints: const BoxConstraints(
                                                  maxHeight: 40,
                                                ),
                                                child: Padding(
                                                  padding: const EdgeInsets.only(top: 4.0),
                                                  child: Text(
                                                    fullDay,
                                                    style: TextStyle(
                                                      fontSize: 9, // Smaller font
                                                      color: Colors.grey.shade600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                              // Above average indicator - FIXED: Smaller and limited space
                                              if (isAboveAverage && amount > 0)
                                                Container(
                                                  margin: const EdgeInsets.only(top: 2),
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 2,
                                                    vertical: 1,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.shade50,
                                                    borderRadius: BorderRadius.circular(3),
                                                    border: Border.all(
                                                      color: Colors.red.shade100,
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '↑',
                                                    style: TextStyle(
                                                      fontSize: 7,
                                                      color: Colors.red.shade700,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              // Spacer to fill remaining space
                                              const Spacer(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    print('Error rendering horizontal bar: $e');
                                    return Expanded(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        height: 220,
                                        child: const Column(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            SizedBox(height: 20),
                                            Text('Error', style: TextStyle(fontSize: 8)),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                }).toList(),
                              ),
                            ),

                            // Average Line Indicator - MOVED: Below bars
                            Container(
                              margin: const EdgeInsets.only(top: 16, bottom: 12),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade100),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 12,
                                    height: 2,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Average Line',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade800,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 12,
                                    height: 2,
                                    color: Colors.blue,
                                  ),
                                ],
                              ),
                            ),

                            // Summary Statistics
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  // Total Spent
                                  _buildStatItem(
                                    icon: Icons.attach_money,
                                    label: 'Total Spent',
                                    value: _formatCompactCurrency(_calculateTotalSpent()),
                                    color: Colors.orange,
                                  ),
                                  // Average Daily
                                  _buildStatItem(
                                    icon: Icons.trending_up,
                                    label: 'Daily Avg',
                                    value: _formatCompactCurrency(_calculateAverageSpent()),
                                    color: Colors.blue,
                                  ),
                                  // Highest Day
                                  _buildStatItem(
                                    icon: Icons.arrow_upward,
                                    label: 'Peak Day',
                                    value: _formatCompactCurrency(_getPeakDayAmount()),
                                    color: Colors.red,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 12),

                      // Compact Legend
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Color Guide:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              children: [
                                _buildLegendItem(Colors.red.shade400, 'High'),
                                _buildLegendItem(Colors.orange, 'Above Avg'),
                                _buildLegendItem(Colors.yellow.shade700, 'Average'),
                                _buildLegendItem(Colors.green.shade400, 'Below Avg'),
                                _buildLegendItem(Colors.grey.shade400, 'No Spend'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Notifications header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent Alerts (${_notifications.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Stay updated on your account',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        onPressed: _loadNotifications,
                        icon: Icon(
                          Icons.refresh,
                          size: 20,
                          color: _isLoading ? Colors.grey : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Dynamic Notification cards - SAFE ACCESS
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_hasError)
                  _errorCard()
                else if (_notifications.isEmpty)
                    _emptyNotificationsCard()
                  else
                    ..._notifications.map((notification) {
                      try {
                        final title = notification['title']?.toString() ?? 'Notification';
                        final content = notification['content']?.toString() ?? '';
                        final urgency = notification['urgency']?.toString() ?? 'low';
                        final date = notification['date'];

                        return Column(
                          children: [
                            _notificationCard(
                              title: title,
                              subtitle: content,
                              urgency: urgency,
                              time: _formatNotificationTime(date),
                              buttonLabel:
                              urgency.toLowerCase() == 'high' ? 'Take Action' : null,
                            ),
                            const SizedBox(height: 12),
                          ],
                        );
                      } catch (e) {
                        print('Error rendering notification: $e');
                        return Container(); // Return empty container on error
                      }
                    }).toList(),

                const SizedBox(height: 90),
              ],
            ),
          ),
        ),
      ),
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

  // Keep all your existing methods below (they remain unchanged):
  Future<void> _checkUserAndLoadData() async {
    final user = getCurrentUser();

    if (user != null && user['type'] == 'merchant') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Merchants should use merchant dashboard'),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MerchantHomePage()),
        );
      });
    } else {
      await _loadNotifications();
    }
  }

  Future<bool> _verifyPin(String pin) async {
    try {
      final user = getCurrentUser();
      if (user == null || user['email'] == null) {
        print('❌ No user found');
        return false;
      }

      final email = user['email'] as String;
      print('🔍 Verifying PIN for email: $email');

      final response = await http.post(
        Uri.parse("http://localhost:8000/api/verify-pin/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'email': email,
          'pin': pin,
        }),
      );

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        print('📊 Response data: $data');

        // Check for 'success' field (could be boolean or string)
        final dynamic success = data['success'];

        if (success is bool) {
          return success;
        } else if (success is String) {
          return success.toLowerCase() == 'true';
        } else if (success is int) {
          return success == 1;
        }

        // Try to find success in other possible fields
        if (data.containsKey('verified') && data['verified'] == true) {
          return true;
        }
        if (data.containsKey('status') && data['status'] == 'success') {
          return true;
        }

        return false;
      } else {
        print('❌ API Error: ${response.body}');
        return false;
      }
    } catch (e) {
      print('🔥 Error verifying PIN: $e');
      return false;
    }
  }

  Future<void> _fetchUserBalance() async {
    try {
      final user = getCurrentUser();
      if (user == null || user['email'] == null) {
        return;
      }

      final response = await http.get(
        Uri.parse("http://localhost:8000/api/user-details/?email=${user['email']}"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Balance response: $data');

        // Try to get balance from response
        final dynamic balance = data['balance'] ??
            data['account_balance'] ??
            data['accountBalance'];

        if (balance != null) {
          double balanceValue = 0.0;

          // Convert to double if it's not already
          if (balance is int) {
            balanceValue = balance.toDouble();
          } else if (balance is double) {
            balanceValue = balance;
          } else if (balance is String) {
            final parsed = double.tryParse(balance);
            if (parsed != null) {
              balanceValue = parsed;
            }
          }

          print('💰 Setting balance to: $balanceValue');
          if (mounted) {
            setState(() {
              _userBalance = balanceValue;
            });
          }
        } else {
          print('⚠️ No balance found in response');
          if (mounted) {
            setState(() {
              _userBalance = 0.0;
            });
          }
        }
      } else {
        print('❌ Failed to fetch balance, status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching balance: $e');
    }
  }

  Future<void> _loadNotifications() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      final user = getCurrentUser();
      if (user == null || user['email'] == null) {
        // Use mock data for testing if no user
        _loadMockNotifications();
        return;
      }

      final email = user['email'] as String;
      final uri = Uri.parse("http://localhost:8000/api/notifications/?email=$email");

      print('🔍 Loading notifications from: $uri');

      final response = await http.get(
        uri,
        headers: {"Content-Type": "application/json"},
      );

      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        print('📊 Response data: $data');

        // Safely extract notifications
        final dynamic notificationsData = data['notifications'] ?? [];

        // Ensure it's a List and convert to proper type
        List<Map<String, dynamic>> parsedNotifications = [];

        if (notificationsData is List) {
          for (var item in notificationsData) {
            if (item is Map<String, dynamic>) {
              parsedNotifications.add(item);
            } else if (item is Map) {
              // Convert dynamic map to typed map
              parsedNotifications.add(Map<String, dynamic>.from(item));
            }
          }
        }

        print('✅ Parsed ${parsedNotifications.length} notifications');

        // Safely get unread count
        final dynamic unreadCount = data['unread_count'];
        final int finalUnreadCount = (unreadCount is int)
            ? unreadCount
            : parsedNotifications.length;

        setState(() {
          _notifications = parsedNotifications;
          _unreadCount = finalUnreadCount;
          _isLoading = false;
          _hasError = false;
        });
      } else {
        print('❌ API Error: ${response.body}');
        // Fall back to mock data for testing
        _loadMockNotifications();
      }
    } catch (e) {
      print('🔥 Error loading notifications: $e');
      // Fall back to mock data for testing
      _loadMockNotifications();
    }
  }

  void _loadMockNotifications() {
    // Mock data for testing
    setState(() {
      _notifications = [
        {
          'title': 'Welcome to VubaPay!',
          'content': 'Thank you for joining VubaPay. Start by adding funds to your wallet.',
          'urgency': 'low',
          'date': DateTime.now().subtract(const Duration(hours: 1)).toString(),
          'designated_to': 'user'
        },
        {
          'title': 'Security Update',
          'content': 'We have enhanced our security features. Please update your app.',
          'urgency': 'medium',
          'date': DateTime.now().subtract(const Duration(days: 1)).toString(),
          'designated_to': 'all'
        },
        {
          'title': 'Payment Successful',
          'content': 'Your payment of 15,000 FRW to Kigali Market was successful.',
          'urgency': 'low',
          'date': DateTime.now().subtract(const Duration(days: 2)).toString(),
          'designated_to': 'user'
        },
      ];
      _unreadCount = _notifications.length;
      _isLoading = false;
      _hasError = false;
    });
  }

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
        return Colors.red.shade600;
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
        return Colors.red.shade50;
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

  void _showBalancePinDialog() {
    _pinController.clear();
    _pinError = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          const Color orange = Color(0xFFFF8A00);
          const Color lightOrange = Color(0xFFFFF3E0);

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: orange,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: const Text(
                'Enter PIN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your 6-digit PIN to view your balance',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: lightOrange,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: orange, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: orange, width: 2),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.red, width: 1),
                      ),
                      errorText: _pinError.isNotEmpty ? _pinError : null,
                      hintText: '••••••',
                      hintStyle: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        color: Colors.grey.shade400,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isPinLoading)
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(orange),
                    ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isPinLoading
                            ? null
                            : () async {
                          if (_pinController.text.length != 6) {
                            setDialogState(() {
                              _pinError = 'PIN must be 6 digits';
                            });
                            return;
                          }

                          setDialogState(() {
                            _isPinLoading = true;
                            _pinError = '';
                          });

                          final isValid = await _verifyPin(_pinController.text);
                          print('✅ PIN verification result: $isValid');

                          setDialogState(() {
                            _isPinLoading = false;
                          });

                          if (isValid) {
                            // Close the dialog
                            Navigator.pop(dialogContext);

                            // Update the main state
                            if (mounted) {
                              print('🔓 Setting balance visible to true');
                              setState(() {
                                _isBalanceVisible = true;
                              });

                              // Force a rebuild immediately
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() {});
                                }
                              });

                              // Auto-hide balance after 30 seconds
                              Future.delayed(const Duration(seconds: 30), () {
                                if (mounted && _isBalanceVisible) {
                                  print('🔒 Auto-hiding balance after 30 seconds');
                                  setState(() {
                                    _isBalanceVisible = false;
                                  });
                                }
                              });
                            }
                          } else {
                            setDialogState(() {
                              _pinError = 'Invalid PIN. Please try again.';
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        child: _isPinLoading
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : const Text(
                          'View Balance',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);

    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const OrderPage()),
      );
    }
    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PayPage()),
      );
    }
    if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WalletPage()),
      );
    }
    if (index == 4) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ReceivePage()),
      );
    }
  }

  Map<String, dynamic> _getGreetingData() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return {
        'greeting': 'Good morning',
        'icon': Icons.wb_sunny,
        'iconColor': Colors.yellow[300],
      };
    } else if (hour >= 12 && hour < 18) {
      return {
        'greeting': 'Good afternoon',
        'icon': Icons.wb_sunny,
        'iconColor': Colors.amber[300],
      };
    } else {
      return {
        'greeting': 'Good night',
        'icon': Icons.nights_stay,
        'iconColor': Colors.blue[200],
      };
    }
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }

  Widget _emptyNotificationsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.notifications_off,
            size: 40,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 10),
          const Text(
            'No notifications yet',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'You\'re all caught up!',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _loadNotifications,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade100,
            ),
            child: const Text(
              'Refresh',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            size: 40,
            color: Colors.red.shade400,
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
          const Text(
            'Please check your connection and try again',
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _loadNotifications,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade100,
            ),
            child: const Text(
              'Retry',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notificationCard({
    required String title,
    required String subtitle,
    required String urgency,
    required String time,
    String? buttonLabel,
  }) {
    final bgColor = _getUrgencyBackgroundColor(urgency);
    final iColor = _getUrgencyColor(urgency);
    final icon = _getNotificationIcon(urgency);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iColor.withOpacity(0.2),
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
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                time,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
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
          if (buttonLabel != null) ...[
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Action triggered for: $title'),
                      backgroundColor: iColor,
                    ),
                  );
                },
                child: Text(
                  buttonLabel,
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
}