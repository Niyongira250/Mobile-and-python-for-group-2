import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:myapp/merchanthome_page.dart';
import 'merchant_wallet.dart';
import 'home_page.dart';
import 'order_page.dart';
import 'pay_page.dart';
import 'profile_overlay.dart';
import 'services/data_service.dart';
import 'package:http/http.dart' as http;

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  int _selectedIndex = 3;
  DateTime? selectedDate;
  List<dynamic> transactions = [];
  double balance = 0.0;
  String username = '';
  bool isLoading = true;
  bool isRefreshing = false;
  String? selectedYear;
  String? selectedMonth;
  String? selectedDay;

  // Balance visibility states
  bool _isBalanceVisible = false;
  TextEditingController _pinController = TextEditingController();
  bool _isPinLoading = false;
  String _pinError = '';

  @override
  void initState() {
    super.initState();
    final u = getCurrentUser();
    if (u != null && u['type'] == 'merchant') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Merchants should use the merchant wallet'),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MerchantWallet()),
        );
      });
    } else {
      _fetchUserTransactions();
    }
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

  Future<void> _fetchUserTransactions() async {
    setState(() => isLoading = true);

    try {
      final currentUser = getCurrentUser();
      if (currentUser == null) {
        throw Exception('No user logged in');
      }

      final email = currentUser['email'];
      if (email == null) {
        throw Exception('User email not found');
      }

      final data = await getUserTransactions(
        email: email,
        year: selectedYear,
        month: selectedMonth,
        day: selectedDay,
      );

      setState(() {
        transactions = data['transactions'] ?? [];
        balance = (data['balance'] as num?)?.toDouble() ?? 0.0;
        username = data['username']?.toString() ?? currentUser['username'] ?? 'User';
        isLoading = false;
        isRefreshing = false;
      });
    } catch (e) {
      print('❌ Error fetching transactions: $e');
      setState(() {
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

  void _onRefresh() {
    setState(() => isRefreshing = true);
    _fetchUserTransactions();
  }

  void _clearFilters() {
    setState(() {
      selectedYear = null;
      selectedMonth = null;
      selectedDay = null;
      selectedDate = null;
    });
    _fetchUserTransactions();
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);

    if (index == 0) {
      final u = getCurrentUser();
      if (u != null && u['type'] == 'merchant') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Merchants should use merchant dashboard'),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MerchantHomePage()),
        );
        return;
      }
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
      final u = getCurrentUser();
      if (u == null || u['type'] != 'merchant') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Merchant pages are only for merchants'),
          ),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MerchantHomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);
    const green = Color(0xFF4CAF50);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF2E9),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: orange,
        unselectedItemColor: Colors.grey,
        onTap: _onNavTap,
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
      body: SafeArea(
        child: Column(
          children: [
            // HEADER WITH USERNAME
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 15,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFF8A00), Color(0xFFFFB74D)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(25),
                  bottomRight: Radius.circular(25),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Welcome back,",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        username,
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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
                      setState(() {});
                    },
                    child: Builder(
                      builder: (context) {
                        final user = getCurrentUser();
                        final imgPath = user?['profilePicturePath'] as String?;
                        final provider = imageProviderFromPath(imgPath);
                        if (provider != null) {
                          return CircleAvatar(
                            radius: 22,
                            backgroundImage: provider,
                          );
                        }
                        return CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white,
                          child: Text(
                            username.isNotEmpty ? username[0].toUpperCase() : "U",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF8A00),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  _onRefresh();
                  await Future.delayed(const Duration(seconds: 1));
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // BALANCE CARD WITH VIEW BUTTON
                      _balanceCard(),
                      const SizedBox(height: 20),

                      // DATE FILTERS
                      _filterSection(),
                      const SizedBox(height: 20),

                      // TRANSACTIONS HEADER
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Transaction History",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
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
                      const SizedBox(height: 10),

                      // LOADING INDICATOR
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
                      // TRANSACTIONS LIST
                        Column(
                          children: [
                            ..._buildGroupedTransactions(),
                            const SizedBox(height: 20),
                            _fundWalletSection(),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // BALANCE CARD WITH VIEW BUTTON FEATURE
  Widget _balanceCard() {
    final progressValue = balance > 100000 ? 1.0 : balance / 100000;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A00), Color(0xFFFFB74D)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 110,
                width: 110,
                child: CircularProgressIndicator(
                  value: progressValue,
                  strokeWidth: 10,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                  backgroundColor: Colors.white.withOpacity(0.3),
                ),
              ),
              Container(
                height: 70,
                width: 70,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  size: 40,
                  color: Color(0xFFFF8A00),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Account Balance",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
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
                              ? "${balance.toStringAsFixed(0)} RWF"
                              : "•••••• RWF",
                          style: const TextStyle(
                            fontSize: 28,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
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
                            color: Colors.white.withOpacity(0.2),
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
                ),
                const SizedBox(height: 8),
                Text(
                  "Active transactions: ${transactions.length}",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // FILTER SECTION
  Widget _filterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
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
                    onPressed: _fetchUserTransactions,
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
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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

  Widget _transactionItem(Map<String, dynamic> trans) {
    final isReceived = trans['type'] == 'received';
    final otherParty = trans['other_party']?.toString() ?? 'Unknown User';
    final otherPartyType = trans['other_party_type']?.toString() ?? 'user';
    final amount = trans['amount']?.toDouble() ?? 0.0;
    final total = trans['total']?.toDouble() ?? 0.0;
    final dateTime = trans['date']?.toString() ?? '';
    final status = trans['status']?.toString() ?? 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isReceived
              ? [const Color(0xFFC8E6C9), const Color(0xFFA5D6A7)]
              : [const Color(0xFFFFE0B2), const Color(0xFFFFCC80)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
                  color: isReceived ? const Color(0xFF4CAF50) : const Color(0xFFFF8A00),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isReceived ? Icons.arrow_downward : Icons.arrow_upward,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isReceived ? "Received from" : "Sent to",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      otherParty,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: otherPartyType == 'merchant'
                            ? Colors.orange.withOpacity(0.2)
                            : Colors.blue.withOpacity(0.2),
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
                      color: isReceived ? const Color(0xFF4CAF50) : Colors.red,
                    ),
                  ),
                  Text(
                    dateTime,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
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
                  color: status == 'success' ? const Color(0xFF4CAF50) : Colors.orange,
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
                  "Fee: ${(total - amount).toStringAsFixed(0)} RWF",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
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
          Image.asset(
            "assets/images/wallet.png",
            height: 100,
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

  Widget _fundWalletSection() {
    return Column(
      children: [
        ElevatedButton(
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
      ],
    );
  }
}