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
  final bool onlyTodayOrdered;

  const StockOrderReportPage({
    super.key,
    this.initialBranchId,
    this.initialFromDate,
    this.initialToDate,
    this.categoryId,
    this.categoryName,
    this.departmentId,
    this.departmentName,
    this.onlyTodayOrdered = false,
  });

  @override
  State<StockOrderReportPage> createState() => _StockOrderReportPageState();
}

class _StockOrderReportPageState extends State<StockOrderReportPage> {
  bool _loading = true;
  bool _loadingBranches = true;
  bool _isSaving = false;
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
  List<Map<String, dynamic>> _consolidatedItems = []; // Deprecated - replaced by specific lists
  List<Map<String, dynamic>> _consolidatedItemsGrid = [];
  List<Map<String, dynamic>> _consolidatedItemsReport = [];
  String _headerBranchCodes = '';
  String _headerDeliveryStr = '';
  String _headerCreatedStr = '';
  String _headerSubtitle = '';
  
  bool _isConsolidatedExpanded = false;
  bool _isReportView = false;
  
  String _selectedDepartmentFilter = 'ALL';
  Set<String> _availableDepartments = {'ALL'};
  String _statusFilter = 'ALL';

  // Map to track local edits: OrderID_ItemID -> Controller
  final Map<String, TextEditingController> _controllers = {};
  
  // Track recently updated items to delay sorting move
  final Set<String> _recentlyUpdatedIds = {};
  
  void _markUpdated(String productId) {
      if (_recentlyUpdatedIds.contains(productId)) return; // Already tracking
      
      setState(() {
         _recentlyUpdatedIds.add(productId);
      });
      
      // Wait 5 seconds then remove and refresh sorting
      Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
              setState(() {
                  _recentlyUpdatedIds.remove(productId);
                  _processStockOrders();
              });
          }
      });
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    if (widget.onlyTodayOrdered) {
       fromDate = now;
       toDate = now;
    } else {
       fromDate = widget.initialFromDate ?? now;
       toDate = widget.initialToDate ?? now;
    }
    
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

  double _getFixedChefQty(String? branchName, String? categoryName) {
    // Logic previously had hardcoded values (50, 15, 10) for specific branches/categories.
    // User requested to remove them / respects dashboard nulls.
    // Defaulting to 0 so it uses the 'requiredQty' (ordered count) instead.
    return 0;
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
    return val.toStringAsFixed(2);
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
  Future<void> _handleFullRefresh() async {
    setState(() {
       final now = DateTime.now();
       fromDate = now;
       toDate = now;
       selectedBranchId = widget.initialBranchId ?? 'ALL';
       _selectedCategoryFilter = 'ALL';
       _selectedDepartmentFilter = 'ALL';
       _statusFilter = 'ALL'; // Reset status filter on refresh
       _loading = true; // Show loader
    });
    await _fetchStockOrders();
  }


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
      final filteredOrders = stockOrders.where((o) {
          final b = o['branch'];
          final bid = b is Map ? (b['id'] ?? b['_id'])?.toString() : null;
          
          bool matchesBranch = selectedBranchId == 'ALL' || bid == selectedBranchId.toString();
          
          // Determine if it's a same-day order (Ordered Today & Delivery Today)
          bool isSameDayOrder = false;
          final now = DateTime.now();
          // Convert to local time before comparing day/month/year
          final cDate = DateTime.tryParse(o['createdAt'] ?? '')?.toLocal();
          final dDate = DateTime.tryParse(o['deliveryDate'] ?? '')?.toLocal();
          
          if (cDate != null && dDate != null) {
            bool isOrderedToday = cDate.year == now.year && cDate.month == now.month && cDate.day == now.day;
            bool isDeliveryToday = dDate.year == now.year && dDate.month == now.month && dDate.day == now.day;
            isSameDayOrder = isOrderedToday && isDeliveryToday;
          }

          if (widget.onlyTodayOrdered) {
            // Branch Mode: Only show same-day orders
            return matchesBranch && isSameDayOrder;
          } else {
            // Stock Mode: Exclude same-day orders
            return matchesBranch && !isSameDayOrder;
          }
      }).toList();

      _visibleStockOrders = filteredOrders;
      Set<String> uniqueCategories = {}; // Init Set
      Set<String> uniqueDepartments = {'ALL'}; // Init Set for Footer

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
            
            // 1. Collect Departments (from all items in branch/date)
            uniqueDepartments.add(dept);
            
            // 2. Filter by Selected Department (Footer)
            if (_selectedDepartmentFilter != 'ALL' && dept != _selectedDepartmentFilter) {
               continue;
            }

            // 3. Collect Categories (only from items in selected department)
            uniqueCategories.add(cat);
            
            // 4. Filter by Selected Category
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
              grp['pickedQty'] = (grp['pickedQty'] as double) + ((item['pickedQty'] as num?) ?? 0).toDouble();
              
              if (!grp.containsKey('receivedQty')) grp['receivedQty'] = 0.0;
              
              if (item['status'] == 'received') {
                 // Logic: If status is received, we count the picked qty as received (or confirmed if picked is 0, etc.)
                 final p = ((item['pickedQty'] as num?) ?? 0).toDouble();
                 final c = ((item['confirmedQty'] as num?) ?? 0).toDouble();
                 final s = ((item['sendingQty'] as num?) ?? 0).toDouble();
                 final val = p > 0 ? p : (c > 0 ? c : s);
                 grp['receivedQty'] = (grp['receivedQty'] as double) + val;
              }

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
      List<Map<String, dynamic>> rawList = productGroups.values.toList().cast<Map<String, dynamic>>();
      
      // Apply Status Filter (APPROVED / NOT APPROVED)
      if (_statusFilter != 'ALL') {
          rawList = rawList.where((item) {
             bool isApproved = false;
             // Logic same as sort logic for "Done" items
             if (isChef) {
                isApproved = ((item['sendingQty'] as num?) ?? 0) > 0;
             } else if (isSupervisor) {
                isApproved = ((item['confirmedQty'] as num?) ?? 0) > 0;
             } else if (isDriver) {
                isApproved = ((item['pickedQty'] as num?) ?? 0) > 0;
             } else {
                // Determine logic for Factory or others - defaulting to Chef logic (Sending > 0) or just ignore
                // Let's assume sending > 0 for now as generic "Action Taken"
                 isApproved = ((item['sendingQty'] as num?) ?? 0) > 0;
             }
             
             if (_statusFilter == 'APPROVED') {
                 return isApproved;
             } else {
                 return !isApproved;
             }
          }).toList();
      }

      // 1. Grid List (Alphabetical Only)
      List<Map<String, dynamic>> gridList = List.from(rawList);
      gridList.sort((a, b) {
         int cmp = (a['departmentName'] ?? '').compareTo(b['departmentName'] ?? '');
         if (cmp != 0) return cmp;
         
         cmp = (a['categoryName'] ?? '').compareTo(b['categoryName'] ?? '');
         if (cmp != 0) return cmp;

         return (a['productName'] ?? '').compareTo(b['productName'] ?? '');
      });

      // 2. Report List (Status Sorting - "Done" items to bottom)
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
          
          // Delay sorting move for recently updated items
          final aId = (a['productId'] as String?) ?? '';
          final bId = (b['productId'] as String?) ?? '';
          
          if (_recentlyUpdatedIds.contains(aId)) {
             aDone = false;
          }
          if (_recentlyUpdatedIds.contains(bId)) {
             bDone = false;
          }

          if (aDone != bDone) {
             return aDone ? 1 : -1; // Done Items LAST
          }
          
          return (a['productName'] ?? '').compareTo(b['productName'] ?? '');
      });

      
       // Define Totals Calculation
       Map<String, Map<String, double>> categoryTotals = {}; 
       Map<String, Map<String, double>> departmentTotals = {};
       // Reset global totals to calculate from filtered list
       totalReqAmt = 0;
       totalSent = 0;
       
       for (var item in rawList) { 
          final cat = item['categoryName'] as String;
          final dept = item['departmentName'] as String;
          final price = (item['price'] as num).toDouble();
          final req = (item['requiredQty'] as num).toDouble();
          final sent = (item['sendingQty'] as num).toDouble();

          // Global Totals (Filtered)
          totalReqAmt += (req * price);
          totalSent += sent;

          // Category Totals
          if (!categoryTotals.containsKey(cat)) {
             categoryTotals[cat] = {'req': 0.0, 'sent': 0.0, 'conf': 0.0, 'pick': 0.0};
          }
          final cTotals = categoryTotals[cat]!;
          cTotals['req'] = (cTotals['req']!) + req;
          cTotals['sent'] = (cTotals['sent']!) + sent;
          cTotals['conf'] = (cTotals['conf']!) + ((item['confirmedQty'] as num).toDouble());
          cTotals['pick'] = (cTotals['pick']!) + ((item['pickedQty'] as num).toDouble());

          // Department Totals
          if (!departmentTotals.containsKey(dept)) {
             departmentTotals[dept] = {'req': 0.0, 'sent': 0.0, 'conf': 0.0, 'pick': 0.0};
          }
          final dTotals = departmentTotals[dept]!;
          dTotals['req'] = (dTotals['req']!) + req;
          dTotals['sent'] = (dTotals['sent']!) + sent;
          dTotals['conf'] = (dTotals['conf']!) + ((item['confirmedQty'] as num).toDouble());
          dTotals['pick'] = (dTotals['pick']!) + ((item['pickedQty'] as num).toDouble());
       }

      List<Map<String, dynamic>> generateList(List<Map<String, dynamic>> source) {
           List<Map<String, dynamic>> res = [];
           String? lastDept;
           String? lastCat;
           int sIdx = 0;
           
           for (var item in source) {
              final dept = item['departmentName'] as String;
              final cat = item['categoryName'] as String;
              
              if (dept != lastDept && widget.categoryId == null) {
                  final dTotals = departmentTotals[dept] ?? {'req': 0.0, 'sent': 0.0, 'conf': 0.0, 'pick': 0.0};
                  res.add({
                      'type': 'header_dept', 
                      'title': dept,
                      'totals': dTotals
                  });
                  lastDept = dept;
                  lastCat = null; 
              }
              if (cat != lastCat && widget.categoryId == null) {
                  final totals = categoryTotals[cat] ?? {'req': 0.0, 'sent': 0.0, 'conf': 0.0, 'pick': 0.0};
                  res.add({
                      'type': 'header_cat', 
                      'title': cat,
                      'totals': totals
                  });
                  lastCat = cat;
              }
              item['stripeIndex'] = sIdx++;
              res.add(item);
           }
           return res;
      }

      _consolidatedItemsReport = generateList(rawList);
      _consolidatedItemsGrid = generateList(gridList);
      _consolidatedItems = _consolidatedItemsReport; // Default to report view logic for others

      _headerSubtitle = '${_consolidatedItems.where((i) => i['type'] == 'item').length} Products     Req Amt: ${totalReqAmt.toInt()}     Snt Qty: ${_formatQty(totalSent)}';
      _availableDepartments = uniqueDepartments; // Update Footer Options
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

  Future<void> _updateItemStatus(String orderId, Map<String, dynamic> itemToUpdate, double newSentQty, {String? pName}) async {
    final token = await _getToken();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Updating...'), duration: Duration(milliseconds: 500)),
    );

    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
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
        Map<String, dynamic> apiItem = Map<String, dynamic>.from(item);
        
        if (pid == targetPid) {
          found = true;
          // Fix Product to be ID string for the updated item
          apiItem['product'] = pid; 
          apiItem['sendingQty'] = newSentQty;
          apiItem['status'] = 'sending';
          apiItem['sendingDate'] = nowStr;
          
          itemToUpdate['status'] = 'sending';
          itemToUpdate['sendingQty'] = newSentQty;
          itemToUpdate['sendingDate'] = nowStr;
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
        String msg = 'Saved successfully';
        if (pName != null) {
           msg = '${_formatQty(newSentQty)} $pName Sending';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.green, duration: const Duration(milliseconds: 800)),
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

  Future<void> _updateConfirmQty(String orderId, Map<String, dynamic> itemToUpdate, double qty, {String? pName}) async {
    final token = await _getToken();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Confirming...'), duration: Duration(milliseconds: 500)),
    );

    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
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
        
        if (pid == targetPid) {
          found = true;
          apiItem['product'] = pid; 
          apiItem['confirmedQty'] = qty;
          apiItem['status'] = itemToUpdate['status'] ?? 'confirmed'; 
          apiItem['confirmedDate'] = nowStr;
          
          itemToUpdate['confirmedQty'] = qty;
          itemToUpdate['confirmedDate'] = nowStr;
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
        String msg = 'Confirmed successfully';
        if (pName != null) {
           msg = '${_formatQty(qty)} $pName Confirmed';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.green, duration: const Duration(milliseconds: 800)),
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
      if (_isSaving) return;
      setState(() => _isSaving = true);
      try {
        _markUpdated(entry['productId']);
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
         
         await _updateConfirmQty(orderId, item, currentSent, pName: entry['productName']);
      }
      
      setState(() {
         entry['confirmedQty'] = newTotalConfirmed;
         entry['statuses'] = {'confirmed'}; // Update local aggregate status
         _processStockOrders();
      });
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
  }



  // Update params to accept num/double
  Future<void> _saveStockOrder(Map<String, dynamic> entry, double totalQty) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
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
        
        await _updateItemStatus(orderId, item, totalQty, pName: entry['productName']);
        
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
           await _updateItemStatus(orderId, item, allocated, pName: entry['productName']);
       }
    }

    setState(() {
       entry['sendingQty'] = totalQty;
       entry['statuses'] = newStatuses;
       _processStockOrders();
    });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveManualConsolidatedConfirm(Map<String, dynamic> entry, double newVal) async {
       if (_isSaving) return;
       setState(() => _isSaving = true);
       try {
         _markUpdated(entry['productId']);
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
         await _updateConfirmQty(orderId, item, allocated, pName: entry['productName']);
      }
      
      setState(() {
         entry['confirmedQty'] = newVal;
         if (newVal > 0) {
            final stats = (entry['statuses'] as Set);
            stats.add('confirmed'); // Add confirmed status
         }
         _processStockOrders();
      });
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
  }

  Future<void> _updatePickQty(String orderId, Map<String, dynamic> itemToUpdate, double qty, {String? pName}) async {
    final token = await _getToken();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final orderIndex = stockOrders.indexWhere((o) => (o['id'] ?? o['_id']) == orderId);
      if (orderIndex == -1) return;
      final order = stockOrders[orderIndex];
      // We will construct the payload for this order
      // Assuming we need to send ALL items for this order or just the updated one?
      // Usually checking the API: if we send a partial list, it might replace them?
      // Let's assume we modify the specific item in the list and send the whole list back 
      // OR if the backend supports partial updates on items array. 
      // Based on previous code, we rebuild the list.
      
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
        
        if (pid == targetPid) {
          found = true;
          apiItem['product'] = pid; 
          apiItem['pickedQty'] = qty;
          apiItem['status'] = 'picked';
          apiItem['pickedDate'] = nowStr;
          
          itemToUpdate['pickedQty'] = qty;
          itemToUpdate['status'] = 'picked';
          itemToUpdate['pickedDate'] = nowStr;
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
      // Success feedback
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      String msg = 'Picked successfully';
      if (pName != null) {
         msg = '${_formatQty(qty)} $pName Picked';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green, duration: const Duration(milliseconds: 800)),
      );
    } catch (e) {
         debugPrint('Error picking qty: $e');
         ScaffoldMessenger.of(context).hideCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error picking: $e'), backgroundColor: Colors.red),
         );
    }
  }

  Future<void> _saveManualConsolidatedPick(Map<String, dynamic> entry, double val) async {
       if (_isSaving) return;
       setState(() => _isSaving = true);
       try {
         _markUpdated(entry['productId']);
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
         
         await _updatePickQty(orderId, item, apply, pName: entry['productName']);
         
         remaining -= apply;
         newTotalPicked += apply;
      }
      
      setState(() {
         entry['pickedQty'] = newTotalPicked;
         if (newTotalPicked > 0) entry['statuses'] = {'picked'};
         _processStockOrders();
      });
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
  }

  Future<void> _saveConsolidatedPick(Map<String, dynamic> entry) async {
      if (_isSaving) return;
      setState(() => _isSaving = true);
      try {
        _markUpdated(entry['productId']);
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
         
         await _updatePickQty(orderId, item, currentConfirmed, pName: entry['productName']);
      }
      
      setState(() {
         entry['pickedQty'] = newTotalPicked;
         entry['statuses'] = {'picked'}; 
         _processStockOrders();
      });
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
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
              height: 36,
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
            height: 36,
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
        height: 40,
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
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
               child: GridView.builder(
                 shrinkWrap: true,
                 physics: const NeverScrollableScrollPhysics(),
                 gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                   crossAxisCount: 3,
                   childAspectRatio: 0.75, 
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
                    childAspectRatio: 0.75, 
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

    for (var item in _consolidatedItemsGrid) {
       if (item['type'] == 'header_dept') {
          flushGroup();
          isUnderCategory = false; // Reset
          slivers.add(SliverToBoxAdapter(
             child: Padding(
               padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                          Expanded(
                            child: Text(
                              (item['title'] ?? '').toString().toUpperCase(),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildTotalsText(item['totals']),
                      ],
                   ),
                   const Divider(color: Colors.black54, thickness: 2, height: 8),
                 ],
               ),
             ),
          ));
       } else if (item['type'] == 'header_cat') {
          flushGroup();
          isUnderCategory = true; // Start category section
          
          slivers.add(SliverToBoxAdapter(
             child: Container(
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
               child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                      Expanded(
                        child: Text(
                          (item['title'] ?? '').toString(),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildTotalsText(item['totals']),
                  ],
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

  Widget _buildFactoryConsolidatedView() {
      // Filter out headers for clean data iteration if needed, OR verify _consolidatedItems structure.
      // _consolidatedItems contains: header_dept, header_cat, item.
      // We want to render a single long card with this structure.

      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Card(
            elevation: 0,
            color: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 // Top Header
                 Padding(
                   padding: const EdgeInsets.all(16),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                        const Text('ALL BRANCHES CONSOLIDATED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 4),
                        Text('Delivery: $_headerDeliveryStr', style: TextStyle(color: Colors.blue[700], fontSize: 14, fontWeight: FontWeight.bold)),
                        Text('Created: $_headerCreatedStr', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                     ],
                   ),
                 ),
                 const Divider(height: 1),
                 
                 // Table Header
                 Container(
                     padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                     child: Row(
                        children: [
                          const Expanded(flex: 3, child: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          const Expanded(flex: 1, child: Center(child: Text('Ord', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                          const Expanded(flex: 1, child: Center(child: Text('Snt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                          const Expanded(flex: 1, child: Center(child: Text('Con', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                          const Expanded(flex: 1, child: Center(child: Text('Pic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                          const Expanded(flex: 1, child: Center(child: Text('Rec', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                        ],
                     ),
                 ),
                 
                 // Content
                 ..._consolidatedItemsReport.map((entry) {
                     if (entry['type'] == 'header_dept') {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          child: Text(
                             (entry['title'] as String).toUpperCase(),
                             style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                             textAlign: TextAlign.center,
                          ),
                        );
                     } else if (entry['type'] == 'header_cat') {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                          child: Text(
                             (entry['title'] as String).toUpperCase(),
                             style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                             textAlign: TextAlign.center,
                          ),
                        );
                     } else if (entry['type'] == 'item') {
                         final req = ((entry['requiredQty'] as num?) ?? 0).toDouble();
                         final sent = ((entry['sendingQty'] as num?) ?? 0).toDouble();
                         final conf = ((entry['confirmedQty'] as num?) ?? 0).toDouble();
                         final picked = ((entry['pickedQty'] as num?) ?? 0).toDouble();
                         final rec = ((entry['receivedQty'] as num?) ?? 0).toDouble();
                         final price = ((entry['price'] as num?) ?? 0).toDouble();
                         final unit = entry['unit'] ?? '';
                         
                         return Container(
                           padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                           decoration: BoxDecoration(
                               border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                           ),
                           child: Row(
                             children: [
                                Expanded(
                                  flex: 3, 
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(entry['productName'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                      Text('${_formatQty(price)} $unit', style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                Expanded(flex: 1, child: Center(child: Text(_formatQty(req), style: const TextStyle(fontSize: 12)))),
                                Expanded(flex: 1, child: Center(child: Text(_formatQty(sent), style: const TextStyle(fontSize: 12, color: Colors.blue)))),
                                Expanded(flex: 1, child: Center(child: Text(_formatQty(conf), style: const TextStyle(fontSize: 12, color: Colors.orange)))),
                                Expanded(flex: 1, child: Center(child: Text(_formatQty(picked), style: const TextStyle(fontSize: 12, color: Colors.purple)))),
                                Expanded(flex: 1, child: Center(child: Text(rec > 0 ? _formatQty(rec) : '-', style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold)))),
                             ],
                           ),
                         );
                     }
                     return const SizedBox.shrink();
                 }),
                 
                 const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildSummaryColumn(String label, double value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(_formatQty(value), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
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
    final isStrictFactory = _userRole == 'factory';
    final isSupervisor = _userRole == 'supervisor';

    if (isStrictFactory) {
       return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               // Header
               Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(invoiceNumber, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                    _buildStatusChip(status),
                  ],
               ),
               const SizedBox(height: 4),
               Text(branchName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
               const SizedBox(height: 4),
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Text('Delivery: $deliveryStr', style: TextStyle(color: Colors.blue[700], fontSize: 14, fontWeight: FontWeight.bold)),
                   Text(createdStr, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                 ],
               ),
               
               const Divider(height: 16),
               
               // Table Header
               Container(
                 padding: const EdgeInsets.symmetric(vertical: 8),
                 color: const Color(0xFFEFEBE9), 
                 child: Row(
                    children: [
                      const Expanded(flex: 3, child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      const Expanded(flex: 1, child: Center(child: Text('Ord', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                      const Expanded(flex: 1, child: Center(child: Text('Snt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                      const Expanded(flex: 1, child: Center(child: Text('Con', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                      const Expanded(flex: 1, child: Center(child: Text('Pic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                      const Expanded(flex: 1, child: Center(child: Text('Rec', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                    ],
                 ),
               ),
               
               // Items List
               ...filteredItems.map((item) {
                   final product = item['product'];
                   final pName = (product is Map ? product['name'] : 'Unknown') ?? 'Unknown';
                   final req = ((item['requiredQty'] as num?) ?? 0).toDouble();
                   final sent = ((item['sendingQty'] as num?) ?? 0).toDouble();
                   final conf = ((item['confirmedQty'] as num?) ?? 0).toDouble();
                   final picked = ((item['pickedQty'] as num?) ?? 0).toDouble();
                   final itemStatus = (item['status'] as String?)?.toLowerCase() ?? 'pending';
                   
                   double received = 0;
                   if (itemStatus == 'received') {
                       received = picked > 0 ? picked : (conf > 0 ? conf : sent);
                   }

                   // Price/Unit Logic
                   double price = 0.0;
                   String unit = '';
                   if (product is Map) {
                       if (product['defaultPriceDetails'] is Map) {
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

                   return Container(
                     padding: const EdgeInsets.symmetric(vertical: 8),
                     decoration: BoxDecoration(
                         color: received > 0 ? Colors.green.shade50 : Colors.red.shade50,
                         border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                     ),
                     child: Row(
                       children: [
                          Expanded(
                            flex: 3, 
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                Text('${_formatQty(price)} $unit', style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Expanded(flex: 1, child: Center(child: Text(_formatQty(req), style: const TextStyle(fontSize: 12)))),
                          Expanded(flex: 1, child: Center(child: Text(_formatQty(sent), style: const TextStyle(fontSize: 12, color: Colors.blue)))),
                          Expanded(flex: 1, child: Center(child: Text(_formatQty(conf), style: const TextStyle(fontSize: 12, color: Colors.orange)))),
                          Expanded(flex: 1, child: Center(child: Text(_formatQty(picked), style: const TextStyle(fontSize: 12, color: Colors.purple)))),
                          Expanded(flex: 1, child: Center(child: Text(received > 0 ? _formatQty(received) : '-', style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold)))),
                       ],
                     ),
                   );
               }),
            ],
          ),
        ),
       );
    }

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
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: Text(
                        dept.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                    ));
                    lastDept = dept;
                    lastCat = null;
                  }
                  
                  if (cat != lastCat) {
                    widgets.add(Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
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
                       _updateItemStatus(orderId, item, currentVal, pName: productName);
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
                                    });
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
                                     _updateConfirmQty(orderId, item, val.toDouble(), pName: productName);
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
        decoration: const BoxDecoration(
          // color: Colors.brown.shade100, // Removed
          // border: const Border( // Removed
          //   left: BorderSide(color: Colors.white, width: 0), // Adjust if needed
          // ),
        ),
        // Hack to match Card layout: Card usually has 4 margin. We use padding/margin to align.
        // Actually, best to wrap in a Material to match Card exactly.
        child: Material(
          color: Colors.transparent, // Changed from Colors.brown.shade100
          elevation: 0, 
          // We wrap in a container with side margins to match the Header Card's visual width
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), // Match Header padding X
            child: Row(
              children: [
                const Expanded(flex: 3, child: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black))),
                if (!isSupervisor && !isDriver) 
                   const Expanded(flex: 1, child: Center(child: Text('Req', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)))),
                if (!isDriver)
                    const Expanded(flex: 1, child: Center(child: Text('Snt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)))),
                if (isSupervisor || isDriver)
                   const Expanded(flex: 1, child: Center(child: Text('Con', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)))),
                if (isDriver)
                   const Expanded(flex: 1, child: Center(child: Text('Pic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)))),
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
         // color: Colors.white, // Removed
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
        width: double.infinity,
        alignment: Alignment.center,
        child: Text(
          (entry['title'] as String).toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
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
    
    // Lock if Confirmed or Picked
    final isLocked = statuses.contains('confirmed') || statuses.contains('picked');
    
    final key = 'supervisor_confirm_${entry['productId']}';
    if (!_controllers.containsKey(key)) {
        _controllers[key] = TextEditingController(text: _formatQty(confirmedDisplay));
    }
    final controller = _controllers[key]!;

    // Unified Interaction Logic
    void onAutoAction() {
      if (_isSaving) return;
      if (isLocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item is picked by Driver. Cannot edit.'), duration: Duration(milliseconds: 1000)),
        );
        return;
      }
      
      double valToSave = confirmedDisplay;
      if (entry['isTyping'] == true) {
        valToSave = double.tryParse(controller.text) ?? confirmedDisplay;
      }

      // Compulsory Double Tap to Save
      _saveManualConsolidatedConfirm(entry, valToSave);
      setState(() {
         entry['isTyping'] = false;
      });
    }

    void onManualEdit() {
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
    }

    return Card(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Top Section: Image & Badges (Flex 8)
          Expanded(
            flex: 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image Area with Unified Gesture
                GestureDetector(
                  onTap: onManualEdit,
                  onDoubleTap: onAutoAction,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageProvider != null)
                        Image(image: imageProvider, fit: BoxFit.cover)
                      else
                        Container(child: const Icon(Icons.fastfood, size: 40, color: Colors.grey)),
                    ],
                  ),
                ),

                // Top Left: Sent Qty (Badges sit ON TOP of gesture detector)
                Positioned(
                  top: 2,
                  left: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatQty(sent),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),

                // Top Right: Price & Unit (Compact)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatQty(entry['price']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                
                // Product Name Overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                    ),
                    child: Text(
                      productName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Section: Interaction Strip (Flex 2)
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onManualEdit,
                    onDoubleTap: onAutoAction,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      color: (statuses.contains('sending') || statuses.contains('confirmed') || statuses.contains('picked')) ? Colors.green : Colors.black87,
                      child: entry['isTyping'] == true
                          ? SizedBox(
                              height: 18,
                              child: TextField(
                                controller: controller,
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                textAlignVertical: TextAlignVertical.center,
                                 style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.0),
                                cursorColor: Colors.white,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isCollapsed: true,
                                ),
                                textInputAction: TextInputAction.done,
                                onTapOutside: (event) {
                                   final doubleVal = double.tryParse(controller.text) ?? 0;
                                   setState(() {
                                     entry['confirmedQty'] = doubleVal;
                                     entry['isTyping'] = false;
                                   });
                                   FocusManager.instance.primaryFocus?.unfocus();
                                },
                                onSubmitted: (val) {
                                   final doubleVal = double.tryParse(val) ?? 0;
                                   setState(() {
                                     entry['confirmedQty'] = doubleVal;
                                     entry['isTyping'] = false;
                                   });
                                 },
                              ),
                            )
                          : Text(
                              _formatQty(confirmedDisplay),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1.0),
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
                ),
              ],
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
  
  // Lock if Picked or Received
  final isLocked = statuses.contains('picked') || statuses.contains('received');
  
  final key = 'driver_pick_${entry['productId']}';
  if (!_controllers.containsKey(key)) {
      _controllers[key] = TextEditingController(text: _formatQty(pickedDisplay));
  }
  final controller = _controllers[key]!;

  // Unified Interaction Logic
  void onAutoAction() {
     if (_isSaving) return;
     if (isLocked) {
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Item is received by Branch. Cannot edit.'), duration: Duration(milliseconds: 1000)),
        );
        return;
     }

    double valToSave = pickedDisplay;
    if (entry['isTyping'] == true) {
      valToSave = double.tryParse(controller.text) ?? pickedDisplay;
    }

    // Compulsory Double Tap to Save
    _saveManualConsolidatedPick(entry, valToSave); 
    setState(() {
      entry['isTyping'] = false;
    });
  }

  void onManualEdit() {
     if (isLocked) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Item is received by Branch. Cannot edit.'), duration: Duration(milliseconds: 1000)),
       );
       return;
     }
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
  }

  return Card(
    elevation: 0,
    color: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide.none,
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
          // Top Section (Flex 8)
          Expanded(
            flex: 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image Area with Unified Gesture
                GestureDetector(
                  onTap: onManualEdit,
                  onDoubleTap: onAutoAction,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageProvider != null)
                        Image(image: imageProvider, fit: BoxFit.cover)
                      else
                        Container(child: const Icon(Icons.fastfood, size: 40, color: Colors.grey)),
                    ],
                  ),
                ),

                // Top Left: Confirmed Qty
                Positioned(
                  top: 2,
                  left: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatQty(confirmedRaw),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ),
                ),

                // Top Right: Price
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatQty(entry['price']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                
                // Product Name Overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                    ),
                    child: Text(
                      productName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Bottom Section: Interaction Strip (Flex 2)
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onManualEdit,
                    onDoubleTap: onAutoAction,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      color: (statuses.contains('sending') || statuses.contains('confirmed') || statuses.contains('picked')) ? Colors.green : Colors.black87,
                      child: entry['isTyping'] == true
                          ? SizedBox(
                              height: 18,
                              child: TextField(
                                 controller: controller,
                                 autofocus: true,
                                 keyboardType: TextInputType.number,
                                 textAlign: TextAlign.center,
                                 textAlignVertical: TextAlignVertical.center,
                                 style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.0),
                                 cursorColor: Colors.white,
                                 decoration: const InputDecoration(
                                   border: InputBorder.none,
                                   contentPadding: EdgeInsets.zero,
                                   isCollapsed: true,
                                 ),
                                 textInputAction: TextInputAction.done,
                                 onTapOutside: (event) {
                                   final intVal = double.tryParse(controller.text) ?? 0;
                                   setState(() {
                                     entry['pickedQty'] = intVal;
                                     entry['isTyping'] = false;
                                   });
                                   FocusManager.instance.primaryFocus?.unfocus();
                                 },
                                 onSubmitted: (val) {
                                   final intVal = double.tryParse(val) ?? 0;
                                   setState(() {
                                     entry['pickedQty'] = intVal;
                                     entry['isTyping'] = false;
                                   });
                                 },
                              ),
                            )
                          : Center(
                              child: Text(
                                _formatQty((entry['pickedQty'] == 0 || entry['pickedQty'] == null) ? confirmedRaw : entry['pickedQty']),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1.0),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
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
    final isLocked = statuses.contains('sending') || statuses.contains('confirmed') || statuses.contains('picked') || confirmedQty > 0;

    // Resolve branch name for fixed qty logic
    String? currentBranchName;
    if (selectedBranchId != 'ALL') {
       final found = branches.firstWhere((b) => b['id'] == selectedBranchId, orElse: () => {});
       if (found.isNotEmpty) currentBranchName = found['name'];
    }
    final fixedQty = _getFixedChefQty(currentBranchName, entry['categoryName']);
    final suggestedVal = fixedQty > 0 ? fixedQty : req;

    // Unified Interaction Logic
    void onAutoAction() {
      if (isLocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item is confirmed/picked. Cannot edit.'), duration: Duration(milliseconds: 1000)),
        );
        return;
      }
      
      final currentSent = ((entry['sendingQty'] as num?) ?? 0).toDouble();
      double valToSave = (currentSent > 0) ? currentSent : suggestedVal;
      
      if (entry['isTyping'] == true) {
        valToSave = double.tryParse(controller.text) ?? valToSave;
      }

      // Compulsory Double Tap to Save
      _saveStockOrder(entry, valToSave);
      setState(() {
        entry['isTyping'] = false;
      });
    }

    void onManualEdit() {
      if (isLocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item is confirmed/picked. Cannot edit.'), duration: Duration(milliseconds: 1000)),
        );
        return;
      }
      setState(() {
        entry['isTyping'] = true;
        final current = ((entry['sendingQty'] as num?) ?? 0).toDouble();
        controller.text = _formatQty(current == 0 ? req : current);
      });
    }

    return Card(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
            // Top Section (Flex 8)
            Expanded(
              flex: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image Area with Unified Gesture
                  GestureDetector(
                    onTap: onManualEdit,
                    onDoubleTap: onAutoAction,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageProvider != null)
                          Image(image: imageProvider, fit: BoxFit.cover)
                        else
                          Container(child: const Icon(Icons.fastfood, size: 40, color: Colors.grey)),


                      ],
                    ),
                  ),

                  // Top Left: Ordered Qty
                  Positioned(
                    top: 2,
                    left: 2,
                    child: GestureDetector(
                      onTap: () {
                         if (isLocked) return;
                         double current = ((entry['sendingQty'] as num?) ?? 0).toDouble();
                             if (current > 0) {
                                setState(() {
                                   entry['sendingQty'] = (current - 1).clamp(0, double.infinity);
                                });
                             }                    },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatQty(req),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                        ),
                      ),
                    ),
                  ),

                  // Top Right: Price
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatQty(entry['price']),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),

                  // Product Name Overlay
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                      ),
                      child: Text(
                        productName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Bottom Section: Interaction Strip (Flex 2)
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onManualEdit,
                      onDoubleTap: onAutoAction,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        color: (statuses.contains('sending') || statuses.contains('confirmed') || statuses.contains('picked')) ? Colors.green : Colors.black87,
                        child: entry['isTyping'] == true
                            ? SizedBox(
                                height: 18,
                                child: TextField(
                                   controller: controller,
                                   autofocus: true,
                                   keyboardType: TextInputType.number,
                                   textAlign: TextAlign.center,
                                   textAlignVertical: TextAlignVertical.center,
                                   style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.0),
                                   cursorColor: Colors.white,
                                   decoration: const InputDecoration(
                                     border: InputBorder.none,
                                     contentPadding: EdgeInsets.zero,
                                     isCollapsed: true,
                                   ),
                                   textInputAction: TextInputAction.done,
                                   onTapOutside: (event) {
                                     final doubleVal = double.tryParse(controller.text) ?? 0;
                                     setState(() {
                                       entry['sendingQty'] = doubleVal;
                                       entry['isTyping'] = false;
                                     });
                                     FocusManager.instance.primaryFocus?.unfocus();
                                   },
                                   onSubmitted: (val) {
                                     final doubleVal = double.tryParse(val) ?? 0;
                                     setState(() {
                                       entry['sendingQty'] = doubleVal;
                                       entry['isTyping'] = false;
                                     });
                                   },
                                ),
                              )
                            : Text(
                                (entry['sendingQty'] == null || entry['sendingQty'] == 0) ? _formatQty(suggestedVal) : _formatQty(entry['sendingQty']),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1.0),
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ),
                  ),
                ],
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
    // Lock if Confirmed or Picked
    final isLocked = statuses.contains('confirmed') || statuses.contains('picked');
    
    final key = 'supervisor_grid_${entry['productId']}';
    if (!_controllers.containsKey(key)) {
        _controllers[key] = TextEditingController(text: _formatQty(confirmedDisplay));
    }
    final controller = _controllers[key]!;

    // Unified Interaction Logic
    void onAutoAction() {
       if (isLocked) {
          ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Nothing sent by Chef. Cannot confirm.'), duration: Duration(milliseconds: 1000)),
          );
          return;
       }

       double valToSave = confirmedDisplay;
       if (entry['isTyping'] == true) {
          valToSave = double.tryParse(controller.text) ?? confirmedDisplay;
       }

       // Compulsory Double Tap to Save
       _saveManualConsolidatedConfirm(entry, valToSave); 
       setState(() {
         entry['isTyping'] = false;
       });
    }

    void onManualEdit() {
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
    }

    return Card(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
            // Top Section (Flex 8)
            Expanded(
              flex: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image Area with Unified Gesture
                  GestureDetector(
                    onTap: onManualEdit,
                    onDoubleTap: onAutoAction,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageProvider != null)
                          Image(image: imageProvider, fit: BoxFit.cover)
                        else
                          Container(child: const Icon(Icons.fastfood, size: 40, color: Colors.grey)),


                      ],
                    ),
                  ),

                  // Top Left: Sent Qty
                  Positioned(
                    top: 2,
                    left: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatQty(sent),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                  ),

                  // Top Right: Price
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatQty(entry['price']),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),

                // Product Name Overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                    ),
                    child: Text(
                      productName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Bottom Section: Interaction Strip (Flex 2)
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(
                    child: GestureDetector(
                      onTap: onManualEdit,
                      onDoubleTap: onAutoAction,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        color: (statuses.contains('sending') || statuses.contains('confirmed') || statuses.contains('picked')) ? Colors.green : Colors.black87,
                        child: entry['isTyping'] == true
                            ? SizedBox(
                                height: 18,
                                child: TextField(
                                   controller: controller,
                                   autofocus: true,
                                   keyboardType: TextInputType.number,
                                   textAlign: TextAlign.center,
                                   textAlignVertical: TextAlignVertical.center,
                                   style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.0),
                                   cursorColor: Colors.white,
                                   decoration: const InputDecoration(
                                     border: InputBorder.none,
                                     contentPadding: EdgeInsets.zero,
                                     isCollapsed: true,
                                   ),
                                   textInputAction: TextInputAction.done,
                                   onTapOutside: (event) {
                                   final doubleVal = double.tryParse(controller.text) ?? 0;
                                   setState(() {
                                     entry['confirmedQty'] = doubleVal;
                                     entry['isTyping'] = false;
                                   });
                                   FocusManager.instance.primaryFocus?.unfocus();
                                },
                                   onSubmitted: (val) {
                                   final doubleVal = double.tryParse(val) ?? 0;
                                   setState(() {
                                     entry['confirmedQty'] = doubleVal;
                                     entry['isTyping'] = false;
                                   });
                                 },
                                ),
                              )
                            : Text(
                                _formatQty((entry['confirmedQty'] == 0 || entry['confirmedQty'] == null) ? sent : entry['confirmedQty']),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1.0),
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ),
                  ),
                ],
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
  final isStrictFactory = _userRole == 'factory';
  final isSupervisor = _userRole == 'supervisor';
    // Chef View
    final isChef = _userRole == 'chef';

    Widget mainContent = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                   _buildDateSelector(),
              const SizedBox(height: 8),
              _buildCategoryChips(),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : stockOrders.isEmpty
                  ? const Center(child: Text('No stock orders found'))
              : (isStrictFactory && selectedBranchId == 'ALL')
                  ? _buildFactoryConsolidatedView()
                  : (isChef || isSupervisor || _userRole == 'driver')
                  ? _isReportView 
                      ? _buildReportView()
                      : CustomScrollView(
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.onlyTodayOrdered ? 'Branch Orders' : 'Stock Orders'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Center(child: Text(_userRole.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _handleFullRefresh,
          ),
           if (isChef || isSupervisor || isDriver)
            IconButton(
              icon: Icon(_isReportView ? Icons.grid_view : Icons.table_chart),
              onPressed: () {
                setState(() {
                  _isReportView = !_isReportView;
                });
              },
            ),
        ],
      ),
      body: mainContent, 
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            _buildDepartmentFooter(), // Department Footer First
            _buildStatusFilterBar(),  // Status Filter Second (Bottom)
        ],
      ),
    );
  }
  
  Widget _buildStatusFilterBar() {
      final isAll = _statusFilter == 'ALL'; 
      final isApproved = _statusFilter == 'APPROVED';
      final isNotApproved = _statusFilter == 'NOT_APPROVED';
      
      // Fixed Backgrounds - distinct from Department Footer (Black)
      final Color approvedBg = Colors.grey[900]!; 
      final Color notApprovedBg = Colors.grey[900]!;

      return SizedBox(
        height: 40, // Reduced height
        width: double.infinity,
        child: Row(
             children: [
               Expanded(
                   child: GestureDetector(
                       onTap: () {
                          setState(() {
                             _statusFilter = isApproved ? 'ALL' : 'APPROVED';
                             _processStockOrders();
                          });
                       },
                       child: Container(
                          color: approvedBg,
                          alignment: Alignment.center,
                          child: Text(
                             'APPROVED', 
                             style: TextStyle(
                                 fontWeight: FontWeight.bold, 
                                 fontSize: 16, 
                                 // Active: Green, Inactive: White
                                 // If Not Approved is active, this one is dim white
                                 color: isApproved 
                                    ? Colors.greenAccent 
                                    : (isNotApproved ? Colors.white.withOpacity(0.3) : Colors.white)
                             )
                          ),
                       ),
                   ),
               ),
               Expanded(
                   child: GestureDetector(
                       onTap: () {
                          setState(() {
                             _statusFilter = isNotApproved ? 'ALL' : 'NOT_APPROVED';
                             _processStockOrders();
                          });
                       },
                       child: Container(
                          color: notApprovedBg,
                          alignment: Alignment.center,
                          child: Text(
                             'NOT APPROVED', 
                             style: TextStyle(
                                 fontWeight: FontWeight.bold, 
                                 fontSize: 16, 
                                 // Active: Red, Inactive: White
                                 // If Approved is active, this one is dim white
                                 color: isNotApproved 
                                     ? Colors.redAccent 
                                     : (isApproved ? Colors.white.withOpacity(0.3) : Colors.white)
                             )
                          ),
                       ),
                   ),
               ),
             ],
        ),
      );
  }

  Widget _buildDepartmentFooter() {
     if (_availableDepartments.isEmpty || _availableDepartments.length <= 1) return const SizedBox.shrink();
     
     final sortedDepts = _availableDepartments.toList()..sort();
     // Ensure ALL is first
     if (sortedDepts.contains('ALL')) {
        sortedDepts.remove('ALL');
        sortedDepts.insert(0, 'ALL');
     }

     return Container(
        height: 60,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        color: Colors.black, // Dark Footer
        child: ListView.separated(
           scrollDirection: Axis.horizontal,
           itemCount: sortedDepts.length,
           separatorBuilder: (context, index) => const SizedBox(width: 8),
           itemBuilder: (context, index) {
              final dept = sortedDepts[index];
              final isSelected = _selectedDepartmentFilter == dept;
              return ChoiceChip(
                 label: Text(dept),
                 selected: isSelected,
                 onSelected: (selected) {
                    if (selected) {
                       setState(() {
                          _selectedDepartmentFilter = dept;
                          _selectedCategoryFilter = 'ALL'; // Reset category on department change
                          _processStockOrders();
                       });
                    }
                 },
                 selectedColor: Colors.white,
                 labelStyle: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold
                 ),
                 backgroundColor: Colors.grey.shade900,
                 shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Colors.transparent),
                 ),
              );
           },
        ),
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

  Widget _buildReportView() {
     return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _consolidatedItemsReport.length,
        separatorBuilder: (context, index) {
            final type = _consolidatedItemsReport[index]['type'];
            if (type == 'header_dept' || type == 'header_cat') return const SizedBox.shrink();
            return const Divider(height: 1);
        },
        itemBuilder: (context, index) {
           final item = _consolidatedItemsReport[index]; // Map<String, dynamic>
           final type = item['type'];
           
           if (type == 'header_dept') {
              return Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          (item['title'] ?? '').toString().toUpperCase(),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                        ),
                        _buildTotalsText(item['totals']),
                      ],
                    ),
                    const Divider(color: Colors.blueGrey, thickness: 2),
                  ],
                ),
              );
           } else if (type == 'header_cat') {
              return Container(
                 margin: const EdgeInsets.only(top: 12, bottom: 4),
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                 child: Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     Text(
                        (item['title'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                     ),
                     _buildTotalsText(item['totals']),
                   ],
                 ),
              );
           }
           
           return _buildReportItem(item);
        },
     );
  }

  Widget _buildTotalsText(dynamic totalsRaw) {
      if (totalsRaw == null) return const SizedBox.shrink();
      final totals = totalsRaw as Map<String, dynamic>;
      
      String p1Label = '', p1Val = '';
      String p2Label = '', p2Val = '';
      String diffVal = '';
      
      if (isChef) {
         final req = (totals['req'] ?? 0) as double;
         final sent = (totals['sent'] ?? 0) as double;
         p1Label = 'Ord:'; p1Val = _formatQty(req);
         p2Label = 'Snt:'; p2Val = _formatQty(sent);
         diffVal = _formatQty(req - sent);
         
      } else if (isSupervisor) {
         final sent = (totals['sent'] ?? 0) as double;
         final conf = (totals['conf'] ?? 0) as double;
         p1Label = 'Snt:'; p1Val = _formatQty(sent);
         p2Label = 'Con:'; p2Val = _formatQty(conf);
         diffVal = _formatQty(sent - conf);
         
      } else if (isDriver) {
         final conf = (totals['conf'] ?? 0) as double;
         final pick = (totals['pick'] ?? 0) as double;
         p1Label = 'Con:'; p1Val = _formatQty(conf);
         p2Label = 'Pic:'; p2Val = _formatQty(pick);
         diffVal = _formatQty(conf - pick);
      }
      
      return RichText(
         text: TextSpan(
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
            children: [
               TextSpan(text: '$p1Label $p1Val   '),
               TextSpan(text: '$p2Label $p2Val   '),
               TextSpan(
                  text: 'Dif: $diffVal',
                  style: const TextStyle(color: Colors.red), // Red Color for Dif
               ),
            ],
         ),
      );
  }

  Widget _buildReportItem(Map<String, dynamic> item) {
      if (item['type'] != 'item') return const SizedBox.shrink();
      
      final pName = item['productName'] ?? 'Unknown';
      final price = item['price'];
      final unit = item['unit'];
      String priceStr = '';
      if (price != null) {
         priceStr = '${_formatQty(price)} $unit';
      }

    // Determine Status
    final statuses = (item['statuses'] as Set?) ?? {};
    String statusStr = '';
    if (statuses.contains('picked')) {
        statusStr = ' - picked';
    } else if (statuses.contains('received')) { 
        statusStr = ' - received';
    } else if (statuses.contains('confirmed')) {
        statusStr = ' - confirmed';
    } else if (statuses.contains('sending')) {
        statusStr = ' - sending';
    } else {
        statusStr = ' - ordered';
    }

      // Columns based on Role
      Widget col1 = const SizedBox.shrink();
      Widget col2 = const SizedBox.shrink();
      
      if (isChef) {
         // Ordered | Sending
         final ord = ((item['requiredQty'] as num?) ?? 0).toDouble();
         final sent = ((item['sendingQty'] as num?) ?? 0).toDouble();
         
         col1 = _buildReportCol('Ordered', ord, Colors.red);
         col2 = _buildReportCol('Sending', sent, Colors.green);
      } else if (isSupervisor) {
         // Sent | Confirmed
         final sent = ((item['sendingQty'] as num?) ?? 0).toDouble();
         final conf = ((item['confirmedQty'] as num?) ?? 0).toDouble();
         
         col1 = _buildReportCol('Sent', sent, Colors.red);
         col2 = _buildReportCol('Confirmed', conf, Colors.green);
      } else if (isDriver) {
         // Confirmed | Picked
         final conf = ((item['confirmedQty'] as num?) ?? 0).toDouble();
         final pick = ((item['pickedQty'] as num?) ?? 0).toDouble();
         
         col1 = _buildReportCol('Confirmed', conf, Colors.red);
         col2 = _buildReportCol('Picked', pick, Colors.green);
      }

      // Determine Approval Status for Background Color
    final sentRaw = ((item['sendingQty'] as num?) ?? 0).toDouble();
    final confRaw = ((item['confirmedQty'] as num?) ?? 0).toDouble();
    final pickRaw = ((item['pickedQty'] as num?) ?? 0).toDouble();
    final isAnyUpdate = sentRaw > 0 || confRaw > 0 || pickRaw > 0;

    final bgColor = isAnyUpdate ? Colors.green.shade50 : Colors.red.shade50;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
      margin: const EdgeInsets.only(bottom: 1), // Separation
      child: Row(
         children: [
            Expanded(
               flex: 4,
               child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Text(pName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                     if (priceStr.isNotEmpty)
                       Text(
                           '$priceStr $statusStr'.trim(), 
                           style: TextStyle(color: Colors.grey[600], fontSize: 12)
                       ),
                  ],
               ),
            ),
            Expanded(
               flex: 2,
               child: col1,
            ),
            Expanded(
               flex: 2,
               child: col2,
            ),
         ],
      ),
    );
  }

  Widget _buildReportCol(String label, double val, Color color) {
     return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
           Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
           const SizedBox(height: 2),
           Text(
              _formatQty(val), 
              style: TextStyle(
                 fontWeight: FontWeight.bold, 
                 fontSize: 16, 
                 color: val > 0 ? color : Colors.grey.shade400
              ),
            ),
        ],
     );
  }
}
