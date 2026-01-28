import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'home_page.dart';
import 'order_page.dart';
import 'pay_page.dart';
import 'receive_page.dart';
import 'services/data_service.dart';
import 'profile_overlay.dart';

class MerchantWallet extends StatefulWidget {
  const MerchantWallet({super.key});

  @override
  State<MerchantWallet> createState() => _MerchantWalletState();
}

class _MerchantWalletState extends State<MerchantWallet> {
  DateTime? selectedDate;
  List<dynamic> transactions = [];
  double? balance;
  String username = 'Merchant';
  bool isLoading = true;
  bool isRefreshing = false;
  String? selectedYear;
  String? selectedMonth;
  String? selectedDay;
  List<FlSpot> monthlySpots = [];
  List<FlSpot> weeklySpots = [];
  double maxGraphValue = 0;

  // Balance visibility states
  bool _isBalanceVisible = false;
  TextEditingController _pinController = TextEditingController();
  bool _isPinLoading = false;
  String _pinError = '';

  @override
  void initState() {
    super.initState();
    _fetchMerchantTransactions();
    _initializeGraphData();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
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

        final dynamic success = data['success'];

        if (success is bool) {
          return success;
        } else if (success is String) {
          return success.toLowerCase() == 'true';
        } else if (success is int) {
          return success == 1;
        }

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

  Future<void> _fetchMerchantTransactions() async {
    setState(() => isLoading = true);

    try {
      final currentUser = getCurrentUser();
      if (currentUser == null || currentUser['type'] != 'merchant') {
        throw Exception('Merchant not logged in');
      }

      final email = currentUser['email'];
      if (email == null) {
        throw Exception('Merchant email not found');
      }

      final data = await getUserTransactions(
        email: email,
        year: selectedYear,
        month: selectedMonth,
        day: selectedDay,
      );

      setState(() {
        transactions = data['transactions'] as List<dynamic>? ?? [];
        balance = (data['balance'] as num?)?.toDouble();
        username = data['username']?.toString() ?? currentUser['username'] ?? 'Merchant';
        isLoading = false;
        isRefreshing = false;
      });

      // Update graph data based on transactions
      _updateGraphData();
    } catch (e) {
      print('❌ Error fetching merchant transactions: $e');
      setState(() {
        transactions = [];
        isLoading = false;
        isRefreshing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load transactions: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _initializeGraphData() {
    // Initialize with sample data
    monthlySpots = [
      FlSpot(1, 700000),
      FlSpot(2, 350000),
      FlSpot(3, 780000),
      FlSpot(4, 450000),
      FlSpot(5, 900000),
      FlSpot(6, 600000),
    ];

    weeklySpots = [
      FlSpot(1, 150000),
      FlSpot(2, 80000),
      FlSpot(3, 200000),
      FlSpot(4, 120000),
      FlSpot(5, 300000),
      FlSpot(6, 180000),
      FlSpot(7, 250000),
    ];

    maxGraphValue = 1000000;
  }

  void _updateGraphData() {
    // Always ensure spots lists are not null
    monthlySpots = monthlySpots;
    weeklySpots = weeklySpots;

    if (transactions.isEmpty) {
      // If no transactions, use default data but ensure lists are not empty
      if (monthlySpots.isEmpty) {
        monthlySpots = [FlSpot(0, 0)];
      }
      if (weeklySpots.isEmpty) {
        weeklySpots = [FlSpot(0, 0)];
      }
      maxGraphValue = 1000000;
      setState(() {});
      return;
    }

    // Group transactions by month for monthly graph
    final Map<int, double> monthlyData = {};
    final Map<int, double> weeklyData = {};

    for (var trans in transactions) {
      final dateString = trans['date'];
      if (dateString != null) {
        try {
          final parts = dateString.split(' ');
          if (parts.length >= 4) {
            final day = int.tryParse(parts[0]) ?? 1;
            final month = _getMonthNumber(parts[1]);
            final year = int.tryParse(parts[2]) ?? DateTime.now().year;

            // Monthly data
            final monthKey = month;
            final amount = trans['amount']?.toDouble() ?? 0;
            monthlyData[monthKey] = (monthlyData[monthKey] ?? 0) + amount;

            // Weekly data (simplified - using day of month)
            final weekKey = ((day - 1) ~/ 7) + 1;
            weeklyData[weekKey] = (weeklyData[weekKey] ?? 0) + amount;
          }
        } catch (e) {
          print('Error parsing date: $e');
        }
      }
    }

    // Update monthly spots - ensure at least one spot
    monthlySpots = monthlyData.entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
        .toList();

    if (monthlySpots.isEmpty) {
      monthlySpots = [FlSpot(0, 0)];
    }

    // Update weekly spots - ensure at least one spot
    weeklySpots = weeklyData.entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
        .toList();

    if (weeklySpots.isEmpty) {
      weeklySpots = [FlSpot(0, 0)];
    }

    // Update max value for graph
    final allValues = [...monthlyData.values, ...weeklyData.values];
    maxGraphValue = allValues.isNotEmpty ?
    allValues.reduce((a, b) => a > b ? a : b) * 1.2 :
    1000000;

    setState(() {});
  }

  int _getMonthNumber(String monthName) {
    const months = {
      'January': 1, 'February': 2, 'March': 3, 'April': 4,
      'May': 5, 'June': 6, 'July': 7, 'August': 8,
      'September': 9, 'October': 10, 'November': 11, 'December': 12,
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'Maey': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
    };
    return months[monthName] ?? 1;
  }

  Future<void> _onRefresh() async {
    setState(() => isRefreshing = true);
    await _fetchMerchantTransactions();
  }

  void _clearFilters() {
    setState(() {
      selectedYear = null;
      selectedMonth = null;
      selectedDay = null;
      selectedDate = null;
    });
    _fetchMerchantTransactions();
  }

  void _onNavTap(int index) {
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
    if (index == 4) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReceivePage()),
      );
    }
  }

  Widget _transactionItem(Map<String, dynamic> trans) {
    final isReceived = trans['type'] == 'received';
    final otherParty = trans['other_party']?.toString() ?? 'Unknown User';
    final otherPartyType = trans['other_party_type']?.toString() ?? 'user';
    final amount = trans['amount']?.toDouble() ?? 0.0;
    final total = trans['total']?.toDouble() ?? 0.0;
    final dateTime = trans['date']?.toString() ?? '';
    final status = trans['status']?.toString() ?? 'completed';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: isReceived
              ? [const Color(0xFFB2FFDA), const Color(0xFF5BE7A9)]
              : [const Color(0xFFFF9A6C), const Color(0xFFFF6E7F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isReceived ? Icons.call_received : Icons.call_made, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isReceived ? "Received from" : "Sent to",
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    Text(
                      otherParty,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Account type badge
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: otherPartyType == 'merchant'
                            ? Colors.orange.withOpacity(0.3)
                            : Colors.blue.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: otherPartyType == 'merchant'
                              ? Colors.orange
                              : Colors.blue,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        otherPartyType == 'merchant' ? 'Merchant' : 'User',
                        style: TextStyle(
                          fontSize: 10,
                          color: otherPartyType == 'merchant'
                              ? Colors.orange
                              : Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${isReceived ? '+' : '-'}${amount.toStringAsFixed(0)} RWF",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isReceived ? Colors.green.shade900 : Colors.red.shade900,
                    ),
                  ),
                  Text(
                    dateTime,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: status == 'success'
                      ? Colors.green.withOpacity(0.8)
                      : Colors.orange.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!isReceived)
                Text(
                  "Fee: ${((total - amount) ?? 0).toStringAsFixed(0)} RWF",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
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
                            Navigator.pop(dialogContext);

                            if (mounted) {
                              print('🔓 Setting balance visible to true');
                              setState(() {
                                _isBalanceVisible = true;
                              });

                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() {});
                                }
                              });

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

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _bottomBar(),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            _balanceCard(),

            /// EVERYTHING BELOW SCROLLS
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      /// DATE FILTERS
                      _filterSection(),
                      const SizedBox(height: 15),

                      /// GRAPH SECTION
                      _graphCard(),
                      const SizedBox(height: 20),

                      /// TRANSACTIONS HEADER
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Transaction History",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              "${transactions.length} transactions",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      /// LOADING INDICATOR
                      if (isLoading)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Column(
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(orange),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Loading transactions...',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      else if (transactions.isEmpty)
                        _noTransactionsView()
                      else
                      /// TRANSACTIONS LIST
                        Column(
                          children: [
                            ..._buildGroupedTransactions(),
                            const SizedBox(height: 20),
                            _moreSection(),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // ================= HEADER =================
  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFB74D), Color(0xFFFF8A00)],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            username,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
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
                  child: Icon(Icons.store, color: Colors.orange),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ================= BALANCE CARD WITH VIEW BUTTON =================
  Widget _balanceCard() {
    final currentBalance = balance ?? 0.0;
    final progressValue = currentBalance > 1000000 ? 1.0 : currentBalance / 1000000;

    return GestureDetector(
      onTap: () {
        if (!_isBalanceVisible) {
          _showBalancePinDialog();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFE3C2), Color(0xFFFFC178)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 95,
                  width: 95,
                  child: CircularProgressIndicator(
                    value: progressValue,
                    strokeWidth: 12,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF16A085)),
                    backgroundColor: Colors.white30,
                  ),
                ),
                Container(
                  height: 60,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    size: 30,
                    color: Color(0xFFFF8A00),
                  ),
                )
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Account Balance",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isBalanceVisible
                              ? "${currentBalance.toStringAsFixed(0)} RWF"
                              : "•••••• RWF",
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!_isBalanceVisible)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.visibility,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'View',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
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
                          icon: const Icon(
                            Icons.visibility_off,
                            color: Colors.white,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "${transactions.length} transactions",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= FILTER SECTION =================
  Widget _filterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Filter Transactions",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _filterButton(
                  label: selectedYear ?? "Year",
                  onTap: () => _showYearPicker(context),
                  isActive: selectedYear != null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _filterButton(
                  label: selectedMonth != null
                      ? _getMonthName(int.parse(selectedMonth!))
                      : "Month",
                  onTap: () => _showMonthPicker(context),
                  isActive: selectedMonth != null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _filterButton(
                  label: selectedDay ?? "Day",
                  onTap: () => _showDayPicker(context),
                  isActive: selectedDay != null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (selectedYear != null || selectedMonth != null || selectedDay != null)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _fetchMerchantTransactions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      "Apply Filters",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _clearFilters,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    "Clear",
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _filterButton({
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFF8A00) : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? const Color(0xFFFF8A00) : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.arrow_drop_down,
              color: isActive ? Colors.white : Colors.black,
            ),
          ],
        ),
      ),
    );
  }

  void _showYearPicker(BuildContext context) {
    final now = DateTime.now();
    final years = List.generate(10, (index) => (now.year - 5 + index).toString());

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Select Year",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: years.length,
                  itemBuilder: (context, index) {
                    final year = years[index];
                    return ListTile(
                      title: Text(year),
                      trailing: selectedYear == year
                          ? const Icon(Icons.check, color: Color(0xFFFF8A00))
                          : null,
                      onTap: () {
                        setState(() {
                          selectedYear = year;
                          selectedMonth = null;
                          selectedDay = null;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMonthPicker(BuildContext context) {
    const months = [
      {"number": "1", "name": "January"},
      {"number": "2", "name": "February"},
      {"number": "3", "name": "March"},
      {"number": "4", "name": "April"},
      {"number": "5", "name": "May"},
      {"number": "6", "name": "June"},
      {"number": "7", "name": "July"},
      {"number": "8", "name": "August"},
      {"number": "9", "name": "September"},
      {"number": "10", "name": "October"},
      {"number": "11", "name": "November"},
      {"number": "12", "name": "December"},
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Select Month",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: months.length,
                  itemBuilder: (context, index) {
                    final month = months[index];
                    return ListTile(
                      title: Text(month['name']!),
                      trailing: selectedMonth == month['number']
                          ? const Icon(Icons.check, color: Color(0xFFFF8A00))
                          : null,
                      onTap: () {
                        setState(() {
                          selectedMonth = month['number'];
                          selectedDay = null;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDayPicker(BuildContext context) {
    final days = List.generate(31, (index) => (index + 1).toString());

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Select Day",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    crossAxisSpacing: 5,
                    mainAxisSpacing: 5,
                  ),
                  itemCount: days.length,
                  itemBuilder: (context, index) {
                    final day = days[index];
                    return GestureDetector(
                      onTap: () {
                        setState(() => selectedDay = day);
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: selectedDay == day
                              ? const Color(0xFFFF8A00)
                              : Colors.grey[200],
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          day,
                          style: TextStyle(
                            color: selectedDay == day
                                ? Colors.white
                                : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getMonthName(int month) {
    switch (month) {
      case 1: return 'Jan';
      case 2: return 'Feb';
      case 3: return 'Mar';
      case 4: return 'Apr';
      case 5: return 'May';
      case 6: return 'Jun';
      case 7: return 'Jul';
      case 8: return 'Aug';
      case 9: return 'Sep';
      case 10: return 'Oct';
      case 11: return 'Nov';
      case 12: return 'Dec';
      default: return 'Month';
    }
  }

  List<Widget> _buildGroupedTransactions() {
    final Map<String, List<dynamic>> grouped = {};

    for (var trans in transactions) {
      final date = trans['short_date'] ?? 'Unknown Date';
      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      grouped[date]!.add(trans);
    }

    return grouped.entries.map((entry) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
              entry.key,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ),
          ...entry.value.map((trans) => _transactionItem(trans)),
          const SizedBox(height: 10),
        ],
      );
    }).toList();
  }

  // ================= GRAPH CARD =================
  Widget _graphCard() {
    // Ensure monthlySpots is never null and has at least one element
    final chartSpots = monthlySpots.isNotEmpty ? monthlySpots : [FlSpot(0, 0)];

    return Container(
      height: 250,
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE3C0), Color(0xFFFFC089)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Sales Overview",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxGraphValue,
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: maxGraphValue / 5,
                      reservedSize: 40,
                      getTitlesWidget: (value, _) {
                        if (value == 0) return const Text("0", style: TextStyle(fontSize: 10));
                        final valueInK = value / 1000;
                        return Text(
                          "${valueInK.toStringAsFixed(valueInK >= 1000 ? 0 : 1)}${valueInK >= 1000 ? 'k' : 'k'}",
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, _) {
                        if (value.toInt() >= 1 && value.toInt() <= 12) {
                          return Text(
                            _getMonthName(value.toInt()),
                            style: const TextStyle(fontSize: 10),
                          );
                        }
                        return const Text("");
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    color: const Color(0xFF16A085),
                    barWidth: 3,
                    isCurved: true,
                    spots: chartSpots,
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF16A085).withOpacity(0.3),
                          const Color(0xFF16A085).withOpacity(0.1),
                        ],
                      ),
                    ),
                    dotData: const FlDotData(show: true),
                  )
                ],
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.3),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.3),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF16A085),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "Monthly Revenue",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noTransactionsView() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.store,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 20),
          const Text(
            "No transactions found",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            selectedYear != null || selectedMonth != null || selectedDay != null
                ? "Try changing your filters"
                : "Your transaction history will appear here",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _clearFilters,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A00),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              "Clear Filters",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ================= MORE SECTION =================
  Widget _moreSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('More transactions feature coming soon!'),
              backgroundColor: Color(0xFFFF8A00),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFFF8A00), width: 2),
          ),
          minimumSize: const Size(double.infinity, 50),
        ),
        child: const Text(
          "Load More Transactions",
          style: TextStyle(
            color: Color(0xFFFF8A00),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ================= BOTTOM BAR =================
  Widget _bottomBar() {
    return BottomNavigationBar(
      currentIndex: 3,
      selectedItemColor: Colors.orange,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      onTap: _onNavTap,
      items: [
        BottomNavigationBarItem(
          icon: Padding(
            padding: const EdgeInsets.all(4),
            child: Image.asset("assets/images/home.png", height: 26),
          ),
          label: "Home",
        ),
        BottomNavigationBarItem(
          icon: Padding(
            padding: const EdgeInsets.all(4),
            child: Image.asset("assets/images/order.png", height: 26),
          ),
          label: "Order",
        ),
        BottomNavigationBarItem(
          icon: Padding(
            padding: const EdgeInsets.all(4),
            child: Image.asset("assets/images/pay.png", height: 26),
          ),
          label: "Pay",
        ),
        BottomNavigationBarItem(
          icon: Padding(
            padding: const EdgeInsets.all(4),
            child: Image.asset("assets/images/wallet.png", height: 26),
          ),
          label: "Wallet",
        ),
        BottomNavigationBarItem(
          icon: Padding(
            padding: const EdgeInsets.all(4),
            child: Image.asset("assets/images/receive.png", height: 26),
          ),
          label: "Receive",
        ),
      ],
    );
  }
}