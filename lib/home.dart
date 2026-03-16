import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'common_scaffold.dart';
import 'branch_list.dart';
import 'stock_ticket_list.dart';
import 'api_service.dart';
import 'stockorder_report.dart';
import 'review_list.dart';
import 'package:audioplayers/audioplayers.dart';
import 'notification_service.dart';
import 'kitchen_notifications_page.dart';
import 'kitchen_chats_screen.dart';
import 'kitchen_footer.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // final ApiService _api = ApiService(); // Singleton usage
  final _storage = const FlutterSecureStorage();
  int _stockCount = 0;
  int _branchCount = 0;
  int _reviewCount = 0;
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _branches = [];
  String _selectedDepartmentFilter = 'ALL';
  String _selectedBranch = 'ALL';
  List<dynamic> _recentOrders = [];
  bool _isLoading = true;
  String _userRole = '';
  String _userBranchId = '';
  String _userKitchenId = '';
  List<String> _userKitchenCategoryIds = [];
  List<dynamic> _kitchenOrders = [];
  final PageController _kitchenPageController = PageController();
  int _kitchenViewIndex = 0;
  DateTime _selectedDate = DateTime.now();
  Timer? _syncTimer;
  Timer? _kitchenClockTimer;
  bool _isKitchenSyncInProgress = false;
  bool _hasLoadedKitchenOrdersOnce = false;
  List<Map<String, dynamic>> _kitchenNotifications = [];
  final Set<String> _readNotificationIds = {};
  final Set<String> _suppressedNotificationItemKeys = {};
  final Set<String> _selectedKitchenItemKeys = {};
  final Map<String, String> _kitchenItemStartedAtByKey = {};
  final Map<String, int> _suppressedItemCountByBucket = {};
  final _audioPlayer = AudioPlayer();
  String _userId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initData();
    _startSyncTimer();
    _startKitchenClockTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _kitchenClockTimer?.cancel();
    _kitchenPageController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_userRole == 'kitchen') {
        _fetchKitchenOrders(showLoader: false);
        _syncLiveNotifications();
      }
    }
  }

  Future<void> _initData() async {
    await _fetchUserRole();
    await _fetchDepartments();
    if (_userRole == 'kitchen') {
      await _fetchKitchenOrders();
      await _syncLiveNotifications();
    } else {
      await Future.wait([_fetchCounts(), _fetchReviewsCount()]);
    }
    await _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    try {
      final branches = await ApiService.instance.fetchBranches();
      if (mounted) {
        setState(() {
          _branches = branches.cast<Map<String, dynamic>>();
          _branches.sort(
            (a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''),
          );
        });
      }
    } catch (e) {
      debugPrint('Error fetching branches: $e');
    }
  }

  Future<void> _fetchUserRole() async {
    final role = await _storage.read(key: 'userRole');
    final bId = await _storage.read(key: 'userBranchId');
    final kId = await _storage.read(key: 'userKitchenId');
    final catIds = await _storage.read(key: 'userKitchenCategoryIds');
    String uId =
        await _storage.read(key: 'userId') ??
        await _storage.read(key: 'user_id') ??
        '';

    // Fallback: If userId is missing (e.g. session from before update), fetch it
    if (uId.isEmpty) {
      try {
        final profile = await ApiService.instance.fetchUserProfile();
        uId = (profile['id'] ?? profile['_id'])?.toString() ?? '';
        if (uId.isNotEmpty) {
          await _storage.write(key: 'userId', value: uId);
        }
      } catch (e) {
        debugPrint('DEBUG: Fallback userId fetch failed: $e');
      }
    }

    if (mounted) {
      setState(() {
        _userRole = role?.toLowerCase() ?? '';
        _userBranchId = bId ?? '';
        _userKitchenId = kId ?? '';
        _userId = uId;
        _userKitchenCategoryIds =
            catIds?.split(',').where((id) => id.isNotEmpty).toList() ?? [];
      });
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_userRole == 'kitchen') {
        if (_isKitchenSyncInProgress) return;
        _isKitchenSyncInProgress = true;
        Future.wait([
          _fetchKitchenOrders(showLoader: false),
          _syncLiveNotifications(),
        ]).whenComplete(() {
          _isKitchenSyncInProgress = false;
        });
        return;
      }
    });
  }

  void _startKitchenClockTimer() {
    _kitchenClockTimer?.cancel();
    _kitchenClockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _userRole != 'kitchen') return;
      setState(() {});
    });
  }

  Future<void> _syncLiveNotifications() async {
    try {
      if (_userRole != 'kitchen') {
        debugPrint(
          'DEBUG: _syncLiveNotifications skipped - non-kitchen role: $_userRole',
        );
        return;
      }

      debugPrint(
        'DEBUG: _syncLiveNotifications running for role: $_userRole, user: $_userId, branch: $_userBranchId',
      );

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      // Fetch pending/ordered billings
      final billings = await ApiService.instance.fetchBillings(
        status: null, // We'll filter in the backend manually or update service
        fromDate: todayStart,
        createdBy: null,
        branchId: _userBranchId.isNotEmpty ? _userBranchId : null,
        limit: 50,
      );

      // Update: Filter for pending/ordered status if not already done in service
      // But fetchBillings currently doesn't support list of statuses easily.
      // Let's rely on the fromDate and user filters for now.

      debugPrint('DEBUG: Found ${billings.length} billings to check');

      List<Map<String, dynamic>> readyItems = [];
      for (var bill in billings) {
        if (!_isKotTableOrder(bill)) continue;
        if (_isBillClosedForNotification(bill)) continue;
        final billId = (bill['id'] ?? bill['_id'])?.toString() ?? '';
        if (billId.isEmpty) continue;
        final tableObj = bill['table'] ?? bill['tableDetails'];

        final tableName =
            (tableObj is Map
                    ? (tableObj['name'] ?? tableObj['tableNumber'])
                    : tableObj)
                ?.toString() ??
            'N/A';
        final items = bill['items'] as List?;
        if (items == null) continue;
        final Map<String, int> suppressedUsedByBucket = {};

        for (var item in items) {
          final itemKeys = _buildNotificationItemKeys(billId, item);
          if (itemKeys.any(_suppressedNotificationItemKeys.contains)) continue;

          final status = (item['status'] as String?)?.toLowerCase();
          if (_isHiddenKitchenItemStatus(status)) {
            _suppressedNotificationItemKeys.addAll(itemKeys);
            continue;
          }

          if (status == 'ordered' &&
              _shouldSuppressByPreparedCount(
                billId,
                item,
                suppressedUsedByBucket,
              )) {
            continue;
          }

          final productName =
              (item['name'] ??
                      (item['product'] is Map
                          ? item['product']['name']
                          : null) ??
                      'Item')
                  .toString();
          final quantity =
              item['quantity'] ??
              item['requiredQty'] ??
              item['sendingQty'] ??
              0;
          final String itemId = _buildNotificationItemKey(billId, item);

          if (_readNotificationIds.contains(itemId)) continue;

          if (status == 'ordered') {
            readyItems.add({
              'id': itemId,
              'itemKey': itemId,
              'billId': billId,
              'kotNumber': bill['kotNumber']?.toString() ?? 'N/A',
              'tableName': tableName,
              'productName': productName,
              'quantity': quantity,
              'status': status,
              'updatedAt': item['updatedAt'],
            });
          }
        }
      }

      bool hasNew = false;
      final existingIds = _kitchenNotifications
          .map((n) => n['id'] as String)
          .toSet();

      for (var n in readyItems) {
        if (!existingIds.contains(n['id'])) {
          hasNew = true;
          break;
        }
      }

      final newItems = readyItems
          .where((n) => !existingIds.contains(n['id']))
          .toList();
      debugPrint(
        'DEBUG: readyItems=${readyItems.length}, existing=${existingIds.length}, new=${newItems.length}',
      );

      if (hasNew) {
        try {
          await _audioPlayer.play(AssetSource('sounds/alert.wav'));
        } catch (e) {
          debugPrint('DEBUG: Failed to play alert sound: $e');
        }

        if (newItems.isNotEmpty) {
          final item = newItems.first;
          try {
            await NotificationService().showNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: 'New Table Order - ${item['tableName']}',
              body: '${item['productName']} (${item['quantity']})',
            );
          } catch (e) {
            debugPrint('DEBUG: Failed to show local notification: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          _kitchenNotifications = readyItems;
        });
      }
    } catch (e) {
      debugPrint('Error syncing notifications: $e');
    }
  }

  bool _isKotTableOrder(dynamic bill) {
    if (bill is! Map) return false;

    // Must be table-based order
    final tableObj = bill['table'] ?? bill['tableDetails'];
    if (tableObj == null) return false;

    // Must have a valid KOT number
    final kotNumber = (bill['kotNumber'] ?? '').toString().trim();
    if (kotNumber.isEmpty || kotNumber.toLowerCase() == 'null') return false;

    // If type hints exist, block non-table/normal billing types.
    final typeHint = (bill['orderType'] ?? bill['type'] ?? bill['serviceType'])
        ?.toString()
        .toLowerCase();
    if (typeHint != null &&
        (typeHint.contains('normal') ||
            typeHint.contains('parcel') ||
            typeHint.contains('takeaway') ||
            typeHint.contains('delivery'))) {
      return false;
    }

    if (tableObj is Map) {
      final tableName = (tableObj['name'] ?? '').toString().trim();
      final tableNumber = (tableObj['tableNumber'] ?? '').toString().trim();
      if (tableName.isEmpty && tableNumber.isEmpty) return false;
    }

    return true;
  }

  bool _isHiddenKitchenItemStatus(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    if (s.isEmpty) return false;
    // Kitchen screen/notifications should only show active ordered items.
    // Any progressed status must be hidden for all devices.
    return s != 'ordered';
  }

  bool _isBillClosedForNotification(dynamic bill) {
    if (bill is! Map) return false;

    final status =
        (bill['status'] ?? bill['billingStatus'] ?? bill['orderStatus'] ?? '')
            .toString()
            .toLowerCase()
            .trim();

    const closedStatuses = {
      'completed',
      'closed',
      'cancelled',
      'paid',
      'delivered',
      'settled',
      'archived',
      'returned',
    };

    if (closedStatuses.contains(status)) return true;

    bool isTrue(dynamic v) => v == true || v.toString().toLowerCase() == 'true';

    if (isTrue(bill['isClosed']) ||
        isTrue(bill['closed']) ||
        isTrue(bill['isCompleted']) ||
        isTrue(bill['isCancelled']) ||
        isTrue(bill['isPaid'])) {
      return true;
    }

    bool hasValue(dynamic v) => v != null && v.toString().trim().isNotEmpty;

    if (hasValue(bill['closedAt']) ||
        hasValue(bill['completedAt']) ||
        hasValue(bill['cancelledAt']) ||
        hasValue(bill['paidAt'])) {
      return true;
    }

    return false;
  }

  String _buildNotificationItemKey(String billId, dynamic item) {
    return _buildNotificationItemKeys(billId, item).first;
  }

  String _buildKitchenSelectionKey(String billId, dynamic item) {
    if (item is! Map) return '${billId}_${item.hashCode}';

    final itemId = (item['id'] ?? item['_id'])?.toString().trim() ?? '';
    if (itemId.isNotEmpty) {
      return '${billId}_$itemId';
    }

    final product = item['product'];
    final productId = product is Map
        ? ((product['id'] ?? product['_id'])?.toString().trim() ?? '')
        : '';
    final name = (item['name'] ?? '').toString().trim().toLowerCase();
    final createdAt =
        (item['createdAt'] ??
                item['addedAt'] ??
                item['orderedAt'] ??
                item['updatedAt'] ??
                item['timestamp'] ??
                item['billingCreatedAt'] ??
                item['orderCreatedAt'])
            ?.toString()
            .trim() ??
        '';
    final qty =
        (item['quantity'] ?? item['requiredQty'] ?? item['sendingQty'] ?? '')
            .toString()
            .trim();

    return '${billId}_${productId}_${name}_${createdAt}_$qty';
  }

  Set<String> _buildNotificationItemKeys(String billId, dynamic item) {
    if (item is! Map) return {'${billId}_${item.hashCode}'};

    final keys = <String>{};

    final itemId = (item['id'] ?? item['_id'])?.toString().trim() ?? '';
    if (itemId.isNotEmpty) {
      keys.add('${billId}_$itemId');
    }

    final product = item['product'];
    String productId = '';
    if (product is Map) {
      productId = (product['id'] ?? product['_id'])?.toString().trim() ?? '';
    } else if (product != null) {
      productId = product.toString().trim();
    }

    final name = (item['name'] ?? '').toString().trim().toLowerCase();
    final createdAt =
        (item['createdAt'] ?? item['addedAt'] ?? item['orderedAt'])
            ?.toString()
            .trim();
    final updatedAt = (item['updatedAt'] ?? '').toString().trim();
    final qty =
        (item['quantity'] ?? item['requiredQty'] ?? item['sendingQty'] ?? '')
            .toString()
            .trim();

    keys.add('${billId}_${productId}_${name}_${createdAt ?? ''}_$qty');
    keys.add('${billId}_${productId}_${name}_$updatedAt');

    return keys;
  }

  String _buildSuppressionBucketKey(String billId, dynamic item) {
    if (item is! Map) return '${billId}_${item.hashCode}';

    final product = item['product'];
    String productId = '';
    if (product is Map) {
      productId = (product['id'] ?? product['_id'])?.toString().trim() ?? '';
    } else if (product != null) {
      productId = product.toString().trim();
    }

    final name = (item['name'] ?? '').toString().trim().toLowerCase();
    return '${billId}_${productId}_$name';
  }

  bool _shouldSuppressByPreparedCount(
    String billId,
    dynamic item,
    Map<String, int> usedByBucket,
  ) {
    final bucketKey = _buildSuppressionBucketKey(billId, item);
    final suppressLimit = _suppressedItemCountByBucket[bucketKey] ?? 0;
    if (suppressLimit <= 0) return false;

    final used = usedByBucket[bucketKey] ?? 0;
    if (used < suppressLimit) {
      usedByBucket[bucketKey] = used + 1;
      return true;
    }
    return false;
  }

  void _removeKitchenItemLocally({
    required String billingId,
    required String selectionKey,
    String? itemId,
  }) {
    final updatedOrders = <dynamic>[];

    for (final group in _kitchenOrders) {
      if (group is! Map<String, dynamic>) {
        updatedOrders.add(group);
        continue;
      }

      final groupBillingId = (group['billingId'] ?? group['id'] ?? group['_id'])
          ?.toString()
          .trim();
      final rawItems = (group['items'] as List?) ?? const [];
      final filteredItems = <dynamic>[];

      for (final rawItem in rawItems) {
        if (rawItem is! Map) {
          filteredItems.add(rawItem);
          continue;
        }

        final itemMap = Map<String, dynamic>.from(rawItem);
        final rawItemId =
            (itemMap['id'] ?? itemMap['_id'])?.toString().trim() ?? '';
        final rawSelectionKey =
            itemMap['selectionKey']?.toString() ??
            _buildKitchenSelectionKey(
              (itemMap['billingId'] ?? groupBillingId ?? billingId).toString(),
              itemMap,
            );

        final sameBilling = (groupBillingId ?? billingId) == billingId;
        final sameItemById =
            itemId != null && itemId.isNotEmpty && rawItemId == itemId;
        final sameItemBySelection = rawSelectionKey == selectionKey;

        if (sameBilling && (sameItemById || sameItemBySelection)) {
          continue;
        }

        filteredItems.add(itemMap);
      }

      if (filteredItems.isEmpty) continue;

      final updatedGroup = Map<String, dynamic>.from(group);
      updatedGroup['items'] = filteredItems;
      updatedOrders.add(updatedGroup);
    }

    _kitchenOrders = updatedOrders;
    _selectedKitchenItemKeys.remove(selectionKey);
    _kitchenItemStartedAtByKey.remove(selectionKey);
  }

  void _markNotificationAsRead(String id) {
    setState(() {
      _readNotificationIds.add(id);
      _kitchenNotifications.removeWhere((n) => n['id'] == id);
    });
  }

  Widget _buildNotificationIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => KitchenNotificationsPage(
                  notifications: List.from(_kitchenNotifications),
                  onMarkAsRead: (id) {
                    _markNotificationAsRead(id);
                  },
                  onRefresh: _syncLiveNotifications,
                ),
              ),
            );
          },
        ),
        if (_kitchenNotifications.isNotEmpty)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '${_kitchenNotifications.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _fetchKitchenOrders({bool showLoader = true}) async {
    debugPrint(
      'DEBUG: _fetchKitchenOrders called. Role: $_userRole, Branch: $_userBranchId, Kitchen: $_userKitchenId',
    );
    if (_userBranchId.isEmpty || _userKitchenId.isEmpty) {
      debugPrint('DEBUG: Branch or Kitchen ID is empty. Stopping fetch.');
      if (mounted && showLoader) setState(() => _isLoading = false);
      return;
    }
    try {
      if (mounted && showLoader) setState(() => _isLoading = true);

      // Fetch Kitchen categories if empty or to ensure sync
      if (_userKitchenCategoryIds.isEmpty) {
        debugPrint('DEBUG: Categories empty, fetching kitchen details...');
        final kitchen = await ApiService.instance.fetchKitchenDetails(
          _userKitchenId,
        );
        final cats = (kitchen['categories'] as List?) ?? [];
        final List<String> fetchedCatIds = [];
        for (var c in cats) {
          final id = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
          if (id.isNotEmpty) fetchedCatIds.add(id);
        }
        if (mounted) {
          setState(() {
            _userKitchenCategoryIds = fetchedCatIds;
          });
        }
        debugPrint(
          'DEBUG: Fetched ${fetchedCatIds.length} categories from API',
        );
      }

      final orders = await ApiService.instance.fetchKitchenKOTs(
        branchId: _userBranchId,
        kitchenId: _userKitchenId,
        fromDate: DateTime.now(),
      );
      debugPrint('DEBUG: fetchKitchenKOTs returned ${orders.length} billings');

      // Group and Filter by Kitchen Categories
      final List<Map<String, dynamic>> groupedOrders = [];
      final validKitchenSelectionKeys = <String>{};
      for (var billing in orders) {
        final bId = (billing['id'] ?? billing['_id'])?.toString();
        final isTargetOrder = bId == '6986e2f542fe15984da62652';

        if (isTargetOrder) {
          debugPrint('DEBUG: Found target order $bId. Checking items...');
        }

        final items = (billing['items'] as List?) ?? [];
        final List<dynamic> tableItems = [];
        final Map<String, int> suppressedUsedByBucket = {};

        for (var item in items) {
          final status =
              (item['status'] as String?)?.toLowerCase() ?? 'ordered';
          if (isTargetOrder) {
            debugPrint(
              'DEBUG: Item in target order: ${item['name']}, status: $status',
            );
          }

          if (_isHiddenKitchenItemStatus(status)) {
            final billKey = (bId ?? '').isNotEmpty ? (bId ?? '') : 'unknown';
            _suppressedNotificationItemKeys.addAll(
              _buildNotificationItemKeys(billKey, item),
            );
            continue;
          }

          if (status == 'ordered' &&
              _shouldSuppressByPreparedCount(
                (bId ?? '').isNotEmpty ? (bId ?? '') : 'unknown',
                item,
                suppressedUsedByBucket,
              )) {
            continue;
          }

          final product = item['product'];
          if (product is Map) {
            final category = product['category'];
            String cId = '';
            if (category is Map) {
              cId =
                  category['id']?.toString() ??
                  category['_id']?.toString() ??
                  '';
            } else if (category is String) {
              cId = category;
            }

            if (isTargetOrder) {
              debugPrint(
                'DEBUG: Item ${item['name']} cId: $cId, KitchenCats: $_userKitchenCategoryIds',
              );
            }

            if (cId.isNotEmpty && _userKitchenCategoryIds.contains(cId)) {
              final flatItem = Map<String, dynamic>.from(item as Map);
              flatItem['billingId'] = bId;
              final selectionKey = _buildKitchenSelectionKey(
                (bId ?? '').isNotEmpty ? (bId ?? '') : 'unknown',
                flatItem,
              );
              final initialFallbackStartedAt =
                  billing['createdAt'] ?? billing['updatedAt'];
              final itemStartedAt =
                  _parseKitchenOrderStartedAt(
                    flatItem,
                    allowBillingFallback: false,
                  )?.toIso8601String() ??
                  _kitchenItemStartedAtByKey[selectionKey] ??
                  (_hasLoadedKitchenOrdersOnce
                      ? DateTime.now().toIso8601String()
                      : (initialFallbackStartedAt?.toString().trim().isNotEmpty ??
                              false)
                          ? initialFallbackStartedAt.toString().trim()
                          : DateTime.now().toIso8601String());
              flatItem['selectionKey'] = selectionKey;
              flatItem['itemStartedAt'] = itemStartedAt;
              _kitchenItemStartedAtByKey[selectionKey] = itemStartedAt;
              validKitchenSelectionKeys.add(
                flatItem['selectionKey']?.toString() ?? '',
              );
              tableItems.add(flatItem);
            }
          }
        }

        if (tableItems.isNotEmpty) {
          final tableData = billing['tableDetails'];
          final tableNum =
              (tableData is Map ? tableData['tableNumber'] : tableData)
                  ?.toString() ??
              'N/A';

          final billingId = billing['id'] ?? billing['_id'];

          // Attach tableNum and billingId to each item for interaction
          for (var item in tableItems) {
            item['tableNumber'] = tableNum;
            item['billingId'] = billingId;
            item['billingCreatedAt'] = billing['createdAt'];
            item['orderCreatedAt'] =
                billing['createdAt'] ?? billing['updatedAt'];
          }

          groupedOrders.add({
            'billingId': billingId,
            'invoiceNumber': billing['invoiceNumber'],
            'createdAt': billing['createdAt'],
            'tableDetails': tableData,
            'kotNumber': _resolveKitchenKotLabel(billing),
            'waiterName': _resolveKitchenWaiterName(billing),
            'items': tableItems,
          });
        } else if (isTargetOrder) {
          debugPrint(
            'DEBUG: Target order $bId had no items matching kitchen categories or all were prepared.',
          );
        }
      }

      debugPrint(
        'DEBUG: Grouped into ${groupedOrders.length} tables after filtering',
      );

      if (mounted) {
        setState(() {
          _kitchenOrders = groupedOrders;
          _selectedKitchenItemKeys.retainWhere(validKitchenSelectionKeys.contains);
          _kitchenItemStartedAtByKey.removeWhere(
            (key, value) => !validKitchenSelectionKeys.contains(key),
          );
          _hasLoadedKitchenOrdersOnce = true;
          if (showLoader) _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('DEBUG: Error in _fetchKitchenOrders: $e');
      if (mounted && showLoader) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCounts({bool forceRefresh = false}) async {
    try {
      if (forceRefresh || _recentOrders.isEmpty) {
        if (mounted) setState(() => _isLoading = true);
      }

      // Use _selectedDate for filtering
      final from = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final to = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );

      final orders = await ApiService.instance.fetchStockOrders(
        fromDate: from,
        toDate: to,
        forceRefresh: forceRefresh,
      );

      int stockCount = 0;
      int branchCount = 0;
      List<dynamic> validOrders = [];

      for (var o in orders) {
        final cDate = DateTime.tryParse(o['createdAt'] ?? '')?.toLocal();
        final dDate = DateTime.tryParse(o['deliveryDate'] ?? '')?.toLocal();

        if (cDate != null && dDate != null) {
          bool isOrderedOnFilterDate =
              cDate.year == _selectedDate.year &&
              cDate.month == _selectedDate.month &&
              cDate.day == _selectedDate.day;
          bool isDeliveryOnFilterDate =
              dDate.year == _selectedDate.year &&
              dDate.month == _selectedDate.month &&
              dDate.day == _selectedDate.day;

          final items = (o['items'] as List?) ?? [];

          // Role-Based Visibility Logic
          bool shouldShow = false;

          if (_userRole == 'chef') {
            // Chef sees orders with ANY Pending, Ordered OR Sending items
            shouldShow = items.any((item) {
              final s = (item['status'] as String?)?.toLowerCase() ?? 'pending';
              return s == 'ordered' || s == 'pending' || s == 'sending';
            });
          } else if (_userRole == 'supervisor') {
            // Supervisor sees orders with ANY Sending OR Confirmed items
            shouldShow = items.any((item) {
              final s = (item['status'] as String?)?.toLowerCase() ?? 'sending';
              return s == 'sending' || s == 'confirmed';
            });
          } else if (_userRole == 'driver') {
            // Driver sees orders with ANY Confirmed OR Picked items
            shouldShow = items.any((item) {
              final s =
                  (item['status'] as String?)?.toLowerCase() ?? 'confirmed';
              return s == 'confirmed' || s == 'picked';
            });
          } else {
            // Default/Factory: Show New/Untouched Orders (Old Logic) or All?
            // Using old logic for safety: Show if NOT opened (i.e. all pending/ordered)
            bool isOpened = items.any((item) {
              final s = (item['status'] as String?)?.toLowerCase() ?? 'pending';
              return s != 'ordered' && s != 'pending';
            });
            shouldShow = !isOpened;
          }

          if (shouldShow) {
            validOrders.add(o);

            // Notification Count Logic: Only count NEW orders (Status 0)
            int status = _getOrderStatus(o);
            if (status == 0) {
              // 0 = New
              if (isOrderedOnFilterDate && isDeliveryOnFilterDate) {
                branchCount++;
              } else if (isDeliveryOnFilterDate) {
                stockCount++;
              }
            }
          }
        }
      }

      // Generate Short Codes
      final Map<String, List<Map<String, dynamic>>> ordersByBranch = {};
      for (var o in validOrders) {
        final bName = (o['branch'] is Map ? o['branch']['name'] : 'UNK')
            .toString();
        ordersByBranch.putIfAbsent(bName, () => []).add(o);
      }

      for (var entry in ordersByBranch.entries) {
        final bName = entry.key;
        final branchOrders = entry.value;
        // Sort by creation time to ensure stable ordering
        branchOrders.sort((a, b) {
          final da = DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime(0);
          final db = DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime(0);
          return da.compareTo(db);
        });

        final codePrefix = bName.length > 3
            ? bName.substring(0, 3).toUpperCase()
            : bName.toUpperCase();
        for (int i = 0; i < branchOrders.length; i++) {
          String suffix = (i + 1).toString().padLeft(2, '0');

          final invoice = (branchOrders[i]['invoiceNumber'] ?? '').toString();
          if (invoice.isNotEmpty && invoice.contains('-')) {
            final internalParts = invoice.split('-');
            final lastPart = internalParts.last;
            if (int.tryParse(lastPart) != null) {
              suffix = lastPart.padLeft(2, '0');
            }
          }

          branchOrders[i]['shortCode'] = '$codePrefix-$suffix';
        }
      }

      if (mounted) {
        setState(() {
          _stockCount = stockCount;
          _branchCount = branchCount;
          _recentOrders = validOrders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchReviewsCount() async {
    try {
      final reviews = await ApiService.instance.fetchReviews();
      int count = 0;
      for (var review in reviews) {
        final items = (review['items'] as List?) ?? [];
        for (var item in items) {
          final itemStatus = item['status'] ?? 'waiting';
          final hasReply = (item['chefReply'] as String?)?.isNotEmpty ?? false;
          if (itemStatus == 'waiting' && !hasReply) {
            count++;
          }
        }
      }
      if (mounted) {
        setState(() {
          _reviewCount = count;
        });
      }
    } catch (e) {
      debugPrint('Error fetching reviews count: $e');
    }
  }

  Future<void> _fetchDepartments() async {
    try {
      final docs = await ApiService.instance.fetchDepartments();
      if (mounted) {
        setState(() {
          // Ensure unique departments and sorting if needed
          _departments = docs.cast<Map<String, dynamic>>();
          _departments.sort(
            (a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''),
          );
          // Add ALL if not present (handled in UI usually, but good to have)
        });
      }
    } catch (e) {
      debugPrint('Error fetching departments: $e');
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _isLoading = true;
      });
      _fetchCounts();
    }
  }

  Widget _buildChip(String label, int count, int index) {
    bool isSelected = _selectedTab == index;
    Color badgeColor = Colors.red;
    if (index == 1) {
      badgeColor = Colors.yellow[700]!; // Darker yellow for white text contrast
    } else if (index == 2) {
      badgeColor = Colors.green;
    }

    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase()),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      selected: isSelected,
      onSelected: (bool selected) {
        if (selected) setState(() => _selectedTab = index);
      },
      selectedColor: Colors.black,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
        fontWeight: FontWeight.bold,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
    );
  }

  int _selectedTab = 0; // 0=New, 1=Working, 2=Completed

  int _getOrderStatus(dynamic order) {
    final items = (order['items'] as List?) ?? [];
    if (items.isEmpty) return 0; // New (Safe default)

    int totalItems = items.length;
    int touchedItems = 0;

    for (var item in items) {
      bool isTouched = false;
      if (_userRole == 'chef') {
        isTouched = ((item['sendingQty'] as num?) ?? 0) > 0;
      } else if (_userRole == 'supervisor') {
        isTouched = ((item['confirmedQty'] as num?) ?? 0) > 0;
      } else if (_userRole == 'driver') {
        isTouched = ((item['pickedQty'] as num?) ?? 0) > 0;
      }

      if (isTouched) touchedItems++;
    }

    if (touchedItems == 0) return 0; // New
    if (touchedItems == totalItems) return 2; // Completed
    return 1; // Working
  }

  @override
  Widget build(BuildContext context) {
    if (_userRole == 'kitchen') {
      return _buildKitchenDashboard();
    }
    final dateStr = DateFormat('MMM dd').format(_selectedDate).toUpperCase();

    // Calculate Counts
    int newCount = 0;
    int workingCount = 0;
    int completedCount = 0;

    for (var order in _recentOrders) {
      // Branch Filter Check
      if (_selectedBranch != 'ALL') {
        final bId =
            (order['branch'] is Map
                    ? (order['branch']['id'] ?? order['branch']['_id'])
                    : null)
                ?.toString() ??
            '';
        if (bId != _selectedBranch) continue;
      }

      final status = _getOrderStatus(order);
      if (status == 0) {
        newCount++;
      } else if (status == 1) {
        workingCount++;
      } else if (status == 2) {
        completedCount++;
      }
    }

    // Filter Logic
    final filteredOrders = _recentOrders.where((order) {
      if (_getOrderStatus(order) != _selectedTab) return false;

      if (_selectedBranch != 'ALL') {
        final bId =
            (order['branch'] is Map
                    ? (order['branch']['id'] ?? order['branch']['_id'])
                    : null)
                ?.toString() ??
            '';
        if (bId != _selectedBranch) return false;
      }

      if (_selectedDepartmentFilter != 'ALL') {
        return _doesOrderContainDepartment(order, _selectedDepartmentFilter);
      }
      return true;
    }).toList();

    return CommonScaffold(
      title: 'Home',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            setState(() {
              _isLoading = true;
            });
            _fetchCounts(forceRefresh: true);
            _fetchReviewsCount();
          },
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetchCounts(forceRefresh: true),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Date & Branch Filter Row
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        // Date Picker
                        Expanded(
                          flex: 2,
                          child: InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              height: 48,
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    dateStr,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Branch Dropdown
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            height: 48,
                            alignment: Alignment.centerLeft,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedBranch,
                                dropdownColor: Colors.grey[900],
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.white,
                                ),
                                isExpanded: true,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: 'ALL',
                                    child: Text('All Branches'),
                                  ),
                                  ..._branches.map((b) {
                                    return DropdownMenuItem(
                                      value: b['id'].toString(),
                                      child: Text(
                                        b['name'] ?? 'Unknown',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedBranch = val;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    crossAxisSpacing: 16.0,
                    mainAxisSpacing: 16.0,
                    children: [
                      _buildGridItem(
                        context,
                        'Stock',
                        Icons.inventory,
                        _stockCount,
                      ),
                      _buildGridItem(
                        context,
                        'Live',
                        Icons.store,
                        _branchCount,
                      ),
                      _buildGridItem(
                        context,
                        'Reviews',
                        Icons.reviews,
                        _reviewCount,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      _buildChip('New', newCount, 0),
                      const SizedBox(width: 8),
                      _buildChip('PREPARING', workingCount, 1),
                      const SizedBox(width: 8),
                      _buildChip('Completed', completedCount, 2),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (filteredOrders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32.0),
                      child: Center(
                        child: Text(
                          'No orders found.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ...filteredOrders.map(_buildTicketItem),
                ],
              ),
            ),
      bottomNavigationBar: _buildDepartmentFooter(),
    );
  }

  Widget _buildKitchenDashboard() {
    return CommonScaffold(
      title: 'Kitchen Dashboard',
      actions: [
        _buildNotificationIcon(),
        IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: _showKitchenInfo,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _fetchKitchenOrders,
        ),
      ],
      body: Container(
        color: const Color(0xFFF6F6F1),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _kitchenOrders.isEmpty
            ? RefreshIndicator(
                onRefresh: _fetchKitchenOrders,
                child: _buildKitchenEmptyOrdersView(),
              )
            : PageView(
                controller: _kitchenPageController,
                onPageChanged: (index) {
                  if (!mounted) return;
                  setState(() {
                    _kitchenViewIndex = index;
                  });
                },
                children: [
                  RefreshIndicator(
                    onRefresh: _fetchKitchenOrders,
                    child: _buildKitchenTablesPage(),
                  ),
                  RefreshIndicator(
                    onRefresh: _fetchKitchenOrders,
                    child: _buildKitchenCombinedOrdersPage(),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: KitchenFooter(
        selectedTab: KitchenFooterTab.kot,
        onSelected: _handleKitchenFooterSelection,
      ),
    );
  }

  Widget _buildKitchenEmptyOrdersView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
      children: const [
        Center(
          child: Text(
            'No kitchen orders found.',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildKitchenTablesPage() {
    return ListView.builder(
      key: const PageStorageKey('kitchen-table-grid'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
      itemCount: _kitchenOrders.length,
      itemBuilder: (context, index) {
        final group = _kitchenOrders[index] as Map<String, dynamic>;
        return _buildKitchenTableSection(group);
      },
    );
  }

  Widget _buildKitchenCombinedOrdersPage() {
    final combinedItems = _buildKitchenCombinedOrderItems();

    return ListView.separated(
      key: const PageStorageKey('kitchen-combined-orders'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
      itemCount: combinedItems.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          final totalQty = combinedItems.fold<int>(
            0,
            (sum, item) => sum + ((item['quantity'] as int?) ?? 0),
          );
          return Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COMBINED ORDERS',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Swipe right for table view',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$totalQty QTY',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return _buildKitchenCombinedOrderRow(combinedItems[index - 1]);
      },
    );
  }

  List<Map<String, dynamic>> _buildKitchenCombinedOrderItems() {
    final combinedByKey = <String, Map<String, dynamic>>{};

    for (final group in _kitchenOrders) {
      if (group is! Map<String, dynamic>) continue;
      final items = (group['items'] as List?) ?? [];
      final tableData = group['tableDetails'];
      final groupTableNumber =
          (tableData is Map ? tableData['tableNumber'] : tableData)
              ?.toString()
              .trim();

      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final product = item['product'];
        final rawName = (item['name'] ?? (product is Map ? product['name'] : null) ?? 'Item')
            .toString();
        final unit = (product is Map ? product['unit'] : null)?.toString() ?? '';
        final formattedName = _formatKitchenProductName(
          (unit.isNotEmpty ? '$rawName ($unit)' : rawName).toUpperCase(),
        );
        final instruction = _resolveKitchenItemInstruction(item, product);
        final productId = product is Map
            ? ((product['id'] ?? product['_id'])?.toString().trim() ?? '')
            : '';
        final key =
            '${productId.isEmpty ? formattedName : productId}|${instruction ?? ''}';
        final qty = _resolveKitchenItemQuantity(item);
        final tableNumber =
            (item['tableNumber'] ?? groupTableNumber)?.toString().trim() ?? '';
        final tableLabel = tableNumber.isEmpty ? 'T' : 'T-$tableNumber';
        final tableStartedAt =
            item['billingCreatedAt'] ??
            item['orderCreatedAt'] ??
            item['createdAt'] ??
            group['createdAt'];

        final existing = combinedByKey[key];
        if (existing == null) {
          combinedByKey[key] = {
            'productName': formattedName,
            'instruction': instruction,
            'quantity': qty,
            'tables': <Map<String, dynamic>>[
              {'label': tableLabel, 'startedAt': tableStartedAt},
            ],
          };
        } else {
          existing['quantity'] = ((existing['quantity'] as int?) ?? 0) + qty;
          final tables = List<Map<String, dynamic>>.from(
            (existing['tables'] as List?) ?? const [],
          );
          final alreadyAdded = tables.any(
            (table) => (table['label']?.toString() ?? '') == tableLabel,
          );
          if (!alreadyAdded) {
            tables.add({'label': tableLabel, 'startedAt': tableStartedAt});
          }
          existing['tables'] = tables;
        }
      }
    }

    return combinedByKey.values.toList();
  }

  int _resolveKitchenItemQuantity(Map<String, dynamic> item) {
    final rawQuantity =
        item['quantity'] ?? item['requiredQty'] ?? item['sendingQty'] ?? 0;
    if (rawQuantity is int) return rawQuantity;
    if (rawQuantity is num) return rawQuantity.round();
    return int.tryParse(rawQuantity.toString()) ?? 0;
  }

  Widget _buildKitchenCombinedOrderRow(Map<String, dynamic> item) {
    final productName = (item['productName'] ?? 'ITEM').toString();
    final instruction = item['instruction']?.toString();
    final quantity = (item['quantity'] as int?) ?? 0;
    final tableBadges = List<Map<String, dynamic>>.from(
      (item['tables'] as List?) ?? const [],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$productName - $quantity',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 0.2,
                ),
              ),
              ...tableBadges.map(
                (table) {
                  final runningTime =
                      _formatKitchenElapsedTime({
                        'createdAt': table['startedAt'],
                      }) ??
                      '0';

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getKitchenElapsedTimeColor({
                        'createdAt': table['startedAt'],
                      }),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${table['label']?.toString() ?? 'T'} $runningTime',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          if (instruction != null && instruction.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                instruction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _handleKitchenFooterSelection(KitchenFooterTab tab) {
    switch (tab) {
      case KitchenFooterTab.kot:
        _toggleKitchenKotView();
        break;
      case KitchenFooterTab.review:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                const ReviewListScreen(showKitchenFooter: true),
          ),
        );
        break;
      case KitchenFooterTab.chats:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (routeContext) => KitchenChatsScreen(
              onKotTap: () {
                Navigator.of(routeContext).popUntil((route) => route.isFirst);
              },
              onReviewTap: () {
                Navigator.pushReplacement(
                  routeContext,
                  MaterialPageRoute(
                    builder: (context) =>
                        const ReviewListScreen(showKitchenFooter: true),
                  ),
                );
              },
            ),
          ),
        );
        break;
    }
  }

  void _toggleKitchenKotView() {
    if (_kitchenOrders.isEmpty) return;

    final nextIndex = _kitchenViewIndex == 0 ? 1 : 0;

    if (!_kitchenPageController.hasClients) {
      setState(() {
        _kitchenViewIndex = nextIndex;
      });
      return;
    }

    _kitchenPageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildKitchenTableSection(Map<String, dynamic> group) {
    final table = group['tableDetails'] ?? {};
    final tableNumber =
        (table is Map ? table['tableNumber'] : table)?.toString() ?? 'N/A';
    final kotNumber = (group['kotNumber'] ?? '').toString().trim();
    final waiterName = (group['waiterName'] ?? 'Waiter').toString().trim();
    final items = (group['items'] as List?) ?? [];
    final startedAtFallback = group['createdAt'];
    final tableBadgeMainLabel = 'TABLE $tableNumber';

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                      children: [
                        TextSpan(
                          text: tableBadgeMainLabel,
                          style: const TextStyle(color: Color(0xFFFFD54F)),
                        ),
                        if (kotNumber.isNotEmpty)
                          const TextSpan(
                            text: ' - ',
                            style: TextStyle(color: Colors.white),
                          ),
                        if (kotNumber.isNotEmpty)
                          TextSpan(
                            text: kotNumber,
                            style: const TextStyle(color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    waiterName.isEmpty ? 'Waiter' : waiterName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (group['createdAt'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getKitchenElapsedTimeColor({
                        'createdAt': group['createdAt'],
                      }),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time_filled_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatKitchenElapsedTime({
                                'createdAt': group['createdAt'],
                              }) ??
                              '0s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return _buildKitchenOrderCard(
                items[index],
                fallbackStartedAt: startedAtFallback,
              );
            },
          ),
        ],
      ),
    );
  }

  void _showKitchenInfo() {
    final branch = _branches.firstWhere(
      (b) => (b['id'] ?? b['_id']).toString() == _userBranchId,
      orElse: () => {},
    );
    final branchName = branch['name'] ?? 'Unknown Branch';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Kitchen Session Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Role: $_userRole'),
            const Divider(),
            Text('Branch Name: $branchName'),
            Text('Branch ID: $_userBranchId'),
            const Divider(),
            const Text(
              'Kitchen Info:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('ID: $_userKitchenId'),
            Text('Categories: ${_userKitchenCategoryIds.length} loaded'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  String? _resolveKitchenProductImageUrl(dynamic product) {
    if (product is! Map) return null;

    String? imageUrl;
    final images = product['images'];
    if (images is List && images.isNotEmpty) {
      imageUrl = _extractKitchenImageUrl(images.first);
      if (imageUrl == null && images.first is Map) {
        imageUrl = _extractKitchenImageUrl((images.first as Map)['image']);
      }
    }

    imageUrl ??= _extractKitchenImageUrl(product['image']);
    imageUrl ??= _extractKitchenImageUrl(product['thumbnail']);

    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        !imageUrl.startsWith('http')) {
      imageUrl = 'https://blackforest.vseyal.com$imageUrl';
    }

    return (imageUrl == null || imageUrl.isEmpty) ? null : imageUrl;
  }

  String? _extractKitchenImageUrl(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Map) {
      final direct = value['url']?.toString();
      if (direct != null && direct.isNotEmpty) return direct;
      return _extractKitchenImageUrl(value['image']);
    }
    return null;
  }

  String _formatKitchenProductName(String rawName) {
    final normalized = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.isEmpty ? rawName : normalized;
  }

  String _resolveKitchenKotLabel(dynamic billing) {
    if (billing is! Map) return '';

    final rawKot =
        (billing['kotNumber'] ??
                billing['kotNo'] ??
                billing['invoiceNumber'] ??
                billing['orderNumber'])
            ?.toString()
            .trim() ??
        '';

    if (rawKot.isEmpty) return '';

    final upperKot = rawKot.toUpperCase();
    final kotMatch = RegExp(r'(KOT[-\s]?\d+)$').firstMatch(upperKot);
    if (kotMatch != null) {
      return kotMatch.group(1)!.replaceAll(' ', '');
    }

    if (upperKot.startsWith('KOT')) {
      return upperKot.replaceAll(' ', '');
    }

    final lastPart = rawKot.split('-').last.trim().toUpperCase();
    return lastPart.startsWith('KOT') ? lastPart.replaceAll(' ', '') : '';
  }

  String? _normalizeKitchenInstruction(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (normalized.isEmpty || normalized.toLowerCase() == 'null') {
        return null;
      }
      return normalized.toUpperCase();
    }

    if (value is List) {
      final parts = value
          .map(_normalizeKitchenInstruction)
          .whereType<String>()
          .toList();
      if (parts.isEmpty) return null;
      return parts.join(', ');
    }

    if (value is Map) {
      final candidates = [
        value['instruction'],
        value['instructions'],
        value['note'],
        value['notes'],
        value['remark'],
        value['remarks'],
        value['comment'],
        value['comments'],
        value['text'],
        value['label'],
        value['name'],
      ];

      for (final candidate in candidates) {
        final normalized = _normalizeKitchenInstruction(candidate);
        if (normalized != null) return normalized;
      }
    }

    return null;
  }

  String? _resolveKitchenItemInstruction(dynamic item, dynamic product) {
    final candidates = <dynamic>[
      if (item is Map) ...[
        item['instruction'],
        item['instructions'],
        item['note'],
        item['notes'],
        item['remark'],
        item['remarks'],
        item['comment'],
        item['comments'],
        item['specialInstruction'],
        item['specialInstructions'],
        item['customerNote'],
        item['customerNotes'],
        item['description'],
      ],
      if (product is Map) ...[
        product['instruction'],
        product['instructions'],
        product['note'],
        product['notes'],
      ],
    ];

    for (final candidate in candidates) {
      final normalized = _normalizeKitchenInstruction(candidate);
      if (normalized != null) return normalized;
    }

    return null;
  }

  String? _extractKitchenPersonName(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      if (RegExp(r'^[a-f0-9]{24}$', caseSensitive: false).hasMatch(trimmed)) {
        return null;
      }
      if (trimmed.contains('@')) {
        final prefix = trimmed.split('@').first.trim();
        return prefix.isEmpty ? null : prefix;
      }
      return trimmed;
    }

    if (value is Map) {
      final candidates = [
        value['name'],
        value['fullName'],
        value['displayName'],
        value['userName'],
        value['username'],
        value['email'],
        value['user'],
      ];

      for (final candidate in candidates) {
        final name = _extractKitchenPersonName(candidate);
        if (name != null && name.isNotEmpty) return name;
      }
    }

    return null;
  }

  String _resolveKitchenWaiterName(dynamic billing) {
    if (billing is! Map) return 'Waiter';

    final candidates = [
      billing['waiter'],
      billing['waiterName'],
      billing['server'],
      billing['serverName'],
      billing['captain'],
      billing['captainName'],
      billing['staff'],
      billing['staffName'],
      billing['servedBy'],
      billing['createdBy'],
      billing['user'],
    ];

    for (final candidate in candidates) {
      final name = _extractKitchenPersonName(candidate);
      if (name != null && name.isNotEmpty) return name;
    }

    return 'Waiter';
  }

  DateTime? _parseKitchenOrderStartedAt(
    dynamic item, {
    dynamic fallbackStartedAt,
    bool allowBillingFallback = true,
  }) {
    if (item is! Map) {
      if (!allowBillingFallback) return null;
      final raw = fallbackStartedAt?.toString().trim();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toLocal();
    }

    final candidates = <dynamic>[
      item['itemStartedAt'],
      item['createdAt'],
      item['addedAt'],
      item['orderedAt'],
      item['updatedAt'],
      item['timestamp'],
      if (allowBillingFallback) item['billingCreatedAt'],
      if (allowBillingFallback) item['orderCreatedAt'],
      if (allowBillingFallback) fallbackStartedAt,
    ];

    for (final candidate in candidates) {
      final raw = candidate?.toString().trim();
      if (raw == null || raw.isEmpty) continue;

      final parsed = DateTime.tryParse(raw)?.toLocal();
      if (parsed != null) return parsed;
    }

    return null;
  }

  String? _formatKitchenElapsedTime(
    dynamic item, {
    dynamic fallbackStartedAt,
    bool allowBillingFallback = true,
  }) {
    final startedAt = _parseKitchenOrderStartedAt(
      item,
      fallbackStartedAt: fallbackStartedAt,
      allowBillingFallback: allowBillingFallback,
    );
    if (startedAt == null) return null;

    final totalSeconds = DateTime.now().difference(startedAt).inSeconds;
    final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    final seconds = safeSeconds % 60;
    final minuteLabel = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
    final secondLabel = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minuteLabel:$secondLabel';
    }
    if (minutes == 0) {
      return seconds.toString();
    }
    return '$minuteLabel:$secondLabel';
  }

  Color _getKitchenElapsedTimeColor(
    dynamic item, {
    dynamic fallbackStartedAt,
    bool allowBillingFallback = true,
  }) {
    final startedAt = _parseKitchenOrderStartedAt(
      item,
      fallbackStartedAt: fallbackStartedAt,
      allowBillingFallback: allowBillingFallback,
    );
    if (startedAt == null) return Colors.black.withValues(alpha: 0.72);

    final minutes = DateTime.now().difference(startedAt).inMinutes;

    if (minutes >= 10) {
      return Colors.red;
    } else if (minutes >= 5) {
      return Colors.orange[800]!;
    } else {
      return Colors.green[700]!;
    }
  }

  Color? _getKitchenOrderCardOverlayColor(DateTime? startedAt) {
    if (startedAt == null) return null;

    final minutes = DateTime.now().difference(startedAt).inMinutes;

    if (minutes >= 10) {
      return Colors.red.withValues(alpha: 0.28);
    }
    if (minutes >= 5) {
      return Colors.orange.withValues(alpha: 0.24);
    }
    return null;
  }

  Widget _buildKitchenOrderCard(dynamic item, {dynamic fallbackStartedAt}) {
    final product = item['product'] ?? {};
    final rawName = (item['name'] ?? product['name'] ?? 'Item').toString();
    final unit = (product['unit'] ?? '').toString();
    final productName = (unit.isNotEmpty ? '$rawName ($unit)' : rawName)
        .toUpperCase();
    final formattedProductName = _formatKitchenProductName(productName);
    final instructionText = _resolveKitchenItemInstruction(item, product);
    final qty = item['quantity'] ?? 0;
    final imageUrl = _resolveKitchenProductImageUrl(product);
    final itemStartedAt = _parseKitchenOrderStartedAt(
      item,
      allowBillingFallback: false,
    );
    final elapsedLabel = _formatKitchenElapsedTime(
      item,
      allowBillingFallback: false,
    );
    final elapsedColor =
        itemStartedAt == null
            ? Colors.green[700]!
            : _getKitchenElapsedTimeColor(
                {'createdAt': itemStartedAt.toIso8601String()},
                allowBillingFallback: false,
              );
    final orderOverlayColor = _getKitchenOrderCardOverlayColor(itemStartedAt);
    final hasInstruction = instructionText != null;
    final selectionKey = item is Map ? item['selectionKey']?.toString() : null;
    final isSelected =
        selectionKey != null && _selectedKitchenItemKeys.contains(selectionKey);

    return GestureDetector(
      onTap: () => _onKitchenItemTapped(item),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.95),
                  width: 2.2,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              spreadRadius: 1,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE8E1D6), Color(0xFFB39A7D)],
                      ),
                    ),
                    child: Icon(
                      Icons.fastfood_rounded,
                      color: Colors.white.withValues(alpha: 0.75),
                      size: 54,
                    ),
                  );
                },
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE8E1D6), Color(0xFFB39A7D)],
                  ),
                ),
                child: Icon(
                  Icons.fastfood_rounded,
                  color: Colors.white.withValues(alpha: 0.75),
                  size: 54,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: hasInstruction ? 118 : 88,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.34),
                    ],
                    stops: const [0.0, 0.62, 1.0],
                  ),
                  ),
                ),
              ),
            if (!isSelected && orderOverlayColor != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: orderOverlayColor),
                ),
              ),
            if (isSelected)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.36),
                  ),
                ),
              ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 36,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    qty.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: elapsedColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Text(
                  elapsedLabel ?? '0',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    height: 1,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasInstruction)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF2E7D32),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                      ),
                      child: KitchenInstructionMarquee(
                        text: instructionText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          height: 1.1,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    color: Colors.black.withValues(alpha: 0.74),
                    child: SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formattedProductName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            height: 1,
                            letterSpacing: 0.05,
                          ),
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Quantity Overlay (Always shown as it's an order)
          ],
        ),
      ),
    );
  }

  Future<void> _onKitchenItemTapped(dynamic item) async {
    final billingId = item['billingId'];
    final itemId = item['id'] ?? item['_id'];
    final selectionKey =
        (item is Map ? item['selectionKey']?.toString() : null) ??
        _buildKitchenSelectionKey(billingId.toString(), item);

    if (!_selectedKitchenItemKeys.contains(selectionKey)) {
      if (mounted) {
        setState(() {
          _selectedKitchenItemKeys
            ..clear()
            ..add(selectionKey);
        });
      }
      return;
    }

    final itemKeys = _buildNotificationItemKeys(billingId.toString(), item);
    if (itemId != null && itemId.toString().trim().isNotEmpty) {
      itemKeys.add('${billingId}_${itemId.toString().trim()}');
    }
    final currentStatus =
        (item['status'] as String?)?.toLowerCase() ?? 'ordered';

    String nextStatus = '';
    String loadingMsg = '';
    String successMsg = '';
    Color successColor = Colors.blue;

    if (currentStatus == 'ordered' || currentStatus == 'confirmed') {
      nextStatus = 'prepared';
      loadingMsg = 'Marking as prepared...';
      successMsg = 'Item Prepared & Removed';
      successColor = Colors.green;
    } else {
      return;
    }

    try {
      // Show immediate feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loadingMsg),
          duration: const Duration(milliseconds: 500),
        ),
      );

      await ApiService.instance.updateBillingItemStatus(
        billingId: billingId,
        itemId: itemId,
        status: nextStatus,
      );

      // Never show the same item notification again once marked prepared.
      if (mounted) {
        setState(() {
          _removeKitchenItemLocally(
            billingId: billingId.toString(),
            selectionKey: selectionKey,
            itemId: itemId?.toString().trim(),
          );
          final bucketKey = _buildSuppressionBucketKey(
            billingId.toString(),
            item,
          );
          _suppressedItemCountByBucket[bucketKey] =
              (_suppressedItemCountByBucket[bucketKey] ?? 0) + 1;
          _suppressedNotificationItemKeys.addAll(itemKeys);
          _kitchenNotifications.removeWhere(
            (n) =>
                itemKeys.contains((n['itemKey'] ?? n['id']).toString().trim()),
          );
          _readNotificationIds.addAll(itemKeys);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMsg),
            backgroundColor: successColor,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _doesOrderContainDepartment(dynamic order, String deptId) {
    final items = (order['items'] as List?) ?? [];
    for (var item in items) {
      final product = item['product'];
      if (product is Map) {
        final cat = product['category'];
        if (cat is Map) {
          final dept = cat['department']; // May be String ID or Map
          String dId = '';
          if (dept is Map) {
            dId = dept['id'] ?? dept['_id'] ?? '';
          } else if (dept is String) {
            dId = dept;
          }

          if (deptId == 'OTHERS') {
            if (dId.isEmpty) return true;
          } else if (dId == deptId) {
            return true;
          }
        } else if (deptId == 'OTHERS') {
          // If product or category is malformed/missing, it's Others
          return true;
        }
      } else if (deptId == 'OTHERS') {
        // If product or category is malformed/missing, it's Others
        return true;
      }
    }
    return false;
  }

  Widget _buildDepartmentFooter() {
    if (_departments.isEmpty) return const SizedBox.shrink();

    // Clone and sort departments, ensure ALL is first
    final sortedDepts = List<Map<String, dynamic>>.from(_departments);
    // Check if ALL exists, if not add it
    if (!sortedDepts.any((d) => d['id'] == 'ALL')) {
      sortedDepts.insert(0, {'id': 'ALL', 'name': 'All'});
    }
    // Add 'Others' option
    if (!sortedDepts.any((d) => d['id'] == 'OTHERS')) {
      sortedDepts.add({'id': 'OTHERS', 'name': 'Others'});
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
          final deptId = dept['id'];
          final isSelected = _selectedDepartmentFilter == deptId;
          return ChoiceChip(
            label: Text(dept['name'] ?? ''),
            selected: isSelected,
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _selectedDepartmentFilter = deptId;
                });
              }
            },
            selectedColor: Colors.white,
            labelStyle: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
            backgroundColor: Colors.grey.shade900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.transparent),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _buildTicketItem(dynamic order) {
    // Extract Data
    final shortCode = order['shortCode'] ?? '';
    final invoiceNo = order['invoiceNumber'] ?? 'No Invoice';

    // Calculate Amounts
    double totalOrdered = 0.0;
    double totalSending = 0.0;
    double totalConfirmed = 0.0;
    double totalPicked = 0.0;

    final items = (order['items'] as List?) ?? [];
    for (var item in items) {
      final product = item['product'];
      double price = 0.0;
      if (product is Map) {
        if (product['defaultPriceDetails'] != null &&
            product['defaultPriceDetails'] is Map) {
          price = ((product['defaultPriceDetails']['price'] ?? 0) as num)
              .toDouble();
        } else {
          price = ((product['price'] ?? 0) as num).toDouble();
        }
      }
      final reqQty = ((item['requiredQty'] as num?) ?? 0).toDouble();
      final sentQty = ((item['sendingQty'] as num?) ?? 0).toDouble();
      final confQty = ((item['confirmedQty'] as num?) ?? 0).toDouble();
      final pickQty = ((item['pickedQty'] as num?) ?? 0).toDouble();

      totalOrdered += (price * reqQty);
      totalSending += (price * sentQty);
      totalConfirmed += (price * confQty);
      totalPicked += (price * pickQty);
    }

    final cDate = DateTime.tryParse(order['createdAt'] ?? '')?.toLocal();
    final dDate = DateTime.tryParse(order['deliveryDate'] ?? '')?.toLocal();
    final now = DateTime.now();

    bool isLive = false;
    if (cDate != null && dDate != null) {
      bool isOrderedToday =
          cDate.year == now.year &&
          cDate.month == now.month &&
          cDate.day == now.day;
      bool isDeliveryToday =
          dDate.year == now.year &&
          dDate.month == now.month &&
          dDate.day == now.day;
      isLive = isOrderedToday && isDeliveryToday;
    }

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    // Determine Overall Bill Status
    // Use the explicit status from the order object (managed by office team)
    String rawStatus = (order['status'] ?? 'pending').toString().toLowerCase();
    String billStatus = rawStatus.toUpperCase(); // Default to Uppercase

    Color statusColor = Colors.orange; // Default for Ordered/Pending

    if (rawStatus == 'confirmed') {
      statusColor = Colors.blue;
    } else if (rawStatus == 'processing') {
      statusColor = Colors.blueAccent;
    } else if (rawStatus == 'completed') {
      statusColor = Colors.green;
    } else if (rawStatus == 'cancelled') {
      statusColor = Colors.red;
    } else if (rawStatus == 'ordered') {
      statusColor = Colors.orange;
    }
    // Capitalize first letter for display if preferred, or keep CAPS
    // billStatus is already CAPS.
    if (billStatus == 'PENDING') {
      billStatus = 'ORDERED';
    }

    // Determine Amounts to Display based on Role
    String label1 = 'Ord';
    double val1 = totalOrdered;
    Color color1 = Colors.blueGrey;

    String label2 = 'Snt';
    double val2 = totalSending;
    Color color2 = Colors.green;

    if (_userRole == 'chef') {
      label1 = 'Ord';
      val1 = totalOrdered;
      label2 = 'Snt';
      val2 = totalSending;
    } else if (_userRole == 'supervisor') {
      label1 = 'Snt';
      val1 = totalSending;
      color1 = Colors.red;
      label2 = 'Con';
      val2 = totalConfirmed;
      color2 = Colors.green;
    } else if (_userRole == 'driver') {
      label1 = 'Con';
      val1 = totalConfirmed;
      color1 = Colors.red;
      label2 = 'Pic';
      val2 = totalPicked;
      color2 = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Role Check
          if ([
            'chef',
            'supervisor',
            'driver',
            'factory',
            'kitchen',
          ].contains(_userRole)) {
            final branchId =
                (order['branch'] is Map
                        ? (order['branch']['id'] ?? order['branch']['_id'])
                        : null)
                    ?.toString();
            if (branchId == null) return;

            final orderId = (order['id'] ?? order['_id'])?.toString();

            // Use Delivery Date for Filter (as per user request)
            DateTime initialFrom = dDate ?? DateTime.now();
            DateTime initialTo = dDate ?? DateTime.now();

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StockOrderReportPage(
                  initialBranchId: branchId,
                  initialFromDate: initialFrom,
                  initialToDate: initialTo,
                  initialOrderId: orderId,
                  initialIsReportView: false, // Force Grid
                  onlyTodayOrdered: isLive,
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You are not authorized to update orders.'),
                duration: Duration(milliseconds: 1000),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    shortCode,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isLive ? Colors.red : Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isLive ? 'Live' : 'Stock',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    billStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (cDate != null)
                        Text(
                          'Ord: ${dateFormat.format(cDate)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (dDate != null)
                        Text(
                          'Del: ${dateFormat.format(dDate)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Inv: $invoiceNo',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$label1: ${currencyFormat.format(val1)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: color1,
                        ),
                      ),
                      Text(
                        '$label2: ${currencyFormat.format(val2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: color2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridItem(
    BuildContext context,
    String title,
    IconData icon,
    int count,
  ) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox.expand(
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () {
                if (title == 'Stock') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StockTicketListScreen(),
                    ),
                  );
                } else if (title == 'Live') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BranchListPage(),
                    ),
                  );
                } else if (title == 'Reviews') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ReviewListScreen(),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 40, color: Colors.black),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (count > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class KitchenInstructionMarquee extends StatefulWidget {
  final String text;
  final TextStyle style;

  const KitchenInstructionMarquee({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  State<KitchenInstructionMarquee> createState() =>
      _KitchenInstructionMarqueeState();
}

class _KitchenInstructionMarqueeState extends State<KitchenInstructionMarquee>
    with SingleTickerProviderStateMixin {
  static const double _gap = 28;
  static const double _pixelsPerSecond = 14;

  late final AnimationController _controller;
  double _lastTextWidth = 0;
  double _lastAvailableWidth = 0;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateScrollState({
    required double textWidth,
    required double availableWidth,
  }) {
    final shouldScroll = textWidth > availableWidth + 1;

    if (!shouldScroll) {
      if (_isScrolling || _controller.value != 0) {
        _controller
          ..stop()
          ..value = 0;
      }
      _isScrolling = false;
      return;
    }

    final loopWidth = textWidth + _gap;
    final durationMs = ((loopWidth / _pixelsPerSecond) * 1000)
        .round()
        .clamp(3500, 12000);

    if (_isScrolling &&
        (_lastTextWidth - textWidth).abs() < 1 &&
        (_lastAvailableWidth - availableWidth).abs() < 1 &&
        _controller.duration?.inMilliseconds == durationMs) {
      return;
    }

    _controller
      ..duration = Duration(milliseconds: durationMs)
      ..repeat();
    _isScrolling = true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();

        final textWidth = textPainter.width;
        final availableWidth = constraints.maxWidth;
        final needsUpdate =
            (_lastTextWidth - textWidth).abs() > 1 ||
            (_lastAvailableWidth - availableWidth).abs() > 1;

        if (needsUpdate) {
          _lastTextWidth = textWidth;
          _lastAvailableWidth = availableWidth;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _updateScrollState(
              textWidth: textWidth,
              availableWidth: availableWidth,
            );
          });
        }

        if (textWidth <= availableWidth + 1) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        return ClipRect(
          child: SizedBox(
            width: double.infinity,
            height: textPainter.height,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final travel = textWidth + _gap;
                return Transform.translate(
                  offset: Offset(-travel * _controller.value, 0),
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.text,
                          maxLines: 1,
                          softWrap: false,
                          style: widget.style,
                        ),
                        const SizedBox(width: _gap),
                        Text(
                          widget.text,
                          maxLines: 1,
                          softWrap: false,
                          style: widget.style,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
