import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String _baseUrl = 'https://admin.theblackforestcakes.com/api';
  static const storage = FlutterSecureStorage();

  Future<String?> _getToken() async {
    return storage.read(key: 'token');
  }

  Future<List<dynamic>> fetchDepartments() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/departments?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load departments');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchCategories({bool onlyStock = false, String? departmentId}) async {
    try {
      final token = await _getToken();
      // Added depth=1 to ensure department is populated in the response
      String url = '$_baseUrl/categories?limit=1000&depth=1';
      if (onlyStock) {
        url += '&where[isStock][equals]=true';
      }
      if (departmentId != null) {
        url += '&where[department][equals]=$departmentId';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load categories');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchStockOrders({required DateTime fromDate, DateTime? toDate}) async {
    try {
      final token = await _getToken();
      final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
      final end = toDate != null
          ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59)
          : DateTime(fromDate.year, fromDate.month, fromDate.day, 23, 59, 59);

      // Using deliveryDate as per recent requirement changes
      final url = '$_baseUrl/stock-orders?limit=1000&depth=2'
          '&where[deliveryDate][greater_than]=${start.toUtc().toIso8601String()}'
          '&where[deliveryDate][less_than]=${end.toUtc().toIso8601String()}';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load stock orders');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchBranches() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/branches?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load branches');
      }
    } catch (e) {
      rethrow;
    }
  }
}
