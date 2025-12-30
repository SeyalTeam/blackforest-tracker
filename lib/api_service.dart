import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_config.dart';

class ApiService {
  // Singleton Pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  static ApiService get instance => _instance;

  static const storage = FlutterSecureStorage();

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    final headers = Map<String, String>.from(ApiConfig.headers);
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // Cache Storage
  List<dynamic>? _cachedDepartments;
  List<dynamic>? _cachedBranches;
  final Map<String, List<dynamic>> _cachedCategories = {}; // Key: "onlyStock_deptId"
  final Map<String, List<dynamic>> _cachedStockOrders = {}; // Key: "start_end"

  void clearCache() {
    _cachedDepartments = null;
    _cachedBranches = null;
    _cachedCategories.clear();
    _cachedStockOrders.clear();
  }

  Future<String?> _getToken() async {
    return storage.read(key: 'token');
  }

  Future<List<dynamic>> fetchDepartments({bool forceRefresh = false}) async {
    if (_cachedDepartments != null && !forceRefresh) {
      return _cachedDepartments!;
    }

    try {
      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/departments?limit=1000'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _cachedDepartments = (data['docs'] as List?) ?? [];
        return _cachedDepartments!;
      } else {
        throw Exception('Failed to load departments');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchCategories({bool onlyStock = false, String? departmentId, bool forceRefresh = false}) async {
    final cacheKey = '${onlyStock}_${departmentId ?? "ALL"}';
    if (_cachedCategories.containsKey(cacheKey) && !forceRefresh) {
      return _cachedCategories[cacheKey]!;
    }

    try {
      // Added depth=1 to ensure department is populated in the response
      String url = '${ApiConfig.baseUrl}/categories?limit=1000&depth=1';
      if (onlyStock) {
        url += '&where[isStock][equals]=true';
      }
      if (departmentId != null) {
        url += '&where[department][equals]=$departmentId';
      }

      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['docs'] as List?) ?? [];
        _cachedCategories[cacheKey] = list;
        return list;
      } else {
        throw Exception('Failed to load categories');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchStockOrders({required DateTime fromDate, DateTime? toDate, bool forceRefresh = false}) async {
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = toDate != null
        ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59)
        : DateTime(fromDate.year, fromDate.month, fromDate.day, 23, 59, 59);

    final cacheKey = '${start.toIso8601String()}_${end.toIso8601String()}';
    
    if (_cachedStockOrders.containsKey(cacheKey) && !forceRefresh) {
      return _cachedStockOrders[cacheKey]!;
    }

    try {
      // Using deliveryDate as per recent requirement changes
      final url = '${ApiConfig.baseUrl}/stock-orders?limit=1000&depth=2'
          '&where[deliveryDate][greater_than]=${start.toUtc().toIso8601String()}'
          '&where[deliveryDate][less_than]=${end.toUtc().toIso8601String()}';

      final headers = await _getHeaders();

      final res = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['docs'] as List?) ?? [];
        _cachedStockOrders[cacheKey] = list;
        return list;
      } else {
        throw Exception('Failed to load stock orders');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchBranches({bool forceRefresh = false}) async {
    if (_cachedBranches != null && !forceRefresh) {
      return _cachedBranches!;
    }

    try {
      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches?limit=1000'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _cachedBranches = (data['docs'] as List?) ?? [];
        return _cachedBranches!;
      } else {
        throw Exception('Failed to load branches');
      }
    } catch (e) {
      rethrow;
    }
  }
}
