import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'dart:math';

/// ===============================
/// BASE CONFIG
/// ===============================
const String baseUrl = "http://localhost:8000/api"; // change for emulator/device

/// ===============================
/// CURRENT USER (IN-MEMORY)
/// ===============================
Map<String, dynamic>? _currentUser;

void setCurrentUser(Map<String, dynamic>? user) {
  _currentUser = user;
}

Map<String, dynamic>? getCurrentUser() => _currentUser;

/// ===============================
/// USER REGISTRATION (WITH IMAGE)
/// ===============================
Future<int> createUserWithProfile({
  required String nationalId,
  required String email,
  required String username,
  required String phoneNumber,
  required String password,
  String accountType = 'user',
  File? profileImage,
  DateTime? dateOfBirth,
  String? businessType,
  DateTime? dateOfCreation,
}) async {
  final uri = Uri.parse("$baseUrl/register/");
  final request = http.MultipartRequest('POST', uri);

  request.fields.addAll({
    "accountType": accountType,
    "nationalId": nationalId,
    "email": email,
    "username": username,
    "phone": phoneNumber,
    "password": password,
    if (dateOfBirth != null)
      "dateOfBirth": dateOfBirth.toIso8601String().split('T')[0],
    if (dateOfCreation != null)
      "dateOfCreation": dateOfCreation.toIso8601String().split('T')[0],
    if (businessType != null) "businessType": businessType,
  });

  if (profileImage != null && await profileImage.exists()) {
    request.files.add(
      await http.MultipartFile.fromPath(
        'profilePicture',
        profileImage.path,
      ),
    );
  }

  final streamed = await request.send();
  final response = await http.Response.fromStream(streamed);

  if (response.statusCode == 200 || response.statusCode == 201) {
    final data = jsonDecode(response.body);
    return data['id'];
  } else {
    throw Exception("Registration failed: ${response.body}");
  }
}

/// ===============================
/// USER LOGIN
/// ===============================
Future<Map<String, dynamic>> authenticate(String email, String password) async {
  try {
    final response = await http.post(
      Uri.parse("$baseUrl/login/"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email, "password": password}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);

      print('✅ Login successful for: ${data['email']}');
      print('📊 Login data received: ${data.keys.toList()}');

      // Now fetch complete user details including paycode
      try {
        print('🔍 Fetching complete user details...');
        final Map<String, dynamic> userDetails = await getUserDetails(email);

        print('✅ User details fetched: ${userDetails.keys.toList()}');
        print('💰 Paycode in details: ${userDetails['paycode'] ?? userDetails['merchantpaycode']}');

        // Merge login data with user details
        final Map<String, dynamic> completeUserData = {};
        completeUserData.addAll(data);
        completeUserData.addAll(userDetails);

        print('🎯 Complete user data keys: ${completeUserData.keys.toList()}');
        print('💳 Final paycode: ${completeUserData['paycode'] ?? completeUserData['merchantpaycode']}');

        setCurrentUser(completeUserData);
        return completeUserData;
      } catch (e) {
        // If we can't get details, just use login data
        print('⚠️ Could not fetch user details: $e');
        print('🔄 Using login data only');
        setCurrentUser(data);
        return data;
      }
    } else {
      print('❌ Login failed with status: ${response.statusCode}');
      print('📄 Response body: ${response.body}');
      throw Exception("Login failed: ${response.body}");
    }
  } on TimeoutException {
    print('⏰ Login request timed out');
    throw Exception("Login request timed out. Please check your connection.");
  } catch (e) {
    print('🔥 Login error: $e');
    throw Exception("Login error: $e");
  }
}

/// ===============================
/// GET COMPLETE USER DETAILS INCLUDING PAYCODE
/// ===============================
Future<Map<String, dynamic>> getUserDetails(String email) async {
  try {
    print('🔍 Fetching user details for: $email');
    final response = await http.get(
      Uri.parse("$baseUrl/user-details/?email=$email"),
      headers: {"Content-Type": "application/json"},
    ).timeout(const Duration(seconds: 10));

    print('📡 User details response status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      print('✅ User details received: ${data.keys.toList()}');
      print('💰 Paycode found: ${data['paycode'] ?? data['merchantpaycode']}');
      return data;
    } else {
      print('❌ Failed to fetch user details: ${response.statusCode}');
      print('📄 Response body: ${response.body}');
      throw Exception("Failed to fetch user details: ${response.statusCode}");
    }
  } on TimeoutException {
    print('⏰ User details request timed out');
    throw Exception("User details request timed out");
  } catch (e) {
    print('🔥 Error fetching user details: $e');
    rethrow;
  }
}

/// ===============================
/// GET USER BY EMAIL
/// ===============================
Future<Map<String, dynamic>> getUserByEmail(String email) async {
  try {
    final response = await http.get(
      Uri.parse("$baseUrl/users/$email/"),
      headers: {"Content-Type": "application/json"},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to fetch user: ${response.body}");
    }
  } on TimeoutException {
    throw Exception("Request timed out");
  } catch (e) {
    throw Exception("Error fetching user: $e");
  }
}

/// ===============================
/// UPDATE USER PROFILE
/// ===============================
Future<Map<String, dynamic>> updateUserProfile({
  required String email,
  String? username,
  String? phone,
  String? nationalId,
  String? currentPassword,
  String? newPassword,
}) async {
  try {
    final Map<String, dynamic> requestData = {'email': email};

    if (username != null) requestData['username'] = username;
    if (phone != null) requestData['phone'] = phone;
    if (nationalId != null) requestData['national_id'] = nationalId;
    if (currentPassword != null) requestData['current_password'] = currentPassword;
    if (newPassword != null) requestData['new_password'] = newPassword;

    print('📤 Updating profile for: $email');
    print('📝 Update data: ${requestData.keys.toList()}');

    final response = await http.put(
      Uri.parse("$baseUrl/update-profile/"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(requestData),
    ).timeout(const Duration(seconds: 10));

    print('📡 Update response status: ${response.statusCode}');
    print('📄 Update response body: ${response.body}');

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);

      // Update local user data
      final currentUser = getCurrentUser();
      if (currentUser != null) {
        if (username != null) currentUser['username'] = username;
        if (phone != null) currentUser['phoneNumber'] = phone;
        setCurrentUser(currentUser);
      }

      return data;
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['error']?.toString() ?? 'Failed to update profile');
    }
  } on TimeoutException {
    throw Exception("Request timed out");
  } catch (e) {
    throw Exception("Error updating profile: $e");
  }
}

/// ===============================
/// UPDATE PROFILE PICTURE
/// ===============================
Future<String> updateProfilePicture({
  File? imageFile,                // mobile / desktop
  Uint8List? webBytes,            // web
  required String filename,       // required for web
}) async {
  try {
    final user = getCurrentUser();
    if (user == null) {
      throw Exception("No logged-in user");
    }

    final uri = Uri.parse("$baseUrl/update-profile-picture/");
    final request = http.MultipartRequest('PUT', uri);

    request.fields['email'] = user['email'];

    if (kIsWeb) {
      if (webBytes == null) {
        throw Exception("Web image bytes are null");
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'profilePicture',
          webBytes,
          filename: filename,
        ),
      );
    } else {
      if (imageFile == null || !await imageFile.exists()) {
        throw Exception("Image file not found");
      }

      request.files.add(
        await http.MultipartFile.fromPath(
          'profilePicture',
          imageFile.path,
          filename: filename,
        ),
      );
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);

      user['profilePicture'] = data['profilePicture'];
      setCurrentUser(user);

      return data['profilePicture'];
    } else {
      throw Exception("Profile picture update failed: ${response.body}");
    }
  } on TimeoutException {
    throw Exception("Profile picture upload timed out");
  } catch (e) {
    throw Exception("Error updating profile picture: $e");
  }
}

/// Update profile picture path for a user identified by email
/// Returns old image path (if any) so caller can delete it
Future<String?> updateProfilePictureForEmail(String email, File newImage) async {
  if (_currentUser == null) return null;

  if (_currentUser!['email'] != email) return null;

  final oldPath = _currentUser!['profilePicturePath'] as String?;

  _currentUser!['profilePicturePath'] = newImage.path;

  return oldPath;
}

/// ===============================
/// PRODUCT APIs
/// ===============================
Future<int> createProduct({
  required String productName,
  required double price,
  int amountInStock = 0,
  String? productPicturePath,
  required int categoryId,
  required String merchantId,
}) async {
  try {
    final response = await http.post(
      Uri.parse("$baseUrl/products/"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "productName": productName,
        "price": price,
        "amountInStock": amountInStock,
        "productPicture": productPicturePath,
        "categoryId": categoryId,
        "merchantId": merchantId,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return data['productid'];
    } else {
      throw Exception("Failed to create product: ${response.body}");
    }
  } on TimeoutException {
    throw Exception("Product creation timed out");
  } catch (e) {
    throw Exception("Error creating product: $e");
  }
}

Future<List<dynamic>> listAllProducts() async {
  try {
    final response = await http.get(
      Uri.parse("$baseUrl/products/"),
      headers: {"Content-Type": "application/json"},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to fetch products: ${response.statusCode}");
    }
  } on TimeoutException {
    throw Exception("Products fetch timed out");
  } catch (e) {
    throw Exception("Error fetching products: $e");
  }
}

/// ===============================
/// IMAGE HELPER
/// ===============================
ImageProvider? imageProviderFromPath(String? path) {
  if (path == null || path.isEmpty) return null;

  if (path.startsWith('http')) {
    return NetworkImage(path);
  }

  final file = File(path);
  if (file.existsSync()) {
    return FileImage(file);
  }

  return null;
}

/// ===============================
/// NOTIFICATION APIs
/// ===============================
Future<List<dynamic>> getUserNotifications(String email) async {
  try {
    final response = await http.get(
      Uri.parse("$baseUrl/notifications/?email=$email"),
      headers: {"Content-Type": "application/json"},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return data['notifications'] ?? [];
    } else {
      throw Exception("Failed to fetch notifications: ${response.body}");
    }
  } on TimeoutException {
    print('⏰ Notifications request timed out');
    return [];
  } catch (e) {
    print('🔥 Error fetching notifications: $e');
    return [];
  }
}

Future<int> getUnreadNotificationCount(String email) async {
  try {
    final response = await http.get(
      Uri.parse("$baseUrl/notifications/?email=$email"),
      headers: {"Content-Type": "application/json"},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return data['unread_count'] ?? 0;
    }
    return 0;
  } on TimeoutException {
    print('⏰ Notification count request timed out');
    return 0;
  } catch (e) {
    print('🔥 Error fetching notification count: $e');
    return 0;
  }
}

/// ===============================
/// LOGOUT
/// ===============================
void logout() {
  _currentUser = null;
}

/// ===============================
/// VALIDATE PASSWORD
/// ===============================
bool validatePassword(String password) {
  // At least 8 characters
  if (password.length < 8) return false;

  // Contains at least one uppercase letter
  if (!password.contains(RegExp(r'[A-Z]'))) return false;

  // Contains at least one lowercase letter
  if (!password.contains(RegExp(r'[a-z]'))) return false;

  // Contains at least one digit
  if (!password.contains(RegExp(r'[0-9]'))) return false;

  // Contains at least one special character
  if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) return false;

  return true;
}

/// ===============================
/// VALIDATE EMAIL
/// ===============================
bool validateEmail(String email) {
  final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  return emailRegex.hasMatch(email);
}

/// ===============================
/// VALIDATE PHONE NUMBER
/// ===============================
bool validatePhoneNumber(String phone) {
  // Simple validation for Rwandan phone numbers
  final phoneRegex = RegExp(r'^\+250[0-9]{9}$|^0[0-9]{9}$');
  return phoneRegex.hasMatch(phone);
}

/// ===============================
/// FORMAT CURRENCY
/// ===============================
String formatCurrency(double amount) {
  return '${amount.toStringAsFixed(0)} FRW';
}

/// ===============================
/// GENERATE RANDOM PAYCODE (FALLBACK)
/// ===============================
String generateRandomPaycode({String prefix = 'PAY'}) {
  final random = Random();
  final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  final randomNum = random.nextInt(9000) + 1000;
  return '$prefix-$timestamp$randomNum';
}

/// ===============================
/// LOOKUP USER BY PAYCODE
/// ===============================
Future<Map<String, dynamic>?> lookupByPaycode(String paycode) async {
  try {
    final response = await http.get(
      Uri.parse("$baseUrl/user-by-paycode/?paycode=$paycode"),
      headers: {"Content-Type": "application/json"},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return {
        'username': data['username'] ?? '',
        'paycode': data['paycode'] ?? '',
        'email': data['email'] ?? '',
        'phone': data['phone'] ?? '',
        'type': data['type'] ?? '',
        'business_type': data['business_type'] ?? '',
        'profile_picture': data['profile_picture'] ?? '',
      };
    } else {
      debugPrint('❌ lookupByPaycode failed: ${response.statusCode}');
      return null;
    }
  } on TimeoutException {
    debugPrint('⏰ lookupByPaycode request timed out');
    return null;
  } catch (e) {
    debugPrint('🔥 lookupByPaycode error: $e');
    return null;
  }
}

/// ===============================
/// UPDATE LOCAL USER BALANCE
/// ===============================
void updateLocalUserBalance(double newBalance) {
  // Get current user data
  final currentUser = getCurrentUser();
  if (currentUser != null) {
    // Update balance in local storage
    currentUser['balance'] = newBalance;
    print('✅ Local balance updated to: $newBalance');
  }
}
/// ===============================
/// PROCESS PAYMENT
/// ===============================
Future<Map<String, dynamic>> processPayment({
  required String senderPaycode,
  required String receiverPaycode,
  required String pin,
  required double amount,
}) async {
  try {
    print('💰 Processing payment...');
    print('👤 Sender paycode: $senderPaycode');
    print('👥 Receiver paycode: $receiverPaycode');
    print('💵 Amount: $amount');
    print('🔐 PIN entered: ${"*" * pin.length}');

    final response = await http.post(
      Uri.parse('$baseUrl/process-payment/'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'sender_paycode': senderPaycode,
        'receiver_paycode': receiverPaycode,
        'pin': pin,
        'amount': amount,
      }),
    ).timeout(const Duration(seconds: 30));

    print('📡 Payment response status: ${response.statusCode}');
    print('📄 Payment response body: ${response.body}');

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      return data;
    } else {
      final errorData = json.decode(response.body);
      throw Exception(errorData['error']?.toString() ?? 'Payment failed');
    }
  } on TimeoutException catch (e) {
    print('⏰ Payment request timeout: $e');
    throw Exception("Payment request timed out. Please try again.");
  } on http.ClientException catch (e) {
    print('🌐 Payment network error: $e');
    throw Exception("Network error. Please check your connection.");
  } catch (e) {
    print('🔥 Payment unexpected error: $e');
    throw Exception("Payment error: $e");
  }
}

/// ===============================
/// UPDATE USER PROFILE WITH IMAGE
/// ===============================
Future<Map<String, dynamic>> updateUserProfileWithImage({
  required String email,
  String? username,
  String? phone,
  String? nationalId,
  String? currentPassword,
  String? newPassword,
  File? profileImage,
}) async {
  try {
    final uri = Uri.parse("$baseUrl/update-profile/");
    final request = http.MultipartRequest('PUT', uri);

    request.fields['email'] = email;
    if (username != null) request.fields['username'] = username;
    if (phone != null) request.fields['phone'] = phone;
    if (nationalId != null) request.fields['national_id'] = nationalId;
    if (currentPassword != null) request.fields['current_password'] = currentPassword;
    if (newPassword != null) request.fields['new_password'] = newPassword;

    if (profileImage != null && await profileImage.exists()) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'profilePicture',
          profileImage.path,
        ),
      );
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);

      // Update local user data
      final currentUser = getCurrentUser();
      if (currentUser != null) {
        if (username != null) currentUser['username'] = username;
        if (phone != null) currentUser['phoneNumber'] = phone;
        setCurrentUser(currentUser);
      }

      return data;
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['error']?.toString() ?? 'Failed to update profile');
    }
  } on TimeoutException {
    throw Exception("Request timed out");
  } catch (e) {
    throw Exception("Error updating profile: $e");
  }
}

/// ===============================
/// GET MERCHANT PRODUCTS
/// ===============================
Future<List<dynamic>> getMerchantProducts(String merchantId) async {
  try {
    final response = await http.get(
      Uri.parse("$baseUrl/merchant-products/?merchant_id=$merchantId"),
      headers: {"Content-Type": "application/json"},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return data['products'] ?? [];
    } else {
      throw Exception("Failed to fetch merchant products: ${response.body}");
    }
  } on TimeoutException {
    throw Exception("Products fetch timed out");
  } catch (e) {
    throw Exception("Error fetching products: $e");
  }
}

/// ===============================
/// GET MERCHANT MENU
/// ===============================
Future<List<dynamic>> getMerchantMenu(String merchantId) async {
  try {
    final response = await http.get(
      Uri.parse("$baseUrl/merchant-menu/?merchant_id=$merchantId"),
      headers: {"Content-Type": "application/json"},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return data['menu'] ?? [];
    } else {
      throw Exception("Failed to fetch merchant menu: ${response.body}");
    }
  } on TimeoutException {
    throw Exception("Menu fetch timed out");
  } catch (e) {
    throw Exception("Error fetching menu: $e");
  }
}

/// ===============================
/// CREATE PRODUCT FOR MERCHANT
/// ===============================
Future<int> createMerchantProduct({
  required String productName,
  required double price,
  int amountInStock = 0,
  String category = '',
  required String merchantId,
  File? productImage,
}) async {
  try {
    final uri = Uri.parse("$baseUrl/create-product/");
    final request = http.MultipartRequest('POST', uri);

    request.fields.addAll({
      "merchant_id": merchantId,
      "product_name": productName,
      "price": price.toString(),
      "amount_in_stock": amountInStock.toString(),
      "category": category,
      "add_to_menu": "true",
    });

    if (productImage != null && await productImage.exists()) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'product_picture',
          productImage.path,
        ),
      );
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 201) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return data['product_id'] ?? 0;
    } else {
      throw Exception("Failed to create product: ${response.body}");
    }
  } on TimeoutException {
    throw Exception("Product creation timed out");
  } catch (e) {
    throw Exception("Error creating product: $e");
  }
}
Future<Map<String, dynamic>> getUserTransactions({
  required String email,
  String? year,
  String? month,
  String? day,
}) async {
  try {
    String url = '$baseUrl/get-user-transactions/?email=$email';

    if (year != null) {
      url += '&year=$year';
    }
    if (month != null) {
      url += '&month=$month';
    }
    if (day != null) {
      url += '&day=$day';
    }

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        return data;
      } else {
        throw Exception(data['error'] ?? 'Failed to fetch transactions');
      }
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ Error fetching transactions: $e');
    rethrow;
  }
}