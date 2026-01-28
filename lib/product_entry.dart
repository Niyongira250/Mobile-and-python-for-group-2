import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'services/data_service.dart';
import 'dart:async';
import 'package:http_parser/http_parser.dart';
import 'dart:developer';

class ProductEntryPage extends StatefulWidget {
  const ProductEntryPage({super.key});

  @override
  State<ProductEntryPage> createState() => _ProductEntryPageState();
}

class _ProductEntryPageState extends State<ProductEntryPage> {
  // Current merchant info
  Map<String, dynamic>? merchantData;
  int? merchantId;

  // Form state
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Dynamic custom fields
  final List<TextEditingController> _customFieldControllers = [];
  final List<String> _customFields = [];

  // Image handling
  Uint8List? _webImageBytes;
  File? _mobileImageFile;
  final ImagePicker _picker = ImagePicker();
  String? _uploadedImageUrl;

  // Categories
  List<String> categories = [
    "Fresh sea products",
    "Bakery",
    "Beverages",
    "Snacks",
    "Meals",
    "Desserts",
    "Groceries",
    "Electronics",
    "Clothing"
  ];
  String selectedCategory = "Fresh sea products";

  // Existing products
  List<Map<String, dynamic>> _existingProducts = [];
  List<Map<String, dynamic>> _menuProducts = [];
  bool _isLoadingProducts = false;
  bool _isLoadingMenu = false;

  // UI State
  bool _isSaving = false;
  bool _isUploadingImage = false;
  String _errorMessage = '';
  String _successMessage = '';
  int _currentTab = 0; // 0: Add, 1: Manage, 2: Menu

  // Editing state
  bool _isEditing = false;
  int? _editingProductId;
  String? _editingProductImageUrl;

  @override
  void initState() {
    super.initState();
    _initializeMerchant();
  }

  Future<void> _testConnection() async {
    try {
      print('🔍 Testing connection to Django...');

      // Test basic connection
      final testResponse = await http.get(
        Uri.parse("http://localhost:8000/api/test/"),
      ).timeout(const Duration(seconds: 10));

      print('✅ Connection test: ${testResponse.statusCode}');
      print('Response: ${testResponse.body}');

      // Test merchant details endpoint
      final user = getCurrentUser();
      if (user != null && user['email'] != null) {
        final merchantResponse = await http.get(
          Uri.parse("http://localhost:8000/api/merchant-details/?email=${user['email']}"),
        );

        print('✅ Merchant details: ${merchantResponse.statusCode}');
        print('Response: ${merchantResponse.body}');
      }

    } catch (e) {
      print('❌ Connection test failed: $e');
      _showError('Cannot connect to server: $e');
    }
  }

  Future<void> _initializeMerchant() async {
    final user = getCurrentUser();
    if (user == null || user['type'] != 'merchant') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only merchants can access this page'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      });
      return;
    }

    merchantData = user;

    // Try to get merchant ID from user data first
    if (user['merchantid'] != null) {
      setState(() {
        merchantId = _safeParseInt(user['merchantid']);
      });
      _showMessage('Merchant ID from session: $merchantId', isError: false);
    }

    // Fetch from API if not found
    await _loadMerchantDetails();

    // Load other data if merchant ID is available
    if (merchantId != null) {
      await _loadExistingProducts();
      await _loadMenuProducts();
    }
  }

  int? _safeParseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      try {
        return int.tryParse(value);
      } catch (e) {
        return null;
      }
    }
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    return null;
  }

  double? _safeParseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.tryParse(value);
      } catch (e) {
        return null;
      }
    }
    if (value is num) return value.toDouble();
    return null;
  }

  Future<void> _loadMerchantDetails() async {
    try {
      final user = getCurrentUser();
      if (user == null) {
        _showMessage('No merchant logged in', isError: true);
        return;
      }

      // Check if merchant ID is already in user data
      if (user['merchantid'] != null) {
        setState(() {
          merchantId = _safeParseInt(user['merchantid']);
        });
        _showMessage('Merchant ID from user data: $merchantId', isError: false);
        return;
      }

      // If not, fetch from API
      final email = user['email'] as String;
      _showMessage('Fetching merchant details for: $email', isError: false);

      final response = await http.get(
        Uri.parse("http://localhost:8000/api/merchant-details/?email=$email"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          merchantId = _safeParseInt(data['merchantid']);
          merchantData = data;
        });
        _showMessage('Loaded merchant ID from API: $merchantId', isError: false);

        // Update user data with merchant ID for future use
        user['merchantid'] = merchantId;
        setCurrentUser(user);
      } else {
        _showMessage('Failed to load merchant details: ${response.statusCode}', isError: true);
      }
    } catch (e) {
      _showMessage('Error loading merchant details: $e', isError: true);
    }
  }

  Future<void> _loadExistingProducts() async {
    if (merchantId == null) {
      _showMessage('Cannot load products: Merchant ID not found', isError: true);
      return;
    }

    setState(() => _isLoadingProducts = true);
    try {
      print('🔄 Loading products for merchant ID: $merchantId');

      final response = await http.get(
        Uri.parse("http://localhost:8000/api/merchant-products/?merchant_id=$merchantId"),
        headers: {"Content-Type": "application/json"},
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          print('✅ API Response data: $data');

          if (data['success'] == true) {
            final products = List<Map<String, dynamic>>.from(data['products'] ?? []);
            print('✅ Loaded ${products.length} products');

            // Normalize data types
            final normalizedProducts = products.map((product) {
              return {
                'productid': _safeParseInt(product['productid']),
                'productname': product['productname']?.toString() ?? 'Unnamed',
                'price': _safeParseDouble(product['price']) ?? 0.0,
                'amountinstock': _safeParseInt(product['amountinstock']) ?? 0,
                'category': product['category']?.toString() ?? 'Uncategorized',
                'merchantid': _safeParseInt(product['merchantid']),
                'productpicture': product['productpicture']?.toString(),
              };
            }).toList();

            setState(() {
              _existingProducts = normalizedProducts;
            });

            _showMessage('Loaded ${products.length} products', isError: false);
          } else {
            print('❌ API returned success: false');
            _showMessage('Failed to load products: ${data['error']}', isError: true);
          }
        } catch (e) {
          print('❌ JSON parsing error: $e');
          _showMessage('Error parsing product data: $e', isError: true);
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
        _showMessage('Failed to load products: ${response.statusCode}', isError: true);
      }
    } catch (e) {
      print('❌ Error loading products: $e');
      _showMessage('Error loading products: $e', isError: true);
    } finally {
      setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _loadMenuProducts() async {
    if (merchantId == null) {
      _showMessage('Cannot load menu: Merchant ID not found', isError: true);
      return;
    }

    setState(() => _isLoadingMenu = true);
    try {
      print('🔄 Loading menu for merchant ID: $merchantId');

      final response = await http.get(
        Uri.parse("http://localhost:8000/api/merchant-menu/?merchant_id=$merchantId"),
        headers: {"Content-Type": "application/json"},
      );

      print('📥 Menu response status: ${response.statusCode}');
      print('📥 Menu response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          print('✅ Menu API Response data: $data');

          if (data['success'] == true) {
            final menuItems = List<Map<String, dynamic>>.from(data['menu'] ?? []);
            print('✅ Loaded ${menuItems.length} menu items');

            // Normalize data types
            final normalizedMenu = menuItems.map((item) {
              return {
                'menuid': _safeParseInt(item['menuid']),
                'productid': _safeParseInt(item['productid']),
                'productname': item['productname']?.toString() ?? 'Unnamed',
                'price': _safeParseDouble(item['price']) ?? 0.0,
                'amountinstock': _safeParseInt(item['amountinstock']) ?? 0,
                'category': item['category']?.toString() ?? 'Uncategorized',
                'productpicture': item['productpicture']?.toString(),
                'availability': item['availability'] == true || item['availability'] == 'true',
              };
            }).toList();

            setState(() {
              _menuProducts = normalizedMenu;
            });

            _showMessage('Loaded ${menuItems.length} menu items', isError: false);
          } else {
            print('❌ Menu API returned success: false');
            _showMessage('Failed to load menu: ${data['error']}', isError: true);
          }
        } catch (e) {
          print('❌ Menu JSON parsing error: $e');
          _showMessage('Error parsing menu data: $e', isError: true);
        }
      } else {
        print('❌ Menu HTTP Error: ${response.statusCode}');
        _showMessage('Failed to load menu: ${response.statusCode}', isError: true);
      }
    } catch (e) {
      print('❌ Error loading menu: $e');
      _showMessage('Error loading menu: $e', isError: true);
    } finally {
      setState(() => _isLoadingMenu = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() => _isUploadingImage = true);
      _showMessage('Uploading image...', isError: false);

      if (kIsWeb) {
        _webImageBytes = await picked.readAsBytes();
        _mobileImageFile = null;
      } else {
        final bytes = await picked.readAsBytes();
        _mobileImageFile = File(picked.path);
        _webImageBytes = null;
      }

      setState(() => _isUploadingImage = false);
      _showSuccess('Image selected successfully');
    } catch (e) {
      setState(() => _isUploadingImage = false);
      _showError('Failed to select image: $e');
    }
  }

  Future<void> _createProduct() async {
    if (_isSaving) return;

    final name = _productNameController.text.trim();
    final price = _safeParseDouble(_priceController.text) ?? 0.0;
    final stock = _safeParseInt(_stockController.text) ?? 0;
    final category = selectedCategory;

    if (name.isEmpty) {
      _showError('Product name is required');
      return;
    }

    if (price <= 0) {
      _showError('Price must be greater than 0');
      return;
    }

    if (merchantId == null) {
      _showError('Merchant ID not found. Please make sure you are logged in as a merchant.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = '';
      _successMessage = '';
    });

    print('🚀 Starting product creation...');
    print('   Name: $name');
    print('   Price: $price');
    print('   Stock: $stock');
    print('   Category: $category');
    print('   Merchant ID: $merchantId');

    _showMessage('Creating product "$name"...', isError: false);

    try {
      final uri = Uri.parse("http://localhost:8000/api/create-product/");

      // Create multipart request
      var request = http.MultipartRequest('POST', uri);

      // Add form fields
      request.fields['merchant_id'] = merchantId.toString();
      request.fields['product_name'] = name;
      request.fields['price'] = price.toStringAsFixed(2);
      request.fields['amount_in_stock'] = stock.toString();
      request.fields['category'] = category;
      request.fields['description'] = _descriptionController.text.trim();
      request.fields['add_to_menu'] = 'true';
      request.fields['custom_fields'] = jsonEncode(_customFields.where((e) => e.isNotEmpty).toList());

      // Add image if available
      if (_mobileImageFile != null && _mobileImageFile!.existsSync()) {
        print('📁 Adding image file: ${_mobileImageFile!.path}');
        request.files.add(await http.MultipartFile.fromPath(
          'product_picture',
          _mobileImageFile!.path,
          filename: 'product_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      } else if (_webImageBytes != null) {
        print('📁 Adding web image (${_webImageBytes!.length} bytes)');
        request.files.add(http.MultipartFile.fromBytes(
          'product_picture',
          _webImageBytes!,
          filename: 'product_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      } else {
        print('📁 No image provided');
      }

      print('📤 Sending request to: ${uri.toString()}');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      // Check if response is valid JSON
      try {
        final data = jsonDecode(response.body);

        if (response.statusCode == 201 && data['success'] == true) {
          print('✅ Product created successfully!');
          print('✅ Product ID: ${data['product_id']}');
          print('✅ Product Name: ${data['product_name']}');

          _showSuccess('Product "${data['product_name']}" created successfully! Added to menu.');
          _resetForm();

          // Wait a bit for the database to update
          await Future.delayed(const Duration(seconds: 1));

          // Refresh both product lists
          print('🔄 Refreshing product lists...');
          await _loadExistingProducts();
          await _loadMenuProducts();

          // Switch to Manage Products tab
          setState(() => _currentTab = 1);
        } else {
          print('❌ Product creation failed');
          print('❌ Error: ${data['error']}');
          _showError(data['error']?.toString() ?? 'Failed to create product. Status: ${response.statusCode}');
        }
      } catch (e) {
        // If not JSON, it's probably HTML error page
        print('❌ Response is not JSON. Might be HTML error page.');
        print('❌ Error parsing JSON: $e');
        _showError('Server returned invalid response. Check Django server logs.');
      }
    } on TimeoutException {
      print('⏰ Request timed out');
      _showError('Request timed out. Please check if Django server is running at http://localhost:8000');
    } on SocketException {
      print('🔌 Socket exception - cannot connect');
      _showError('Cannot connect to Django server. Make sure it\'s running at http://localhost:8000');
    } catch (e) {
      print('❌ Error creating product: $e');
      _showError('Error creating product: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _updateProduct() async {
    if (_isSaving || _editingProductId == null) return;

    final name = _productNameController.text.trim();
    final price = _safeParseDouble(_priceController.text) ?? 0.0;
    final stock = _safeParseInt(_stockController.text) ?? 0;
    final category = selectedCategory;

    if (name.isEmpty) {
      _showError('Product name is required');
      return;
    }

    if (price <= 0) {
      _showError('Price must be greater than 0');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = '';
      _successMessage = '';
    });

    print('🔄 Updating product ID: $_editingProductId');
    print('   Name: $name');
    print('   Price: $price');
    print('   Stock: $stock');
    print('   Category: $category');

    _showMessage('Updating product "$name"...', isError: false);

    try {
      final uri = Uri.parse("http://localhost:8000/api/update-product/");

      // Create multipart request
      var request = http.MultipartRequest('PUT', uri);

      // Add form fields
      request.fields['product_id'] = _editingProductId.toString();
      request.fields['product_name'] = name;
      request.fields['price'] = price.toStringAsFixed(2);
      request.fields['amount_in_stock'] = stock.toString();
      request.fields['category'] = category;
      request.fields['description'] = _descriptionController.text.trim();
      request.fields['custom_fields'] = jsonEncode(_customFields.where((e) => e.isNotEmpty).toList());

      // Add image if available (only if new image is selected)
      if (_mobileImageFile != null && _mobileImageFile!.existsSync()) {
        print('📁 Adding updated image file: ${_mobileImageFile!.path}');
        request.files.add(await http.MultipartFile.fromPath(
          'product_picture',
          _mobileImageFile!.path,
          filename: 'product_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      } else if (_webImageBytes != null) {
        print('📁 Adding updated web image (${_webImageBytes!.length} bytes)');
        request.files.add(http.MultipartFile.fromBytes(
          'product_picture',
          _webImageBytes!,
          filename: 'product_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));
      }

      print('📤 Sending update request to: ${uri.toString()}');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Update response status: ${response.statusCode}');
      print('📥 Update response body: ${response.body}');

      try {
        final data = jsonDecode(response.body);

        if (response.statusCode == 200 && data['success'] == true) {
          print('✅ Product updated successfully!');
          _showSuccess('Product "$name" updated successfully!');
          _resetEditMode();

          // Refresh both product lists
          await _loadExistingProducts();
          await _loadMenuProducts();

          // Switch to Manage Products tab
          setState(() => _currentTab = 1);
        } else {
          print('❌ Product update failed');
          print('❌ Error: ${data['error']}');
          _showError(data['error']?.toString() ?? 'Failed to update product. Status: ${response.statusCode}');
        }
      } catch (e) {
        print('❌ Update response JSON error: $e');
        _showError('Error updating product: Invalid server response');
      }
    } catch (e) {
      print('❌ Error updating product: $e');
      _showError('Error updating product: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _addToMenu(int productId, String productName) async {
    if (merchantId == null) {
      _showError('Merchant ID not found');
      return;
    }

    try {
      setState(() => _isSaving = true);
      _showMessage('Adding "$productName" to menu...', isError: false);

      final response = await http.post(
        Uri.parse("http://localhost:8000/api/add-to-menu/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'merchant_id': merchantId,
          'product_id': productId,
          'availability': true,
        }),
      );

      print('📥 Add to menu response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 201) {
        _showSuccess('Added "$productName" to menu!');
        await _loadMenuProducts();
      } else {
        try {
          final error = jsonDecode(response.body);
          _showError(error['error']?.toString() ?? 'Failed to add to menu');
        } catch (e) {
          _showError('Failed to add to menu: ${response.statusCode}');
        }
      }
    } catch (e) {
      _showError('Error adding to menu: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _removeFromMenu(int menuId, String productName) async {
    try {
      setState(() => _isSaving = true);
      _showMessage('Removing "$productName" from menu...', isError: false);

      final response = await http.delete(
        Uri.parse("http://localhost:8000/api/remove-from-menu/?menu_id=$menuId"),
        headers: {"Content-Type": "application/json"},
      );

      print('📥 Remove from menu response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        _showSuccess('Removed "$productName" from menu!');
        await _loadMenuProducts();
      } else {
        try {
          final error = jsonDecode(response.body);
          _showError(error['error']?.toString() ?? 'Failed to remove from menu');
        } catch (e) {
          _showError('Failed to remove from menu: ${response.statusCode}');
        }
      }
    } catch (e) {
      _showError('Error removing from menu: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleProductAvailability(int productId, bool currentStatus) async {
    try {
      _showMessage('Updating product availability...', isError: false);

      print('🔄 Toggling availability for product $productId from $currentStatus to ${!currentStatus}');

      final response = await http.put(
        Uri.parse("http://localhost:8000/api/toggle-product-availability/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'product_id': productId,
          'available': !currentStatus,
        }),
      );

      print('📥 Toggle availability response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        _showSuccess('Availability updated!');
        // Refresh both lists
        await _loadExistingProducts();
        await _loadMenuProducts();
      } else {
        try {
          final error = jsonDecode(response.body);
          _showError(error['error']?.toString() ?? 'Failed to update availability');
        } catch (e) {
          _showError('Failed to update availability: ${response.statusCode}');
        }
      }
    } catch (e) {
      _showError('Error updating availability: $e');
    }
  }

  Future<void> _toggleMenuAvailability(int menuId, bool currentStatus) async {
    try {
      _showMessage('Updating menu availability...', isError: false);

      print('🔄 Toggling menu availability for menu $menuId from $currentStatus to ${!currentStatus}');

      // First get the product ID from the menu item
      final menuItem = _menuProducts.firstWhere((item) => item['menuid'] == menuId);
      final productId = menuItem['productid'];

      // Call the toggle endpoint
      final response = await http.put(
        Uri.parse("http://localhost:8000/api/toggle-product-availability/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'product_id': productId,
          'available': !currentStatus,
        }),
      );

      print('📥 Toggle menu availability response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        _showSuccess('Menu availability updated!');
        // Refresh both lists
        await _loadExistingProducts();
        await _loadMenuProducts();
      } else {
        try {
          final error = jsonDecode(response.body);
          _showError(error['error']?.toString() ?? 'Failed to update menu availability');
        } catch (e) {
          _showError('Failed to update menu availability: ${response.statusCode}');
        }
      }
    } catch (e) {
      _showError('Error updating menu availability: $e');
    }
  }

  Future<void> _deleteProduct(int productId, String productName) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "$productName"? This will also remove it from the menu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                setState(() => _isSaving = true);
                _showMessage('Deleting "$productName"...', isError: false);

                final response = await http.delete(
                  Uri.parse("http://localhost:8000/api/delete-product/?product_id=$productId"),
                  headers: {"Content-Type": "application/json"},
                );

                print('📥 Delete response: ${response.statusCode} - ${response.body}');

                if (response.statusCode == 200) {
                  _showSuccess('Product deleted successfully!');
                  await _loadExistingProducts();
                  await _loadMenuProducts();
                } else {
                  try {
                    final error = jsonDecode(response.body);
                    _showError(error['error']?.toString() ?? 'Failed to delete product');
                  } catch (e) {
                    _showError('Failed to delete product: ${response.statusCode}');
                  }
                }
              } catch (e) {
                _showError('Error deleting product: $e');
              } finally {
                setState(() => _isSaving = false);
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _startEditProduct(Map<String, dynamic> product) {
    setState(() {
      _isEditing = true;
      _editingProductId = _safeParseInt(product['productid']);
      _editingProductImageUrl = product['productpicture']?.toString();

      _productNameController.text = product['productname']?.toString() ?? '';
      _priceController.text = (_safeParseDouble(product['price']) ?? 0.0).toString();
      _stockController.text = (_safeParseInt(product['amountinstock']) ?? 0).toString();
      selectedCategory = product['category']?.toString() ?? categories[0];
      _descriptionController.text = product['description']?.toString() ?? '';

      // Clear any existing image selection
      _webImageBytes = null;
      _mobileImageFile = null;

      // Switch to Add Product tab for editing
      _currentTab = 0;
    });

    _showMessage('Editing product: ${product['productname']}', isError: false);
  }

  void _resetEditMode() {
    setState(() {
      _isEditing = false;
      _editingProductId = null;
      _editingProductImageUrl = null;
    });
    _resetForm();
  }

  void _resetForm() {
    _productNameController.clear();
    _priceController.clear();
    _stockController.clear();
    _descriptionController.clear();
    _uploadedImageUrl = null;
    _webImageBytes = null;
    _mobileImageFile = null;
    _customFields.clear();
    for (var controller in _customFieldControllers) {
      controller.dispose();
    }
    _customFieldControllers.clear();
    selectedCategory = categories[0];
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.blue.shade600,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
      _successMessage = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    setState(() {
      _successMessage = message;
      _errorMessage = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
    Widget? suffix,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF1a3250),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.white,
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hintText,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              suffixIcon: suffix,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildImageUpload() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Product Image',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF1a3250),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF8A00),
                width: 2,
                style: BorderStyle.solid,
              ),
              color: Colors.grey.shade50,
            ),
            child: _isUploadingImage
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(Color(0xFFFF8A00)),
                  ),
                  SizedBox(height: 8),
                  Text('Uploading image...'),
                ],
              ),
            )
                : (_webImageBytes != null || _mobileImageFile != null)
                ? Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: kIsWeb
                      ? Image.memory(_webImageBytes!, fit: BoxFit.cover)
                      : Image.file(_mobileImageFile!, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            )
                : _isEditing && _editingProductImageUrl != null
                ? Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    _editingProductImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Icon(
                          Icons.photo,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Current',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            )
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_upload,
                  size: 40,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap to upload image',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'JPG, PNG (Max 5MB)',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_webImageBytes != null || _mobileImageFile != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'New image selected ✓',
              style: TextStyle(
                color: Colors.green.shade600,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Category',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF1a3250),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.white,
          ),
          child: DropdownButton<String>(
            value: selectedCategory,
            isExpanded: true,
            underline: Container(),
            items: categories
                .map((category) => DropdownMenuItem(
              value: category,
              child: Text(category),
            ))
                .toList(),
            onChanged: (value) {
              setState(() {
                selectedCategory = value!;
              });
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCustomFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Custom Input Fields',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF1a3250),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add custom fields that customers need to provide (e.g., "Table Number", "Custom Message")',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),

        // Quick action buttons
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildQuickFieldButton('Table Name', Icons.table_restaurant),
            _buildQuickFieldButton('Special Instructions', Icons.edit_note),
            _buildQuickFieldButton('Allergies', Icons.warning),
            _buildQuickFieldButton('Pickup Time', Icons.access_time),
          ],
        ),

        const SizedBox(height: 16),

        // Add new field button
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _customFieldControllers.add(TextEditingController());
              _customFields.add('');
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade100,
            foregroundColor: Colors.grey.shade800,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Custom Field'),
        ),

        const SizedBox(height: 16),

        // Custom field inputs
        ...List.generate(_customFieldControllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customFieldControllers[index],
                    decoration: InputDecoration(
                      hintText: 'Enter field name (e.g., "Table Number")',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _customFields[index] = value.trim();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _customFieldControllers[index].dispose();
                      _customFieldControllers.removeAt(index);
                      _customFields.removeAt(index);
                    });
                  },
                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                ),
              ],
            ),
          );
        }),

        // Display active custom fields
        if (_customFields.where((e) => e.isNotEmpty).isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Active Custom Fields:',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _customFields
                .where((e) => e.isNotEmpty)
                .map((field) => Chip(
              label: Text(field),
              backgroundColor: const Color(0xFFFF8A00).withOpacity(0.1),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () {
                final index = _customFields.indexOf(field);
                if (index != -1) {
                  setState(() {
                    _customFieldControllers[index].dispose();
                    _customFieldControllers.removeAt(index);
                    _customFields.removeAt(index);
                  });
                }
              },
            ))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildQuickFieldButton(String label, IconData icon) {
    return ElevatedButton.icon(
      onPressed: () {
        if (!_customFields.contains(label)) {
          setState(() {
            _customFieldControllers.add(TextEditingController(text: label));
            _customFields.add(label);
          });
          _showMessage('Added "$label" as custom field', isError: false);
        } else {
          _showMessage('"$label" is already added', isError: true);
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFFFF8A00),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: const Color(0xFFFF8A00).withOpacity(0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final productId = _safeParseInt(product['productid']);
    final productName = product['productname']?.toString() ?? 'Unnamed';
    final price = _safeParseDouble(product['price']) ?? 0.0;
    final category = product['category']?.toString() ?? 'Uncategorized';
    final stock = _safeParseInt(product['amountinstock']) ?? 0;
    final imageUrl = product['productpicture']?.toString();
    final isInMenu = _menuProducts.any((p) => _safeParseInt(p['productid']) == productId);
    final isAvailable = stock > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade100,
                    image: imageUrl != null && imageUrl.isNotEmpty
                        ? DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    )
                        : null,
                  ),
                  child: imageUrl == null || imageUrl.isEmpty
                      ? Icon(Icons.store, color: Colors.grey.shade400)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${price.toStringAsFixed(0)} RWF',
                        style: TextStyle(
                          color: const Color(0xFFFF8A00),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isAvailable
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isAvailable ? 'In Stock ($stock)' : 'Out of Stock',
                              style: TextStyle(
                                color: isAvailable
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isInMenu
                                  ? Colors.blue.shade50
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isInMenu ? 'In Menu' : 'Not in Menu',
                              style: TextStyle(
                                color: isInMenu
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade700,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        category,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Switch(
                      value: isAvailable,
                      onChanged: (value) => _toggleProductAvailability(
                        productId!,
                        isAvailable,
                      ),
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      onPressed: () => _startEditProduct(product),
                      icon: Icon(Icons.edit, color: Colors.blue.shade600),
                      tooltip: 'Edit Product',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _addToMenu(productId!, productName),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isInMenu ? Colors.grey.shade400 : Colors.green.shade400,
                      ),
                      backgroundColor: isInMenu ? Colors.grey.shade50 : null,
                    ),
                    child: Text(
                      isInMenu ? 'Already in Menu ✓' : 'Add to Menu',
                      style: TextStyle(
                        color: isInMenu ? Colors.grey.shade600 : Colors.green.shade600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _deleteProduct(productId!, productName),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Delete Product',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(Map<String, dynamic> menuItem) {
    final menuId = _safeParseInt(menuItem['menuid']);
    final productId = _safeParseInt(menuItem['productid']);
    final productName = menuItem['productname']?.toString() ?? 'Unnamed';
    final price = _safeParseDouble(menuItem['price']) ?? 0.0;
    final stock = _safeParseInt(menuItem['amountinstock']) ?? 0;
    final isAvailable = menuItem['availability'] == true || menuItem['availability'] == 'true';
    final imageUrl = menuItem['productpicture']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.green.shade100, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade100,
                image: imageUrl != null && imageUrl.isNotEmpty
                    ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                )
                    : null,
              ),
              child: imageUrl == null || imageUrl.isEmpty
                  ? Icon(Icons.store, color: Colors.grey.shade400)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${price.toStringAsFixed(0)} RWF',
                    style: TextStyle(
                      color: const Color(0xFFFF8A00),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Switch(
                        value: isAvailable,
                        onChanged: (value) => _toggleMenuAvailability(menuId!, isAvailable),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isAvailable
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isAvailable ? 'Available' : 'Unavailable',
                          style: TextStyle(
                            color: isAvailable
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Stock: $stock',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Menu Item #$menuId • Product ID: $productId',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _removeFromMenu(menuId!, productName),
              icon: const Icon(Icons.remove_circle, color: Colors.red),
              tooltip: 'Remove from Menu',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddProductTab() {
    return Column(
      children: [
        // Status Info
        if (merchantId != null)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isEditing ? Colors.blue.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _isEditing ? Colors.blue.shade100 : Colors.green.shade100),
            ),
            child: Row(
              children: [
                Icon(
                  _isEditing ? Icons.edit : Icons.check_circle,
                  color: _isEditing ? Colors.blue.shade600 : Colors.green.shade600,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isEditing
                        ? 'Editing Product ID: $_editingProductId'
                        : 'Merchant ID: $merchantId • Ready to add products',
                    style: TextStyle(
                      color: _isEditing ? Colors.blue.shade800 : Colors.green.shade800,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (_isEditing)
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.blue.shade600, size: 18),
                    onPressed: _resetEditMode,
                    tooltip: 'Cancel Editing',
                  ),
              ],
            ),
          ),

        if (merchantId == null)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange.shade600, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Loading merchant information...',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh, color: Colors.orange.shade600, size: 18),
                  onPressed: _loadMerchantDetails,
                ),
              ],
            ),
          ),

        // Product Info Section
        _buildSection(
          title: _isEditing ? 'Edit Product Information' : 'Product Information',
          child: Column(
            children: [
              _buildInputField(
                label: 'Product Name',
                controller: _productNameController,
                hintText: 'e.g., Margherita Pizza',
              ),
              _buildCategoryDropdown(),
              _buildInputField(
                label: 'Price (RWF)',
                controller: _priceController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                hintText: 'e.g., 4500',
              ),
              _buildInputField(
                label: 'Stock Quantity',
                controller: _stockController,
                keyboardType: TextInputType.number,
                hintText: 'e.g., 50',
              ),
              _buildInputField(
                label: 'Description (Optional)',
                controller: _descriptionController,
                hintText: 'Product description for customers',
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              _buildImageUpload(),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Custom Fields Section
        _buildSection(
          title: 'Custom Fields',
          child: _buildCustomFields(),
        ),

        const SizedBox(height: 32),

        // Submit Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSaving || merchantId == null
                ? null
                : _isEditing
                ? _updateProduct
                : _createProduct,
            style: ElevatedButton.styleFrom(
              backgroundColor: merchantId == null
                  ? Colors.grey.shade400
                  : _isEditing
                  ? Colors.blue.shade600
                  : const Color(0xFFFF8A00),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : Text(
              _isEditing ? 'Update Product' : 'Create Product',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),

        if (_isEditing)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _resetEditMode,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Cancel Editing',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildManageProductsTab() {
    return Column(
      children: [
        const SizedBox(height: 20),

        // Stats
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF8A00), Color(0xFFFFB74D)],
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.inventory, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_existingProducts.length} Products',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_menuProducts.length} in Menu',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                    if (merchantId != null)
                      Text(
                        'Merchant ID: $merchantId',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadExistingProducts,
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh Products',
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Product List
        if (merchantId == null)
          Container(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                Icon(
                  Icons.store_mall_directory,
                  size: 60,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Merchant information not loaded',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we load your merchant details',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loadMerchantDetails,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Loading'),
                ),
              ],
            ),
          )
        else if (_isLoadingProducts)
          const Padding(
            padding: EdgeInsets.all(40.0),
            child: Column(
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Color(0xFFFF8A00)),
                ),
                SizedBox(height: 16),
                Text('Loading products...'),
              ],
            ),
          )
        else if (_existingProducts.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    Icons.inventory_2,
                    size: 60,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No products yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first product using the "Add Product" tab',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => setState(() => _currentTab = 0),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A00),
                    ),
                    child: const Text('Go to Add Product'),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _existingProducts.length,
              itemBuilder: (context, index) =>
                  _buildProductCard(_existingProducts[index]),
            ),
      ],
    );
  }

  Widget _buildMenuTab() {
    return Column(
      children: [
        const SizedBox(height: 20),

        // Menu Stats
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF27AE60), Color(0xFF2ECC71)],
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.restaurant_menu, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_menuProducts.length} Items in Menu',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Available on your store page',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                    if (merchantId != null)
                      Text(
                        'Merchant ID: $merchantId',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadMenuProducts,
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh Menu',
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Menu Items List
        if (merchantId == null)
          Container(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                Icon(
                  Icons.restaurant_menu,
                  size: 60,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Merchant information not loaded',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we load your merchant details',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          )
        else if (_isLoadingMenu)
          const Padding(
            padding: EdgeInsets.all(40.0),
            child: Column(
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Color(0xFF27AE60)),
                ),
                SizedBox(height: 16),
                Text('Loading menu items...'),
              ],
            ),
          )
        else if (_menuProducts.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    Icons.restaurant_menu,
                    size: 60,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Menu is empty',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add products to your menu from the "Manage Products" tab',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => setState(() => _currentTab = 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27AE60),
                    ),
                    child: const Text('Go to Manage Products'),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _menuProducts.length,
              itemBuilder: (context, index) =>
                  _buildMenuCard(_menuProducts[index]),
            ),
      ],
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1a3250),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Product Management',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (merchantId != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Merchant ID: $merchantId',
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios),
        ),
        backgroundColor: const Color(0xFFFF8A00),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Tab Navigation
          Container(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildTabButton('Add Product', 0, Icons.add_circle_outline),
                  _buildTabButton('Manage Products', 1, Icons.inventory),
                  _buildTabButton('Menu', 2, Icons.restaurant_menu),
                ],
              ),
            ),
          ),

          // Error/Success Messages
          if (_errorMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red.shade600, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.red.shade600, size: 18),
                    onPressed: () {
                      setState(() {
                        _errorMessage = '';
                      });
                    },
                  ),
                ],
              ),
            ),

          if (_successMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: Colors.green.shade50,
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _successMessage,
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.green.shade600, size: 18),
                    onPressed: () {
                      setState(() {
                        _successMessage = '';
                      });
                    },
                  ),
                ],
              ),
            ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _currentTab == 0
                  ? _buildAddProductTab()
                  : _currentTab == 1
                  ? _buildManageProductsTab()
                  : _buildMenuTab(),
            ),
          ),
        ],
      ),
      floatingActionButton: merchantId != null && !_isEditing
          ? FloatingActionButton(
        onPressed: () {
          _resetEditMode();
          setState(() => _currentTab = 0);
        },
        backgroundColor: const Color(0xFFFF8A00),
        child: const Icon(Icons.add, color: Colors.white),
        tooltip: 'Add New Product',
      )
          : null,
    );
  }

  Widget _buildTabButton(String label, int tabIndex, IconData icon) {
    final isSelected = _currentTab == tabIndex;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _currentTab = tabIndex),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isSelected ? const Color(0xFFFF8A00) : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: isSelected ? const Color(0xFFFF8A00) : Colors.grey.shade500,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFFF8A00) : Colors.grey.shade600,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _productNameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _descriptionController.dispose();
    for (var controller in _customFieldControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}