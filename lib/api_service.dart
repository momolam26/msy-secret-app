import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // ✅ Ajoute cette ligne
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl =
      'https://pancake-lion-unsent.ngrok-free.dev/api';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_token', token);
  }

  static Future<Map<String, String>> _headers() async {
    // final token = await getToken();
    const token = '1|d7hUWDDLpb8f9HUJ7ToV6DF1mqwDiVlt0OzOLMDwe842692a';

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  // Test de connexion
  static Future<Map<String, dynamic>> ping() async {
    try {
      debugPrint('Tentative connexion vers: $baseUrl/ping');
      final response = await http
          .get(Uri.parse('$baseUrl/ping'))
          .timeout(const Duration(seconds: 10));
      debugPrint('Status: ${response.statusCode}');
      debugPrint('Body: ${response.body}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('Erreur: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
  // static Future<Map<String, dynamic>> ping() async {
  //   try {
  //     final token = await getToken();
  //     debugPrint('Token utilisé: $token');
  //     debugPrint('URL: $baseUrl/ping');

  //     final response = await http
  //         .get(Uri.parse('$baseUrl/ping'), headers: await _headers())
  //         .timeout(const Duration(seconds: 5));

  //     debugPrint('Response: ${response.statusCode} ${response.body}');
  //     return jsonDecode(response.body);
  //   } catch (e) {
  //     debugPrint('Erreur ping: $e');
  //     return {'success': false, 'message': 'Serveur inaccessible: $e'};
  //   }
  // }

  // Détection automatique de paiement
  static Future<Map<String, dynamic>> notifyPayment({
    required double amount,
    required String phone,
    required String paymentMethod,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/payment-detected'),
        headers: await _headers(),
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

  // Liste des commandes non payées
  static Future<List<dynamic>> getUnpaidOrders() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/orders/unpaid'),
        headers: await _headers(),
      );
      final data = jsonDecode(response.body);
      return data['orders'] ?? [];
    } catch (e) {
      return [];
    }
  }

  // Confirmation manuelle
  static Future<Map<String, dynamic>> confirmPayment({
    required int orderId,
    required String paymentMethod,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/payment-confirm'),
        headers: await _headers(),
        body: jsonEncode({
          'order_id': orderId,
          'payment_method': paymentMethod,
        }),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Modifier le numéro de paiement
  static Future<Map<String, dynamic>> updatePaymentPhone({
    required int orderId,
    required String phone,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/orders/$orderId/payment-phone'),
        headers: await _headers(),
        body: jsonEncode({'payment_phone': phone}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
