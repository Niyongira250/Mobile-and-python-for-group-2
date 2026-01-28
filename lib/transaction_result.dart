import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'home_page.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:open_file/open_file.dart';
import 'dart:html' as html; // For web only

class TransactionResultPage extends StatelessWidget {
  final String receiverName;
  final String receiverType; // 'user' or 'merchant'
  final double amount;
  final double charge;
  final double total;
  final double balance;
  final int transactionId;
  final String senderType; // 'user' or 'merchant'
  final DateTime date;
  final int? senderId;
  final int? receiverId;

  const TransactionResultPage({
    super.key,
    required this.receiverName,
    required this.receiverType,
    required this.amount,
    required this.charge,
    required this.total,
    required this.balance,
    required this.transactionId,
    required this.senderType,
    required this.date,
    this.senderId,
    this.receiverId,
  });

  // Helper method to format date - now accessible throughout the class
  String _formatDate(DateTime d) {
    return "${d.day} ${_getMonthName(d.month)} ${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  String _getMonthName(int m) {
    const months = [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December"
    ];
    return months[m - 1];
  }

  // Getter to check if transaction is to a merchant
  bool get isMerchantTransaction => receiverType == 'merchant';

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF8A00);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF2E9),
      body: SafeArea(
        child: Column(
          children: [
            // ------------ COMPACT SUCCESS HEADER ------------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF4CAF50),
                    Colors.green.shade300,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Success icon (smaller)
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Color(0xFF4CAF50),
                      size: 32,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Success message and transaction ID in one column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Payment Successful!",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          "ID: $transactionId",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Account type indicators (compact)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Sender type
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: senderType == 'merchant' ? Colors.orange : Colors.blue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            senderType == 'merchant' ? 'M' : 'U',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.arrow_forward, size: 12, color: Colors.white),
                        ),

                        // Receiver type
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isMerchantTransaction ? Colors.orange : Colors.blue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isMerchantTransaction ? 'M' : 'U',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Success summary (smaller)
                    Text(
                      "Successfully paid ${amount.toStringAsFixed(0)} RWF to $receiverName",
                      style: const TextStyle(fontSize: 14, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // ----------- COMPACT PAYMENT DETAILS BOX -----------
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: orange, width: 1.2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _compactRow("Transaction ID", transactionId.toString()),
                          _compactRow("Date", _formatDate(date)),
                          _compactRow("Type", "Normal transfer"),
                          _compactRow("Sender", senderType == 'merchant' ? "Merchant" : "User"),
                          _compactRow("Receiver", receiverName),
                          _compactRow("Receiver Account", isMerchantTransaction ? "Merchant" : "User"),
                          _compactRow("Amount", "${amount.toStringAsFixed(0)} RWF"),
                          _compactRow("Fee", "${charge.toStringAsFixed(0)} RWF"),
                          _compactRow("Total", "${total.toStringAsFixed(0)} RWF"),
                          _compactRow("New Balance", "${balance.toStringAsFixed(0)} RWF"),

                          const SizedBox(height: 8),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Status",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text(
                                  "Success",
                                  style: TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Account type info card (more compact)
                    if (isMerchantTransaction)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange, width: 0.8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.store,
                              color: Colors.orange.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "This payment was made to a merchant account.",
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue, width: 0.8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person,
                              color: Colors.blue.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "This payment was made to a user account.",
                                style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Action buttons (more compact)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => const HomePage()),
                                    (route) => false,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: orange,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              "Back to Home",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _generateReceiptPDF(context);
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: orange),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              "Save Receipt",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Share button (more compact)
                    OutlinedButton.icon(
                      onPressed: () {
                        _shareTransaction(context);
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.green),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.share, color: Colors.green, size: 16),
                      label: const Text(
                        "Share Transaction",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ---------- COMPACT TOTAL AMOUNT FOOTER ----------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isMerchantTransaction ? Colors.orange : Colors.green,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      "TOTAL PAID",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${total.toStringAsFixed(0)} RWF",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _compactRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                fontSize: 12,
              )
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _shareTransaction(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Share Transaction",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.message, color: Colors.green),
                title: const Text("Copy Details"),
                onTap: () {
                  Navigator.pop(context);
                  _copyToClipboard(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.save, color: Colors.blue),
                title: const Text("Save Receipt as PDF"),
                onTap: () {
                  Navigator.pop(context);
                  _generateReceiptPDF(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.orange),
                title: const Text("Show Receipt Preview"),
                onTap: () {
                  Navigator.pop(context);
                  _showReceiptPreview(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _copyToClipboard(BuildContext context) {
    final details = '''
Transaction ID: $transactionId
Date: ${_formatDate(date)}
Amount: ${amount.toStringAsFixed(0)} RWF
Receiver: $receiverName (${isMerchantTransaction ? 'Merchant' : 'User'})
Status: Success
Total: ${total.toStringAsFixed(0)} RWF
    ''';

    Clipboard.setData(ClipboardData(text: details));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Transaction details copied to clipboard"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ========== GENERATE PDF RECEIPT USING DJANGO API ==========
  Future<void> _generateReceiptPDF(BuildContext context) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generating receipt PDF...'),
            ],
          ),
        ),
      );

      // Call Django API to generate PDF receipt
      final uri = Uri.parse("http://localhost:8000/api/generate-transaction-receipt/")
          .replace(queryParameters: {
        'transaction_id': transactionId.toString(),
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      // Close loading dialog
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (response.statusCode == 200) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filename = 'receipt_$transactionId.pdf';

        if (kIsWeb) {
          await _downloadFileWeb(response.bodyBytes, filename);
        } else {
          await _downloadFileMobile(response.bodyBytes, filename);
        }
      } else {
        print('❌ Failed to generate receipt: ${response.statusCode}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to generate receipt: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on TimeoutException {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt generation timed out'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        print('🔥 Error generating receipt: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('Receipt downloaded: $filename'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ Web download error: $e');
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
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

      final receiptsDir = Directory('${directory!.path}/Receipts');
      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }

      final file = File('${receiptsDir.path}/$filename');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('Receipt saved: $filename'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      print('❌ Mobile download error: $e');
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('Error saving file: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showReceiptPreview(BuildContext context) {
    final receiptText = _generateReceiptText();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Receipt Preview'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    receiptText,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => _copyReceiptToClipboard(context),
                  child: const Text('Copy to Clipboard'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _copyReceiptToClipboard(BuildContext context) async {
    try {
      final receiptText = _generateReceiptText();
      await Clipboard.setData(ClipboardData(text: receiptText));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Receipt copied to clipboard"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error copying to clipboard: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _generateReceiptText() {
    return '''
# LOCO
## Free

### Amount in word
- For:
  - ACCT: ${amount.toStringAsFixed(0)} RWF
  - PAD: ${total.toStringAsFixed(0)} RWF
  - DUE: ${date.day}/${date.month}/${date.year}

---

### Receipt No.: $transactionId
- Date: ${_formatDate(date)}

---

**Transaction Details:**
- Sender: $senderType Account
- Receiver: $receiverName
- Receiver Type: ${isMerchantTransaction ? 'Merchant' : 'User'}
- Amount: ${amount.toStringAsFixed(0)} RWF
- Transaction Fee: ${charge.toStringAsFixed(0)} RWF
- Total Amount: ${total.toStringAsFixed(0)} RWF
- Date: ${_formatDate(date)}
- Status: Success
- Transaction ID: $transactionId

---

**A:** unidimensional  
**B:** uncertain objects  
**C:** uncertain objects  

---

**D:** Double  
**E:** Binary object  

---

**F:** Automated Signature

---
Generated on: ${DateTime.now().toString()}
''';
  }
}