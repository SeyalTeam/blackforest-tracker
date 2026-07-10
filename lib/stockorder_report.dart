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
import 'api_service.dart';

class StockOrderReportPage extends StatefulWidget {
  final String? initialBranchId;
  final DateTime? initialFromDate;
  final DateTime? initialToDate;
  final String? categoryId;
  final String? categoryName;
  final String? departmentId;
  final String? departmentName;
  final bool onlyTodayOrdered;

  final String? initialOrderId;
  final bool? initialIsReportView;

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
    this.initialOrderId,
    this.initialIsReportView,
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
  String _filterBy = 'deliveryDate'; // Default filter type

  bool get isChef => _userRole == 'chef';
  bool get isSupervisor => _userRole == 'supervisor';
  bool get isDriver => _userRole == 'driver';
  bool get isFactory => _userRole == 'factory';
  // Consolidated View Cache
  List<Map<String, dynamic>> _consolidatedItems =
      []; // Deprecated - replaced by specific lists
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
  String? _selectedOrderId;
  Map<String, String> _orderShortForms = {};
  Map<String, bool> _billOpenedStatus = {};
  Map<String, int> _billPendingItemCounts = {};
  Map<String, bool> _orderIsLive = {};

  // Category Filter State
  List<String> _availableCategories = ['ALL'];
  String _selectedCategoryFilter = 'ALL';

  // Map to track local edits: OrderID_ItemID -> Controller
  final Map<String, TextEditingController> _controllers = {};

  // Track recently updated items to delay sorting move
  final Set<String> _recentlyUpdatedIds = {};
  String? _cachedToken;
  String? _cachedUserId;

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

    if (widget.initialOrderId != null) {
      _selectedOrderId = widget.initialOrderId;
    }

    if (widget.initialIsReportView != null) {
      _isReportView = widget.initialIsReportView!;
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
    _cachedToken = await storage.read(key: 'token');
    _cachedUserId = await storage.read(key: 'userId');
    String? role = await storage.read(key: 'userRole');
    if (!mounted) return;
    setState(() {
      _userRole = role?.toLowerCase() ?? '';
    });
  }

  // Removed _getToken() as it is handled by ApiService

  double _getFixedChefQty(String? branchName, String? categoryName) {
    return 0;
  }

  Future<void> _fetchBranches({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _loadingBranches = true);
    try {
      final docs = await ApiService.instance.fetchBranches(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      final list = <Map<String, String>>[];
      for (var b in docs) {
        final id = (b['id'] ?? b['_id'])?.toString();
        final name = (b['name'] ?? 'Unnamed Branch').toString();
        // Keep branch metadata (like type) if needed, but here we just need id/name for the list
        // However, we filter by type later, so let's keep it.
        final type = b['type']?.toString() ?? 'branch';
        if (id != null) list.add({'id': id, 'name': name, 'type': type});
      }
      setState(() => branches = list);
    } catch (e) {
      debugPrint('fetchBranches error: $e');
      if (!mounted) return;
      setState(
        () => branches = [
          {'id': '1', 'name': 'Factory', 'type': 'branch'},
        ],
      );
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  Future<void> _fetchDepartments({bool forceRefresh = false}) async {
    try {
      final docs = await ApiService.instance.fetchDepartments(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        departments = docs.cast<Map<String, dynamic>>();
      });
    } catch (e) {
      debugPrint('Error fetching departments: $e');
    }
  }

  // Helper
  String _formatQty(num val) {
    if (val % 1 == 0) return val.toInt().toString();
    return val.toStringAsFixed(2);
  }

  Future<void> _fetchCategories({bool forceRefresh = false}) async {
    try {
      final docs = await ApiService.instance.fetchCategories(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        categories = docs.cast<Map<String, dynamic>>();
      });
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
    // Force refresh all data
    await _fetchBranches(forceRefresh: true);
    await _fetchDepartments(forceRefresh: true);
    await _fetchCategories(forceRefresh: true);
    await _fetchStockOrders(forceRefresh: true);
  }

  Future<void> _fetchStockOrders({bool forceRefresh = false}) async {
    if (fromDate == null) return;

    if (!mounted) return;
    // Only show loader if we don't have data or we are forcing a refresh
    if (forceRefresh || stockOrders.isEmpty) {
      setState(() {
        _loading = true;
        if (forceRefresh) stockOrders = [];
      });
      _controllers.clear();
    }

    try {
      final docs = await ApiService.instance.fetchStockOrders(
        fromDate: fromDate!,
        toDate: toDate,
        filterBy: _filterBy,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
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
    } catch (e) {
      debugPrint('fetchStockOrders error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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

    // PHASE 1: Generate Short Codes & Pre-Calculations (Using ALL Orders for Branch)
    // This ensures indices (ETT-01, ETT-02) match the Home Screen regardless of Live/Stock visibility.

    final Map<String, List<Map<String, dynamic>>> ordersByBranch = {};

    // Filter by Branch selection only for short code generation context
    final allBranchOrders = stockOrders.where((o) {
      final b = o['branch'];
      final bid = b is Map ? (b['id'] ?? b['_id'])?.toString() : null;
      return selectedBranchId == 'ALL' || bid == selectedBranchId.toString();
    }).toList();

    for (var o in allBranchOrders) {
      final b = o['branch'];
      final bName = b is Map ? (b['name'] ?? 'UNK').toString() : 'UNK';
      ordersByBranch.putIfAbsent(bName, () => []).add(o);
    }

    _orderShortForms.clear();
    _billOpenedStatus.clear();
    _billPendingItemCounts.clear();
    _orderIsLive.clear();

    for (var entry in ordersByBranch.entries) {
      final bName = entry.key;
      final branchOrders = entry.value;
      branchOrders.sort((a, b) {
        final dateA = DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime(0);
        final dateB = DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime(0);
        return dateA.compareTo(dateB);
      });

      final code = bName.length > 3
          ? bName.substring(0, 3).toUpperCase()
          : bName.toUpperCase();

      // Track used codes for uniqueness within this branch group
      final Set<String> usedCodes = {};

      for (int i = 0; i < branchOrders.length; i++) {
        final order = branchOrders[i];
        final id = (order['id'] ?? order['_id']).toString();

        // Generate Short Code
        String suffix = (i + 1).toString().padLeft(2, '0');
        final invoice = (order['invoiceNumber'] ?? '').toString();
        if (invoice.isNotEmpty && invoice.contains('-')) {
          final internalParts = invoice.split('-');
          final lastPart = internalParts.last;
          if (int.tryParse(lastPart) != null) {
            suffix = lastPart.padLeft(2, '0');
          }
        }

        String finalCode = '$code-$suffix';

        // Ensure Uniqueness
        if (usedCodes.contains(finalCode)) {
          int counter = 2;
          while (usedCodes.contains('${finalCode}_$counter')) {
            counter++;
          }
          finalCode = '${finalCode}_$counter';
        }
        usedCodes.add(finalCode);

        _orderShortForms[id] = finalCode;

        // Determine if "Opened"
        final items = (order['items'] as List?) ?? [];
        bool isOpened = items.any((item) {
          final s = (item['status'] as String?)?.toLowerCase() ?? 'pending';
          return s != 'ordered' && s != 'pending';
        });
        _billOpenedStatus[id] = isOpened;

        // Calculate Pending Items
        int pendingItems = 0;
        for (var item in items) {
          bool isDone = false;
          if (isChef) {
            isDone = ((item['sendingQty'] as num?) ?? 0) > 0;
          } else if (isSupervisor) {
            isDone = ((item['confirmedQty'] as num?) ?? 0) > 0;
          } else if (isDriver) {
            isDone = ((item['pickedQty'] as num?) ?? 0) > 0;
          } else {
            isDone = ((item['sendingQty'] as num?) ?? 0) > 0;
          }
          if (!isDone) pendingItems++;
        }
        _billPendingItemCounts[id] = pendingItems;

        // Determine if Live
        final now = DateTime.now();
        final cDate = DateTime.tryParse(order['createdAt'] ?? '')?.toLocal();
        final dDate = DateTime.tryParse(order['deliveryDate'] ?? '')?.toLocal();
        bool isSameDay = false;
        if (cDate != null && dDate != null) {
          bool isOrderedToday =
              cDate.year == now.year &&
              cDate.month == now.month &&
              cDate.day == now.day;
          bool isDeliveryToday =
              dDate.year == now.year &&
              dDate.month == now.month &&
              dDate.day == now.day;
          isSameDay = isOrderedToday && isDeliveryToday;
        }
        _orderIsLive[id] = isSameDay;
      }
    }

    // PHASE 2: Apply Live/Stock Filters & Order Selection
    final filteredOrders = allBranchOrders
        .where((o) {
          // Live vs Stock Filter
          final id = (o['id'] ?? o['_id']).toString();
          bool isSameDayOrder = _orderIsLive[id] ?? false;

          if (widget.onlyTodayOrdered) {
            return isSameDayOrder;
          } else {
            return !isSameDayOrder;
          }
        })
        .where((o) {
          // Selected Order Filter
          if (_selectedOrderId == null || _selectedOrderId == 'ALL')
            return true;
          final id = (o['id'] ?? o['_id']).toString();
          return id == _selectedOrderId;
        })
        .toList();

    final finalFilteredOrders =
        filteredOrders; // For compatibility with lower code

    _visibleStockOrders = finalFilteredOrders;
    Set<String> uniqueCategories = {}; // Init Set
    Set<String> uniqueDepartments = {'ALL'}; // Init Set for Footer

    for (var order in finalFilteredOrders) {
      final orderId = (order['id'] ?? order['_id'])?.toString() ?? '';
      if (orderId.isEmpty) continue;

      final branch = order['branch'];
      String code = 'UNK';
      if (branch is Map && branch['name'] != null) {
        String name = branch['name'];
        code = name.length > 3
            ? name.substring(0, 3).toUpperCase()
            : name.toUpperCase();
      }

      final dDate = DateTime.tryParse(order['deliveryDate'] ?? '');
      if (dDate != null) {
        if (maxDeliveryDate == null || dDate.isAfter(maxDeliveryDate))
          maxDeliveryDate = dDate;
      }

      final cDate = DateTime.tryParse(order['createdAt'] ?? '');
      if (cDate != null) {
        if (maxCreatedDate == null || cDate.isAfter(maxCreatedDate))
          maxCreatedDate = cDate;
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
          final found = categories.firstWhere(
            (c) => c['id'] == cId,
            orElse: () => {},
          );
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
            if (d is Map)
              dId = d['id'] ?? d['_id'] ?? '';
            else if (d is String)
              dId = d;
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
        if (_selectedDepartmentFilter != 'ALL' &&
            dept != _selectedDepartmentFilter) {
          continue;
        }

        // 3. Collect Categories (only from items in selected department)
        uniqueCategories.add(cat);

        // 4. Filter by Selected Category
        if (_selectedCategoryFilter != 'ALL' &&
            cat != _selectedCategoryFilter) {
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
        grp['confirmedQty'] =
            (grp['confirmedQty'] as double) +
            ((item['confirmedQty'] as num?) ?? 0).toDouble();
        grp['pickedQty'] =
            (grp['pickedQty'] as double) +
            ((item['pickedQty'] as num?) ?? 0).toDouble();

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
          if (product['defaultPriceDetails'] != null &&
              product['defaultPriceDetails'] is Map) {
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
    _headerDeliveryStr = maxDeliveryDate != null
        ? dateFmt.format(
            maxDeliveryDate.add(const Duration(hours: 5, minutes: 30)),
          )
        : '';
    _headerCreatedStr = maxCreatedDate != null
        ? dateFmt.format(
            maxCreatedDate.add(const Duration(hours: 5, minutes: 30)),
          )
        : '';
    _headerBranchCodes = branchCodes.join(', ');

    // Flatten groups to list and Sort
    List<Map<String, dynamic>> rawList = productGroups.values
        .toList()
        .cast<Map<String, dynamic>>();

    // Apply Status Filter (APPROVED / NOT APPROVED)
    if (_statusFilter != 'ALL') {
      rawList = rawList.where((item) {
        final sent = ((item['sendingQty'] as num?) ?? 0) > 0;
        final conf = ((item['confirmedQty'] as num?) ?? 0) > 0;
        final pick = ((item['pickedQty'] as num?) ?? 0) > 0;
        final recv = (item['statuses'] as Set).contains('received');

        switch (_statusFilter) {
          case 'PENDING':
            return !sent && !conf && !pick && !recv;
          case 'SENDING':
            return sent && !conf && !pick && !recv;
          case 'CONFIRMED':
            return conf && !pick && !recv;
          case 'PICKED':
            return pick && !recv;
          case 'RECEIVED':
            return recv;
          case 'APPROVED':
            if (isChef) return sent;
            if (isSupervisor) return conf;
            if (isDriver) return pick;
            return sent;
          case 'NOT_APPROVED':
            if (isChef) return !sent;
            if (isSupervisor) return !conf;
            if (isDriver) return !pick;
            return !sent;
          default:
            return true;
        }
      }).toList();
    }

    // 1. Grid List (Alphabetical Only - removes updated/done products for instant KOT-like speed)
    List<Map<String, dynamic>> gridList = rawList.where((item) {
      if (['APPROVED', 'SENDING', 'CONFIRMED', 'PICKED', 'RECEIVED'].contains(_statusFilter)) {
        return true;
      }
      if (_recentlyUpdatedIds.contains(item['productId'])) {
        return true; // Keep in list temporarily (delay hiding for 5s)
      }
      bool isDone = false;
      if (isChef) {
        isDone = ((item['sendingQty'] as num?) ?? 0) > 0;
      } else if (isSupervisor) {
        isDone = ((item['confirmedQty'] as num?) ?? 0) > 0;
      } else if (isDriver) {
        isDone = ((item['pickedQty'] as num?) ?? 0) > 0;
      } else {
        isDone = ((item['sendingQty'] as num?) ?? 0) > 0;
      }
      return !isDone;
    }).toList();
    gridList.sort((a, b) {
      int cmp = (a['departmentName'] ?? '').compareTo(
        b['departmentName'] ?? '',
      );
      if (cmp != 0) return cmp;

      cmp = (a['categoryName'] ?? '').compareTo(b['categoryName'] ?? '');
      if (cmp != 0) return cmp;

      return (a['productName'] ?? '').compareTo(b['productName'] ?? '');
    });

    // 2. Report List (keeps all products, including updated/done ones, and sorts them)
    List<Map<String, dynamic>> reportList = List<Map<String, dynamic>>.from(rawList);

    reportList.sort((a, b) {
      int cmp = (a['departmentName'] ?? '').compareTo(
        b['departmentName'] ?? '',
      );
      if (cmp != 0) return cmp;

      cmp = (a['categoryName'] ?? '').compareTo(b['categoryName'] ?? '');
      if (cmp != 0) return cmp;

      // Sort Approved/Done items to bottom of category (in case they are not hidden, e.g. when APPROVED filter is active)
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
        categoryTotals[cat] = {
          'req': 0.0,
          'sent': 0.0,
          'conf': 0.0,
          'pick': 0.0,
        };
      }
      final cTotals = categoryTotals[cat]!;
      cTotals['req'] = (cTotals['req']!) + req;
      cTotals['sent'] = (cTotals['sent']!) + sent;
      cTotals['conf'] =
          (cTotals['conf']!) + ((item['confirmedQty'] as num).toDouble());
      cTotals['pick'] =
          (cTotals['pick']!) + ((item['pickedQty'] as num).toDouble());

      // Department Totals
      if (!departmentTotals.containsKey(dept)) {
        departmentTotals[dept] = {
          'req': 0.0,
          'sent': 0.0,
          'conf': 0.0,
          'pick': 0.0,
        };
      }
      final dTotals = departmentTotals[dept]!;
      dTotals['req'] = (dTotals['req']!) + req;
      dTotals['sent'] = (dTotals['sent']!) + sent;
      dTotals['conf'] =
          (dTotals['conf']!) + ((item['confirmedQty'] as num).toDouble());
      dTotals['pick'] =
          (dTotals['pick']!) + ((item['pickedQty'] as num).toDouble());
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
          final dTotals =
              departmentTotals[dept] ??
              {'req': 0.0, 'sent': 0.0, 'conf': 0.0, 'pick': 0.0};
          res.add({'type': 'header_dept', 'title': dept, 'totals': dTotals});
          lastDept = dept;
          lastCat = null;
        }
        if (cat != lastCat && widget.categoryId == null) {
          final totals = Map<String, dynamic>.from(
            categoryTotals[cat] ??
                {'req': 0.0, 'sent': 0.0, 'conf': 0.0, 'pick': 0.0},
          );
          totals['categoryName'] = cat;
          res.add({'type': 'header_cat', 'title': cat, 'totals': totals});
          lastCat = cat;
        }
        item['stripeIndex'] = sIdx++;
        res.add(item);
      }
      return res;
    }

    _consolidatedItemsReport = generateList(reportList);
    _consolidatedItemsGrid = generateList(gridList);
    _consolidatedItems =
        _consolidatedItemsReport; // Default to report view logic for others

    _headerSubtitle =
        '${_consolidatedItems.where((i) => i['type'] == 'item').length} Products     Req Amt: ${totalReqAmt.toInt()}     Snt Qty: ${_formatQty(totalSent)}';
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
      final foundCat = categories.firstWhere(
        (c) => c['id'] == catObj,
        orElse: () => {},
      );
      if (foundCat.isNotEmpty) {
        catName = foundCat['name'] ?? 'Uncategorized';
        // Check dept in category
        final d = foundCat['department'];
        if (d is Map)
          deptName = d['name'] ?? 'No Department';
        else if (d is String) {
          final foundDept = departments.firstWhere(
            (dp) => dp['id'] == d,
            orElse: () => {},
          );
          if (foundDept.isNotEmpty)
            deptName = foundDept['name'] ?? 'No Department';
        }
      }
    } else if (catObj is Map) {
      catName = catObj['name'] ?? 'Uncategorized';
      final d = catObj['department'];
      if (d is Map)
        deptName = d['name'] ?? 'No Department';
      else if (d is String) {
        final foundDept = departments.firstWhere(
          (dp) => dp['id'] == d,
          orElse: () => {},
        );
        if (foundDept.isNotEmpty)
          deptName = foundDept['name'] ?? 'No Department';
      }
    }

    return {'name': pName, 'category': catName, 'department': deptName};
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

  // --- Sequential Task Queue for Reliability ---
  final List<Future<void> Function()> _taskQueue = [];
  bool _isProcessingQueue = false;

  void _addToQueue(Future<void> Function() task) {
    _taskQueue.add(task);
    if (!_isProcessingQueue) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    while (_taskQueue.isNotEmpty) {
      final task = _taskQueue.removeAt(0);
      try {
        await task();
      } catch (e) {
        debugPrint('Queue Error: $e');
      }
    }
    _isProcessingQueue = false;
  }

  void _showQueuedSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blueGrey,
        duration: const Duration(seconds: 10),
      ),
    );
  }

  String _extractProductId(dynamic product) {
    if (product is Map) {
      return (product['id'] ?? product['_id'] ?? '').toString();
    }
    return (product ?? '').toString();
  }

  Map<String, dynamic> _buildApiStockItem(Map<String, dynamic> item) {
    final apiItem = <String, dynamic>{};

    // Keep only scalar fields from each sub-item; this avoids sending
    // nested populated objects back to Payload for older orders.
    item.forEach((key, value) {
      if (key == 'product') return;
      if (key == 'createdAt' || key == 'updatedAt') return;
      if (value is Map || value is List) return;
      apiItem[key] = value;
    });

    final productId = _extractProductId(item['product']);
    if (productId.isNotEmpty) {
      apiItem['product'] = productId;
    }

    return apiItem;
  }

  // --- Core Batch Update Helper ---
  Future<void> _updateStockOrderBatch({
    required String orderId,
    required List<Map<String, dynamic>> itemsToUpdate,
    String mode = 'sending',
  }) async {
    final token = _cachedToken ?? await ApiService.storage.read(key: 'token');
    final userId = _cachedUserId ?? await ApiService.storage.read(key: 'userId');
    final nowStr = DateTime.now().toUtc().toIso8601String();

    final orderIndex = stockOrders.indexWhere(
      (o) => (o['id'] ?? o['_id']) == orderId,
    );
    if (orderIndex == -1) return;

    final order = stockOrders[orderIndex];
    final currentItems = (order['items'] as List?) ?? [];
    List<Map<String, dynamic>> apiItems = [];

    for (var item in currentItems) {
      Map<String, dynamic> apiItem = _buildApiStockItem(
        Map<String, dynamic>.from(item),
      );
      final pid = _extractProductId(item['product']);

      final updateEntry = itemsToUpdate.firstWhere(
        (u) {
          final upid = _extractProductId(u['product']);
          return pid == upid && pid.isNotEmpty;
        },
        orElse: () => {},
      );

      if (updateEntry.isNotEmpty) {
        apiItem['product'] = pid;
        apiItem['status'] = mode;
        if (mode == 'sending') {
          apiItem['sendingQty'] = updateEntry['sendingQty'];
          apiItem['sendingDate'] = nowStr;
          apiItem['sendingUpdatedBy'] = userId;
        } else if (mode == 'confirmed') {
          apiItem['confirmedQty'] = updateEntry['confirmedQty'];
          apiItem['confirmedDate'] = nowStr;
          apiItem['confirmedUpdatedBy'] = userId;
        } else if (mode == 'picked') {
          apiItem['pickedQty'] = updateEntry['pickedQty'];
          apiItem['pickedDate'] = nowStr;
          apiItem['pickedUpdatedBy'] = userId;
        }
      }
      apiItems.add(apiItem);
    }

    final url = 'https://blackforest4.vseyal.com/api/stock-orders/$orderId';

    int retryCount = 0;
    http.Response? res;
    dynamic lastError;

    while (retryCount < 2) {
      try {
        res = await http
            .patch(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: jsonEncode({'items': apiItems}),
            )
            .timeout(const Duration(seconds: 90));

        if (res.statusCode == 200) return;

        // If not a gateway error, don't retry
        if (res.statusCode != 504 &&
            res.statusCode != 502 &&
            res.statusCode != 503) {
          break;
        }
      } catch (e) {
        lastError = e;
        if (retryCount == 1) break;
      }

      retryCount++;
      await Future.delayed(Duration(seconds: 1 * retryCount));
    }

    if (res != null && res.statusCode != 200) {
      final body = res.body.trim();
      final shortBody =
          body.isEmpty
              ? ''
              : (body.length > 350 ? body.substring(0, 350) : body);
      throw Exception(
        'Failed to update order $orderId: ${res.statusCode}${shortBody.isEmpty ? '' : ' - $shortBody'}',
      );
    } else if (lastError != null) {
      throw lastError;
    }
  }

  // --- Individual Item Update Wrappers ---

  Future<void> _updateItemStatus({
    required String orderId,
    required Map<String, dynamic> itemToUpdate,
    required double newSentQty,
    String? pName,
  }) async {
    _showQueuedSnackBar('Sending update...');
    _addToQueue(() async {
      try {
        await _updateStockOrderBatch(
          orderId: orderId,
          itemsToUpdate: [
            {...itemToUpdate, 'sendingQty': newSentQty, 'status': 'sending'},
          ],
          mode: 'sending',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_formatQty(newSentQty)} ${pName ?? "Item"} Sending',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  Future<void> _showQuantityEditDialog(
    Map<String, dynamic> entry,
    double initialQty,
  ) async {
    final controller = TextEditingController(text: _formatQty(initialQty));
    final double req = ((entry['requiredQty'] as num?) ?? 0).toDouble();

    await showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Edit Quantity'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['productName'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: isChef
                        ? 'Sending Quantity'
                        : (isSupervisor ? 'Confirmed Quantity' : 'Picked Quantity'),
                    hintText: 'Required: ${_formatQty(req)}',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () {
                  final val = double.tryParse(controller.text) ?? 0;
                  setState(() {
                    entry['val_local'] = val;
                  });
                  Navigator.pop(dialogContext);
                },
                child: const Text('SET'),
              ),
            ],
          ),
    );
  }


  Future<void> _updateConfirmQty({
    required String orderId,
    required Map<String, dynamic> itemToUpdate,
    required double qty,
    String? pName,
  }) async {
    _showQueuedSnackBar('Confirming update...');
    _addToQueue(() async {
      try {
        await _updateStockOrderBatch(
          orderId: orderId,
          itemsToUpdate: [
            {...itemToUpdate, 'confirmedQty': qty, 'status': 'confirmed'},
          ],
          mode: 'confirmed',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_formatQty(qty)} ${pName ?? "Item"} Confirmed'),
              backgroundColor: Colors.green,
              duration: const Duration(milliseconds: 800),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  Future<void> _updatePickQty({
    required String orderId,
    required Map<String, dynamic> itemToUpdate,
    required double qty,
    String? pName,
  }) async {
    _showQueuedSnackBar('Picking update...');
    _addToQueue(() async {
      try {
        await _updateStockOrderBatch(
          orderId: orderId,
          itemsToUpdate: [
            {...itemToUpdate, 'pickedQty': qty, 'status': 'picked'},
          ],
          mode: 'picked',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_formatQty(qty)} ${pName ?? "Item"} Picked'),
              backgroundColor: Colors.green,
              duration: const Duration(milliseconds: 800),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDate: fromDate ?? now,
    );
    if (picked != null) {
      final pickedTo = await showDatePicker(
        context: context,
        firstDate: picked,
        lastDate: DateTime(now.year + 1),
        initialDate: toDate ?? picked,
      );
      if (pickedTo != null) {
        if (!mounted) return;
        setState(() {
          fromDate = picked;
          toDate = pickedTo;
          _selectedOrderId = null; // Reset bill filter
          _processStockOrders();
        });
        _bootstrap();
      }
    }
  }

  // --- Supervisor / Chef / Driver Actions ---

  Future<void> _saveStockOrder(
    Map<String, dynamic> entry,
    double totalQty,
  ) async {
    final originalItems = entry['originalItems'] as List;
    final originalSending = entry['sendingQty'];
    final originalStatuses = Set.from(entry['statuses']);
    final originalItemsBackup = originalItems
        .map(
          (o) => {
            'item': o['item'],
            'status': o['item']['status'],
            'sendingQty': o['item']['sendingQty'],
          },
        )
        .toList();

    _markUpdated(entry['productId']);
    double remaining = totalQty;
    Map<String, List<Map<String, dynamic>>> groupedUpdates = {};

    for (int i = 0; i < originalItems.length; i++) {
      final original = originalItems[i];
      final item = original['item'] as Map<String, dynamic>;
      final orderId = (original['orderId'] ?? '').toString();
      if (orderId.isEmpty) continue;
      final req = ((item['requiredQty'] as num?) ?? 0).toDouble();
      double apply = (remaining >= req) ? req : remaining;
      if (i == originalItems.length - 1 && remaining > 0) apply = remaining;
      item['sendingQty'] = apply;
      item['status'] = 'sending';
      remaining -= apply;
      if (!groupedUpdates.containsKey(orderId)) groupedUpdates[orderId] = [];
      groupedUpdates[orderId]!.add(item);
    }

    _showQueuedSnackBar('Sending update...');
    setState(() {
      entry['sendingQty'] = totalQty;
      entry['statuses'] = {'sending'};
      _processStockOrders();
    });

    _addToQueue(() async {
      try {
        for (var orderId in groupedUpdates.keys) {
          await _updateStockOrderBatch(
            orderId: orderId,
            itemsToUpdate: groupedUpdates[orderId]!,
            mode: 'sending',
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_formatQty(totalQty)} ${entry['productName']} Sending',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        for (var b in originalItemsBackup) {
          b['item']['status'] = b['status'];
          b['item']['sendingQty'] = b['sendingQty'];
        }
        if (!mounted) return;
        setState(() {
          entry['sendingQty'] = originalSending;
          entry['statuses'] = originalStatuses;
          _processStockOrders();
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  Future<void> _saveConsolidatedConfirm(Map<String, dynamic> entry) async {
    final originalItems = entry['originalItems'] as List;
    final totalQty = ((entry['sendingQty'] as num?) ?? 0).toDouble();
    final originalConfirmed = entry['confirmedQty'];
    final originalStatuses = Set.from(entry['statuses']);
    final originalItemsBackup = originalItems
        .map(
          (o) => {
            'item': o['item'],
            'status': o['item']['status'],
            'confirmedQty': o['item']['confirmedQty'],
          },
        )
        .toList();

    _markUpdated(entry['productId']);
    Map<String, List<Map<String, dynamic>>> groupedUpdates = {};
    for (var original in originalItems) {
      final item = original['item'] as Map<String, dynamic>;
      final orderId = (original['orderId'] ?? '').toString();
      if (orderId.isEmpty) continue;
      item['confirmedQty'] = ((item['sendingQty'] as num?) ?? 0).toDouble();
      item['status'] = 'confirmed';
      if (!groupedUpdates.containsKey(orderId)) groupedUpdates[orderId] = [];
      groupedUpdates[orderId]!.add(item);
    }

    setState(() {
      entry['confirmedQty'] = totalQty;
      entry['statuses'].add('confirmed');
      _processStockOrders();
    });
    _showQueuedSnackBar('Confirming update...');

    _addToQueue(() async {
      try {
        for (var orderId in groupedUpdates.keys) {
          await _updateStockOrderBatch(
            orderId: orderId,
            itemsToUpdate: groupedUpdates[orderId]!,
            mode: 'confirmed',
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_formatQty(totalQty)} ${entry['productName']} Confirmed',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(milliseconds: 800),
            ),
          );
        }
      } catch (e) {
        for (var b in originalItemsBackup) {
          b['item']['status'] = b['status'];
          b['item']['confirmedQty'] = b['confirmedQty'];
        }
        if (!mounted) return;
        setState(() {
          entry['confirmedQty'] = originalConfirmed;
          entry['statuses'] = originalStatuses;
          _processStockOrders();
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  Future<void> _saveManualConsolidatedConfirm(
    Map<String, dynamic> entry,
    double newVal,
  ) async {
    final originalItems = entry['originalItems'] as List;
    final originalConfirmed = entry['confirmedQty'];
    final originalStatuses = Set.from(entry['statuses']);
    final originalItemsBackup = originalItems
        .map(
          (o) => {
            'item': o['item'],
            'status': o['item']['status'],
            'confirmedQty': o['item']['confirmedQty'],
          },
        )
        .toList();

    _markUpdated(entry['productId']);
    double remaining = newVal;
    Map<String, List<Map<String, dynamic>>> groupedUpdates = {};

    for (var original in originalItems) {
      final item = original['item'] as Map<String, dynamic>;
      final orderId = (original['orderId'] ?? '').toString();
      if (orderId.isEmpty) continue;
      final sent = ((item['sendingQty'] as num?) ?? 0).toDouble();
      double apply = (remaining >= sent) ? sent : remaining;
      if (original == originalItems.last && remaining > 0) apply = remaining;
      item['confirmedQty'] = apply;
      item['status'] = 'confirmed';
      remaining -= apply;
      if (!groupedUpdates.containsKey(orderId)) groupedUpdates[orderId] = [];
      groupedUpdates[orderId]!.add(item);
    }

    setState(() {
      entry['confirmedQty'] = newVal;
      if (newVal > 0) entry['statuses'].add('confirmed');
      _processStockOrders();
    });
    _showQueuedSnackBar('Confirming update...');

    _addToQueue(() async {
      try {
        for (var orderId in groupedUpdates.keys) {
          await _updateStockOrderBatch(
            orderId: orderId,
            itemsToUpdate: groupedUpdates[orderId]!,
            mode: 'confirmed',
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_formatQty(newVal)} ${entry['productName']} Confirmed',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(milliseconds: 800),
            ),
          );
        }
      } catch (e) {
        for (var b in originalItemsBackup) {
          b['item']['status'] = b['status'];
          b['item']['confirmedQty'] = b['confirmedQty'];
        }
        if (!mounted) return;
        setState(() {
          entry['confirmedQty'] = originalConfirmed;
          entry['statuses'] = originalStatuses;
          _processStockOrders();
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  void _handleCategoryDoubleTap(String categoryTitle) {
    final safeCategoryTitle = categoryTitle.trim().isEmpty
        ? 'this category'
        : categoryTitle;

    if (selectedBranchId == 'ALL') {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot update ALL Branches. Please select a specific branch.',
          ),
          duration: Duration(milliseconds: 1500),
        ),
      );
      return;
    }

    final itemsToUpdate = _consolidatedItems.where((i) {
      if (i['type'] != 'item') return false;
      return i['categoryName'] == categoryTitle;
    }).toList();

    if (itemsToUpdate.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No items found in $safeCategoryTitle.'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
      return;
    }

    int updateCount = 0;
    for (var entry in itemsToUpdate) {
      final statuses = entry['statuses'] as Set;

      if (isChef) {
        final confirmedQty = ((entry['confirmedQty'] as num?) ?? 0).toDouble();
        final isLocked =
            statuses.contains('sending') ||
            statuses.contains('confirmed') ||
            statuses.contains('picked') ||
            confirmedQty > 0;

        if (!isLocked) {
          final req = ((entry['requiredQty'] as num?) ?? 0).toDouble();
          String? currentBranchName;
          final found = branches.firstWhere(
            (b) => b['id'] == selectedBranchId,
            orElse: () => {},
          );
          if (found.isNotEmpty) currentBranchName = found['name'];
          final fixedQty = _getFixedChefQty(
            currentBranchName,
            entry['categoryName'],
          );
          final val = fixedQty > 0 ? fixedQty : req;

          _saveStockOrder(entry, val);
          updateCount++;
        }
      } else if (isSupervisor) {
        final isLocked =
            statuses.contains('confirmed') || statuses.contains('picked');
        if (!isLocked) {
          final sent = ((entry['sendingQty'] as num?) ?? 0).toDouble();
          if (sent > 0) {
            _saveConsolidatedConfirm(entry);
            updateCount++;
          }
        }
      } else if (isDriver) {
        final isLocked = statuses.contains('picked');
        if (!isLocked) {
          final conf = ((entry['confirmedQty'] as num?) ?? 0).toDouble();
          if (conf > 0) {
            _saveConsolidatedPick(entry);
            updateCount++;
          }
        }
      }
    }

    if (updateCount > 0) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updating $updateCount items in $safeCategoryTitle...'),
          backgroundColor: Colors.blue,
          duration: const Duration(milliseconds: 1000),
        ),
      );
      return;
    }

    String noActionMessage =
        'No eligible items to update in $safeCategoryTitle.';
    if (isChef) {
      noActionMessage = 'No pending qty to send in $safeCategoryTitle.';
    } else if (isSupervisor) {
      noActionMessage = 'No sent qty to confirm in $safeCategoryTitle.';
    } else if (isDriver) {
      noActionMessage = 'No confirmed qty to pick in $safeCategoryTitle.';
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(noActionMessage),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _saveManualConsolidatedPick(
    Map<String, dynamic> entry,
    double val,
  ) async {
    final originalItems = entry['originalItems'] as List;
    final originalPicked = entry['pickedQty'];
    final originalStatuses = Set.from(entry['statuses']);
    final originalItemsBackup = originalItems
        .map(
          (o) => {
            'item': o['item'],
            'status': o['item']['status'],
            'pickedQty': o['item']['pickedQty'],
          },
        )
        .toList();

    _markUpdated(entry['productId']);
    double remaining = val;
    Map<String, List<Map<String, dynamic>>> groupedUpdates = {};

    for (var original in originalItems) {
      final item = original['item'] as Map<String, dynamic>;
      final orderId = (original['orderId'] ?? '').toString();
      if (orderId.isEmpty) continue;
      final conf = ((item['confirmedQty'] as num?) ?? 0).toDouble();
      double apply = (remaining >= conf) ? conf : remaining;
      if (original == originalItems.last && remaining > 0) apply = remaining;
      item['pickedQty'] = apply;
      item['status'] = 'picked';
      remaining -= apply;
      if (!groupedUpdates.containsKey(orderId)) groupedUpdates[orderId] = [];
      groupedUpdates[orderId]!.add(item);
    }

    setState(() {
      entry['pickedQty'] = val;
      if (val > 0) entry['statuses'] = {'picked'};
      _processStockOrders();
    });
    _showQueuedSnackBar('Picking update...');

    _addToQueue(() async {
      try {
        for (var orderId in groupedUpdates.keys) {
          await _updateStockOrderBatch(
            orderId: orderId,
            itemsToUpdate: groupedUpdates[orderId]!,
            mode: 'picked',
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_formatQty(val)} ${entry['productName']} Picked',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(milliseconds: 800),
            ),
          );
        }
      } catch (e) {
        for (var b in originalItemsBackup) {
          b['item']['status'] = b['status'];
          b['item']['pickedQty'] = b['pickedQty'];
        }
        if (!mounted) return;
        setState(() {
          entry['pickedQty'] = originalPicked;
          entry['statuses'] = originalStatuses;
          _processStockOrders();
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  Future<void> _saveConsolidatedPick(Map<String, dynamic> entry) async {
    final originalItems = entry['originalItems'] as List;
    final originalPicked = entry['pickedQty'];
    final originalStatuses = Set.from(entry['statuses']);
    final originalItemsBackup = originalItems
        .map(
          (o) => {
            'item': o['item'],
            'status': o['item']['status'],
            'pickedQty': o['item']['pickedQty'],
          },
        )
        .toList();

    _markUpdated(entry['productId']);
    Map<String, List<Map<String, dynamic>>> groupedUpdates = {};
    double totalPicked = 0;

    for (var original in originalItems) {
      final item = original['item'] as Map<String, dynamic>;
      final orderId = (original['orderId'] ?? '').toString();
      if (orderId.isEmpty) continue;
      final conf = ((item['confirmedQty'] as num?) ?? 0).toDouble();
      item['pickedQty'] = conf;
      item['status'] = 'picked';
      totalPicked += conf;
      if (!groupedUpdates.containsKey(orderId)) groupedUpdates[orderId] = [];
      groupedUpdates[orderId]!.add(item);
    }

    setState(() {
      entry['pickedQty'] = totalPicked;
      entry['statuses'] = {'picked'};
      _processStockOrders();
    });
    _showQueuedSnackBar('Picking update...');

    _addToQueue(() async {
      try {
        for (var orderId in groupedUpdates.keys) {
          await _updateStockOrderBatch(
            orderId: orderId,
            itemsToUpdate: groupedUpdates[orderId]!,
            mode: 'picked',
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_formatQty(totalPicked)} ${entry['productName']} Picked',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(milliseconds: 800),
            ),
          );
        }
      } catch (e) {
        for (var b in originalItemsBackup) {
          b['item']['status'] = b['status'];
          b['item']['pickedQty'] = b['pickedQty'];
        }
        if (!mounted) return;
        setState(() {
          entry['pickedQty'] = originalPicked;
          entry['statuses'] = originalStatuses;
          _processStockOrders();
        });
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    });
  }

  Widget _buildDateAndBranchFilter() {
    final label = (fromDate != null && toDate != null)
        ? (fromDate == toDate
              ? DateFormat('dd MMM yyyy').format(fromDate!)
              : '${DateFormat('dd MMM').format(fromDate!)} - ${DateFormat('dd MMM yyyy').format(toDate!)}')
        : 'Select Date Range';

    final displayBranches = branches
        .where((b) => b['type'] == 'branch')
        .toList();
    List<DropdownMenuItem<String>> branchItems = [
      const DropdownMenuItem(
        value: 'ALL',
        child: Text(
          'ALL BRANCHES',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      ...displayBranches.map((b) {
        final name = (b['name'] as String? ?? 'UNK').toUpperCase();
        return DropdownMenuItem(
          value: b['id'] as String,
          child: Text(name, overflow: TextOverflow.ellipsis),
        );
      }),
    ];

    final bool valueExists = branchItems.any(
      (item) => item.value == selectedBranchId,
    );

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
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
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
                value: valueExists ? selectedBranchId : 'ALL',
                items: branchItems,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      selectedBranchId = val;
                      _selectedOrderId = null; // NEW: Reset bill filter
                      _processStockOrders();
                    });
                  }
                },
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
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
              backgroundColor: const Color(
                0xFF260206,
              ), // Match branch chip inactive
              selectedColor: Colors.red, // Match active
              labelStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
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

  Widget _buildBillScrollBar() {
    if (_orderShortForms.isEmpty) return const SizedBox.shrink();

    final orderIds = _orderShortForms.keys.toList();
    final liveIds = orderIds.where((id) => _orderIsLive[id] == true).toList();
    final stockIds = orderIds.where((id) => _orderIsLive[id] != true).toList();

    // Sort descending (Latest First)
    liveIds.sort(
      (a, b) => _orderShortForms[b]!.compareTo(_orderShortForms[a]!),
    );
    stockIds.sort(
      (a, b) => _orderShortForms[b]!.compareTo(_orderShortForms[a]!),
    );

    List<Widget> children = [];

    // Determine relevant IDs based on mode
    final relevantIds = widget.onlyTodayOrdered ? liveIds : stockIds;

    // Helper to build chip
    Widget buildChip(String id) {
      final isAll = id == 'ALL';

      String label = '';
      if (isAll) {
        // Count pending items ONLY for relevant orders
        int pendingCount = relevantIds
            .where((oid) => (_billOpenedStatus[oid] ?? false) == false)
            .length;
        String branchCode = 'ALL';
        if (relevantIds.isNotEmpty) {
          final firstShort = _orderShortForms[relevantIds.first] ?? '';
          if (firstShort.contains('-'))
            branchCode = firstShort.split('-').first;
        }
        label = '$branchCode($pendingCount)';
      } else {
        final baseLabel = _orderShortForms[id]!;
        final pendingCnt = _billPendingItemCounts[id] ?? 0;
        label = pendingCnt > 0 ? '$baseLabel ($pendingCnt)' : baseLabel;
      }

      final isSelected =
          (isAll && (_selectedOrderId == null || _selectedOrderId == 'ALL')) ||
          (_selectedOrderId == id);
      final isOpened = !isAll && (_billOpenedStatus[id] ?? false);

      // Fixed Green for ALL, Dynamic for others
      final chipColor = isAll
          ? Colors.green
          : (isOpened ? Colors.green : Colors.red);

      return Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: ChoiceChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              _selectedOrderId = isAll ? null : id;
              _processStockOrders();
            });
          },
          showCheckmark: false,
          backgroundColor: chipColor,
          selectedColor: isSelected ? Colors.blue : chipColor,
          labelStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.transparent),
          ),
        ),
      );
    }

    // ALL Chip Removed as per user request (Show separate bills only)
    // children.add(buildChip('ALL'));

    // Relevant Chips Only
    for (var id in relevantIds) {
      children.add(buildChip(id));
    }

    // Separator and old loop Removed

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: children,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'fulfilled':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      case 'ordered':
        return Colors.orange;
      case 'sending':
        return Colors.blueAccent;
      case 'confirmed':
        return Colors.green;
      case 'picked':
        return Colors.deepPurple;
      case 'received':
        return Colors.teal;
      case 'pending':
      default:
        return Colors.orange;
    }
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Widget> _buildGridSlivers() {
    List<Widget> slivers = [];
    List<Map<String, dynamic>> currentGroup = [];
    bool isUnderCategory = false; // Track if we are inside a category section

    // Check role for builder
    final isChef = _userRole == 'chef' || _userRole == 'kitchen';
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
                crossAxisCount: 2,
                childAspectRatio: 0.85,
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
        slivers.add(
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ); // Gap after section
      } else {
        // Normal SliverGrid (No background)
        Widget grid = SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = items[index];
              if (isChef) return _buildChefGridItem(item);
              if (isSupervisor) return _buildSupervisorGridItem(item);
              return _buildDriverGridItem(item);
            }, childCount: items.length),
          ),
        );
        slivers.add(grid);
      }
    }

    for (var item in _consolidatedItemsGrid) {
      if (item['type'] == 'header_dept') {
        flushGroup();
        isUnderCategory = false; // Reset
        slivers.add(
          SliverToBoxAdapter(
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
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
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
          ),
        );
      } else if (item['type'] == 'header_cat') {
        flushGroup();
        isUnderCategory = true; // Start category section

        slivers.add(
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      (item['title'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildTotalsText(item['totals']),
                ],
              ),
            ),
          ),
        );
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ALL BRANCHES CONSOLIDATED',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Delivery: $_headerDeliveryStr',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Created: $_headerCreatedStr',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Table Header
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      flex: 3,
                      child: Text(
                        'Product Name',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          'Ord',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          'Snt',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          'Con',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          'Pic',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          'Rec',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              ..._consolidatedItemsReport.map((entry) {
                if (entry['type'] == 'header_dept') {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    child: Text(
                      (entry['title'] as String).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                } else if (entry['type'] == 'header_cat') {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 16,
                    ),
                    child: Text(
                      (entry['title'] as String).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                } else if (entry['type'] == 'item') {
                  final req = ((entry['requiredQty'] as num?) ?? 0).toDouble();
                  final sent = ((entry['sendingQty'] as num?) ?? 0).toDouble();
                  final conf = ((entry['confirmedQty'] as num?) ?? 0)
                      .toDouble();
                  final picked = ((entry['pickedQty'] as num?) ?? 0).toDouble();
                  final rec = ((entry['receivedQty'] as num?) ?? 0).toDouble();
                  final price = ((entry['price'] as num?) ?? 0).toDouble();
                  final unit = entry['unit'] ?? '';

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade100),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry['productName'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${_formatQty(price)} $unit',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Text(
                              _formatQty(req),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Text(
                              _formatQty(sent),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Text(
                              _formatQty(conf),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Text(
                              _formatQty(picked),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.purple,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Text(
                              rec > 0 ? _formatQty(rec) : '-',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.teal,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
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

  Widget _buildStockOrderCard(Map<String, dynamic> order) {
    final orderId = (order['id'] ?? order['_id'])?.toString() ?? 'unknown';
    final invoiceNumber = order['invoiceNumber'] ?? 'No Invoice';
    final branchName = order['branch'] is Map
        ? order['branch']['name']
        : 'Unknown Branch';
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
    final createdStr = createdAt != null
        ? dateFmt.format(createdAt.add(const Duration(hours: 5, minutes: 30)))
        : '';
    final deliveryStr = deliveryDate != null
        ? dateFmt.format(
            deliveryDate.add(const Duration(hours: 5, minutes: 30)),
          )
        : '';

    final isFactory =
        _userRole == 'factory' || _userRole == 'chef' || _userRole == 'kitchen';
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
                  Text(
                    invoiceNumber,
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                  _buildStatusChip(status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                branchName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Delivery: $deliveryStr',
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    createdStr,
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),

              const Divider(height: 16),

              // Table Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: const Color(0xFFEFEBE9),
                child: Row(
                  children: [
                    const Expanded(
                      flex: 3,
                      child: Text(
                        'Name',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          'Ord',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          'Snt',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          'Con',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          'Pic',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          'Rec',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Items List
              ...filteredItems.map((item) {
                final product = item['product'];
                final pName =
                    (product is Map ? product['name'] : 'Unknown') ?? 'Unknown';
                final req = ((item['requiredQty'] as num?) ?? 0).toDouble();
                final sent = ((item['sendingQty'] as num?) ?? 0).toDouble();
                final conf = ((item['confirmedQty'] as num?) ?? 0).toDouble();
                final picked = ((item['pickedQty'] as num?) ?? 0).toDouble();
                final itemStatus =
                    (item['status'] as String?)?.toLowerCase() ?? 'pending';

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
                    color: received > 0
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${_formatQty(price)} $unit',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Text(
                            _formatQty(req),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Text(
                            _formatQty(sent),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Text(
                            _formatQty(conf),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Text(
                            _formatQty(picked),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.purple,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Text(
                            received > 0 ? _formatQty(received) : '-',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.teal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
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
                Text(
                  invoiceNumber,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
                _buildStatusChip(status),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              branchName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 3),
            Text(
              'Delivery: $deliveryStr',
              style: TextStyle(
                color: Colors.blue[700],
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'Created: $createdStr',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
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
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Product Name',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Text(
                        'Ord',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Text(
                        'Snt',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            // Original Header for others
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Row(
                children: [
                  const Expanded(
                    flex: 3,
                    child: Text(
                      'Name',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (!isSupervisor) ...[
                    const Expanded(
                      flex: 1,
                      child: Text(
                        'Prc',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Expanded(
                      flex: 1,
                      child: Text(
                        'Req',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const Expanded(
                    flex: 1,
                    child: Text(
                      'Snt',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (isSupervisor)
                    const Expanded(
                      flex: 1,
                      child: Text(
                        'Con',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
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
                  widgets.add(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 16,
                      ),
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: Text(
                        dept.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                  lastDept = dept;
                  lastCat = null;
                }

                if (cat != lastCat) {
                  widgets.add(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 16,
                      ),
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: Text(
                        cat,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                  lastCat = cat;
                }
              }

              // Render Item
              final itemStatus = item['status'] ?? 'ordered';
              final isSending = itemStatus == 'sending';

              final product = item['product'];
              final productName =
                  (product is Map ? product['name'] : 'Unknown Product') ??
                  'Unknown Product';
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
                _controllers[key] = TextEditingController(
                  text: initialVal.toString(),
                );
              }
              final controller = _controllers[key]!;

              Widget row;
              if (isFactory) {
                // Factory Item Row
                row = InkWell(
                  onDoubleTap: () {
                    if (selectedBranchId == 'ALL') {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Cannot update when ALL Branches are selected. Please select a specific branch.',
                          ),
                          duration: Duration(milliseconds: 1500),
                        ),
                      );
                      return;
                    }
                    final currentVal = double.tryParse(controller.text) ?? req;
                    setState(() {
                      item['status'] = 'sending';
                      item['sendingQty'] = currentVal;
                    });
                    _updateItemStatus(
                      orderId: orderId,
                      itemToUpdate: item,
                      newSentQty: currentVal,
                      pName: productName,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: isSending
                          ? Colors.blue.withValues(alpha: 0.1)
                          : Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade100),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                productName,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    'Price: $unitPrice',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'InStock: ${item['inStock'] ?? 0}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (itemStatus != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      itemStatus.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: _getStatusColor(itemStatus),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Text(
                              _formatQty(req),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Container(
                              height: 32,
                              width: 60,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(4),
                                color: Colors.white,
                              ),
                              child: TextField(
                                controller: controller, // Reuse controller
                                keyboardType: TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onSubmitted: (val) {
                                  if (selectedBranchId == 'ALL') {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Cannot update when ALL Branches are selected. Please select a specific branch.',
                                        ),
                                        duration: Duration(milliseconds: 1500),
                                      ),
                                    );
                                    return;
                                  }
                                  final v = double.tryParse(val) ?? req;
                                  setState(() {
                                    item['sendingQty'] = v;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                // Non-Factory Item Row (Original)
                row = Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSending
                        ? Colors.blue.withValues(alpha: 0.1)
                        : Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade100),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          productName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!isSupervisor) ...[
                        Expanded(
                          flex: 1,
                          child: Text(
                            unitPrice.toString(),
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Text(
                              _formatQty(req),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Text(
                            _formatQty(sent),
                            style: TextStyle(
                              color: sent > 0 ? Colors.blueAccent : Colors.grey,
                              fontWeight: sent > 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                      if (isSupervisor) ...[
                        Expanded(
                          flex: 1,
                          child: InkWell(
                            onDoubleTap: () {
                              if (selectedBranchId == 'ALL') {
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Cannot update when ALL Branches are selected. Please select a specific branch.',
                                    ),
                                    duration: Duration(milliseconds: 1500),
                                  ),
                                );
                                return;
                              }
                              // If already confirmed same amount, maybe allow re-confirm or just confirm.
                              // If already confirmed same amount, maybe allow re-confirm or just confirm.
                              // Logic: User wants to confirm "snt qty".
                              // Actually instruction says: "show snt qty number there if we double tap the qty number need to store in Confirmed Qty"
                              final val = sent;
                              _updateConfirmQty(
                                orderId: orderId,
                                itemToUpdate: item,
                                qty: val.toDouble(),
                                pName: productName,
                              );
                              setState(() {
                                item['confirmedQty'] = val;
                              });
                            },
                            child: Center(
                              child: Text(
                                (item['confirmedQty'] != null
                                    ? _formatQty(item['confirmedQty'])
                                    : _formatQty(sent)),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: (item['confirmedQty'] != null)
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
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

  ImageProvider? _getImageProvider(dynamic product) {
    String? imageUrl;
    if (product is Map) {
      if (product['images'] != null &&
          (product['images'] is List) &&
          (product['images'] as List).isNotEmpty) {
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
      imageUrl = 'https://blackforest4.vseyal.com$imageUrl';
    }

    return (imageUrl != null) ? NetworkImage(imageUrl) : null;
  }

  Widget _buildChefGridItem(Map<String, dynamic> entry) {
    if (entry['type'] != 'item') return const SizedBox.shrink();

    final product = entry['product'];
    final productName = entry['productName'] as String;
    final req = ((entry['requiredQty'] as num?) ?? 0).toDouble();
    final sent = ((entry['sendingQty'] as num?) ?? 0).toDouble();

    final imageProvider = _getImageProvider(entry['product']);

    final key = 'consolidated_${entry['productId']}';
    final initialVal = (sent > 0) ? _formatQty(sent) : _formatQty(req);

    if (!_controllers.containsKey(key)) {
      _controllers[key] = TextEditingController(text: initialVal);
    }
    final controller = _controllers[key]!;

    final statuses = entry['statuses'] as Set;

    final confirmedQty = ((entry['confirmedQty'] as num?) ?? 0).toDouble();
    final isLocked =
        statuses.contains('sending') ||
        statuses.contains('confirmed') ||
        statuses.contains('picked') ||
        confirmedQty > 0;

    // Resolve branch name for fixed qty logic
    String? currentBranchName;
    if (selectedBranchId != 'ALL') {
      final found = branches.firstWhere(
        (b) => b['id'] == selectedBranchId,
        orElse: () => {},
      );
      if (found.isNotEmpty) currentBranchName = found['name'];
    }
    final fixedQty = _getFixedChefQty(currentBranchName, entry['categoryName']);
    final suggestedVal = fixedQty > 0 ? fixedQty : req;

    // Determine Status Button Label and Color
    String statusText = 'SENT';
    Color statusColor = Colors.green;
    if (statuses.contains('received')) {
      statusText = 'RECEIVED';
      statusColor = Colors.blue;
    } else if (statuses.contains('picked')) {
      statusText = 'PICKED';
      statusColor = Colors.orange;
    } else if (statuses.contains('confirmed')) {
      statusText = 'CONFIRMED';
      statusColor = Colors.teal;
    } else if (statuses.contains('sending')) {
      statusText = 'SENT';
      statusColor = Colors.green;
    }

    void onAutoAction() {
      try {
        if (selectedBranchId == 'ALL') {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot update when ALL Branches are selected. Please select a specific branch.',
              ),
              duration: Duration(milliseconds: 1500),
            ),
          );
          return;
        }
        if (isLocked) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Item is confirmed/picked. Cannot edit.'),
              duration: Duration(milliseconds: 1000),
            ),
          );
          return;
        }

        final currentSent = ((entry['sendingQty'] as num?) ?? 0).toDouble();
        double valToSave = (currentSent > 0) ? currentSent : suggestedVal;

        if (entry['val_local'] != null) {
          valToSave = entry['val_local'];
        }

        _saveStockOrder(entry, valToSave);
        setState(() {
          entry['val_local'] = null;
          entry['isTyping'] = false;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to update item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
          // Top Section: Image with Overlay (Flex 7)
          Expanded(
            flex: 7,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image Area
                if (imageProvider != null)
                  Image(image: imageProvider, fit: BoxFit.cover)
                else
                  Container(
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.fastfood,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ),

                // Center: Current Qty with Tap-to-Edit
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (isLocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Item is confirmed/picked.'),
                            duration: Duration(milliseconds: 1000),
                          ),
                        );
                        return;
                      }
                      final current =
                          (entry['val_local'] != null)
                              ? entry['val_local']
                              : ((entry['sendingQty'] ?? 0) == 0
                                  ? req
                                  : entry['sendingQty']);
                      _showQuantityEditDialog(entry, current);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (entry['val_local'] != null)
                            ? _formatQty(entry['val_local'])
                            : _formatQty(
                              (entry['sendingQty'] ?? 0) == 0
                                  ? req
                                  : entry['sendingQty'],
                            ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                // Top Left: Required Qty
                Positioned(
                  top: 2,
                  left: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'REQ: ${_formatQty(req)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Text(
                      productName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Section: READY Button (Flex 3)
          if (!isLocked)
            GestureDetector(
              onTap: onAutoAction,
              child: Container(
                width: double.infinity,
                height: 44,
                color: const Color(0xFFC62828), // Kitchen Red
                alignment: Alignment.center,
                child: const Text(
                  'READY',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: 44,
              color: statusColor,
              alignment: Alignment.center,
              child: Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
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

    final imageProvider = _getImageProvider(entry['product']);
    
    final statuses = entry['statuses'] as Set;
    // Lock if Confirmed or Picked
    final isLocked =
        statuses.contains('confirmed') || statuses.contains('picked') || statuses.contains('received');

    // Status Logic for Button
    String statusText = 'CONFIRM';
    Color statusColor = Colors.red;
    if (statuses.contains('picked')) {
      statusText = 'PICKED';
      statusColor = Colors.orange;
    } else if (statuses.contains('confirmed')) {
      statusText = 'CONFIRMED';
      statusColor = Colors.teal;
    } else if (statuses.contains('received')) {
      statusText = 'RECEIVED';
      statusColor = Colors.blue;
    }

    void onAutoAction() {
      final double valToSave = (entry['val_local'] != null)
          ? entry['val_local']
          : (((entry['confirmedQty'] ?? 0) == 0)
              ? sent
              : (entry['confirmedQty'] as num).toDouble());

      _saveManualConsolidatedConfirm(entry, valToSave);
      setState(() {
        entry['val_local'] = null;
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
          // Top Section: Image with Overlay (Flex 7)
          Expanded(
            flex: 7,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image Area
                if (imageProvider != null)
                  Image(image: imageProvider, fit: BoxFit.cover)
                else
                  Container(
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.fastfood,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ),

                // Center: Current Qty with Tap-to-Edit
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (isLocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Item is already confirmed/picked.'),
                            duration: Duration(milliseconds: 1000),
                          ),
                        );
                        return;
                      }
                      if (sent == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Nothing sent by Chef.'),
                            duration: Duration(milliseconds: 1000),
                          ),
                        );
                        return;
                      }
                      final current =
                          (entry['val_local'] != null)
                              ? entry['val_local']
                              : ((entry['confirmedQty'] ?? 0) == 0
                                  ? sent
                                  : entry['confirmedQty']);
                      _showQuantityEditDialog(entry, current);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (entry['val_local'] != null)
                            ? _formatQty(entry['val_local'])
                            : _formatQty(
                              (entry['confirmedQty'] ?? 0) == 0
                                  ? sent
                                  : entry['confirmedQty'],
                            ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                // Top Left: Sent Qty
                Positioned(
                  top: 2,
                  left: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'SENT: ${_formatQty(sent)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                    child: Text(
                      productName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Section: Action Button (Flex 3)
          if (!isLocked)
            GestureDetector(
              onTap: onAutoAction,
              child: Container(
                width: double.infinity,
                height: 44,
                color: Colors.red,
                alignment: Alignment.center,
                child: const Text(
                  'CONFIRM',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: 44,
              color: statusColor,
              alignment: Alignment.center,
              child: Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDriverGridItem(Map<String, dynamic> entry) {
    final imageProvider = _getImageProvider(entry['product']);
    final productName = entry['productName'] ?? 'Unknown';
    final conf = ((entry['confirmedQty'] as num?) ?? 0).toDouble();

    final statuses = entry['statuses'] as Set;
    // Lock if Picked
    final isLocked = statuses.contains('picked') || statuses.contains('received');

    void onAutoAction() {
      final double valToSave = (entry['val_local'] != null)
          ? entry['val_local']
          : (((entry['pickedQty'] ?? 0) == 0)
              ? conf
              : (entry['pickedQty'] as num).toDouble());

      _saveManualConsolidatedPick(entry, valToSave);
      setState(() {
        entry['val_local'] = null;
      });
    }

    // Status Logic for Button
    String statusText = 'PICK';
    Color statusColor = Colors.red;
    if (statuses.contains('received')) {
      statusText = 'RECEIVED';
      statusColor = Colors.blue;
    } else if (statuses.contains('picked')) {
      statusText = 'PICKED';
      statusColor = Colors.orange;
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
          // Top Section: Image with Overlay (Flex 7)
          Expanded(
            flex: 7,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image Area
                if (imageProvider != null)
                  Image(image: imageProvider, fit: BoxFit.cover)
                else
                  Container(
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.fastfood,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ),

                // Center: Current Qty with Tap-to-Edit
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (isLocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Item is already picked/received.'),
                            duration: Duration(milliseconds: 1000),
                          ),
                        );
                        return;
                      }
                      if (conf == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Nothing confirmed by Supervisor.'),
                            duration: Duration(milliseconds: 1000),
                          ),
                        );
                        return;
                      }
                      final current =
                          (entry['val_local'] != null)
                              ? entry['val_local']
                              : ((entry['pickedQty'] ?? 0) == 0
                                  ? conf
                                  : entry['pickedQty']);
                      _showQuantityEditDialog(entry, current);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (entry['val_local'] != null)
                            ? _formatQty(entry['val_local'])
                            : _formatQty(
                              (entry['pickedQty'] ?? 0) == 0
                                  ? conf
                                  : entry['pickedQty'],
                            ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                // Top Left: Confirmed Qty
                Positioned(
                  top: 2,
                  left: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CONF: ${_formatQty(conf)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                    child: Text(
                      productName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Section: Action Button (Flex 3)
          if (!isLocked)
            GestureDetector(
              onTap: onAutoAction,
              child: Container(
                width: double.infinity,
                height: 44,
                color: Colors.red,
                alignment: Alignment.center,
                child: const Text(
                  'PICK',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: 44,
              color: statusColor,
              alignment: Alignment.center,
              child: Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userRole == 'kitchen') {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock Order Report')),
        body: const Center(
          child: Text(
            'No data available',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }
    // Check if user is factory for consolidated view
    // Check if user is factory or supervisor for consolidated view
    final isStrictFactory = _userRole == 'factory';
    final isSupervisor = _userRole == 'supervisor';
    // Chef View
    final isChef = _userRole == 'chef' || _userRole == 'kitchen';

    Widget mainContent = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDateAndBranchFilter(),
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
              : (isChef ||
                    isSupervisor ||
                    _userRole == 'driver' ||
                    isStrictFactory)
              ? _isReportView
                    ? _buildReportView()
                    : CustomScrollView(
                        slivers: [
                          ..._buildGridSlivers(),
                          // Removed Consolidated Header from bottom as requested
                        ],
                      )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
          Center(
            child: Text(
              _userRole.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
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
          _buildBillScrollBar(),
          _buildFilterToggle(),
          _buildUnifiedFilterFooter(), // Single footer for both Dept and Status
        ],
      ),
    );
  }

  Widget _buildFilterToggle() {
    return Container(
      height: 35,
      color: Colors.grey[850],
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text(
            'FILTER BY:',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                _buildFilterChip('DELIVERY', 'deliveryDate'),
                const SizedBox(width: 8),
                _buildFilterChip('ORDERED', 'createdAt'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterBy == value;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() {
            _filterBy = value;
            _loading = true;
          });
          _fetchStockOrders();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade700,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedFilterFooter() {
    // 1. Prepare Departments
    final List<String> sortedDepts = _availableDepartments.toList()..sort();
    if (!sortedDepts.contains('ALL')) {
      sortedDepts.insert(0, 'ALL');
    }

    // 2. Prepare Statuses
    final statuses = [
      'ALL',
      'PENDING',
      'SENDING',
      'CONFIRMED',
      'PICKED',
      'RECEIVED',
    ];

    return Container(
      height: 50,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Department Chips
          ...sortedDepts.map((dept) {
            final isSelected = _selectedDepartmentFilter == dept;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(dept),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedDepartmentFilter = dept;
                      _selectedCategoryFilter = 'ALL';
                      _processStockOrders();
                    });
                  }
                },
                selectedColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                backgroundColor: Colors.grey.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }),

          // Visual Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: VerticalDivider(color: Colors.grey[800], width: 1, thickness: 1),
          ),
          const SizedBox(width: 8),

          // Status Chips
          ...statuses.map((s) {
            final isSelected = _statusFilter == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(s),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _statusFilter = s;
                      _processStockOrders();
                    });
                  }
                },
                selectedColor: Colors.blue,
                labelStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                backgroundColor: Colors.grey.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  bool _matchesCategory(dynamic item) {
    if (widget.categoryId == null) return true;

    final product = item['product'];
    final pMap = product is Map ? product : {};
    dynamic catObj = pMap['category'];
    String cId = '';
    if (catObj is Map) {
      cId = catObj['id'] ?? catObj['_id'] ?? '';
    } else if (catObj is String) {
      cId = catObj;
    }

    return cId == widget.categoryId;
  }

  Widget _buildReportView() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _consolidatedItemsReport.length,
      separatorBuilder: (context, index) {
        final type = _consolidatedItemsReport[index]['type'];
        if (type == 'header_dept' || type == 'header_cat') {
          return const SizedBox.shrink();
        }
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
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
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
      p1Label = 'Ord:';
      p1Val = _formatQty(req);
      p2Label = 'Snt:';
      p2Val = _formatQty(sent);
      diffVal = _formatQty(req - sent);
    } else if (isSupervisor) {
      final sent = (totals['sent'] ?? 0) as double;
      final conf = (totals['conf'] ?? 0) as double;
      p1Label = 'Snt:';
      p1Val = _formatQty(sent);
      p2Label = 'Con:';
      p2Val = _formatQty(conf);
      diffVal = _formatQty(sent - conf);
    } else if (isDriver) {
      final conf = (totals['conf'] ?? 0) as double;
      final pick = (totals['pick'] ?? 0) as double;
      p1Label = 'Con:';
      p1Val = _formatQty(conf);
      p2Label = 'Pic:';
      p2Val = _formatQty(pick);
      diffVal = _formatQty(conf - pick);
    }

    return GestureDetector(
      onDoubleTap: () => _handleCategoryDoubleTap(
        (totalsRaw['categoryName'] ?? '').toString(),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey[800],
          ),
          children: [
            TextSpan(text: '$p1Label $p1Val   '),
            TextSpan(text: '$p2Label $p2Val   '),
            TextSpan(
              text: 'Dif: $diffVal',
              style: const TextStyle(color: Colors.red), // Red Color for Dif
            ),
          ],
        ),
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

    // Determine Approval Status for Background Color (Role-Specific)
    final sentRaw = ((item['sendingQty'] as num?) ?? 0).toDouble();
    final confRaw = ((item['confirmedQty'] as num?) ?? 0).toDouble();
    final pickRaw = ((item['pickedQty'] as num?) ?? 0).toDouble();
    bool isCurrentRoleUpdated = false;
    if (isChef) {
      isCurrentRoleUpdated = sentRaw > 0;
    } else if (isSupervisor) {
      isCurrentRoleUpdated = confRaw > 0;
    } else if (isDriver) {
      isCurrentRoleUpdated = pickRaw > 0;
    } else {
      isCurrentRoleUpdated = sentRaw > 0 || confRaw > 0 || pickRaw > 0;
    }

    final bgColor = isCurrentRoleUpdated
        ? Colors.green.shade50
        : Colors.red.shade50;

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
                Text(
                  pName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (priceStr.isNotEmpty)
                  Text(
                    '$priceStr $statusStr'.trim(),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
              ],
            ),
          ),
          Expanded(flex: 2, child: col1),
          Expanded(flex: 2, child: col2),
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
            color: val > 0 ? color : Colors.grey.shade400,
          ),
        ),
      ],
    );
  }
}
