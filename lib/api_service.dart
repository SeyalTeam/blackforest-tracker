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

  static const String _baseUrl = 'https://blackforest4.vseyal.com/api';
  static String get baseUrl => _baseUrl;
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
    String filterBy = 'deliveryDate',
    bool forceRefresh = false,
  }) async {
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = toDate != null
        ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59)
        : DateTime(fromDate.year, fromDate.month, fromDate.day, 23, 59, 59);

    final cacheKey =
        '${filterBy}_${start.toIso8601String()}_${end.toIso8601String()}';

    if (_cachedStockOrders.containsKey(cacheKey) && !forceRefresh) {
      return _cachedStockOrders[cacheKey]!;
    }

    try {
      final token = await _getToken();

      // Using deliveryDate as per recent requirement changes
      final url =
          '$_baseUrl/stock-orders?limit=1000&depth=2'
          '&where[$filterBy][greater_than]=${start.toUtc().toIso8601String()}'
          '&where[$filterBy][less_than]=${end.toUtc().toIso8601String()}';

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

  Future<List<dynamic>> fetchReviews({DateTime? date, String? branchId}) async {
    try {
      final token = await _getToken();

      String url = '$_baseUrl/reviews?limit=100&depth=1&sort=-createdAt';

      if (branchId != null && branchId.isNotEmpty && branchId != 'ALL') {
        url += '&where[branch][equals]=$branchId';
      }

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

  Future<List<dynamic>> fetchProductsByIds(
    List<String> productIds, {
    int depth = 1,
  }) async {
    final ids = productIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return [];

    try {
      final token = await _getToken();
      String url = '$_baseUrl/products?limit=${ids.length}&depth=$depth';
      for (int i = 0; i < ids.length; i++) {
        url += '&where[id][in][$i]=${Uri.encodeQueryComponent(ids[i])}';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load products by ids');
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

  Future<Map<String, dynamic>> fetchMediaById(String mediaId) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/media/$mediaId';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      } else {
        throw Exception('Failed to load media details');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchMediaByIds(List<String> mediaIds) async {
    final ids = mediaIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return [];

    try {
      final token = await _getToken();
      String url = '$_baseUrl/media?limit=${ids.length}';
      for (int i = 0; i < ids.length; i++) {
        url += '&where[id][in][$i]=${Uri.encodeQueryComponent(ids[i])}';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load media by ids');
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

  Future<void> createStockAlert({
    required String productId,
    required String branchId,
  }) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/stock-alerts'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'product': productId, 'branch': branchId}),
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('Failed to create stock alert: ${res.body}');
      }
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
          '&where[status][in][2]=prepared'
          '&where[status][in][3]=served'
          '&where[status][in][4]=delivered'
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
    String? status,
    int? preparingTime,
    int? preparationTime,
    String? actorUserId,
  }) async {
    try {
      final normalizedStatus = status?.trim();
      if (preparingTime != null && preparingTime < 0) {
        throw Exception('preparingTime must be a whole number >= 0');
      }
      if (preparationTime != null && preparationTime < 0) {
        throw Exception('preparationTime must be a whole number >= 0');
      }

      final payload = <String, dynamic>{'itemId': itemId};
      if (normalizedStatus != null && normalizedStatus.isNotEmpty) {
        payload['status'] = normalizedStatus;
        payload['kitchenStatus'] = normalizedStatus;
      }
      if (preparingTime != null) {
        payload['preparingTime'] = preparingTime;
      } else if (preparationTime != null) {
        payload['preparationTime'] = preparationTime;
      }

      // Send actorUserId so backend can record who performed the action
      if (actorUserId != null && actorUserId.isNotEmpty) {
        payload['actorUserId'] = actorUserId;
      }

      if (!payload.containsKey('status') &&
          !payload.containsKey('preparingTime') &&
          !payload.containsKey('preparationTime')) {
        throw Exception(
          'Either status or preparingTime/preparationTime must be provided',
        );
      }

      final token = await _getToken();
      final url = '$_baseUrl/billings/$billingId/items/status';

      final res = await http.patch(
        Uri.parse(url),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode != 200) {
        debugPrint(
          'DEBUG: updateBillingItemStatus failed. Status: ${res.statusCode}, Body: ${res.body}',
        );
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

  Future<List<dynamic>> fetchCompanies() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/companies?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load companies');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchRawMaterialCategories() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/raw-material-categories?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load raw material categories');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createRawMaterialCategory({
    required String name,
    required List<String> companyIds,
  }) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/raw-material-categories'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'company': companyIds,
        }),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create raw material category: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createRawMaterial({
    required String name,
    required String categoryId,
    required String unit,
    double? minimumStockLevel,
    String? dealerId,
  }) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/raw-materials'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'category': categoryId,
          'unit': unit,
          if (minimumStockLevel != null) 'minimumStockLevel': minimumStockLevel,
          if (dealerId != null) 'dealer': dealerId,
        }),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create raw material: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchRawMaterials() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/raw-materials?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load raw materials');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchDealers() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/dealers?limit=1000&depth=1'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load dealers');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createDealer({
    required String companyName,
    required String address,
    required String phoneNumber,
    required String email,
    required String contactName,
    required List<String> allowedCompanies,
    String? gst,
    String? pan,
  }) async {
    try {
      final token = await _getToken();
      final bodyMap = {
        'companyName': companyName,
        'address': address,
        'phoneNumber': phoneNumber,
        'email': email,
        'contactPerson': {
          'name': contactName,
        },
        'allowedCompanies': allowedCompanies,
        'isGSTRegistered': gst != null && gst.isNotEmpty,
        if (gst != null && gst.isNotEmpty) 'gst': gst,
        if (pan != null && pan.isNotEmpty) 'pan': pan,
        'status': 'active',
      };

      final res = await http.post(
        Uri.parse('$_baseUrl/dealers'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(bodyMap),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create dealer: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchRawMaterialDealers() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/raw-material-dealers?limit=1000&depth=1'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load raw material dealers');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createRawMaterialDealer({
    required String companyName,
    required String address,
    required String phoneNumber,
    required String email,
    required String contactName,
    required List<String> allowedCompanies,
    required bool isGSTRegistered,
    String? gst,
    String? pan,
    String? fssai,
    String? aadhar,
    String? contactDesignation,
    String? contactPhone,
    String? contactEmail,
    String? notes,
    required bool hasBankAccount,
    String? preferredPaymentMethod,
    String? bankName,
    String? accountNumber,
    String? ifscCode,
    String? bankBranch,
  }) async {
    try {
      final token = await _getToken();
      final bodyMap = {
        'companyName': companyName,
        'address': address,
        'phoneNumber': phoneNumber,
        'email': email,
        'contactPerson': {
          'name': contactName,
          if (contactDesignation != null && contactDesignation.isNotEmpty) 'designation': contactDesignation,
          if (contactPhone != null && contactPhone.isNotEmpty) 'phone': contactPhone,
          if (contactEmail != null && contactEmail.isNotEmpty) 'email': contactEmail,
        },
        'allowedCompanies': allowedCompanies,
        'isGSTRegistered': isGSTRegistered,
        if (isGSTRegistered && gst != null && gst.isNotEmpty) 'gst': gst,
        if (isGSTRegistered && pan != null && pan.isNotEmpty) 'pan': pan,
        if (isGSTRegistered && fssai != null && fssai.isNotEmpty) 'fssai': fssai,
        if (!isGSTRegistered && aadhar != null && aadhar.isNotEmpty) 'aadhar': aadhar,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'status': 'active',
        'hasBankAccount': hasBankAccount,
        if (!hasBankAccount && preferredPaymentMethod != null)
          'preferredPaymentMethod': preferredPaymentMethod,
        if (hasBankAccount)
          'bankDetails': {
            if (bankName != null && bankName.isNotEmpty) 'bankName': bankName,
            if (accountNumber != null && accountNumber.isNotEmpty) 'accountNumber': accountNumber,
            if (ifscCode != null && ifscCode.isNotEmpty) 'ifscCode': ifscCode,
            if (bankBranch != null && bankBranch.isNotEmpty) 'branch': bankBranch,
          },
      };

      final res = await http.post(
        Uri.parse('$_baseUrl/raw-material-dealers'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(bodyMap),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create raw material dealer: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchRawMaterialBillings() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/raw-material-billings?limit=1000&depth=2&sort=-date'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load raw material billings');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchLiveWaiters({required String branchId}) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/users?limit=150&depth=1&where[role][equals]=waiter&where[or][0][branch][equals]=$branchId&where[or][1][lastLoginBranch][equals]=$branchId';
      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final waiters = (data['docs'] as List?) ?? [];
        
        return waiters.map((user) {
          return {
            'id': user['id'] ?? user['_id'],
            'name': user['name'] ?? user['username'] ?? 'Waiter',
            'role': user['role'] ?? 'waiter',
            'email': user['email'] ?? '',
          };
        }).toList();
      } else {
        throw Exception('Failed to load waiters');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateBillNotes({
    required String billId,
    required String notes,
  }) async {
    try {
      final token = await _getToken();
      final res = await http.patch(
        Uri.parse('$_baseUrl/billings/$billId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'notes': notes}),
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      } else {
        throw Exception('Failed to update bill notes: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createBilling({
    required Map<String, dynamic> billingData,
  }) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/billings'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(billingData),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body);
      } else {
        throw Exception('Failed to create billing: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> callWaiter({
    required String branchId,
    String? billId,
    required String tableNumber,
    required String section,
    String? waiterId,
    String? callerName,
  }) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/call-waiter'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'branchId': branchId,
          if (billId != null && billId.isNotEmpty) 'billId': billId,
          'tableNumber': tableNumber,
          'section': section,
          if (waiterId != null && waiterId.isNotEmpty) 'waiterId': waiterId,
          if (callerName != null && callerName.isNotEmpty) 'callerName': callerName,
        }),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body);
      } else {
        throw Exception('Failed to trigger waiter call endpoint: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
