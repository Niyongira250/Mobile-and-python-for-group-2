import 'dart:convert';
import 'package:http/http.dart' as http;

class PayLookupService {
  static Future<Map<String, String>?> lookupByPaycode(String paycode) async {
    try {
      final response = await http.get(
        Uri.parse(
          "http://localhost:8000/api/paycode-lookup/?paycode=$paycode",
        ),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          "username": data["username"].toString(),
          "paycode": data["paycode"].toString(),
        };
      }
    } catch (_) {}
    return null;
  }
}
