import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  // Singleton Pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  static ApiService get instance => _instance;

  static const String _baseUrl = 'https://blackforest.vseyal.com/api';
  static const storage = FlutterSecureStorage();

  // Cache Storage
  List<dynamic>? _cachedDepartments;
  List<dynamic>? _cachedBranches;
  final Map<String, List<dynamic>> _cachedCategories =
      {}; // Key: "onlyStock_deptId"
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
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/departments?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
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

  Future<Map<String, dynamic>> fetchUserProfile() async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/users/me';
      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        debugPrint('DEBUG: fetchUserProfile success. Data: ${res.body}');
        return data['user'] ?? {};
      } else {
        throw Exception('Failed to fetch user profile');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchCategories({
    bool onlyStock = false,
    String? departmentId,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${onlyStock}_${departmentId ?? "ALL"}';
    if (_cachedCategories.containsKey(cacheKey) && !forceRefresh) {
      return _cachedCategories[cacheKey]!;
    }

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

  Future<List<dynamic>> fetchStockOrders({
    required DateTime fromDate,
    DateTime? toDate,
    bool forceRefresh = false,
  }) async {
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = toDate != null
        ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59)
        : DateTime(fromDate.year, fromDate.month, fromDate.day, 23, 59, 59);

    final cacheKey = '${start.toIso8601String()}_${end.toIso8601String()}';

    if (_cachedStockOrders.containsKey(cacheKey) && !forceRefresh) {
      return _cachedStockOrders[cacheKey]!;
    }

    try {
      final token = await _getToken();

      // Using deliveryDate as per recent requirement changes
      final url =
          '$_baseUrl/stock-orders?limit=1000&depth=2'
          '&where[deliveryDate][greater_than]=${start.toUtc().toIso8601String()}'
          '&where[deliveryDate][less_than]=${end.toUtc().toIso8601String()}';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
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
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/branches?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
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

  Future<List<dynamic>> fetchReviews({DateTime? date}) async {
    try {
      final token = await _getToken();

      String url = '$_baseUrl/reviews?limit=100&depth=1&sort=-createdAt';

      if (date != null) {
        final start = DateTime(
          date.year,
          date.month,
          date.day,
        ).toUtc().toIso8601String();
        final end = DateTime(
          date.year,
          date.month,
          date.day,
          23,
          59,
          59,
        ).toUtc().toIso8601String();
        url +=
            '&where[createdAt][greater_than]=$start&where[createdAt][less_than]=$end';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception(
          'Failed to load reviews: ${res.statusCode} ${res.body}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> replyToReview(
    String reviewId,
    String itemId,
    String replyText,
  ) async {
    try {
      final token = await _getToken();

      // 1. Fetch the specific review first to get current structure
      final getRes = await http.get(
        Uri.parse('$_baseUrl/reviews/$reviewId'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (getRes.statusCode != 200) {
        throw Exception('Failed to fetch review for update');
      }

      final reviewData = jsonDecode(getRes.body);
      final items = (reviewData['items'] as List?) ?? [];

      // 2. Find and update the specific item
      bool found = false;
      final updatedItems = items.map((item) {
        final currentId = item['id'] ?? item['_id'];
        if (currentId == itemId) {
          found = true;
          return {
            ...item,
            'chefReply': replyText,
            // 'status': 'replied' // Let backend hook handle status
          };
        }
        return item;
      }).toList();

      if (!found) {
        throw Exception('Review item not found');
      }

      // 3. Patch the review with updated items array
      final patchRes = await http.patch(
        Uri.parse('$_baseUrl/reviews/$reviewId'),
        headers: token != null
            ? {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              }
            : {},
        body: jsonEncode({'items': updatedItems}),
      );

      if (patchRes.statusCode != 200) {
        throw Exception('Failed to submit reply: ${patchRes.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchKitchenDetails(String kitchenId) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/kitchens/$kitchenId';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      } else {
        throw Exception('Failed to load kitchen details');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchKitchens() async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/kitchens?limit=1000';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load kitchens');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchProducts({List<String>? categoryIds}) async {
    try {
      final token = await _getToken();
      String url = '$_baseUrl/products?limit=1000&depth=1';

      if (categoryIds != null && categoryIds.isNotEmpty) {
        for (int i = 0; i < categoryIds.length; i++) {
          url += '&where[category][in][$i]=${categoryIds[i]}';
        }
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load products');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchProductById(String productId) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/products/$productId?depth=0';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      } else {
        throw Exception('Failed to load product details');
      }
    } catch (e) {
      rethrow;
    }
  }

  bool? _readIsOutOfStock(Map<String, dynamic> product) {
    final isStock = product['isStock'];
    if (isStock is bool) {
      return !isStock;
    }

    final isOutOfStock = product['isOutOfStock'];
    if (isOutOfStock is bool) {
      return isOutOfStock;
    }

    return null;
  }

  Future<bool> updateProductStockStatus(
    String productId,
    bool isOutOfStock,
  ) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/products/$productId';

      final res = await http.patch(
        Uri.parse(url),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'isStock': !isOutOfStock,
          'isOutOfStock': isOutOfStock,
        }),
      );

      if (res.statusCode != 200) {
        throw Exception('Failed to update product status: ${res.body}');
      }

      final refreshedProduct = await fetchProductById(productId);
      final savedValue = _readIsOutOfStock(refreshedProduct);
      final savedIsStock = refreshedProduct['isStock'];

      if (savedValue is! bool ||
          savedValue != isOutOfStock ||
          savedIsStock is! bool ||
          savedIsStock != !isOutOfStock) {
        throw Exception('Stock status was not saved. Please try again.');
      }

      return savedValue;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchKitchenKOTs({
    required String branchId,
    required String kitchenId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final token = await _getToken();

      String url =
          '$_baseUrl/billings?limit=100&depth=3'
          '&where[branch][equals]=$branchId'
          '&where[status][in][0]=ordered'
          '&where[status][in][1]=confirmed'
          '&sort=-createdAt';

      if (fromDate != null) {
        final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
        url +=
            '&where[createdAt][greater_than]=${start.toUtc().toIso8601String()}';

        final end = toDate != null
            ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59)
            : DateTime(fromDate.year, fromDate.month, fromDate.day, 23, 59, 59);
        url += '&where[createdAt][less_than]=${end.toUtc().toIso8601String()}';
      }

      debugPrint('DEBUG: Calling fetchKitchenKOTs with URL: $url');

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      debugPrint('DEBUG: fetchKitchenKOTs response status: ${res.statusCode}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['docs'] as List?) ?? [];
        debugPrint('DEBUG: fetchKitchenKOTs parsed ${list.length} docs');
        return list;
      } else {
        debugPrint('DEBUG: fetchKitchenKOTs failed: ${res.body}');
        throw Exception('Failed to load kitchen orders');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateBillingItemStatus({
    required String billingId,
    required String itemId,
    required String status,
  }) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/billings/$billingId/items/status';

      final res = await http.patch(
        Uri.parse(url),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'itemId': itemId, 'status': status}),
      );

      if (res.statusCode != 200) {
        throw Exception('Failed to update item status: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> fetchBillingItemPreparationTime({
    required String billingId,
    required String itemId,
  }) async {
    try {
      final token = await _getToken();
      final url =
          '$_baseUrl/billings/$billingId/items/preparation-time?itemId=$itemId';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
        return null;
      }

      if (res.statusCode == 404 || res.statusCode == 204) {
        return null;
      }

      throw Exception('Failed to load preparation time: ${res.body}');
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchBillings({
    String? status,
    DateTime? fromDate,
    String? createdBy,
    String? branchId,
    int depth = 1,
    int limit = 100,
  }) async {
    try {
      final token = await _getToken();
      String url =
          '$_baseUrl/billings?limit=$limit&depth=$depth&sort=-createdAt';

      if (status != null) {
        url += '&where[status][equals]=$status';
      }
      if (branchId != null) {
        url += '&where[branch][equals]=$branchId';
      }
      if (createdBy != null) {
        url += '&where[createdBy][equals]=$createdBy';
      }
      if (fromDate != null) {
        final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
        url +=
            '&where[createdAt][greater_than_equal]=${start.toUtc().toIso8601String()}';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load billings');
      }
    } catch (e) {
      rethrow;
    }
  }
}
