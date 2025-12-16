import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class StockOrderReportPage extends StatefulWidget {
  final String? initialBranchId;
  final DateTime? initialFromDate;
  final DateTime? initialToDate;
  final String? categoryId;
  final String? categoryName;
  final String? departmentId;
  final String? departmentName;

  const StockOrderReportPage({
    super.key,
    this.initialBranchId,
    this.initialFromDate,
    this.initialToDate,
    this.categoryId,
    this.categoryName,
    this.departmentId,
    this.departmentName,
  });

  @override
  State<StockOrderReportPage> createState() => _StockOrderReportPageState();
}

class _StockOrderReportPageState extends State<StockOrderReportPage> {
  bool _loading = true;
  bool _loadingBranches = true;
  DateTime? fromDate;
  DateTime? toDate;
  List<Map<String, String>> branches = [];
  String selectedBranchId = 'ALL';
  List<Map<String, dynamic>> stockOrders = [];
  List<Map<String, dynamic>> _visibleStockOrders = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> departments = [];
  Map<String, dynamic>? _combinedOrder;
  String _userRole = '';
  
  bool get isChef => _userRole == 'chef';
  bool get isSupervisor => _userRole == 'supervisor';
  bool get isDriver => _userRole == 'driver';
  bool get isFactory => _userRole == 'factory';
  // Consolidated View Cache
  List<Map<String, dynamic>> _consolidatedItems = [];
  String _headerBranchCodes = '';
  String _headerDeliveryStr = '';
  String _headerCreatedStr = '';
  String _headerSubtitle = '';
  
  bool _isConsolidatedExpanded = false;

  // Map to track local edits: OrderID_ItemID -> Controller
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    fromDate = widget.initialFromDate ?? now;
    toDate = widget.initialToDate ?? now;
    if (widget.initialBranchId != null) {
      selectedBranchId = widget.initialBranchId!;
    }
    _bootstrap();
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _getUserRole();
    await _fetchBranches();
    await _fetchDepartments();
    await _fetchCategories();
    await _fetchStockOrders();
  }

  Future<void> _getUserRole() async {
    const storage = FlutterSecureStorage();
    String? role = await storage.read(key: 'userRole');
    setState(() {
      _userRole = role?.toLowerCase() ?? '';
    });
  }

  Future<String?> _getToken() async {
    const storage = FlutterSecureStorage();
    return storage.read(key: 'token');
  }

  Future<void> _fetchBranches() async {
    setState(() => _loadingBranches = true);
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/branches?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];
        final list = <Map<String, String>>[]; // 'ALL' is added manually in UI
        for (var b in docs) {
          final id = (b['id'] ?? b['_id'])?.toString();
          final name = (b['name'] ?? 'Unnamed Branch').toString();
          if (id != null) list.add({'id': id, 'name': name});
        }
        setState(() => branches = list);
      }
    } catch (e) {
      debugPrint('fetchBranches error: $e');
      setState(() => branches = [
        {'id': '1', 'name': 'Factory'},
      ]);
    } finally {
      setState(() => _loadingBranches = false);
    }
  }

  Future<void> _fetchDepartments() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/departments?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = (data['docs'] as List?) ?? [];
        setState(() {
          departments = docs.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('Error fetching departments: $e');
    }
  }

  // Helper
  String _formatQty(num val) {
    if (val % 1 == 0) return val.toInt().toString();
    return val.toString();
  }

  Future<void> _fetchCategories() async {
    try {
       final token = await _getToken();
       final res = await http.get(
         Uri.parse('https://admin.theblackforestcakes.com/api/categories?limit=1000'),
         headers: token != null ? {'Authorization': 'Bearer $token'} : {},
       );
       if (res.statusCode == 200) {
         final data = jsonDecode(res.body);
         final docs = (data['docs'] as List?) ?? [];
         setState(() {
           categories = docs.cast<Map<String, dynamic>>();
         });
       }
    } catch (e) {
      debugPrint('Error fetching categories: $e');
    }
  }

  List<Map<String, dynamic>> _availableBranches = [];

  Future<void> _fetchStockOrders() async {
    if (fromDate == null) return;
    setState(() {
       _loading = true;
       stockOrders = []; // Clear to prevent stale data
    });
    // Clear old controllers on refresh
    _controllers.clear();
    
    try {
      final token = await _getToken();
      final start = DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
      final end = toDate != null
          ? DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59)
          : DateTime(fromDate!.year, fromDate!.month, fromDate!.day, 23, 59, 59);

      // Removed branch filter from API to get all potential branches for the chips
      var url = 'https://admin.theblackforestcakes.com/api/stock-orders?limit=1000&depth=2'
          '&where[deliveryDate][greater_than]=${start.toUtc().toIso8601String()}'
          '&where[deliveryDate][less_than]=${end.toUtc().toIso8601String()}'
          '&t=${DateTime.now().millisecondsSinceEpoch}'; // Cache buster

      final res = await http.get(Uri.parse(url), 
        headers: token != null ? {'Authorization': 'Bearer $token'} : {});

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] ?? [];

        setState(() {
          stockOrders = docs.cast<Map<String, dynamic>>();
          stockOrders.sort((a, b) {
            final dateA = DateTime.tryParse(a['createdAt'] ?? '');
            final dateB = DateTime.tryParse(b['createdAt'] ?? '');
            if (dateA == null && dateB == null) return 0;
            if (dateA == null) return 1;
            if (dateB == null) return -1;
            return dateB.compareTo(dateA);
          });
          
          _processStockOrders();
        });
      }
    } catch (e) {
      debugPrint('fetchStockOrders error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _processStockOrders() {
      // 1. No need to filter available branches from orders. Use logic 'branches' from _fetchBranches.
      // Removed complex logic that filtered available branches and reset selectedBranchId
      // This ensures if a user selects a branch, it STAYS selected even if no data is present.

      // 2. Pre-calculate Consolidated Data
      Map<String, Map<String, dynamic>> productGroups = {};
      double totalReqAmt = 0;
      double totalSent = 0;
      
      final Set<String> branchCodes = {};
      DateTime? maxDeliveryDate;
      DateTime? maxCreatedDate;

      // Filter orders by Branch Selection
      final filteredOrders = selectedBranchId == 'ALL' 
          ? stockOrders 
          : stockOrders.where((o) {
              final b = o['branch'];
              final bid = b is Map ? (b['id'] ?? b['_id']) : null;
              return bid == selectedBranchId;
            }).toList();

      _visibleStockOrders = filteredOrders;
      Set<String> uniqueCategories = {}; // Init Set

      for (var order in filteredOrders) {
          final orderId = order['id'] ?? order['_id'];
          
          final branch = order['branch'];
          String code = 'UNK';
          if (branch is Map && branch['name'] != null) {
              String name = branch['name'];
              code = name.length > 3 ? name.substring(0, 3).toUpperCase() : name.toUpperCase();
          }
          
          final dDate = DateTime.tryParse(order['deliveryDate'] ?? '');
          if (dDate != null) {
             if (maxDeliveryDate == null || dDate.isAfter(maxDeliveryDate)) maxDeliveryDate = dDate;
          }
          
          final cDate = DateTime.tryParse(order['createdAt'] ?? '');
          if (cDate != null) {
             if (maxCreatedDate == null || cDate.isAfter(maxCreatedDate)) maxCreatedDate = cDate;
          }

          final items = (order['items'] as List?) ?? [];
          for (var item in items) {
              final product = item['product'];
              final pMap = product is Map ? product : {};
              dynamic catObj = pMap['category'];
              
              // Resolve Category Map for ID and Dept checks
              String cId = '';
              Map<String, dynamic>? cMap;
              if (catObj is Map) {
                 cId = catObj['id'] ?? catObj['_id'] ?? '';
                 cMap = catObj as Map<String, dynamic>;
              } else if (catObj is String) {
                 cId = catObj;
                 final found = categories.firstWhere((c) => c['id'] == cId, orElse: () => {});
                 if (found.isNotEmpty) cMap = found;
              }

              // Filter by Category if set
              if (widget.categoryId != null) {
                 if (cId != widget.categoryId) continue;
              } 
              // Filter by Department if set
              else if (widget.departmentId != null) {
                 String dId = '';
                 if (cMap != null) {
                    final d = cMap['department'];
                    if (d is Map) dId = d['id'] ?? d['_id'] ?? '';
                    else if (d is String) dId = d;
                 }
                 if (dId != widget.departmentId) continue;
              }
              
              // ... (rest of processing)
              
              branchCodes.add(code);

              // product is already declared above
              String pid = '';
              String pName = 'Unknown';
              String pImage = ''; 
              Map<String, dynamic> pObj = {};

              if (product is Map) {
                  pid = product['id'] ?? product['_id'] ?? '';
                  pName = product['name'] ?? 'Unknown';
                  pObj = product as Map<String, dynamic>;
              } else {
                  pid = product.toString();
              }
              
              // Metadata
              final meta = _getItemMetadata(product); 
              pName = meta['name']!;
              final dept = meta['department']!;
              final cat = meta['category']!;
              
              // 1. Collect Categories
              uniqueCategories.add(cat);
              
              // 2. Filter by Selected Category
              if (_selectedCategoryFilter != 'ALL' && cat != _selectedCategoryFilter) {
                 continue;
              }

              final reqQty = ((item['requiredQty'] as num?) ?? 0).toDouble();
              final sentQty = ((item['sendingQty'] as num?) ?? 0).toDouble();
              final status = item['status'] ?? 'pending';

              if (!productGroups.containsKey(pid)) {
                  productGroups[pid] = {
                      'type': 'item',
                      'productId': pid,
                      'productName': pName,
                      'product': pObj, // Store full object for image
                      'departmentName': dept,
                      'categoryName': cat,
                      'requiredQty': 0.0,
                      'sendingQty': 0.0,
                      'confirmedQty': 0.0, 
                      'pickedQty': 0.0, // NEW: Aggregate Picked
                      'inStock': 0,
                      'statuses': <String>{},
                      'originalItems': [], // Track source items for updating
                      'price': 0.0,
                      'unit': '',
                  };
              }
              
              final grp = productGroups[pid]!;
              grp['requiredQty'] = (grp['requiredQty'] as double) + reqQty;
              grp['sendingQty'] = (grp['sendingQty'] as double) + sentQty;
              grp['confirmedQty'] = (grp['confirmedQty'] as double) + ((item['confirmedQty'] as num?) ?? 0).toDouble(); 
              grp['pickedQty'] = (grp['pickedQty'] as double) + ((item['pickedQty'] as num?) ?? 0).toDouble(); // Aggregate Picked

              (grp['statuses'] as Set).add(status);
              if (((item['confirmedQty'] as num?) ?? 0) > 0) {
                 (grp['statuses'] as Set).add('confirmed');
              }
              if (((item['pickedQty'] as num?) ?? 0) > 0) {
                 (grp['statuses'] as Set).add('picked');
              }
              (grp['originalItems'] as List).add({
                 'orderId': orderId,
                 'item': item, // Reference for update
                 'branchCode': code,
              });
              
              // Totals & Metadata
              double price = 0.0;
              String unit = '';

              if (product is Map) {
                  if (product['defaultPriceDetails'] != null && product['defaultPriceDetails'] is Map) {
                      final details = product['defaultPriceDetails'];
                      price = ((details['price'] ?? 0) as num).toDouble();
                      final qty = ((details['quantity'] ?? 0) as num).toDouble();
                      final u = details['unit'] ?? '';
                      unit = '${_formatQty(qty)}$u'; 
                  } else {
                      price = ((product['price'] ?? 0) as num).toDouble();
                      unit = product['unit'] ?? '';
                  }
              }
              
              grp['price'] = price;
              grp['unit'] = unit;
              
              totalReqAmt += (reqQty * price);
              totalSent += sentQty;
          }
      }
      
      // Update Available Categories
      final sortedCats = uniqueCategories.toList()..sort();
      _availableCategories = ['ALL', ...sortedCats];

      final dateFmt = DateFormat('MMM d, h:mm a');
      _headerDeliveryStr = maxDeliveryDate != null ? dateFmt.format(maxDeliveryDate.add(const Duration(hours: 5, minutes: 30))) : '';
      _headerCreatedStr = maxCreatedDate != null ? dateFmt.format(maxCreatedDate.add(const Duration(hours: 5, minutes: 30))) : '';
      _headerBranchCodes = branchCodes.join(', ');
      
      // Flatten groups to list and Sort
      final rawList = productGroups.values.toList().cast<Map<String, dynamic>>();
      rawList.sort((a, b) {
         int cmp = (a['departmentName'] ?? '').compareTo(b['departmentName'] ?? '');
         if (cmp != 0) return cmp;
         
         cmp = (a['categoryName'] ?? '').compareTo(b['categoryName'] ?? '');
         if (cmp != 0) return cmp;

          // Sort Approved/Done items to bottom of category
          bool aDone = false;
          bool bDone = false;

          if (isChef) {
             aDone = ((a['sendingQty'] as num?) ?? 0) > 0;
             bDone = ((b['sendingQty'] as num?) ?? 0) > 0;
          } else if (isSupervisor) {
             aDone = ((a['confirmedQty'] as num?) ?? 0) > 0;
             bDone = ((b['confirmedQty'] as num?) ?? 0) > 0;
          } else if (isDriver) {
             aDone = ((a['pickedQty'] as num?) ?? 0) > 0;
             bDone = ((b['pickedQty'] as num?) ?? 0) > 0;
          }

          if (isSupervisor) {
             // Supervisor Priority:
             // 1. Pending (Sent > 0, Conf == 0) -> Priority 0
             // 2. Zero (Sent == 0) -> Priority 1
             // 3. Approved (Sent > 0, Conf > 0) -> Priority 2 [Requested: Show After Zero]
             
             int getScore(Map<String, dynamic> item) {
                final sent = ((item['sendingQty'] as num?) ?? 0).toDouble();
                final conf = ((item['confirmedQty'] as num?) ?? 0).toDouble();
                
                if (sent > 0 && conf == 0) return 0; // Pending
                if (sent == 0) return 1; // Zero
                return 2; // Approved
             }
             
             final aScore = getScore(a);
             final bScore = getScore(b);
             
             if (aScore != bScore) return aScore - bScore;

          } else if (isDriver) {
             // Driver Priority:
             // 1. Pending (Conf > 0, Pick == 0) -> Priority 0
             // 2. Zero (Conf == 0) -> Priority 1
             // 3. Picked (Conf > 0, Pick > 0)  -> Priority 2 [Requested: Show After Zero]
             
             int getScore(Map<String, dynamic> item) {
                final conf = ((item['confirmedQty'] as num?) ?? 0).toDouble();
                final pick = ((item['pickedQty'] as num?) ?? 0).toDouble();
                
                if (conf > 0 && pick == 0) return 0; // Pending
                if (conf == 0) return 1; // Zero
                return 2; // Picked
             }

             final aScore = getScore(a);
             final bScore = getScore(b);

             if (aScore != bScore) return aScore - bScore;
             
          } else if (aDone != bDone) {
             return aDone ? 1 : -1; // Others: Done Last (Simple)
          }
          
          return (a['productName'] ?? '').compareTo(b['productName'] ?? '');
      });

      // Insert Headers
      _consolidatedItems = []; // Re-populate
       String? lastDept;
       String? lastCat;
       int stripeIdx = 0;
       
       // 2a. Pre-calculate Category Totals
       // We need another pass or efficient way to sum up items per category
       // Since list is sorted by Dept -> Category -> Name, we can do it on the fly or pre-calc map.
       // Map is safer since we might insert headers.
       
       Map<String, Map<String, double>> categoryTotals = {}; 
       // Key: CategoryName, Value: {req, sent, conf, pick}
       
       for (var item in rawList) {
          final cat = item['categoryName'] as String;
          if (!categoryTotals.containsKey(cat)) {
             categoryTotals[cat] = {'req': 0.0, 'sent': 0.0, 'conf': 0.0, 'pick': 0.0};
          }
          final totals = categoryTotals[cat]!;
          totals['req'] = (totals['req']!) + ((item['requiredQty'] as num).toDouble());
          totals['sent'] = (totals['sent']!) + ((item['sendingQty'] as num).toDouble());
          totals['conf'] = (totals['conf']!) + ((item['confirmedQty'] as num).toDouble());
          totals['pick'] = (totals['pick']!) + ((item['pickedQty'] as num).toDouble());
       }

       for (var item in rawList) {
          final dept = item['departmentName'] as String;
          final cat = item['categoryName'] as String;
          if (dept != lastDept && widget.categoryId == null) {
              _consolidatedItems.add({'type': 'header_dept', 'title': dept});
              lastDept = dept;
              lastCat = null; 
          }
          if (cat != lastCat && widget.categoryId == null) {
              final totals = categoryTotals[cat] ?? {'req': 0.0, 'sent': 0.0, 'conf': 0.0, 'pick': 0.0};
              _consolidatedItems.add({
                  'type': 'header_cat', 
                  'title': cat,
                  'totals': totals
              });
              lastCat = cat;
          }
          
          item['stripeIndex'] = stripeIdx++;
          _consolidatedItems.add(item);
       }

      _headerSubtitle = '${_consolidatedItems.where((i) => i['type'] == 'item').length} Products     Req Amt: ${totalReqAmt.toInt()}     Snt Qty: ${_formatQty(totalSent)}';
      _combinedOrder = null; 
  }


  Map<String, String> _getItemMetadata(dynamic product) {
    
    final pMap = product is Map ? product : {};
    final pName = pMap['name'] ?? 'Unknown Product';
    
    // Extract Category and Dept
    // If product has populated category object
    dynamic catObj = pMap['category'];
    String catName = 'Uncategorized';
    String deptName = 'No Department';
    
    if (catObj is String) {
        // ID reference, look up in categories list
        final foundCat = categories.firstWhere((c) => c['id'] == catObj, orElse: () => {});
        if (foundCat.isNotEmpty) {
           catName = foundCat['name'] ?? 'Uncategorized';
           // Check dept in category
           final d = foundCat['department'];
           if (d is Map) deptName = d['name'] ?? 'No Department';
           else if (d is String) {
               final foundDept = departments.firstWhere((dp) => dp['id'] == d, orElse: () => {});
               if (foundDept.isNotEmpty) deptName = foundDept['name'] ?? 'No Department';
           }
        }
    } else if (catObj is Map) {
        catName = catObj['name'] ?? 'Uncategorized';
        final d = catObj['department'];
        if (d is Map) deptName = d['name'] ?? 'No Department';
           else if (d is String) {
               final foundDept = departments.firstWhere((dp) => dp['id'] == d, orElse: () => {});
               if (foundDept.isNotEmpty) deptName = foundDept['name'] ?? 'No Department';
           }
    } 

    return {
      'name': pName,
      'category': catName,
      'department': deptName,
    };
  }

  // Helper to get unique ID for controller key
  String _getItemKey(String orderId, dynamic item) {
    String pid = '';
    if (item['product'] is Map) {
      pid = item['product']['id'] ?? item['product']['_id'] ?? '';
    } else {
      pid = item['product']?.toString() ?? '';
    }
    return '${orderId}_$pid';
  }

  Future<void> _updateItemStatus(String orderId, Map<String, dynamic> itemToUpdate, double newSentQty) async {
    final token = await _getToken();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Updating...'), duration: Duration(milliseconds: 500)),
    );

    try {
      // 1. Find the order to get full list of items
      // We need to send ALL items back to Payload CMS to update the array properly, 
      // or at least that's the safest way without a custom endpoint.
      // We use the local `stockOrders` list which should be up to date with `itemToUpdate` reference generally,
      // but let's be safe and use parameters.
      
      final orderIndex = stockOrders.indexWhere((o) => (o['id'] ?? o['_id']) == orderId);
      if (orderIndex == -1) {
         debugPrint('Order not found locally for update');
         return;
      }
      final order = stockOrders[orderIndex];
      final currentItems = (order['items'] as List?) ?? [];
      
      // 2. Prepare Items Payload
      // We must map existing items to the format expected by API
      // Usually: { "product": "ID", "sendingQty": N, "status": "S", ... }
      
      List<Map<String, dynamic>> apiItems = [];
      bool found = false;

      for (var item in currentItems) {
        // Identify item by product ID
        String pid = '';
        if (item['product'] is Map) {
          pid = item['product']['id'] ?? item['product']['_id'] ?? '';
        } else {
          pid = item['product']?.toString() ?? '';
        }

        String targetPid = '';
        if (itemToUpdate['product'] is Map) {
          targetPid = itemToUpdate['product']['id'] ?? itemToUpdate['product']['_id'] ?? '';
        } else {
          targetPid = itemToUpdate['product']?.toString() ?? '';
        }

        // Clone item for API
        // WARNING: Payload might reject unknown fields if we just dump everything.
        // Safer to construct specific fields or use clean clone.
        // For now, let's try to preserve structure but ensure 'product' is ID.
        Map<String, dynamic> apiItem = Map<String, dynamic>.from(item);
        
        // Fix Product to be ID string
        apiItem['product'] = pid; 

        // Remove expanded fields that shouldn't be sent back if they confuse the API
        apiItem.remove('id'); // ID of the item row itself might be needed or not? usually Payload handles array items by position or _id. 
        // If we remove _id, it might create new items. Let's keep _id if present.
        
        if (pid == targetPid) {
          found = true;
          apiItem['sendingQty'] = newSentQty;
          apiItem['status'] = 'sending';
          
          // Update local reference immediately for UI responsiveness (already done in calling code via setState, but good to ensure)
          itemToUpdate['status'] = 'sending';
          itemToUpdate['sendingQty'] = newSentQty;
        }
        
        apiItems.add(apiItem);
      }

      if (!found) {
         debugPrint('Item not found in order items list');
         return;
      }

      // 3. Send PATCH Request
      final url = 'https://admin.theblackforestcakes.com/api/stock-orders/$orderId';
      final res = await http.patch(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'items': apiItems,
        }),
      );

      if (res.statusCode == 200) {
        // Success
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved successfully'), backgroundColor: Colors.green, duration: Duration(milliseconds: 800)),
        );
      } else {
        throw Exception('Failed to update: ${res.statusCode} ${res.body}');
      }

    } catch (e) {
      debugPrint('Error updating item: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _updateConfirmQty(String orderId, Map<String, dynamic> itemToUpdate, double qty) async {
    final token = await _getToken();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Confirming...'), duration: Duration(milliseconds: 500)),
    );

    try {
      final orderIndex = stockOrders.indexWhere((o) => (o['id'] ?? o['_id']) == orderId);
      if (orderIndex == -1) return;
      final order = stockOrders[orderIndex];
      final currentItems = (order['items'] as List?) ?? [];
      
      List<Map<String, dynamic>> apiItems = [];
      bool found = false;

      for (var item in currentItems) {
        String pid = '';
        if (item['product'] is Map) {
          pid = item['product']['id'] ?? item['product']['_id'] ?? '';
        } else {
          pid = item['product']?.toString() ?? '';
        }

        String targetPid = '';
        if (itemToUpdate['product'] is Map) {
          targetPid = itemToUpdate['product']['id'] ?? itemToUpdate['product']['_id'] ?? '';
        } else {
          targetPid = itemToUpdate['product']?.toString() ?? '';
        }

        Map<String, dynamic> apiItem = Map<String, dynamic>.from(item);
        apiItem['product'] = pid; 
        apiItem.remove('id'); 
        
        if (pid == targetPid) {
          found = true;
          apiItem['confirmedQty'] = qty;
          apiItem['status'] = itemToUpdate['status']; // Update status in API payload
          // Also update local reference just in case
          itemToUpdate['confirmedQty'] = qty;
          // itemToUpdate['status'] is already set by caller before calling this
        }
        apiItems.add(apiItem);
      }

      if (!found) return;

      final url = 'https://admin.theblackforestcakes.com/api/stock-orders/$orderId';
      final res = await http.patch(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'items': apiItems}),
      );

      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirmed successfully'), backgroundColor: Colors.green, duration: Duration(milliseconds: 800)),
        );
      } else {
        throw Exception('Failed to confirm: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error confirming qty: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error confirming: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Grouping Logic simplified / kept same but returns flat list for simplicity inside the card if needed, 
  // currently re-using existing logic is fine but we need to handle the display.

  Future<void> _saveConsolidatedConfirm(Map<String, dynamic> entry) async {
      final originalItems = entry['originalItems'] as List;
      double newTotalConfirmed = 0;
      
      for (var original in originalItems) {
         final item = original['item'] as Map<String, dynamic>;
         final orderId = original['orderId'] as String;
         final currentSent = ((item['sendingQty'] as num?) ?? 0).toDouble();
         
         // Confirm the current sent qty
         item['confirmedQty'] = currentSent;
         item['status'] = 'confirmed'; // Update status
         newTotalConfirmed += currentSent;
         
         _updateConfirmQty(orderId, item, currentSent);
      }
      
      setState(() {
         entry['confirmedQty'] = newTotalConfirmed;
         entry['statuses'] = {'confirmed'}; // Update local aggregate status
         _processStockOrders();
      });
  }



  // Update params to accept num/double
  void _saveStockOrder(Map<String, dynamic> entry, double totalQty) {
    double remaining = totalQty;
    final originalItems = entry['originalItems'] as List;
    Set<String> newStatuses = {};
    double newTotalSent = 0;

    // OPTIMIZATION: Single item case checks
    if (originalItems.length == 1) {
        final original = originalItems[0];
        final item = original['item'] as Map<String, dynamic>;
        final orderId = original['orderId'] as String;
        
        item['status'] = 'sending';
        item['sendingQty'] = totalQty;
        
        _updateItemStatus(orderId, item, totalQty);
        
        newStatuses.add('sending');
        newTotalSent = totalQty;
    } else {
       // ... existing multi-item logic
       for (int i=0; i<originalItems.length; i++) {
           final original = originalItems[i];
           final item = original['item'] as Map<String, dynamic>;
           final orderId = original['orderId'] as String;
           final req = ((item['requiredQty'] as num?) ?? 0).toDouble();
           
           double allocated = 0;
           double apply = 0;
           
           if (remaining > 0) {
               apply = (remaining >= req) ? req : remaining;
               allocated = apply;
               remaining -= apply;
           }
           
           // OVER-SENDING: Dump any remaining surplus into the last item
           if (i == originalItems.length - 1 && remaining > 0) {
               allocated += remaining;
               remaining = 0;
           }
           
           // Update Local
           item['status'] = 'sending';
           item['sendingQty'] = allocated;
           newTotalSent += allocated; 
           newStatuses.add('sending');
           
           // API Update
           _updateItemStatus(orderId, item, allocated);
       }
    }

    setState(() {
       entry['sendingQty'] = totalQty;
       entry['statuses'] = newStatuses;
       _processStockOrders();
    });
  }

  Future<void> _saveManualConsolidatedConfirm(Map<String, dynamic> entry, double newVal) async {
      final originalItems = entry['originalItems'] as List;
      double remainingToAllocate = newVal;
      
      for (var original in originalItems) {
         final item = original['item'] as Map<String, dynamic>;
         final orderId = original['orderId'] as String;
         final currentSent = ((item['sendingQty'] as num?) ?? 0).toDouble();
         
         double allocated = 0;
         if (remainingToAllocate >= currentSent) {
             allocated = currentSent;
             remainingToAllocate -= currentSent;
         } else {
             allocated = remainingToAllocate;
             remainingToAllocate = 0;
         }
         
          if (remainingToAllocate > 0 && original == originalItems.last) {
             allocated += remainingToAllocate;
             remainingToAllocate = 0;
         }

         item['confirmedQty'] = allocated;
         item['status'] = 'confirmed'; // Update status
         _updateConfirmQty(orderId, item, allocated);
      }
      
      setState(() {
         entry['confirmedQty'] = newVal;
         if (newVal > 0) {
            final stats = (entry['statuses'] as Set);
            stats.add('confirmed'); // Add confirmed status
         }
         _processStockOrders();
      });
  }

  Future<void> _updatePickQty(String orderId, Map<String, dynamic> itemToUpdate, double qty) async {
    final token = await _getToken();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    try {
      final orderIndex = stockOrders.indexWhere((o) => (o['id'] ?? o['_id']) == orderId);
      if (orderIndex == -1) return;
      final order = stockOrders[orderIndex];
      final currentItems = (order['items'] as List?) ?? [];
      
      List<Map<String, dynamic>> apiItems = [];
      bool found = false;

      for (var item in currentItems) {
        String pid = '';
        if (item['product'] is Map) {
          pid = item['product']['id'] ?? item['product']['_id'] ?? '';
        } else {
          pid = item['product']?.toString() ?? '';
        }

        String targetPid = '';
        if (itemToUpdate['product'] is Map) {
          targetPid = itemToUpdate['product']['id'] ?? itemToUpdate['product']['_id'] ?? '';
        } else {
          targetPid = itemToUpdate['product']?.toString() ?? '';
        }

        Map<String, dynamic> apiItem = Map<String, dynamic>.from(item);
        apiItem['product'] = pid; 
        apiItem.remove('id'); 
        
        if (pid == targetPid) {
          found = true;
          apiItem['pickedQty'] = qty;
          apiItem['status'] = 'picked';
          itemToUpdate['pickedQty'] = qty;
          itemToUpdate['status'] = 'picked';
        }
        apiItems.add(apiItem);
      }

      if (!found) return;

      final url = 'https://admin.theblackforestcakes.com/api/stock-orders/$orderId';
      await http.patch(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'items': apiItems}),
      );
      // Silent success or maybe small toast?
    } catch (e) {
         debugPrint('Error picking qty: $e');
    }
  }

  Future<void> _saveManualConsolidatedPick(Map<String, dynamic> entry, double val) async {
      double newVal = val;
      if (newVal < 0) newVal = 0;
      
      final originalItems = entry['originalItems'] as List;
      double newTotalPicked = 0;
      
      // Distribute logic 
      double remaining = newVal;
      
      for (var original in originalItems) {
         final item = original['item'] as Map<String, dynamic>;
         final orderId = original['orderId'] as String;
         // Base allocation on confirmed qty
         final conf = ((item['confirmedQty'] as num?) ?? 0).toDouble();
         
         double apply = 0;
         if (remaining > 0) {
             // Try to match confirmed first
             apply = (remaining >= conf) ? conf : remaining;
             
             // Let's allow over-pick on last item if needed.
             if (original == originalItems.last) {
                 apply = remaining;
             }
         }
         
         item['pickedQty'] = apply;
         item['status'] = 'picked';
         
         _updatePickQty(orderId, item, apply);
         
         remaining -= apply;
         newTotalPicked += apply;
      }
      
      setState(() {
         entry['pickedQty'] = newTotalPicked;
         if (newTotalPicked > 0) entry['statuses'] = {'picked'};
         _processStockOrders();
      });
  }

  Future<void> _saveConsolidatedPick(Map<String, dynamic> entry) async {
      final originalItems = entry['originalItems'] as List;
      double newTotalPicked = 0;
      
      for (var original in originalItems) {
         final item = original['item'] as Map<String, dynamic>;
         final orderId = original['orderId'] as String;
         final currentConfirmed = ((item['confirmedQty'] as num?) ?? 0).toDouble();
         
         // Pick the current confirmed qty
         item['pickedQty'] = currentConfirmed;
         item['status'] = 'picked';
         newTotalPicked += currentConfirmed;
         
         _updatePickQty(orderId, item, currentConfirmed);
      }
      
      setState(() {
         entry['pickedQty'] = newTotalPicked;
         entry['statuses'] = {'picked'}; 
         _processStockOrders();
      });
  }
  // Category Filter State
  List<String> _availableCategories = ['ALL'];
  String _selectedCategoryFilter = 'ALL';

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDate: fromDate ?? now,
    );
    if (picked != null) {
      setState(() {
        fromDate = picked;
        toDate = picked;
      });
      await _fetchStockOrders();
    }
  }

  Widget _buildDateSelector() {
    final safeFrom = fromDate ?? DateTime.now();
    final dateFmt = DateFormat('MMM d');
    final label = dateFmt.format(safeFrom);
    
    // Sort branches
    final displayBranches = List<Map<String, dynamic>>.from(branches);
    displayBranches.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    
    // Prepare Dropdown Items
    final List<DropdownMenuItem<String>> branchItems = [
       const DropdownMenuItem(value: 'ALL', child: Text('ALL BRANCHES', style: TextStyle(fontWeight: FontWeight.bold))),
       ...displayBranches.map((b) {
           final name = (b['name'] as String? ?? 'UNK').toUpperCase();
           return DropdownMenuItem(
             value: b['id'] as String,
             child: Text(name, overflow: TextOverflow.ellipsis),
           );
       }),
    ];

    return Row(
      children: [
        // 1. Date Picker
        Expanded(
          flex: 2,
          child: InkWell(
            onTap: _pickDateRange,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                  color: Colors.black, 
                  borderRadius: BorderRadius.circular(8)
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label, 
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 8),
        
        // 2. Branch Dropdown
        Expanded(
          flex: 3,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
               border: Border.all(color: Colors.grey.shade400),
               borderRadius: BorderRadius.circular(8),
               color: Colors.white,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                 isExpanded: true,
                 value: selectedBranchId != null && (selectedBranchId == 'ALL' || branches.any((b) => b['id'] == selectedBranchId)) 
                        ? selectedBranchId 
                        : 'ALL',
                 items: branchItems,
                 onChanged: (val) {
                    if (val != null) {
                        setState(() {
                           selectedBranchId = val;
                           _processStockOrders();
                        });
                    }
                 },
                 style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                 icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildCategoryChips() {
     if (_loadingBranches && branches.isEmpty) { 
        return const SizedBox.shrink(); 
     }

     return SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: _availableCategories.map((cat) {
              final isSelected = _selectedCategoryFilter == cat;
              return Padding(
                 padding: const EdgeInsets.only(right: 8.0),
                 child: ChoiceChip(
                    label: Text(cat.toUpperCase()),
                    selected: isSelected,
                    onSelected: (bool selected) {
                        setState(() {
                           _selectedCategoryFilter = cat;
                           _processStockOrders();
                        });
                    },
                    showCheckmark: false,
                    backgroundColor: const Color(0xFF260206), // Match branch chip inactive
                    selectedColor: Colors.red, // Match active
                    labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Colors.transparent),
                    ),
                 ),
              );
          }).toList(),
        ),
     );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return Colors.green;
      case 'fulfilled': return Colors.blue;
      case 'cancelled': return Colors.red;
      case 'ordered': return Colors.orange;
      case 'sending': return Colors.blueAccent;
      case 'confirmed': return Colors.green;
      case 'picked': return Colors.deepPurple;
      case 'received': return Colors.teal;
      case 'pending': default: return Colors.orange;
    }
  }

  Color _getCategoryColor(String? name) {
    return Colors.amber.shade700; // Dark Yellow
  }

  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
  List<Widget> _buildGridSlivers() {
    List<Widget> slivers = [];
    List<Map<String, dynamic>> currentGroup = [];
    bool isUnderCategory = false; // Track if we are inside a category section
    
    // Check role for builder
    final isChef = _userRole == 'chef';
    final isSupervisor = _userRole == 'supervisor';

    void flushGroup() {
       if (currentGroup.isEmpty) return;
       final items = List<Map<String, dynamic>>.from(currentGroup); // copy
       currentGroup.clear();
       
       if (isUnderCategory) {
           // Use BoxAdapter + GridView to safely apply decoration without semantics crash
           Widget decoratedGrid = SliverToBoxAdapter(
             child: Container(
               decoration: BoxDecoration(
                   color: Colors.yellow.shade100.withOpacity(0.5), // Mild Yellow
                   borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)), // Round bottom
                   border: Border(bottom: BorderSide(color: Colors.brown.shade300, width: 2)),
               ),
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
               child: GridView.builder(
                 shrinkWrap: true,
                 physics: const NeverScrollableScrollPhysics(),
                 gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                   crossAxisCount: 3,
                   childAspectRatio: 0.65, 
                   crossAxisSpacing: 4, 
                   mainAxisSpacing: 4,
                 ),
                 itemCount: items.length,
                 itemBuilder: (context, index) {
                     final item = items[index];
                     if (isChef) return _buildChefGridItem(item);
                     if (isSupervisor) return _buildSupervisorGridItem(item);
                     return _buildDriverGridItem(item);
                 },
               ),
             ),
           );
           
           slivers.add(decoratedGrid);
           slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 12))); // Gap after section
       } else {
           // Normal SliverGrid (No background)
           Widget grid = SliverPadding(
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                 sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.65, 
                      crossAxisSpacing: 4, 
                      mainAxisSpacing: 4,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                         final item = items[index];
                         if (isChef) return _buildChefGridItem(item);
                         if (isSupervisor) return _buildSupervisorGridItem(item);
                         return _buildDriverGridItem(item);
                      },
                      childCount: items.length,
                    ),
                 ),
              );
           slivers.add(grid);
       }
    }

    for (var item in _consolidatedItems) {
       if (item['type'] == 'header_dept') {
          flushGroup();
          isUnderCategory = false; // Reset
          slivers.add(SliverToBoxAdapter(
             child: Padding(
               padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text(
                     (item['title'] ?? '').toString().toUpperCase(),
                     style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87),
                   ),
                   const Divider(color: Colors.black54, thickness: 2, height: 8),
                 ],
               ),
             ),
          ));
       } else if (item['type'] == 'header_cat') {
          flushGroup();
          isUnderCategory = true; // Start category section
          
          final title = (item['title'] ?? '').toString();
          
          // Generate Display String based on Role
          String displayText = title;
          final totals = item['totals'] as Map<String, dynamic>?;
          
          if (totals != null) {
             if (isChef) {
                displayText = '$title (ORD: ${_formatQty(totals['req'] ?? 0)} - SNT: ${_formatQty(totals['sent'] ?? 0)} )';
             } else if (isSupervisor) {
                displayText = '$title (SNT: ${_formatQty(totals['sent'] ?? 0)} - CON: ${_formatQty(totals['conf'] ?? 0)} )';
             } else if (_userRole == 'driver') {
                displayText = '$title (CON: ${_formatQty(totals['conf'] ?? 0)} - PIC: ${_formatQty(totals['pick'] ?? 0)} )';
             } else {
                 // Default (maybe Factory?)
                 displayText = '$title (ORD: ${_formatQty(totals['req'] ?? 0)} - SNT: ${_formatQty(totals['sent'] ?? 0)} )';
             }
          }
          
          slivers.add(SliverToBoxAdapter(
             child: Container(
               color: Colors.yellow.shade100.withOpacity(0.5), // Mild Yellow Background for Header Area
               padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
               child: Container(
                 padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                 decoration: BoxDecoration(
                   color: _getCategoryColor(title),
                   borderRadius: BorderRadius.circular(6),
                 ),
                 child: Text(
                   displayText.toUpperCase(),
                   style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
                 ),
               ),
             ),
          ));
       } else if (item['type'] == 'item') {
          currentGroup.add(item);
       }
    }
    flushGroup();
    
    // Fallback if no headers were found (e.g. filtered view or single list) but items exist
    // The loop handles 'item' type so it should be fine. 
    // If _consolidatedItems has items but no headers, they are added to currentGroup and flushed at end.
    
    return slivers;
  }

  Widget _buildStockOrderCard(Map<String, dynamic> order) {
    final orderId = (order['id'] ?? order['_id'])?.toString() ?? 'unknown';
    final invoiceNumber = order['invoiceNumber'] ?? 'No Invoice';
    final branchName = order['branch'] is Map ? order['branch']['name'] : 'Unknown Branch';
    final status = order['status'] ?? 'pending';
    final items = (order['items'] as List?) ?? [];
    
    // Filter items first
    final filteredItems = items.where(_matchesCategory).toList();
    if (widget.categoryId != null && filteredItems.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Use filteredItems for counts and rendering
    final itemCount = filteredItems.length;
    final createdAt = DateTime.tryParse(order['createdAt'] ?? '');
    final deliveryDate = DateTime.tryParse(order['deliveryDate'] ?? '');
    final dateFmt = DateFormat('MMM d, h:mm a');
    final createdStr = createdAt != null ? dateFmt.format(createdAt.add(const Duration(hours: 5, minutes: 30))) : '';
    final deliveryStr = deliveryDate != null ? dateFmt.format(deliveryDate.add(const Duration(hours: 5, minutes: 30))) : '';

    final isFactory = _userRole == 'factory' || _userRole == 'chef';
    final isSupervisor = _userRole == 'supervisor';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: false, // Start collapsed
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invoiceNumber, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                _buildStatusChip(status),
              ],
            ),
            const SizedBox(height: 2),
            Text(branchName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 3),
            Text('Delivery: $deliveryStr', style: TextStyle(color: Colors.blue[700], fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 1),
            Text('Created: $createdStr', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          ],
        ),
        subtitle: Builder(
            builder: (context) {
              double totalReqAmt = 0;
              double totalSent = 0;
              for (var item in filteredItems) {
                totalReqAmt += (item['requiredAmount'] ?? 0).toDouble();
                totalSent += ((item['sendingQty'] as num?) ?? 0).toDouble();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '$itemCount Items     Req Amt: ${totalReqAmt.toInt()}     Snt Qty: ${_formatQty(totalSent)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              );
            },
          ),
        children: [
          const Divider(height: 1),
          // Factory Header
          if (isFactory)
            Container(
              color: const Color(0xFFEFEBE9), // Light brownish/pinkish matches image
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Row(
                children: const [
                  Expanded(flex: 3, child: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(flex: 1, child: Center(child: Text('Ord', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                  Expanded(flex: 1, child: Center(child: Text('Snt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                ],
              ),
            )
          else 
            // Original Header for others
             Container(
              color: const Color(0xFFEFEBE9), // Light brownish/pinkish
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Row(
                children: [
                  const Expanded(flex: 3, child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                  if (!isSupervisor) ...[
                    const Expanded(flex: 1, child: Text('Prc', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                    const Expanded(flex: 1, child: Text('Req', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                  ],
                  const Expanded(flex: 1, child: Text('Snt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                  if (isSupervisor)
                    const Expanded(flex: 1, child: Text('Con', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                  // ... Keep others if needed, simplifying for brevity based on request
                ],
              ),
            ),

          // Items
          ...() {
             // 1. Enrich Processed Items
             final List<Map<String, dynamic>> processedItems = [];
             for (var item in filteredItems) {
                final product = item['product'];
                final meta = _getItemMetadata(product);
                processedItems.add({
                   'item': item,
                   'dept': meta['department']!,
                   'cat': meta['category']!,
                   'name': meta['name']!,
                });
             }
             
             // 2. Sort
             processedItems.sort((a, b) {
                 int cmp = (a['dept'] as String).compareTo(b['dept'] as String);
                 if (cmp != 0) return cmp;
                 cmp = (a['cat'] as String).compareTo(b['cat'] as String);
                 if (cmp != 0) return cmp;
                 return (a['name'] as String).compareTo(b['name'] as String);
             });
             
             final List<Widget> widgets = [];
             String? lastDept;
             String? lastCat;
             
             for (var entry in processedItems) {
                final item = entry['item'];
                final dept = entry['dept'] as String;
                final cat = entry['cat'] as String;
                
                if (widget.categoryId == null) {
                  if (dept != lastDept) {
                    widgets.add(Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      color: const Color(0xFFA1887F), // Brown 300/400 approx
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: Text(
                        dept.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ));
                    lastDept = dept;
                    lastCat = null;
                  }
                  
                  if (cat != lastCat) {
                    widgets.add(Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                      color: const Color(0xFFEEEEEE), // Grey 200
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: Text(
                        cat,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                    ));
                    lastCat = cat;
                  }
                }
                
                // Render Item
                final itemStatus = item['status'] ?? 'ordered';
                final isSending = itemStatus == 'sending';
             
                final product = item['product'];
                final productName = (product is Map ? product['name'] : 'Unknown Product') ?? 'Unknown Product';
                final req = ((item['requiredQty'] as num?) ?? 0).toDouble();
                final reqAmount = (item['requiredAmount'] ?? 0).toDouble();
                final unitPrice = req > 0 ? (reqAmount / req).round() : 0;
                final sent = ((item['sendingQty'] as num?) ?? 0).toDouble();
                // final inStock = (item['inStock'] ?? 0) as int; // Not used currently in row display logic consistently except below text
                // Actually inStock is usually on product. But `item['inStock']` in consolidated view was aggregated. 
                // For individual card, `item` might have `inStock` if backend sends it. 
                // If not, it won't show. Let's assume it's there or 0.

                final key = _getItemKey(orderId, item);
                final initialVal = (sent > 0) ? sent : req;

                if (!_controllers.containsKey(key)) {
                    _controllers[key] = TextEditingController(text: initialVal.toString());
                }
                final controller = _controllers[key]!;

                Widget row;
                if (isFactory) {
                  // Factory Item Row
                  row = InkWell(
                    onDoubleTap: () {
                       final currentVal = double.tryParse(controller.text) ?? req;
                       setState(() {
                         item['status'] = 'sending';
                         item['sendingQty'] = currentVal;
                       });
                       _updateItemStatus(orderId, item, currentVal);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSending ? Colors.blue.withOpacity(0.1) : Colors.white,
                        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Text(productName, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Row(
                                      children: [
                                        Text('Price: $unitPrice', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                        const SizedBox(width: 8),
                                        Text('InStock: ${item['inStock'] ?? 0}', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                        if (itemStatus != null) ...[
                                           const SizedBox(width: 8),
                                           Text(itemStatus.toUpperCase(), style: TextStyle(fontSize: 10, color: _getStatusColor(itemStatus), fontWeight: FontWeight.bold)),
                                        ]
                                      ],
                                  ),
                              ],
                            ),
                          ),
                          Expanded(flex: 1, child: Center(child: Text(_formatQty(req), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                          Expanded(flex: 1, child: Center(child: Container(
                             height: 32, width: 60,
                             decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4), color: Colors.white),
                             child: TextField(
                                 controller: controller, // Reuse controller
                                 keyboardType: TextInputType.numberWithOptions(decimal: true),
                                 textAlign: TextAlign.center,
                                 style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                 decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                 onSubmitted: (val) {
                                    final v = double.tryParse(val) ?? req;
                                    setState(() {
                                       item['sendingQty'] = v;
                                       item['status'] = 'sending';
                                    });
                                    _updateItemStatus(orderId, item, v);
                                 },
                             ),
                          ))),
                        ],
                      ),
                    ),
                  );
                } else {
                  // Non-Factory Item Row (Original)
                  row = Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      decoration: BoxDecoration(
                        color: isSending ? Colors.blue.withOpacity(0.1) : Colors.white,
                        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                      ),
                      child: Row(
                        children: [
                           Expanded(flex: 3, child: Text(productName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                           if (!isSupervisor) ...[
                              Expanded(flex: 1, child: Text(unitPrice.toString(), style: const TextStyle(fontSize: 12), textAlign: TextAlign.center)),
                              Expanded(flex: 1, child: Center(child: Text(_formatQty(req), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                           ],
                           Expanded(flex: 1, child: Center(child: Text(_formatQty(sent), style: TextStyle(color: sent > 0 ? Colors.blueAccent : Colors.grey, fontWeight: sent > 0 ? FontWeight.bold : FontWeight.normal)))),
                           if (isSupervisor) ...[
                              Expanded(
                                flex: 1,
                                child: InkWell(
                                  onDoubleTap: () {
                                     final qtyToConfirm = ((item['confirmedQty'] as num?) ?? (sent > 0 ? sent : 0)).toDouble();
                                     // If already confirmed same amount, maybe allow re-confirm or just confirm. 
                                     // Logic: User wants to confirm "snt qty".
                                     // Actually instruction says: "show snt qty number there if we double tap the qty number need to store in Confirmed Qty"
                                     final val = sent;
                                     _updateConfirmQty(orderId, item, val.toDouble());
                                     setState(() {
                                        item['confirmedQty'] = val;
                                     });
                                  },
                                  child: Center(
                                    child: Text(
                                      (item['confirmedQty'] != null ? _formatQty(item['confirmedQty']) : _formatQty(sent)), 
                                      style: TextStyle(
                                        fontSize: 12, 
                                        fontWeight: FontWeight.bold, 
                                        color: (item['confirmedQty'] != null) ? Colors.blue : Colors.grey
                                      )
                                    ),
                                  ),
                                ),
                              ),
                           ],
                        ],
                      ),
                  );
                }
                
                widgets.add(row);
             }
             
             return widgets;
          }(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }


  Widget _buildConsolidatedHeader() {
    if (_consolidatedItems.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.only(bottom: _isConsolidatedExpanded ? 0 : 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: _isConsolidatedExpanded 
            ? const BorderRadius.vertical(top: Radius.circular(12)) 
            : BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _isConsolidatedExpanded = !_isConsolidatedExpanded;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Expanded(
                     child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           Text(_headerBranchCodes, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                           const SizedBox(height: 3),
                           Text('Delivery: $_headerDeliveryStr', style: TextStyle(color: Colors.blue[700], fontSize: 14, fontWeight: FontWeight.bold)),
                           const SizedBox(height: 1),
                           Text('Created: $_headerCreatedStr', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                        ],
                     ),
                   ),
                   Icon(_isConsolidatedExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
                 ],
               ),
               const SizedBox(height: 8),
               Text(
                 _headerSubtitle,
                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
               ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsolidatedTableHeader() {
      final isSupervisor = _userRole == 'supervisor';
      final isDriver = _userRole == 'driver';
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4), // Match card margin roughly (Card takes 4 by default)
        decoration: BoxDecoration(
          color: Colors.brown.shade100,
          border: const Border(
            left: BorderSide(color: Colors.white, width: 0), // Adjust if needed
          ),
        ),
        // Hack to match Card layout: Card usually has 4 margin. We use padding/margin to align.
        // Actually, best to wrap in a Material to match Card exactly.
        child: Material(
          color: Colors.brown.shade100,
          elevation: 0, 
          // We wrap in a container with side margins to match the Header Card's visual width
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), // Match Header padding X
            child: Row(
              children: [
                const Expanded(flex: 3, child: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                if (!isSupervisor && !isDriver) 
                   const Expanded(flex: 1, child: Center(child: Text('Req', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                if (!isDriver)
                    const Expanded(flex: 1, child: Center(child: Text('Snt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                if (isSupervisor || isDriver)
                   const Expanded(flex: 1, child: Center(child: Text('Con', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                if (isDriver)
                   const Expanded(flex: 1, child: Center(child: Text('Pic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
              ],
            ),
          ),
        ),
      );
  }

  // Wrapper to make items look like they are inside the card
  Widget _wrapInCardVisual(Widget child, {bool isLast = false}) {
     return Container(
       margin: const EdgeInsets.symmetric(horizontal: 4), // Card default margin
       decoration: BoxDecoration(
         color: Colors.white,
         boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))], // Simulating Card elevation
         borderRadius: isLast 
             ? const BorderRadius.vertical(bottom: Radius.circular(12)) 
             : BorderRadius.zero,
       ),
       child: child,
     );
  }

  Widget _buildConsolidatedItem(int index) {
      if (index >= _consolidatedItems.length) return const SizedBox.shrink();
      
      final entry = _consolidatedItems[index];
      
      if (entry['type'] == 'header_dept') {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          color: const Color(0xFFA1887F), // Dark Brown
          width: double.infinity,
          alignment: Alignment.center,
          child: Text(
            (entry['title'] as String).toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
            textAlign: TextAlign.center,
          ),
        );
      }
            if (entry['type'] == 'header_cat') {
          final title = entry['title'] as String;
          
          // Generate Display String based on Role
          String displayText = title;
  final totals = entry['totals'] as Map<String, dynamic>?;
  final isChef = _userRole == 'chef';
  final isSupervisor = _userRole == 'supervisor';
  
  if (totals != null) {
     if (isChef) {
        displayText = '$title (ORD: ${_formatQty(totals['req'])} - SNT: ${_formatQty(totals['sent'])})';
     } else if (isSupervisor) {
        displayText = '$title (SNT: ${_formatQty(totals['sent'])} - CON: ${_formatQty(totals['conf'])})';
     } else if (_userRole == 'driver') {
        displayText = '$title (CON: ${_formatQty(totals['conf'])} - PIC: ${_formatQty(totals['pick'])})';
     } else {
         displayText = '$title (ORD: ${_formatQty(totals['req'])} - SNT: ${_formatQty(totals['sent'])})';
     }
  }

          return Container(
           padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
           color: _getCategoryColor(title),
           width: double.infinity,
           alignment: Alignment.center,
           child: Text(
             displayText.toUpperCase(),
             style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.black),
             textAlign: TextAlign.center,
           ),
         );
       }


    if (entry['type'] != 'item') return const SizedBox.shrink();

    final product = entry['product'];
    final productName = entry['productName'] as String;
    final sent = ((entry['sendingQty'] as num?) ?? 0).toDouble();
    final confirmedRaw = ((entry['confirmedQty'] as num?) ?? 0).toDouble();
    final confirmedDisplay = (confirmedRaw > 0) ? confirmedRaw : sent;
    
    // Image Handling
    ImageProvider? imageProvider;
    String? imageUrl;
    
    if (product is Map) {
       if (product['images'] != null && (product['images'] is List) && (product['images'] as List).isNotEmpty) {
          final firstImg = product['images'][0];
          if (firstImg is Map && firstImg['image'] != null) {
             final imgObj = firstImg['image'];
             if (imgObj is Map && imgObj['url'] != null) {
                imageUrl = imgObj['url'];
             }
          }
       }
       if (imageUrl == null && product['image'] != null) {
          final img = product['image'];
          if (img is Map && img['url'] != null) {
             imageUrl = img['url'];
          } else if (img is String && img.startsWith('http')) {
             imageUrl = img;
          }
       }
    }
    
    if (imageUrl != null && !imageUrl.startsWith('http')) {
        imageUrl = 'https://admin.theblackforestcakes.com$imageUrl';
    }
    
    if (imageUrl != null) {
       imageProvider = NetworkImage(imageUrl);
    }

    final statuses = entry['statuses'] as Set;
    
    // Lock if Picked (Supervisor cannot edit)
    final pickedQty = ((entry['pickedQty'] as num?) ?? 0).toDouble();
    final isLocked = statuses.contains('picked') || pickedQty > 0;
    
    final key = 'supervisor_confirm_${entry['productId']}';
    if (!_controllers.containsKey(key)) {
        _controllers[key] = TextEditingController(text: _formatQty(confirmedDisplay));
    }
    final controller = _controllers[key]!;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          if (imageProvider != null)
            Image(image: imageProvider, fit: BoxFit.cover)
          else
            Container(color: Colors.grey.shade200, child: const Icon(Icons.fastfood, size: 40, color: Colors.grey)),
            

          
          Container(
             decoration: BoxDecoration(
               gradient: LinearGradient(
                 begin: Alignment.center,
                 end: Alignment.bottomCenter,
                 colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
               ),
             ),
          ),
          
          // Tap Interactions (Background)
           Positioned.fill(
             child: Material(
               color: Colors.transparent,
               child: InkWell(
                 onTap: () {
                    // Close keyboard if typing
                    if (entry['isTyping'] == true) {
                        final val = double.tryParse(controller.text) ?? confirmedDisplay;
                        _saveManualConsolidatedConfirm(entry, val);
                        setState(() {
                          entry['isTyping'] = false;
                        });
                        FocusManager.instance.primaryFocus?.unfocus();
                    }
                 },
                 onDoubleTap: () {
                     if (isLocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Item is picked by Driver. Cannot edit.'), duration: Duration(milliseconds: 1000)),
                        );
                        return;
                     }
                     
                     // Auto-Confirm All Sent
                     if (confirmedRaw < sent) {
                       _saveConsolidatedConfirm(entry); // Use existing auto-confirm
                     }
                 },
                 child: Container(),
               ),
             ),
           ),

          // Top Left: Sending Qty
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: 36,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.red, 
                borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
              ),
              child: Text(
                _formatQty(sent),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          
          // Top Right: Price & Unit
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_formatQty(entry['price'])} ${entry['unit']}'.trim(),
                style: const TextStyle(
                  color: Colors.lightGreenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          
          // Center: Confirmed Qty (Interaction Box)
          Builder(builder: (context) {
             final qtyStr = _formatQty(confirmedDisplay);
             // Dynamic width
             final boxWidth = (qtyStr.length * 9.0) + 20.0;
             double finalWidth = boxWidth > 34 ? boxWidth : 34;
             
             if (entry['isTyping'] == true) {
                 finalWidth = 80.0;
             }
             
             return Center(
               child: entry['isTyping'] == true
               ? Container(
                   width: finalWidth,
                   height: 34,
                   alignment: Alignment.center,
                   decoration: BoxDecoration(
                     color: Colors.black.withOpacity(0.6),
                     borderRadius: BorderRadius.circular(8),
                     boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                     border: Border.all(color: Colors.blueAccent, width: 2),
                   ),
                   child: TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      cursorColor: Colors.white,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.done,
                      onTapOutside: (event) {
                         final doubleVal = double.tryParse(controller.text) ?? 0;
                         _saveManualConsolidatedConfirm(entry, doubleVal);
                         setState(() {
                           entry['isTyping'] = false;
                         });
                         FocusManager.instance.primaryFocus?.unfocus();
                      },
                      onSubmitted: (val) {
                         final doubleVal = double.tryParse(val) ?? 0;
                         _saveManualConsolidatedConfirm(entry, doubleVal);
                         setState(() {
                           entry['isTyping'] = false;
                         });
                      },
                   ),
                 )
               : GestureDetector(
                   onTap: () {
                      if (isLocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Item is picked by Driver. Cannot edit.'), duration: Duration(milliseconds: 1000)),
                        );
                        return;
                      }

                      setState(() {
                         entry['isTyping'] = true;
                         controller.text = _formatQty(confirmedDisplay);
                      });
                   },
                   onDoubleTap: () {
                        if (isLocked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(content: Text('Item is picked by Driver. Cannot edit.'), duration: Duration(milliseconds: 1000)),
                            );
                            return;
                        }
                        
                        // Pass through to parent double tap (Auto Confirm)
                        if (confirmedRaw < sent) {
                           _saveConsolidatedConfirm(entry);
                        }
                   },
                   child: Container(
                     width: finalWidth,
                     height: 34,
                     alignment: Alignment.center,
                     decoration: BoxDecoration(
                       color: Colors.black.withOpacity(0.6),
                       borderRadius: BorderRadius.circular(8),
                       boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                       border: (confirmedRaw > 0) ? Border.all(color: Colors.blueAccent, width: 2) : null,
                     ),
                     child: Text(
                       _formatQty(confirmedDisplay),
                       style: TextStyle(
                         color: (confirmedRaw > 0) ? Colors.blueAccent : Colors.white, 
                         fontSize: 16, 
                         fontWeight: FontWeight.bold
                       ),
                     ),
                   ),
               ),
             );
          }),
          
          // Bottom: Name Only
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              color: Colors.black87,
              child: Text(
                productName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

    Widget _buildDriverGridItem(Map<String, dynamic> entry) {
  if (entry['type'] != 'item') return const SizedBox.shrink();

  final product = entry['product'];
  final productName = entry['productName'] as String;
  final confirmedRaw = ((entry['confirmedQty'] as num?) ?? 0).toDouble();
  final pickedRaw = ((entry['pickedQty'] as num?) ?? 0).toDouble();
  final pickedDisplay = (pickedRaw > 0) ? pickedRaw : confirmedRaw;
  
  // Image Handling
  ImageProvider? imageProvider;
  String? imageUrl;
  
  if (product is Map) {
     if (product['images'] != null && (product['images'] is List) && (product['images'] as List).isNotEmpty) {
        final firstImg = product['images'][0];
        if (firstImg is Map && firstImg['image'] != null) {
           final imgObj = firstImg['image'];
           if (imgObj is Map && imgObj['url'] != null) {
              imageUrl = imgObj['url'];
           }
        }
     }
     if (imageUrl == null && product['image'] != null) {
        final img = product['image'];
        if (img is Map && img['url'] != null) {
           imageUrl = img['url'];
        } else if (img is String && img.startsWith('http')) {
           imageUrl = img;
        }
     }
  }
  
  if (imageUrl != null && !imageUrl.startsWith('http')) {
      imageUrl = 'https://admin.theblackforestcakes.com$imageUrl';
  }
  
  if (imageUrl != null) {
     imageProvider = NetworkImage(imageUrl);
  }

  final statuses = entry['statuses'] as Set;
  
  // Lock if Received (Driver cannot edit)
  final isLocked = statuses.contains('received');
  
  final key = 'driver_pick_${entry['productId']}';
  if (!_controllers.containsKey(key)) {
      _controllers[key] = TextEditingController(text: _formatQty(pickedDisplay));
  }
  final controller = _controllers[key]!;

  return Card(
    elevation: 4,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide.none,
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Background Image
        if (imageProvider != null)
          Image(image: imageProvider, fit: BoxFit.cover)
        else
          Container(color: Colors.grey.shade200, child: const Icon(Icons.fastfood, size: 40, color: Colors.grey)),
          

        
        Container(
           decoration: BoxDecoration(
             gradient: LinearGradient(
               begin: Alignment.center,
               end: Alignment.bottomCenter,
               colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
             ),
           ),
        ),
        
        // Tap Interactions (Background)
         Positioned.fill(
           child: Material(
             color: Colors.transparent,
             child: InkWell(
               onTap: () {
                  // Close keyboard if typing
                  if (entry['isTyping'] == true) {
                      final val = double.tryParse(controller.text) ?? pickedDisplay;
                      _saveManualConsolidatedPick(entry, val);
                      setState(() {
                        entry['isTyping'] = false;
                      });
                      FocusManager.instance.primaryFocus?.unfocus();
                  }
               },
               onDoubleTap: () {
                   if (isLocked) {
                      ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Item is received by Branch. Cannot edit.'), duration: Duration(milliseconds: 1000)),
                      );
                      return;
                   }

                   // Auto-Pick All Confirmed
                   if (pickedRaw < confirmedRaw) {
                     _saveConsolidatedPick(entry); 
                   }
               },
               child: Container(),
             ),
           ),
         ),

        // Top Left: Confirmed Qty (Red Badge)
        Positioned(
          top: 0,
          left: 0,
          child: Container(
            width: 36,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.red, // Red for Confirmed
              borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
            ),
            child: Text(
              _formatQty(confirmedRaw),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),

        // Top Right: Price & Unit
        Positioned(
          top: 6,
          right: 6,
          child: Container(
             padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
             decoration: BoxDecoration(
               color: Colors.black54,
               borderRadius: BorderRadius.circular(4),
             ),
             child: Text(
              '${_formatQty(entry['price'])} ${entry['unit']}'.trim(),
              style: const TextStyle(
                color: Colors.lightGreenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        
        // Center: Picked Qty (Interaction Box)
        Builder(builder: (context) {
           final qtyStr = _formatQty(pickedDisplay);
           // Dynamic width
           final boxWidth = (qtyStr.length * 9.0) + 20.0;
           double finalWidth = boxWidth > 34 ? boxWidth : 34; // Square default
           
           if (entry['isTyping'] == true) {
               finalWidth = 80.0;
           }
           
           return Center(
             child: entry['isTyping'] == true
             ? Container(
                 width: finalWidth,
                 height: 34,
                 alignment: Alignment.center,
                 decoration: BoxDecoration(
                   color: Colors.black.withOpacity(0.6),
                   borderRadius: BorderRadius.circular(8),
                   boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                 ),
                 child: TextField(
                   controller: controller,
                   autofocus: true,
                   keyboardType: TextInputType.number,
                   textAlign: TextAlign.center,
                   style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                   cursorColor: Colors.white,
                   decoration: const InputDecoration(
                     border: InputBorder.none,
                     contentPadding: EdgeInsets.zero,
                     isDense: true,
                   ),
                   textInputAction: TextInputAction.done,
                   onTapOutside: (event) {
                      final intVal = double.tryParse(controller.text) ?? 0;
                      _saveManualConsolidatedPick(entry, intVal);
                      setState(() {
                        entry['isTyping'] = false; 
                      });
                      FocusManager.instance.primaryFocus?.unfocus();
                   },
                   onSubmitted: (val) {
                      final intVal = double.tryParse(val) ?? 0;
                      _saveManualConsolidatedPick(entry, intVal);
                      setState(() {
                        entry['isTyping'] = false; 
                      });
                   },
                 ),
               )
               : GestureDetector(
                   onTap: () {
                      if (isLocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Item is received by Branch. Cannot edit.'), duration: Duration(milliseconds: 1000)),
                        );
                        return;
                      }

                      // Restrict if Confirmed Qty is 0
                      if (confirmedRaw == 0) {
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Nothing confirmed by Supervisor. Cannot pick.'), duration: Duration(milliseconds: 1000)),
                        );
                        return;
                      }

                      setState(() {
                         entry['isTyping'] = true;
                         final current = ((entry['pickedQty'] as num?) ?? 0).toDouble();
                         controller.text = _formatQty(current == 0 ? confirmedRaw : current);
                      });
                   },
                   child: Container(
                     width: finalWidth,
                     height: 34,
                     alignment: Alignment.center,
                     decoration: BoxDecoration(
                       color: Colors.black.withOpacity(0.6),
                       borderRadius: BorderRadius.circular(8),
                       border: (pickedRaw > 0) 
                           ? Border.all(color: Colors.green, width: 2) // Green if Picked > 0 (Done)
                           : null,
                       boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                     ),
                      child: Text(
                        _formatQty((entry['pickedQty'] == 0 || entry['pickedQty'] == null) ? confirmedRaw : entry['pickedQty']),
                        style: TextStyle(
                          color: (confirmedRaw == 0) ? Colors.red : ((pickedRaw > 0) ? Colors.green : Colors.white), 
                          fontSize: 14, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                   ),
               ),
             );
           }),

           // Bottom: Name Only
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                color: Colors.black87,
                child: Text(
                  productName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChefGridItem(Map<String, dynamic> entry) {
    if (entry['type'] != 'item') return const SizedBox.shrink();

    final product = entry['product'];
    final productName = entry['productName'] as String;
    final req = ((entry['requiredQty'] as num?) ?? 0).toDouble();
    final sent = ((entry['sendingQty'] as num?) ?? 0).toDouble();
    
    // Image Handling
    ImageProvider? imageProvider;
    String? imageUrl;
    
    if (product is Map) {
       if (product['images'] != null && (product['images'] is List) && (product['images'] as List).isNotEmpty) {
          final firstImg = product['images'][0];
          if (firstImg is Map && firstImg['image'] != null) {
             final imgObj = firstImg['image'];
             if (imgObj is Map && imgObj['url'] != null) {
                imageUrl = imgObj['url'];
             }
          }
       }
       
       if (imageUrl == null && product['image'] != null) {
          final img = product['image'];
          if (img is Map && img['url'] != null) {
             imageUrl = img['url'];
          } else if (img is String && img.startsWith('http')) {
             imageUrl = img;
          }
       }
    }
    
    if (imageUrl != null && !imageUrl.startsWith('http')) {
        imageUrl = 'https://admin.theblackforestcakes.com$imageUrl';
    }
    
    if (imageUrl != null) {
       imageProvider = NetworkImage(imageUrl);
    }

    final key = 'consolidated_${entry['productId']}';
    final initialVal = (sent > 0) ? _formatQty(sent) : _formatQty(req);
    
    if (!_controllers.containsKey(key)) {
        _controllers[key] = TextEditingController(text: initialVal);
    }
    final controller = _controllers[key]!;

    final statuses = entry['statuses'] as Set;
    
    final confirmedQty = ((entry['confirmedQty'] as num?) ?? 0).toDouble();
    final isLocked = statuses.contains('confirmed') || statuses.contains('picked') || confirmedQty > 0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          if (imageProvider != null)
            Image(image: imageProvider, fit: BoxFit.cover)
          else
            Container(color: Colors.grey.shade200, child: const Icon(Icons.fastfood, size: 40, color: Colors.grey)),

          // Overlay Gradient (Bottom only for text)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
              ),
            ),
          ),

          // Tap Interactions
          Positioned.fill(
             child: Material(
               color: Colors.transparent,
               child: InkWell(
                 onTap: () {
                    // Tap Background: Close Keyboard/Save if Typing
                    if (entry['isTyping'] == true) {
                        final currentVal = double.tryParse(controller.text) ?? ((entry['sendingQty'] as num?) ?? 0).toDouble();
                        _saveStockOrder(entry, currentVal); // Save logic from helper
                        setState(() {
                           entry['isTyping'] = false;
                        });
                    }
                 },
                 onDoubleTap: () {
                     if (isLocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Item is confirmed/picked. Cannot edit.'), duration: Duration(milliseconds: 1000)),
                        );
                        return;
                     } 
                     
                     // Prevent overwriting if already has a value (e.g. manually typed)
                     if ((entry['sendingQty'] ?? 0) > 0) return;

                     final currentVal = req; // Default to full required qty

                     // Distribution Logic
                     double remainingToDistribute = currentVal;
                     final originalItems = entry['originalItems'] as List;
                     double newTotalSent = 0;
                     Set<String> newStatuses = {};
                     
                     // OPTIMIZATION: Single item case checks
                     if (originalItems.length == 1) {
                         final original = originalItems[0];
                         final item = original['item'] as Map<String, dynamic>;
                         final orderId = original['orderId'] as String;
                         
                         item['status'] = 'sending';
                         item['sendingQty'] = currentVal;
                         
                         _updateItemStatus(orderId, item, currentVal);
                         
                         setState(() {
                            entry['sendingQty'] = currentVal;
                            entry['statuses'] = {'sending'};
                            _processStockOrders();
                         });
                         return;
                     }

                     for (var original in originalItems) {
                         final item = original['item'] as Map<String, dynamic>;
                         final orderId = original['orderId'] as String;
                         final itemReq = ((item['requiredQty'] as num?) ?? 0).toDouble();
                         
                         double allocated = 0;
                         if (remainingToDistribute >= itemReq) {
                           allocated = itemReq;
                           remainingToDistribute -= itemReq;
                         } else {
                           allocated = remainingToDistribute;
                           remainingToDistribute = 0;
                         }
                         
                         item['status'] = 'sending';
                         item['sendingQty'] = allocated;
                         
                         newTotalSent += allocated;
                         newStatuses.add('sending');
                         
                         _updateItemStatus(orderId, item, allocated);
                     }
                     
                     setState(() {
                       entry['sendingQty'] = newTotalSent;
                       entry['statuses'] = newStatuses;
                       // Ensure input is closed if it was open
                       entry['showInput'] = false;
                     });
                 },
                 child: Container(),
               ),
             ),
          ),

          // Top Left: Ordered Qty (Just Number)
          Positioned(
            top: 0,
            left: 0,
            child: GestureDetector(
              onTap: () {
                 if (isLocked) return;

                 // Tap to Reduce Logic
                 double current = ((entry['sendingQty'] as num?) ?? 0).toDouble();
                 if (current > 0) {
                    _saveStockOrder(entry, (current - 1).clamp(0, double.infinity));
                 }
              },
              child: Container(
                width: 36,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.red, 
                  borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
                ),
                child: Text(
                  _formatQty(req), // Just the number (Stationary)
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),

          // Top Right: Price & Unit
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_formatQty(entry['price'])} ${entry['unit']}'.trim(),
                style: const TextStyle(
                  color: Colors.lightGreenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          
          // Center Input/Interaction Box (Fixed/Always Visible)
          Builder(builder: (context) {
             final qtyStr = (entry['sendingQty'] ?? 0).toString();
             // Dynamic width calculation: Default to Square (30x30)
             final boxWidth = (qtyStr.length * 9.0) + 20.0;
             double finalWidth = boxWidth > 34 ? boxWidth : 34; // Min width 34
             
             if (entry['isTyping'] == true) {
                 finalWidth = 80.0; 
             }
             
             return Center(
              child: entry['isTyping'] == true
              ? Container(
                width: finalWidth,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                ),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onTapOutside: (event) {
                     final doubleVal = double.tryParse(controller.text) ?? 0;
                     _saveStockOrder(entry, doubleVal);
                     setState(() {
                       entry['isTyping'] = false; 
                     });
                     FocusManager.instance.primaryFocus?.unfocus();
                  },
                  onSubmitted: (val) {
                     final doubleVal = double.tryParse(val) ?? 0;
                     _saveStockOrder(entry, doubleVal);
                     setState(() {
                       entry['isTyping'] = false; 
                     });
                  },
                ),
              )
              : GestureDetector(
                  onTap: () {
                     if (isLocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Item is confirmed/picked. Cannot edit.'), duration: Duration(milliseconds: 1000)),
                        );
                        return;
                     }

                     setState(() {
                        entry['isTyping'] = true;
                        // Pre-fill controller with Req if 0, else current
                        final current = ((entry['sendingQty'] as num?) ?? 0).toDouble();
                        controller.text = _formatQty(current == 0 ? req : current);
                     });
                  },
                  child: Container(
                    width: finalWidth,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                      border: (sent > 0) 
                          ? Border.all(color: Colors.green, width: 2) 
                          : null,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                    ),
                    child: Text(
                      '${(entry['sendingQty'] == null || entry['sendingQty'] == 0) ? _formatQty(req) : _formatQty(entry['sendingQty'])}',
                      style: TextStyle(color: (sent > 0) ? Colors.green : Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
              ),
            );
          }),

          // Bottom: Name Only (Single line, smaller font)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              color: Colors.black87,
              child: Text(
                productName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), // Increased font little
                textAlign: TextAlign.center,
                maxLines: 1, // Single line
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          
        ],
      ),
    );
  }

  Widget _buildSupervisorGridItem(Map<String, dynamic> entry) {
    if (entry['type'] != 'item') return const SizedBox.shrink();

    final product = entry['product'];
    final productName = entry['productName'] as String;
    final sent = ((entry['sendingQty'] as num?) ?? 0).toDouble();
    final confirmedRaw = ((entry['confirmedQty'] as num?) ?? 0).toDouble();
    final confirmedDisplay = (confirmedRaw > 0) ? confirmedRaw : sent;

    // Image Handling
    ImageProvider? imageProvider;
    String? imageUrl;
    
    if (product is Map) {
       if (product['images'] != null && (product['images'] is List) && (product['images'] as List).isNotEmpty) {
          final firstImg = product['images'][0];
          if (firstImg is Map && firstImg['image'] != null) {
             final imgObj = firstImg['image'];
             if (imgObj is Map && imgObj['url'] != null) {
                imageUrl = imgObj['url'];
             }
          }
       }
       if (imageUrl == null && product['image'] != null) {
          final img = product['image'];
          if (img is Map && img['url'] != null) {
             imageUrl = img['url'];
          } else if (img is String && img.startsWith('http')) {
             imageUrl = img;
          }
       }
    }
    
    if (imageUrl != null && !imageUrl.startsWith('http')) {
        imageUrl = 'https://admin.theblackforestcakes.com$imageUrl';
    }
    
    if (imageUrl != null) {
       imageProvider = NetworkImage(imageUrl);
    }

    final statuses = entry['statuses'] as Set;
    // Lock if Sent is 0 (Nothing to confirm)
    final isLocked = sent == 0;
    
    final key = 'supervisor_grid_${entry['productId']}';
    if (!_controllers.containsKey(key)) {
        _controllers[key] = TextEditingController(text: _formatQty(confirmedDisplay));
    }
    final controller = _controllers[key]!;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          if (imageProvider != null)
            Image(image: imageProvider, fit: BoxFit.cover)
          else
            Container(color: Colors.grey.shade200, child: const Icon(Icons.fastfood, size: 40, color: Colors.grey)),

          Container(
             decoration: BoxDecoration(
               gradient: LinearGradient(
                 begin: Alignment.center,
                 end: Alignment.bottomCenter,
                 colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
               ),
             ),
          ),
          
          // Tap Interactions (Background)
           Positioned.fill(
             child: Material(
               color: Colors.transparent,
               child: InkWell(
                 onTap: () {
                    // Close keyboard if typing
                    if (entry['isTyping'] == true) {
                        final val = double.tryParse(controller.text) ?? confirmedDisplay;
                        _saveManualConsolidatedConfirm(entry, val);
                        setState(() {
                          entry['isTyping'] = false;
                        });
                        FocusManager.instance.primaryFocus?.unfocus();
                    }
                 },
                 onDoubleTap: () {
                     if (isLocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Nothing sent by Chef. Cannot confirm.'), duration: Duration(milliseconds: 1000)),
                        );
                        return;
                     }

                     // Auto-Confirm All Sent
                     if (confirmedRaw < sent) {
                       _saveConsolidatedConfirm(entry); 
                     }
                 },
                 child: Container(),
               ),
             ),
           ),

          // Top Left: Sent Qty (Red Badge - Previous Step)
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: 36,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.red, 
                borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
              ),
              child: Text(
                _formatQty(sent),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),

          // Top Right: Price & Unit
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_formatQty(entry['price'])} ${entry['unit']}'.trim(),
                style: const TextStyle(
                  color: Colors.lightGreenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          
          // Center: Confirmed Qty (Interaction Box)
          Builder(builder: (context) {
             final qtyStr = _formatQty(confirmedDisplay);
             // Dynamic width
             final boxWidth = (qtyStr.length * 9.0) + 20.0;
             double finalWidth = boxWidth > 34 ? boxWidth : 34; // Square default
             
             if (entry['isTyping'] == true) {
                 finalWidth = 80.0;
             }
             
             return Center(
               child: entry['isTyping'] == true
               ? Container(
                   width: finalWidth,
                   height: 34,
                   alignment: Alignment.center,
                   decoration: BoxDecoration(
                     color: Colors.black.withOpacity(0.6),
                     borderRadius: BorderRadius.circular(8),
                     boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                   ),
                   child: TextField(
                     controller: controller,
                     autofocus: true,
                     keyboardType: TextInputType.number,
                     textAlign: TextAlign.center,
                     style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                     cursorColor: Colors.white,
                     decoration: const InputDecoration(
                       border: InputBorder.none,
                       contentPadding: EdgeInsets.zero,
                       isDense: true,
                     ),
                     textInputAction: TextInputAction.done,
                     onTapOutside: (event) {
                        final intVal = double.tryParse(controller.text) ?? 0;
                        _saveManualConsolidatedConfirm(entry, intVal);
                        setState(() {
                          entry['isTyping'] = false; 
                        });
                        FocusManager.instance.primaryFocus?.unfocus();
                     },
                     onSubmitted: (val) {
                        final intVal = double.tryParse(val) ?? 0;
                        _saveManualConsolidatedConfirm(entry, intVal);
                        setState(() {
                          entry['isTyping'] = false; 
                        });
                     },
                   ),
                 )
                 : GestureDetector(
                     onTap: () {
                        if (isLocked) {
                          ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('Nothing sent by Chef. Cannot confirm.'), duration: Duration(milliseconds: 1000)),
                          );
                          return;
                        }

                        setState(() {
                           entry['isTyping'] = true;
                           controller.text = _formatQty(confirmedDisplay);
                        });
                     },
                     child: Container(
                       width: finalWidth,
                       height: 34,
                       alignment: Alignment.center,
                       decoration: BoxDecoration(
                         color: Colors.black.withOpacity(0.6),
                         borderRadius: BorderRadius.circular(8),
                         border: (confirmedRaw > 0) 
                             ? Border.all(color: Colors.green, width: 2) // Green if Confirmed > 0 (Done)
                             : null,
                         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                       ),
                        child: Text(
                          _formatQty((entry['confirmedQty'] == 0 || entry['confirmedQty'] == null) ? sent : entry['confirmedQty']),
                          style: TextStyle(
                             color: (sent == 0) ? Colors.red : ((confirmedRaw > 0) ? Colors.green : Colors.white), 
                             fontSize: 14, 
                             fontWeight: FontWeight.bold
                          ),
                        ),
                     ),
                 ),
             );
           }),

           // Bottom: Name Only
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                color: Colors.black87,
                child: Text(
                  productName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if user is factory for consolidated view
    // Check if user is factory or supervisor for consolidated view
    final isFactory = _userRole == 'factory' || _userRole == 'supervisor';
    final isSupervisor = _userRole == 'supervisor';
    // Chef View
    final isChef = _userRole == 'chef';

    Widget mainContent = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                   _buildDateSelector(),
              const SizedBox(height: 12),
              _buildCategoryChips(),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : stockOrders.isEmpty
                  ? const Center(child: Text('No stock orders found'))
                : (isChef || isSupervisor || _userRole == 'driver')
                    ? CustomScrollView(
                               slivers: [
                                  ..._buildGridSlivers(),
                                  // Removed Consolidated Header from bottom as requested
                               ],
                            )
                      : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _visibleStockOrders.length,
                        itemBuilder: (context, index) {
                           return _buildStockOrderCard(_visibleStockOrders[index]);
                        },
                      ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Orders'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Center(child: Text(_userRole.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchStockOrders,
          ),
        ],
      ),
      body: mainContent, 
    );
  }
  bool _matchesCategory(dynamic item) {
     if (widget.categoryId == null) return true;
     
     final product = item['product'];
     final pMap = product is Map ? product : {};
     dynamic catObj = pMap['category'];
     String cId = '';
     if (catObj is Map) cId = catObj['id'] ?? catObj['_id'] ?? '';
     else if (catObj is String) cId = catObj;
     
     return cId == widget.categoryId;
  }
}
