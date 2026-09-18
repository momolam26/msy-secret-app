import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://192.168.1.67/api';
  // ⚠️ Remplace TON_IP_LOCAL par l'IP de ton Mac sur le réseau local
  // ex: 192.168.1.100 — trouve-la avec: ifconfig | grep inet

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_token', token);
  }

  static Future<Map<String, dynamic>> notifyPayment({
    required double amount,
    required String phone,
    required String paymentMethod,
  }) async {
    final token = await getToken();

    if (token == null) {
      return {'success': false, 'message': 'Token non configuré'};
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/payment-detected'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'amount': amount,
          'phone': phone,
          'payment_method': paymentMethod,
        }),
      );

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
