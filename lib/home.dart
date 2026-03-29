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
  final Map<String, String> _kitchenItemPreparedAtByKey = {};
  final Map<String, Map<String, dynamic>> _kitchenItemPrepApiByKey = {};
  final Set<String> _kitchenPreparationFetchInFlight = {};
  final Map<String, int> _suppressedItemCountByBucket = {};
  final _audioPlayer = AudioPlayer();
  String _userId = '';
  List<dynamic>? _cachedStockCategories;
  final Map<String, List<dynamic>> _cachedStockProductsByCategory = {};
  final Map<String, int> _stockOutOrderByProductId = {};
  int _stockOutOrderCounter = 0;

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
          if (_isHiddenKitchenNotificationItemStatus(status)) {
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

  bool _isHiddenKitchenNotificationItemStatus(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    if (s.isEmpty) return false;
    // Notification stream should only alert for active ordered items.
    return s != 'ordered';
  }

  bool _isVisibleKitchenDashboardItemStatus(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    if (s.isEmpty) return true;
    // Combined dashboard keeps prepared/cancelled items visible.
    return s == 'ordered' ||
        s == 'prepared' ||
        s == 'cancelled' ||
        s == 'canceled';
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

  int? _extractKitchenIntMinutes(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) {
      final cleaned = value.trim();
      if (cleaned.isEmpty) return null;
      return int.tryParse(cleaned);
    }
    return null;
  }

  void _mergeKitchenPreparationSnapshotIntoItem(
    Map<String, dynamic> item,
    Map<String, dynamic> snapshot,
  ) {
    const keys = [
      'orderedAt',
      'preparedAt',
      'preparedDurationMinutes',
      'currentPreparationMinutes',
      'status',
    ];

    for (final key in keys) {
      final value = snapshot[key];
      if (value == null) continue;
      item[key] = value;
    }
  }

  void _applyKitchenPreparationSnapshotToItem(
    Map<String, dynamic> item,
    String selectionKey,
  ) {
    final snapshot = _kitchenItemPrepApiByKey[selectionKey];
    if (snapshot != null) {
      _mergeKitchenPreparationSnapshotIntoItem(item, snapshot);
    }

    final cachedPreparedAt = _kitchenItemPreparedAtByKey[selectionKey];
    if (cachedPreparedAt != null && cachedPreparedAt.isNotEmpty) {
      item['preparedAt'] = cachedPreparedAt;
    }
  }

  Map<String, dynamic>? _buildKitchenPreparationSnapshotFromApi(
    Map<String, dynamic> payload,
  ) {
    final rawItem = payload['item'];
    if (rawItem is! Map) return null;

    return {
      'orderedAt': rawItem['orderedAt'],
      'preparedAt': rawItem['preparedAt'],
      'preparedDurationMinutes': rawItem['preparedDurationMinutes'],
      'currentPreparationMinutes': rawItem['currentPreparationMinutes'],
      'status': rawItem['status'],
    };
  }

  void _applyKitchenPreparationSnapshotToOrders(
    String selectionKey,
    Map<String, dynamic> snapshot,
  ) {
    for (final group in _kitchenOrders) {
      if (group is! Map<String, dynamic>) continue;
      final items = (group['items'] as List?) ?? const [];
      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final itemSelectionKey = item['selectionKey']?.toString();
        if (itemSelectionKey != selectionKey) continue;

        _mergeKitchenPreparationSnapshotIntoItem(item, snapshot);
        if ((snapshot['preparedAt']?.toString().trim().isNotEmpty ?? false)) {
          _kitchenItemPreparedAtByKey[selectionKey] = snapshot['preparedAt']
              .toString();
        }
        rawItem.addAll(item);
      }
    }
  }

  Future<void> _fetchKitchenPreparationDurations(
    List<Map<String, String>> requests,
  ) async {
    if (requests.isEmpty) return;

    final updatesBySelectionKey = <String, Map<String, dynamic>>{};

    await Future.wait(
      requests.map((request) async {
        final selectionKey = request['selectionKey'] ?? '';
        final billingId = request['billingId'] ?? '';
        final itemId = request['itemId'] ?? '';
        if (selectionKey.isEmpty || billingId.isEmpty || itemId.isEmpty) return;
        if (_kitchenPreparationFetchInFlight.contains(selectionKey)) return;

        _kitchenPreparationFetchInFlight.add(selectionKey);
        try {
          final payload = await ApiService.instance
              .fetchBillingItemPreparationTime(
                billingId: billingId,
                itemId: itemId,
              );
          if (payload == null) return;

          final snapshot = _buildKitchenPreparationSnapshotFromApi(payload);
          if (snapshot == null) return;
          updatesBySelectionKey[selectionKey] = snapshot;
        } catch (e) {
          debugPrint(
            'DEBUG: fetchBillingItemPreparationTime failed for $selectionKey: $e',
          );
        } finally {
          _kitchenPreparationFetchInFlight.remove(selectionKey);
        }
      }),
    );

    if (!mounted || updatesBySelectionKey.isEmpty) return;

    setState(() {
      updatesBySelectionKey.forEach((selectionKey, snapshot) {
        _kitchenItemPrepApiByKey[selectionKey] = snapshot;
        _applyKitchenPreparationSnapshotToOrders(selectionKey, snapshot);
      });
    });
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
      final updatedItems = <dynamic>[];

      for (final rawItem in rawItems) {
        if (rawItem is! Map) {
          updatedItems.add(rawItem);
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
          final preparedAtIso = DateTime.now().toIso8601String();
          itemMap['status'] = 'prepared';
          itemMap['preparedAt'] = preparedAtIso;
          itemMap['updatedAt'] = preparedAtIso;
          _kitchenItemPreparedAtByKey[rawSelectionKey] = preparedAtIso;
          _kitchenItemPrepApiByKey[rawSelectionKey] = {
            'status': 'prepared',
            'preparedAt': preparedAtIso,
            'orderedAt': itemMap['orderedAt'] ?? itemMap['itemStartedAt'],
            'preparedDurationMinutes': itemMap['preparedDurationMinutes'],
            'currentPreparationMinutes': null,
          };
        }

        updatedItems.add(itemMap);
      }

      final updatedGroup = Map<String, dynamic>.from(group);
      updatedGroup['items'] = updatedItems;
      updatedOrders.add(updatedGroup);
    }

    _kitchenOrders = updatedOrders;
    _selectedKitchenItemKeys.remove(selectionKey);
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
      final prepDurationRequests = <Map<String, String>>[];
      final prepDurationRequestKeys = <String>{};
      for (var billing in orders) {
        final bId = (billing['id'] ?? billing['_id'])?.toString();
        final isTargetOrder = bId == '6986e2f542fe15984da62652';

        if (isTargetOrder) {
          debugPrint('DEBUG: Found target order $bId. Checking items...');
        }

        final items = (billing['items'] as List?) ?? [];
        final List<dynamic> tableItems = [];

        for (var item in items) {
          final status =
              (item['status'] as String?)?.toLowerCase() ?? 'ordered';
          if (isTargetOrder) {
            debugPrint(
              'DEBUG: Item in target order: ${item['name']}, status: $status',
            );
          }

          if (!_isVisibleKitchenDashboardItemStatus(status)) {
            final billKey = (bId ?? '').isNotEmpty ? (bId ?? '') : 'unknown';
            _suppressedNotificationItemKeys.addAll(
              _buildNotificationItemKeys(billKey, item),
            );
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
                      : (initialFallbackStartedAt
                                ?.toString()
                                .trim()
                                .isNotEmpty ??
                            false)
                      ? initialFallbackStartedAt.toString().trim()
                      : DateTime.now().toIso8601String());
              flatItem['selectionKey'] = selectionKey;
              flatItem['itemStartedAt'] = itemStartedAt;
              _kitchenItemStartedAtByKey[selectionKey] = itemStartedAt;
              _applyKitchenPreparationSnapshotToItem(flatItem, selectionKey);
              final itemStatus =
                  (flatItem['status'] as String?)?.toLowerCase().trim() ??
                  'ordered';
              if (itemStatus == 'prepared') {
                final cachedPreparedAt =
                    _kitchenItemPreparedAtByKey[selectionKey];
                final parsedPreparedAt = _parseKitchenOrderPreparedAt(
                  flatItem,
                )?.toIso8601String();
                final statusUpdatedAt = _tryParseKitchenDateTime(
                  flatItem['statusUpdatedAt'],
                )?.toIso8601String();
                final updatedAt = _tryParseKitchenDateTime(
                  flatItem['updatedAt'],
                )?.toIso8601String();
                final resolvedPreparedAt =
                    cachedPreparedAt ??
                    parsedPreparedAt ??
                    statusUpdatedAt ??
                    updatedAt;
                if (resolvedPreparedAt != null &&
                    resolvedPreparedAt.isNotEmpty) {
                  flatItem['preparedAt'] = resolvedPreparedAt;
                  _kitchenItemPreparedAtByKey[selectionKey] =
                      resolvedPreparedAt;
                }

                final preparedDuration = _extractKitchenIntMinutes(
                  flatItem['preparedDurationMinutes'],
                );
                final itemId =
                    (flatItem['id'] ?? flatItem['_id'])?.toString().trim() ??
                    '';
                final billId = (bId ?? '').toString().trim();
                final requestKey = '${selectionKey}_${billId}_$itemId';
                if (preparedDuration == null &&
                    itemId.isNotEmpty &&
                    billId.isNotEmpty &&
                    !prepDurationRequestKeys.contains(requestKey) &&
                    !_kitchenPreparationFetchInFlight.contains(selectionKey)) {
                  prepDurationRequestKeys.add(requestKey);
                  prepDurationRequests.add({
                    'selectionKey': selectionKey,
                    'billingId': billId,
                    'itemId': itemId,
                  });
                }
              } else {
                _kitchenItemPreparedAtByKey.remove(selectionKey);
              }
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
            'createdByName': _resolveKitchenCreatedByName(billing),
            'customerName': _resolveKitchenCustomerName(billing),
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
          _selectedKitchenItemKeys.retainWhere(
            validKitchenSelectionKeys.contains,
          );
          _kitchenItemStartedAtByKey.removeWhere(
            (key, value) => !validKitchenSelectionKeys.contains(key),
          );
          _kitchenItemPreparedAtByKey.removeWhere(
            (key, value) => !validKitchenSelectionKeys.contains(key),
          );
          _hasLoadedKitchenOrdersOnce = true;
          if (showLoader) _isLoading = false;
        });
      }

      if (prepDurationRequests.isNotEmpty) {
        unawaited(_fetchKitchenPreparationDurations(prepDurationRequests));
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
    final visibleTableGroups = <Map<String, dynamic>>[];

    for (final rawGroup in _kitchenOrders) {
      if (rawGroup is! Map<String, dynamic>) continue;
      final items = (rawGroup['items'] as List?) ?? const [];
      final hasOrdered = items.any((rawItem) {
        if (rawItem is! Map) return false;
        final status =
            (rawItem['status'] as String?)?.toLowerCase().trim() ?? 'ordered';
        return status == 'ordered';
      });
      if (!hasOrdered) continue;
      visibleTableGroups.add(rawGroup);
    }

    visibleTableGroups.sort((a, b) {
      List<Map<String, dynamic>> collectItems(Map<String, dynamic> group) {
        return ((group['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }

      int resolvePriority(Map<String, dynamic> group) {
        final items = collectItems(group);
        final activeTimingItems = items.where((item) {
          final status =
              (item['status'] as String?)?.toLowerCase().trim() ?? 'ordered';
          return status == 'ordered';
        }).toList();
        final timingItems = activeTimingItems.isNotEmpty
            ? activeTimingItems
            : items;
        final startedAt = _resolveKitchenGroupStartedAt(group, timingItems);
        final hasPrepared = items.any((item) {
          final status =
              (item['status'] as String?)?.toLowerCase().trim() ?? 'ordered';
          return status == 'prepared';
        });
        final allPrepared =
            items.isNotEmpty &&
            items.every((item) {
              final status =
                  (item['status'] as String?)?.toLowerCase().trim() ??
                  'ordered';
              return status == 'prepared';
            });
        final forcePreparing = hasPrepared && !allPrepared;
        final alertMeta = _resolveKitchenCombinedAlertMeta(
          startedAt,
          allPrepared: allPrepared,
          forcePreparing: forcePreparing,
        );
        return (alertMeta['priority'] as int?) ?? 0;
      }

      DateTime? resolveStartedAt(Map<String, dynamic> group) {
        final items = collectItems(group);
        final activeTimingItems = items.where((item) {
          final status =
              (item['status'] as String?)?.toLowerCase().trim() ?? 'ordered';
          return status == 'ordered';
        }).toList();
        final timingItems = activeTimingItems.isNotEmpty
            ? activeTimingItems
            : items;
        return _resolveKitchenGroupStartedAt(group, timingItems);
      }

      final priorityDiff = resolvePriority(b).compareTo(resolvePriority(a));
      if (priorityDiff != 0) return priorityDiff;

      final aStartedAt = resolveStartedAt(a);
      final bStartedAt = resolveStartedAt(b);
      if (aStartedAt == null && bStartedAt == null) return 0;
      if (aStartedAt == null) return 1;
      if (bStartedAt == null) return -1;
      return aStartedAt.compareTo(bStartedAt);
    });

    return ListView.builder(
      key: const PageStorageKey('kitchen-table-grid'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
      itemCount: visibleTableGroups.length,
      itemBuilder: (context, index) {
        final group = visibleTableGroups[index];
        return _buildKitchenTableSection(group);
      },
    );
  }

  Widget _buildKitchenCombinedOrdersPage() {
    final combinedCards = _buildKitchenCombinedOrderCards();
    final totalQty = combinedCards.fold<int>(
      0,
      (sum, card) => sum + ((card['totalQty'] as int?) ?? 0),
    );
    final delayedCount = combinedCards.where((card) {
      return ((card['alertPriority'] as int?) ?? 0) >= 3;
    }).length;

    return ListView(
      key: const PageStorageKey('kitchen-combined-orders'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'COMBINED ORDERS',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      combinedCards.isEmpty
                          ? 'No active table orders'
                          : 'Scroll down. Alerted tables are shown first.',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (delayedCount > 0)
                    Text(
                      '$delayedCount delayed',
                      style: const TextStyle(
                        color: Color(0xFFC62828),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (combinedCards.isEmpty)
          Container(
            height: 280,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: const Text(
              'No kitchen orders found.',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w700),
            ),
          )
        else
          ...combinedCards.map((card) => _buildKitchenCombinedOrderCard(card)),
      ],
    );
  }

  int _resolveKitchenItemQuantity(Map<String, dynamic> item) {
    final rawQuantity =
        item['quantity'] ?? item['requiredQty'] ?? item['sendingQty'] ?? 0;
    if (rawQuantity is int) return rawQuantity;
    if (rawQuantity is num) return rawQuantity.round();
    return int.tryParse(rawQuantity.toString()) ?? 0;
  }

  List<Map<String, dynamic>> _buildKitchenCombinedOrderCards() {
    final cards = <Map<String, dynamic>>[];

    for (final rawGroup in _kitchenOrders) {
      if (rawGroup is! Map<String, dynamic>) continue;

      final items = ((rawGroup['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (items.isEmpty) continue;

      final activeTimingItems = items.where((item) {
        final status =
            (item['status'] as String?)?.toLowerCase().trim() ?? 'ordered';
        return status == 'ordered';
      }).toList();
      final timingItems = activeTimingItems.isNotEmpty
          ? activeTimingItems
          : items;
      final startedAt = _resolveKitchenGroupStartedAt(rawGroup, timingItems);
      final hasPrepared = items.any((item) {
        final status =
            (item['status'] as String?)?.toLowerCase().trim() ?? 'ordered';
        return status == 'prepared';
      });
      final allPrepared = items.every((item) {
        final status =
            (item['status'] as String?)?.toLowerCase().trim() ?? 'ordered';
        return status == 'prepared';
      });
      final forcePreparing = hasPrepared && !allPrepared;
      final alertMeta = _resolveKitchenCombinedAlertMeta(
        startedAt,
        allPrepared: allPrepared,
        forcePreparing: forcePreparing,
      );
      final totalQty = items.fold<int>(
        0,
        (sum, item) => sum + _resolveKitchenItemQuantity(item),
      );

      cards.add({
        'group': rawGroup,
        'items': items,
        'startedAt': startedAt,
        'totalQty': totalQty,
        'alertPriority': alertMeta['priority'],
        'alertMeta': alertMeta,
      });
    }

    cards.sort((a, b) {
      final priorityDiff = ((b['alertPriority'] as int?) ?? 0).compareTo(
        (a['alertPriority'] as int?) ?? 0,
      );
      if (priorityDiff != 0) return priorityDiff;

      final aStartedAt = a['startedAt'] as DateTime?;
      final bStartedAt = b['startedAt'] as DateTime?;
      if (aStartedAt == null && bStartedAt == null) return 0;
      if (aStartedAt == null) return 1;
      if (bStartedAt == null) return -1;
      return aStartedAt.compareTo(bStartedAt);
    });

    return cards;
  }

  DateTime? _resolveKitchenGroupStartedAt(
    Map<String, dynamic> group,
    List<Map<String, dynamic>> items,
  ) {
    final now = DateTime.now();
    int? maxElapsedSeconds;

    for (final item in items) {
      final elapsedSeconds = _resolveKitchenElapsedSeconds(
        item,
        fallbackStartedAt: group['createdAt'],
        allowBillingFallback: false,
      );
      if (elapsedSeconds == null) continue;
      if (maxElapsedSeconds == null || elapsedSeconds > maxElapsedSeconds) {
        maxElapsedSeconds = elapsedSeconds;
      }
    }

    if (maxElapsedSeconds != null) {
      return now.subtract(Duration(seconds: maxElapsedSeconds));
    }

    DateTime? startedAt;

    for (final item in items) {
      final itemStartedAt = _parseKitchenOrderStartedAt(
        item,
        fallbackStartedAt: group['createdAt'],
      );

      if (itemStartedAt == null) continue;
      if (startedAt == null || itemStartedAt.isBefore(startedAt)) {
        startedAt = itemStartedAt;
      }
    }

    return startedAt ?? _tryParseKitchenDateTime(group['createdAt']);
  }

  Map<String, dynamic> _resolveKitchenCombinedAlertMeta(
    DateTime? startedAt, {
    bool allPrepared = false,
    bool forcePreparing = false,
  }) {
    if (allPrepared) {
      return {
        'priority': -1,
        'label': 'ALL DONE',
        'accentColor': const Color(0xFF2E7D32),
        'badgeColor': const Color(0xFF2E7D32),
        'badgeTextColor': Colors.white,
        'surfaceColor': const Color(0xFFE5F3E8),
        'borderColor': const Color(0xFF9CCC65),
      };
    }

    if (forcePreparing) {
      return {
        'priority': 2,
        'label': 'PREPARING',
        'accentColor': const Color(0xFF9D6D00),
        'badgeColor': const Color(0xFFF0E2A4),
        'badgeTextColor': const Color(0xFF9D6D00),
        'surfaceColor': const Color(0xFFFFF7DD),
        'borderColor': const Color(0xFFFFCC80),
      };
    }

    final minutes = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inMinutes;

    if (minutes >= 10) {
      return {
        'priority': 3,
        'label': 'DELAYED',
        'accentColor': const Color(0xFFC62828),
        'badgeColor': const Color(0xFFC62828),
        'badgeTextColor': Colors.white,
        'surfaceColor': const Color(0xFFFFEBEE),
        'borderColor': const Color(0xFFEF9A9A),
      };
    }

    if (minutes >= 5) {
      return {
        'priority': 2,
        'label': 'PREPARING',
        'accentColor': const Color(0xFF9D6D00),
        'badgeColor': const Color(0xFFF0E2A4),
        'badgeTextColor': const Color(0xFF9D6D00),
        'surfaceColor': const Color(0xFFFFF7DD),
        'borderColor': const Color(0xFFFFCC80),
      };
    }

    if (minutes >= 2) {
      return {
        'priority': 1,
        'label': 'WAITING',
        'accentColor': const Color(0xFF455A64),
        'badgeColor': const Color(0xFF455A64),
        'badgeTextColor': Colors.white,
        'surfaceColor': const Color(0xFFECEFF1),
        'borderColor': const Color(0xFFB0BEC5),
      };
    }

    return {
      'priority': 0,
      'label': 'NEW',
      'accentColor': const Color(0xFF37474F),
      'badgeColor': const Color(0xFFE0E0E0),
      'badgeTextColor': const Color(0xFF424242),
      'surfaceColor': const Color(0xFFF5F5F5),
      'borderColor': const Color(0xFFE0E0E0),
    };
  }

  String _formatKitchenTableLabel(dynamic rawTableNumber) {
    final raw = rawTableNumber?.toString().trim() ?? '';
    if (raw.isEmpty) return 'TABLE';

    final numeric = int.tryParse(raw);
    if (numeric != null) {
      return 'TABLE_${numeric.toString().padLeft(2, '0')}';
    }

    return 'TABLE_${raw.toUpperCase().replaceAll(RegExp(r'\s+'), '_')}';
  }

  String _formatKitchenKotBadgeLabel(Map<String, dynamic> group) {
    final resolvedKot = _resolveKitchenKotLabel(group).trim().toUpperCase();
    if (resolvedKot.isEmpty) return '';

    final match = RegExp(r'KOT[-\s]?(\d+)').firstMatch(resolvedKot);
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!);
      final suffix = parsed?.toString().padLeft(2, '0') ?? match.group(1)!;
      return 'KOT-$suffix';
    }

    final compact = resolvedKot.replaceAll(RegExp(r'\s+'), '');
    if (compact.startsWith('KOT') && !compact.contains('-')) {
      final suffix = compact.substring(3);
      if (suffix.isEmpty) return 'KOT';
      final parsed = int.tryParse(suffix);
      final normalized = parsed?.toString().padLeft(2, '0') ?? suffix;
      return 'KOT-$normalized';
    }

    return compact;
  }

  String _formatKitchenAgoLabel(
    DateTime? startedAt, {
    DateTime? endedAt,
    bool includeAgoSuffix = true,
  }) {
    if (startedAt == null) return '--';
    final effectiveEnd = endedAt ?? DateTime.now();
    final diff = effectiveEnd.difference(startedAt);
    final safeSeconds = diff.inSeconds < 0 ? 0 : diff.inSeconds;
    final suffix = includeAgoSuffix ? ' ago' : '';
    if (safeSeconds >= 3600) return '${safeSeconds ~/ 3600}h$suffix';
    if (safeSeconds >= 60) return '${safeSeconds ~/ 60}m$suffix';
    return '${safeSeconds}s$suffix';
  }

  Widget _buildKitchenCombinedOrderCard(Map<String, dynamic> cardData) {
    final group = cardData['group'] as Map<String, dynamic>? ?? const {};
    final items = List<Map<String, dynamic>>.from(
      (cardData['items'] as List?) ?? const [],
    );
    final startedAt = cardData['startedAt'] as DateTime?;
    final alertMeta =
        cardData['alertMeta'] as Map<String, dynamic>? ?? const {};
    final table = group['tableDetails'] ?? {};
    final tableNumber = (table is Map ? table['tableNumber'] : table)
        ?.toString()
        .trim();
    final tableLabel = _formatKitchenTableLabel(tableNumber);
    final kotBadgeLabel = _formatKitchenKotBadgeLabel(group);
    final waiterName = (group['waiterName'] ?? '').toString().trim();
    final createdByName = (group['createdByName'] ?? '').toString().trim();
    final customerName = (group['customerName'] ?? '').toString().trim();
    final normalizedTableLabel = tableLabel.replaceAll('_', '-');
    final waiterLooksLikeLocation = _isKitchenLocationLikeName(waiterName);
    final createdByLooksLikeLocation = _isKitchenLocationLikeName(
      createdByName,
    );
    final effectiveWaiterName = waiterLooksLikeLocation ? '' : waiterName;
    final hasCustomerName =
        customerName.isNotEmpty &&
        customerName.toLowerCase() != 'customer' &&
        customerName.toLowerCase() != 'guest';
    final hasWaiterName =
        effectiveWaiterName.isNotEmpty &&
        effectiveWaiterName.toLowerCase() != 'waiter';
    // QR-style orders are usually created by branch/location; show customer there.
    final showCustomerName =
        (createdByLooksLikeLocation && hasCustomerName) ||
        (!hasWaiterName && hasCustomerName);
    final showWaiterName = !showCustomerName && hasWaiterName;
    final waiterLabel = effectiveWaiterName.toUpperCase();
    final customerLabel = customerName.toUpperCase();
    final elapsedLabel = startedAt == null
        ? '0m'
        : (_formatKitchenElapsedTime({
                'createdAt': startedAt.toIso8601String(),
              }, allowBillingFallback: false) ??
              '0m');
    final elapsedColor = _getKitchenElapsedTimeColor({
      'createdAt': startedAt?.toIso8601String(),
    }, allowBillingFallback: false);
    final accentColor =
        (alertMeta['accentColor'] as Color?) ?? const Color(0xFF37474F);
    final badgeColor =
        (alertMeta['badgeColor'] as Color?) ?? const Color(0xFFE0E0E0);
    final badgeTextColor =
        (alertMeta['badgeTextColor'] as Color?) ?? const Color(0xFF424242);
    final surfaceColor =
        (alertMeta['surfaceColor'] as Color?) ?? const Color(0xFFF5F5F5);
    final borderColor =
        (alertMeta['borderColor'] as Color?) ?? const Color(0xFFE0E0E0);
    final alertLabel = (alertMeta['label'] ?? 'NEW').toString();
    const commonPersonColor = Color(0xFF263238);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  normalizedTableLabel,
                                  style: const TextStyle(
                                    color: Color(0xFFFFD54F),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              if (kotBadgeLabel.isNotEmpty)
                                const SizedBox(width: 6),
                              if (kotBadgeLabel.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF263238),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    kotBadgeLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            alertLabel,
                            style: TextStyle(
                              color: badgeTextColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            TextSpan(
                              children: [
                                if (showCustomerName) ...[
                                  const TextSpan(
                                    text: 'CUSTOMER: ',
                                    style: TextStyle(
                                      color: commonPersonColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  TextSpan(
                                    text: customerLabel,
                                    style: const TextStyle(
                                      color: commonPersonColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                                if (showWaiterName) ...[
                                  const TextSpan(
                                    text: 'WAITER: ',
                                    style: TextStyle(
                                      color: commonPersonColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  TextSpan(
                                    text: waiterLabel,
                                    style: const TextStyle(
                                      color: commonPersonColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                                if (!showWaiterName && !showCustomerName)
                                  const TextSpan(
                                    text: 'CUSTOMER: WALK-IN',
                                    style: TextStyle(
                                      color: commonPersonColor,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: elapsedColor,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            elapsedLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xFFFAFAFA),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                children: [
                  for (int i = 0; i < items.length; i++)
                    _buildKitchenCombinedOrderLine(
                      items[i],
                      fallbackStartedAt: group['createdAt'],
                      quantityColor: accentColor,
                      showDivider: i != items.length - 1,
                    ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                border: Border(
                  top: BorderSide(color: Colors.black.withValues(alpha: 0.07)),
                ),
              ),
              child: _buildKitchenCombinedOrderActions(alertLabel: alertLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKitchenCombinedOrderLine(
    Map<String, dynamic> item, {
    dynamic fallbackStartedAt,
    required Color quantityColor,
    required bool showDivider,
  }) {
    final product = item['product'];
    final rawName =
        (item['name'] ?? (product is Map ? product['name'] : null) ?? 'Item')
            .toString();
    final unit = (product is Map ? product['unit'] : null)?.toString() ?? '';
    final productName = _formatKitchenProductName(
      (unit.isNotEmpty ? '$rawName ($unit)' : rawName).toUpperCase(),
    );
    final instruction = _resolveKitchenItemInstruction(item, product);
    final quantity = _resolveKitchenItemQuantity(item);
    final status = (item['status'] as String?)?.toLowerCase().trim() ?? '';
    final isPrepared = status == 'prepared';
    final isCancelled = status == 'cancelled' || status == 'canceled';
    final elapsedLabel =
        _formatKitchenElapsedTime(item, fallbackStartedAt: fallbackStartedAt) ??
        '--';
    final elapsedColor = _getKitchenElapsedTimeColor(
      item,
      fallbackStartedAt: fallbackStartedAt,
    );
    final startedAt = _parseKitchenOrderStartedAt(
      item,
      fallbackStartedAt: fallbackStartedAt,
    );
    final finalizedAt = _parseKitchenOrderFinalizedAt(item);
    final startedLabel = startedAt == null
        ? '--:--'
        : DateFormat('HH:mm').format(startedAt);
    final agoLabel = _formatKitchenAgoLabel(
      startedAt,
      endedAt: finalizedAt,
      includeAgoSuffix: finalizedAt == null,
    );
    final selectionKey = item['selectionKey']?.toString();
    final isSelected =
        selectionKey != null && _selectedKitchenItemKeys.contains(selectionKey);
    final shouldStrike = isSelected || isPrepared || isCancelled;
    final quantityDisplayColor = isCancelled
        ? const Color(0xFFC62828)
        : isPrepared
        ? const Color(0xFF8E8E8E)
        : quantityColor;
    final productDisplayColor = isCancelled
        ? const Color(0xFFC62828)
        : isPrepared
        ? const Color(0xFF8E8E8E)
        : const Color(0xFF212121);
    final metaIconColor = isCancelled
        ? const Color(0xFFE57373)
        : isPrepared
        ? const Color(0xFFB0B0B0)
        : elapsedColor;
    final metaTextColor = isCancelled
        ? const Color(0xFFE57373)
        : isPrepared
        ? const Color(0xFFB0B0B0)
        : elapsedColor;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: (isPrepared || isCancelled)
          ? null
          : () => _selectKitchenItem(item),
      onDoubleTap: (isPrepared || isCancelled)
          ? null
          : () => _onKitchenItemTapped(item, requirePreselected: false),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${quantity}x',
                  style: TextStyle(
                    color: quantityDisplayColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 34,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: productDisplayColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      decoration: shouldStrike
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationThickness: 2.0,
                      decorationColor: isCancelled
                          ? const Color(0xFFC62828)
                          : isPrepared
                          ? const Color(0xFF9E9E9E)
                          : const Color(0xFF2E7D32),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (isCancelled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC62828),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Text(
                      'CANCELLED',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 0.8,
                      ),
                    ),
                  )
                else if (shouldStrike)
                  Icon(
                    Icons.check_circle_rounded,
                    color: isPrepared
                        ? const Color(0xFF6BAE95)
                        : const Color(0xFF2E7D32),
                    size: 22,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 12,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 4),
                Text(
                  startedLabel,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.timer_outlined, size: 12, color: metaIconColor),
                const SizedBox(width: 4),
                Text(
                  agoLabel,
                  style: TextStyle(
                    color: metaTextColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  elapsedLabel,
                  style: TextStyle(
                    color: metaTextColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            if (instruction != null && instruction.isNotEmpty) ...[
              const SizedBox(height: 7),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F1F1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SPECIAL: $instruction',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFC62828),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
            if (showDivider) ...[
              const SizedBox(height: 9),
              Divider(height: 1, color: Colors.black.withValues(alpha: 0.08)),
              const SizedBox(height: 9),
            ] else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildKitchenCombinedOrderActions({required String alertLabel}) {
    if (alertLabel == 'PREPARING') {
      return _buildKitchenCombinedActionButton(
        label: 'PREAPARING',
        icon: Icons.check_circle_outline_rounded,
        backgroundColor: const Color(0xFFF4BC00),
        foregroundColor: const Color(0xFF1E1E1E),
        onTap: () => _handleKitchenCombinedCardAction(action: 'complete'),
      );
    }

    String label = 'START PREPPING';
    IconData icon = Icons.play_arrow_rounded;
    Color bg = const Color(0xFF1D1D25);
    Color fg = Colors.white;
    String action = 'start';

    if (alertLabel == 'DELAYED') {
      label = 'EXPEDITE IMMEDIATELY';
      icon = Icons.flash_on_rounded;
      bg = const Color(0xFFC9181D);
      action = 'expedite';
    } else if (alertLabel == 'ALL DONE') {
      label = 'ALL DONE';
      icon = Icons.check_circle_rounded;
      bg = const Color(0xFF2E7D32);
      action = 'done';
    } else if (alertLabel == 'WAITING') {
      label = 'START PREPPING';
      icon = Icons.play_arrow_rounded;
      bg = const Color(0xFF1D1D25);
      action = 'start';
    }

    return _buildKitchenCombinedActionButton(
      label: label,
      icon: icon,
      backgroundColor: bg,
      foregroundColor: fg,
      onTap: () => _handleKitchenCombinedCardAction(action: action),
    );
  }

  Widget _buildKitchenCombinedActionButton({
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 44,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foregroundColor, size: 15),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleKitchenCombinedCardAction({required String action}) {
    if (!mounted) return;

    switch (action) {
      case 'complete':
      case 'complete_order':
        _showKitchenCombinedSnack(
          'Tap once to select, then double tap to mark prepared.',
        );
        break;
      case 'expedite':
        _showKitchenCombinedSnack(
          'Expedite alert acknowledged for this table.',
          color: const Color(0xFFC62828),
        );
        break;
      case 'done':
        _showKitchenCombinedSnack(
          'All items are prepared for this table.',
          color: const Color(0xFF2E7D32),
        );
        break;
      default:
        _showKitchenCombinedSnack(
          'Start prepping by selecting an item, then double tap to confirm.',
        );
    }
  }

  void _showKitchenCombinedSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _handleKitchenFooterSelection(KitchenFooterTab tab) {
    switch (tab) {
      case KitchenFooterTab.kot:
        _toggleKitchenKotView();
        break;
      case KitchenFooterTab.stock:
        _showKitchenStockProducts();
        break;
      case KitchenFooterTab.review:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (routeContext) => ReviewListScreen(
              showKitchenFooter: true,
              onKotTap: _returnToKitchenKotFromNestedScreen,
              onStockTap: _openKitchenStockFromNestedScreen,
            ),
          ),
        );
        break;
      case KitchenFooterTab.chats:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (routeContext) => KitchenChatsScreen(
              onKotTap: _returnToKitchenKotFromNestedScreen,
              onStockTap: _openKitchenStockFromNestedScreen,
              onReviewTap: () {
                Navigator.pushReplacement(
                  routeContext,
                  MaterialPageRoute(
                    builder: (context) => ReviewListScreen(
                      showKitchenFooter: true,
                      onKotTap: _returnToKitchenKotFromNestedScreen,
                      onStockTap: _openKitchenStockFromNestedScreen,
                    ),
                  ),
                );
              },
            ),
          ),
        );
        break;
    }
  }

  void _returnToKitchenKotFromNestedScreen() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openKitchenStockFromNestedScreen() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showKitchenStockProducts();
    });
  }

  Future<void> _showKitchenStockProducts() async {
    String searchQuery = '';
    String? selectedCategoryId;
    String selectedCategoryName = '';

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (_cachedStockCategories == null ||
                _cachedStockProductsByCategory.isEmpty) {
              Future.microtask(() async {
                try {
                  final kitchens = await ApiService.instance.fetchKitchens();
                  final liveK1 = kitchens.firstWhere(
                    (k) =>
                        (k['name'] ?? '').toString().toLowerCase() == 'live-k1',
                    orElse: () => null,
                  );

                  if (liveK1 == null) {
                    if (context.mounted) Navigator.pop(context);
                    return;
                  }

                  final categories = (liveK1['categories'] as List?) ?? [];
                  final List<String> categoryIds = [];
                  for (var cat in categories) {
                    final id = (cat is Map ? (cat['id'] ?? cat['_id']) : cat)
                        ?.toString();
                    if (id != null) categoryIds.add(id);
                  }

                  if (categoryIds.isEmpty) {
                    if (context.mounted) Navigator.pop(context);
                    return;
                  }

                  final categoryDocs = await ApiService.instance
                      .fetchCategories(onlyStock: true);
                  final products = await ApiService.instance.fetchProducts(
                    categoryIds: categoryIds,
                  );

                  final filteredCategories = categoryDocs.where((rawCategory) {
                    if (rawCategory is! Map) return false;
                    final categoryId = (rawCategory['id'] ?? rawCategory['_id'])
                        ?.toString();
                    return categoryId != null &&
                        categoryIds.contains(categoryId);
                  }).toList();

                  filteredCategories.sort((a, b) {
                    final aName = (a['name'] ?? '').toString().toLowerCase();
                    final bName = (b['name'] ?? '').toString().toLowerCase();
                    return aName.compareTo(bName);
                  });

                  final groupedProducts = <String, List<dynamic>>{};
                  for (final rawProduct in products) {
                    if (rawProduct is! Map) continue;

                    String categoryId = '';
                    final category = rawProduct['category'];
                    if (category is Map) {
                      categoryId =
                          (category['id'] ??
                                  category['_id'] ??
                                  category['value'])
                              ?.toString()
                              .trim() ??
                          '';
                    } else if (category is String) {
                      categoryId = category.trim();
                    } else if (category != null) {
                      categoryId = category.toString().trim();
                    }

                    if (categoryId.isEmpty) continue;
                    groupedProducts.putIfAbsent(categoryId, () => []);
                    groupedProducts[categoryId]!.add(rawProduct);
                  }

                  for (final entries in groupedProducts.values) {
                    entries.sort((a, b) {
                      final aName = ((a is Map ? a['name'] : null) ?? '')
                          .toString()
                          .toLowerCase();
                      final bName = ((b is Map ? b['name'] : null) ?? '')
                          .toString()
                          .toLowerCase();
                      return aName.compareTo(bName);
                    });
                  }

                  if (context.mounted) {
                    setSheetState(() {
                      _cachedStockCategories = filteredCategories;
                      _cachedStockProductsByCategory
                        ..clear()
                        ..addAll(groupedProducts);
                    });
                  }
                } catch (e) {
                  if (context.mounted) Navigator.pop(context);
                }
              });
            }

            final categories = (_cachedStockCategories ?? [])
                .cast<Map<String, dynamic>>();
            final selectedProducts = selectedCategoryId == null
                ? <dynamic>[]
                : (_cachedStockProductsByCategory[selectedCategoryId!] ??
                      <dynamic>[]);

            String stockProductId(dynamic rawProduct) {
              if (rawProduct is! Map) return '';
              return (rawProduct['id'] ?? rawProduct['_id'])
                      ?.toString()
                      .trim() ??
                  '';
            }

            bool stockProductIsOut(dynamic rawProduct) {
              if (rawProduct is! Map) return false;
              final isStock = rawProduct['isStock'];
              if (isStock is bool) {
                return !isStock;
              }
              return rawProduct['isOutOfStock'] == true;
            }

            String stockProductName(dynamic rawProduct) {
              if (rawProduct is! Map) return '';
              return (rawProduct['name'] ?? '').toString().toLowerCase();
            }

            final normalizedQuery = searchQuery.trim().toLowerCase();
            final filteredProducts = selectedProducts.where((rawProduct) {
              if (rawProduct is! Map) return false;
              final product = Map<String, dynamic>.from(rawProduct);
              if (normalizedQuery.isEmpty) return true;

              final name = (product['name'] ?? '').toString().toLowerCase();
              final description = (product['description'] ?? '')
                  .toString()
                  .toLowerCase();
              return name.contains(normalizedQuery) ||
                  description.contains(normalizedQuery);
            }).toList();
            filteredProducts.sort((a, b) {
              final aOut = stockProductIsOut(a);
              final bOut = stockProductIsOut(b);
              if (aOut != bOut) {
                return aOut ? -1 : 1;
              }

              if (aOut) {
                final aId = stockProductId(a);
                final bId = stockProductId(b);
                final aOrder = _stockOutOrderByProductId[aId] ?? 1 << 30;
                final bOrder = _stockOutOrderByProductId[bId] ?? 1 << 30;
                if (aOrder != bOrder) {
                  return aOrder.compareTo(bOrder);
                }
              }

              return stockProductName(a).compareTo(stockProductName(b));
            });

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                if (selectedCategoryId != null)
                                  IconButton(
                                    onPressed: () {
                                      setSheetState(() {
                                        selectedCategoryId = null;
                                        selectedCategoryName = '';
                                        searchQuery = '';
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                    ),
                                  ),
                                Text(
                                  selectedCategoryId == null
                                      ? 'STOCK CATEGORIES'
                                      : selectedCategoryName.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: () {
                                setSheetState(() {
                                  _cachedStockCategories = null;
                                  _cachedStockProductsByCategory.clear();
                                  selectedCategoryId = null;
                                  selectedCategoryName = '';
                                  searchQuery = '';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Text(
                                      'Live-k1',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.refresh,
                                      size: 14,
                                      color: Colors.red,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _cachedStockCategories == null
                            ? const Center(child: CircularProgressIndicator())
                            : selectedCategoryId == null
                            ? GridView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  18,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 0.78,
                                    ),
                                itemCount: categories.length,
                                itemBuilder: (context, index) {
                                  final category = categories[index];
                                  final categoryId =
                                      (category['id'] ?? category['_id'])
                                          ?.toString()
                                          .trim() ??
                                      '';
                                  final categoryName =
                                      (category['name'] ?? 'CATEGORY')
                                          .toString();
                                  final imageUrl =
                                      _resolveKitchenCategoryImageUrl(category);

                                  return GestureDetector(
                                    onTap: () {
                                      if (categoryId.isEmpty) return;

                                      setSheetState(() {
                                        selectedCategoryId = categoryId;
                                        selectedCategoryName = categoryName;
                                        searchQuery = '';
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.04,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                    top: Radius.circular(14),
                                                  ),
                                              child: imageUrl != null
                                                  ? Image.network(
                                                      imageUrl,
                                                      fit: BoxFit.cover,
                                                      width: double.infinity,
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            error,
                                                            stackTrace,
                                                          ) {
                                                            return Container(
                                                              color: Colors
                                                                  .grey[200],
                                                              child: const Icon(
                                                                Icons
                                                                    .inventory_2_rounded,
                                                                color:
                                                                    Colors.grey,
                                                              ),
                                                            );
                                                          },
                                                    )
                                                  : Container(
                                                      color: Colors.grey[200],
                                                      child: const Icon(
                                                        Icons
                                                            .inventory_2_rounded,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 10,
                                            ),
                                            child: Text(
                                              categoryName.toUpperCase(),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 11,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              )
                            : Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    child: TextField(
                                      onChanged: (value) {
                                        setSheetState(() {
                                          searchQuery = value;
                                        });
                                      },
                                      decoration: InputDecoration(
                                        hintText: 'Search products...',
                                        prefixIcon: const Icon(Icons.search),
                                        isDense: true,
                                        filled: true,
                                        fillColor: Colors.grey[100],
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 12,
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: selectedProducts.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No products found in this category.',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          )
                                        : filteredProducts.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No matching products found.',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          )
                                        : ListView.separated(
                                            controller: scrollController,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 10,
                                            ),
                                            itemCount: filteredProducts.length,
                                            separatorBuilder:
                                                (context, index) =>
                                                    const Divider(height: 32),
                                            itemBuilder: (context, index) {
                                              final product =
                                                  filteredProducts[index];
                                              final name =
                                                  (product['name'] ?? 'N/A')
                                                      .toString()
                                                      .toUpperCase();
                                              final description =
                                                  (product['description'] ?? '')
                                                      .toString();
                                              bool isOutOfStock =
                                                  product['isStock'] is bool
                                                  ? !(product['isStock']
                                                        as bool)
                                                  : product['isOutOfStock'] ==
                                                        true;

                                              return Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          name,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                height: 1.1,
                                                                color: Color(
                                                                  0xFF1A1A1A,
                                                                ),
                                                              ),
                                                        ),
                                                        if (description
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          Text(
                                                            description,
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              color: Colors
                                                                  .grey[500],
                                                              height: 1.3,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  _buildStockSwitch(
                                                    isOn: !isOutOfStock,
                                                    onChanged: (val) async {
                                                      final previousIsOutOfStock =
                                                          product['isStock']
                                                              is bool
                                                          ? !(product['isStock']
                                                                as bool)
                                                          : product['isOutOfStock'] ==
                                                                true;
                                                      final previousIsStock =
                                                          product['isStock']
                                                              is bool
                                                          ? product['isStock']
                                                                as bool
                                                          : !previousIsOutOfStock;
                                                      final productId =
                                                          (product['id'] ??
                                                                  product['_id'])
                                                              ?.toString()
                                                              .trim() ??
                                                          '';
                                                      final previousOutOrder =
                                                          _stockOutOrderByProductId[productId];

                                                      if (productId.isEmpty) {
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            const SnackBar(
                                                              content: Text(
                                                                'Unable to update this product right now.',
                                                              ),
                                                              backgroundColor:
                                                                  Colors.red,
                                                            ),
                                                          );
                                                        }
                                                        return;
                                                      }

                                                      setSheetState(() {
                                                        if (!val) {
                                                          _stockOutOrderByProductId
                                                              .putIfAbsent(
                                                                productId,
                                                                () {
                                                                  _stockOutOrderCounter +=
                                                                      1;
                                                                  return _stockOutOrderCounter;
                                                                },
                                                              );
                                                        } else {
                                                          _stockOutOrderByProductId
                                                              .remove(
                                                                productId,
                                                              );
                                                        }
                                                        product['isStock'] =
                                                            val;
                                                        product['isOutOfStock'] =
                                                            !val;
                                                      });
                                                      try {
                                                        final savedIsOutOfStock =
                                                            await ApiService
                                                                .instance
                                                                .updateProductStockStatus(
                                                                  productId,
                                                                  !val,
                                                                );
                                                        setSheetState(() {
                                                          if (savedIsOutOfStock) {
                                                            _stockOutOrderByProductId
                                                                .putIfAbsent(
                                                                  productId,
                                                                  () {
                                                                    _stockOutOrderCounter +=
                                                                        1;
                                                                    return _stockOutOrderCounter;
                                                                  },
                                                                );
                                                          } else {
                                                            _stockOutOrderByProductId
                                                                .remove(
                                                                  productId,
                                                                );
                                                          }
                                                          product['isStock'] =
                                                              !savedIsOutOfStock;
                                                          product['isOutOfStock'] =
                                                              savedIsOutOfStock;
                                                        });
                                                      } catch (e) {
                                                        setSheetState(() {
                                                          if (previousOutOrder !=
                                                              null) {
                                                            _stockOutOrderByProductId[productId] =
                                                                previousOutOrder;
                                                          } else {
                                                            _stockOutOrderByProductId
                                                                .remove(
                                                                  productId,
                                                                );
                                                          }
                                                          product['isStock'] =
                                                              previousIsStock;
                                                          product['isOutOfStock'] =
                                                              previousIsOutOfStock;
                                                        });
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                'Stock update failed: $e',
                                                              ),
                                                              backgroundColor:
                                                                  Colors.red,
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    },
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStockSwitch({
    required bool isOn,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!isOn),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 85,
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isOn ? const Color(0xFF1A237E) : const Color(0xFFFFA726),
          boxShadow: [
            BoxShadow(
              color: (isOn ? const Color(0xFF1A237E) : const Color(0xFFFFA726))
                  .withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Align(
              alignment: isOn ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  isOn ? 'IN' : 'OUT',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    final createdByName = (group['createdByName'] ?? '').toString().trim();
    final customerName = (group['customerName'] ?? '').toString().trim();
    final waiterLooksLikeLocation = _isKitchenLocationLikeName(waiterName);
    final createdByLooksLikeLocation = _isKitchenLocationLikeName(
      createdByName,
    );
    final effectiveWaiterName = waiterLooksLikeLocation ? '' : waiterName;
    final hasCustomerName =
        customerName.isNotEmpty &&
        customerName.toLowerCase() != 'customer' &&
        customerName.toLowerCase() != 'guest' &&
        !_isKitchenPlaceholderCustomerName(customerName);
    final hasWaiterName =
        effectiveWaiterName.isNotEmpty &&
        effectiveWaiterName.toLowerCase() != 'waiter';
    final showCustomerName =
        (createdByLooksLikeLocation && hasCustomerName) ||
        (!hasWaiterName && hasCustomerName);
    final showWaiterName = !showCustomerName && hasWaiterName;
    final personSubtitle = showCustomerName
        ? 'CUSTOMER: ${customerName.toUpperCase()}'
        : showWaiterName
        ? 'WAITER: ${effectiveWaiterName.toUpperCase()}'
        : 'CUSTOMER: WALK-IN';
    final items = (group['items'] as List?) ?? [];
    final gridItems = items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
          final status =
              (item['status'] as String?)?.toLowerCase().trim() ?? 'ordered';
          return status == 'ordered';
        })
        .toList();
    gridItems.sort((a, b) {
      final aElapsed = _resolveKitchenElapsedSeconds(
        a,
        fallbackStartedAt: group['createdAt'],
        allowBillingFallback: false,
      );
      final bElapsed = _resolveKitchenElapsedSeconds(
        b,
        fallbackStartedAt: group['createdAt'],
        allowBillingFallback: false,
      );
      return (bElapsed ?? -1).compareTo(aElapsed ?? -1);
    });
    final gridTimingItems = List<Map<String, dynamic>>.from(gridItems);
    final allTimingItems = items.whereType<Map>().map((item) {
      return Map<String, dynamic>.from(item.cast<String, dynamic>());
    }).toList();
    final timingItems = gridTimingItems.isNotEmpty
        ? gridTimingItems
        : allTimingItems;
    final tableStartedAt = _resolveKitchenGroupStartedAt(group, timingItems);
    final tableTimerItem = tableStartedAt == null
        ? null
        : {'createdAt': tableStartedAt.toIso8601String()};
    final startedAtFallback =
        tableStartedAt?.toIso8601String() ?? group['createdAt'];
    final tableBadgeMainLabel = 'TABLE $tableNumber';

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                    const Spacer(),
                    if (tableTimerItem != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getKitchenElapsedTimeColor(tableTimerItem),
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
                              _formatKitchenElapsedTime(tableTimerItem) ?? '0s',
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
                const SizedBox(height: 7),
                Text(
                  personSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF263238),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5,
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
            itemCount: gridItems.length,
            itemBuilder: (context, index) {
              return _buildKitchenOrderCard(
                gridItems[index],
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

  String? _resolveKitchenCategoryImageUrl(dynamic category) {
    if (category is! Map) return null;

    String? imageUrl;
    imageUrl ??= _extractKitchenImageUrl(category['image']);
    imageUrl ??= _extractKitchenImageUrl(category['thumbnail']);

    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        !imageUrl.startsWith('http')) {
      imageUrl = 'https://blackforest.vseyal.com$imageUrl';
    }

    return (imageUrl == null || imageUrl.isEmpty) ? null : imageUrl;
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

  String _resolveKitchenCreatedByName(dynamic billing) {
    if (billing is! Map) return '';

    final candidates = [
      billing['createdByName'],
      billing['createdBy'],
      billing['creatorName'],
      billing['creator'],
      billing['createdUser'],
      billing['createdUserName'],
      billing['user'],
    ];

    for (final candidate in candidates) {
      final name = _extractKitchenPersonName(candidate);
      if (name != null && name.isNotEmpty) return name;
    }

    return '';
  }

  bool _isKitchenLocationLikeName(String value) {
    final normalized = value.trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (normalized.isEmpty) return true;
    if (normalized == 'WAITER') return true;
    if (normalized == 'ETTAYAPURAM RODA') return true;
    if (RegExp(r'\b(ROAD|RODA|STREET|BRANCH)\b').hasMatch(normalized)) {
      return true;
    }
    return false;
  }

  bool _isKitchenPlaceholderCustomerName(String value) {
    final normalized = value.trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (normalized.isEmpty) return true;

    const placeholders = {
      'WALK IN',
      'WALK-IN',
      'CUSTOMER',
      'GUEST',
      'NA',
      'N/A',
      'NONE',
      'UNKNOWN',
    };
    return placeholders.contains(normalized);
  }

  String _resolveKitchenCustomerName(dynamic billing) {
    if (billing is! Map) return '';

    final tableDetails = billing['tableDetails'];
    final customer = billing['customer'];
    final billDetails =
        billing['billDetails'] ??
        billing['billingDetails'] ??
        billing['billingDetail'] ??
        billing['billInfo'] ??
        billing['bill'];
    final customerDetails =
        billing['customerDetails'] ??
        billing['guestDetails'] ??
        billing['clientDetails'] ??
        billing['partyDetails'] ??
        billing['customerInfo'];
    final contactDetails =
        billing['contactDetails'] ??
        billing['contact'] ??
        billing['phoneDetails'];

    String? readPersonFromMap(dynamic rawMap) {
      if (rawMap is! Map) return null;

      const personAliases = [
        'customerName',
        'customerFullName',
        'customerDisplayName',
        'guestName',
        'clientName',
        'partyName',
        'contactName',
        'orderedByName',
        'fullName',
        'displayName',
        'name',
        'label',
      ];

      for (final alias in personAliases) {
        final raw = _readKitchenMapValueByAliases(rawMap, [alias]);
        final name = _extractKitchenPersonName(raw);
        if (name == null || name.isEmpty) continue;
        if (_isKitchenPlaceholderCustomerName(name)) continue;
        return name;
      }

      final linkedCustomer = _readKitchenMapValueByAliases(rawMap, [
        'customer',
        'customerDetails',
        'guest',
        'guestDetails',
        'client',
        'party',
        'contact',
      ]);
      final linkedName = _extractKitchenPersonName(linkedCustomer);
      if (linkedName != null &&
          linkedName.isNotEmpty &&
          !_isKitchenPlaceholderCustomerName(linkedName)) {
        return linkedName;
      }

      return null;
    }

    final candidates = [
      billing['customerName'],
      billing['customerFullName'],
      billing['customerDisplayName'],
      billing['guestName'],
      billing['clientName'],
      billing['contactName'],
      billing['orderedByName'],
      billing['orderedBy'],
      customer,
      customerDetails,
      billDetails,
      contactDetails,
      if (customer is Map) ...[
        customer['name'],
        customer['fullName'],
        customer['displayName'],
        customer['userName'],
      ],
      if (customerDetails is Map) ...[
        customerDetails['customerName'],
        customerDetails['name'],
        customerDetails['fullName'],
        customerDetails['displayName'],
      ],
      if (billDetails is Map) ...[
        billDetails['customerName'],
        billDetails['customer'],
        billDetails['guestName'],
        billDetails['name'],
      ],
      if (tableDetails is Map) ...[
        tableDetails['customerName'],
        tableDetails['guestName'],
        tableDetails['occupiedBy'],
      ],
    ];

    for (final candidate in candidates) {
      final name = _extractKitchenPersonName(candidate);
      if (name == null || name.isEmpty) continue;
      if (_isKitchenPlaceholderCustomerName(name)) continue;
      return name;
    }

    final nestedCandidates = [
      customer,
      customerDetails,
      billDetails,
      tableDetails,
      contactDetails,
    ];
    for (final nested in nestedCandidates) {
      final name = readPersonFromMap(nested);
      if (name != null && name.isNotEmpty) return name;
    }

    return '';
  }

  String _normalizeKitchenDateKey(String key) {
    return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  DateTime? _tryParseKitchenDateTime(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value.toLocal();

    if (value is num) {
      final asInt = value.round();
      final millis = asInt > 9999999999 ? asInt : asInt * 1000;
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
    }

    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

      final numeric = int.tryParse(raw);
      if (numeric != null) {
        final millis = numeric > 9999999999 ? numeric : numeric * 1000;
        return DateTime.fromMillisecondsSinceEpoch(
          millis,
          isUtc: true,
        ).toLocal();
      }

      final isoParsed = DateTime.tryParse(raw)?.toLocal();
      if (isoParsed != null) return isoParsed;

      const patterns = [
        'dd/MM/yyyy HH:mm:ss',
        'dd/MM/yyyy HH:mm',
        'd/M/yyyy HH:mm:ss',
        'd/M/yyyy HH:mm',
        'dd-MM-yyyy HH:mm:ss',
        'dd-MM-yyyy HH:mm',
        'd-M-yyyy HH:mm:ss',
        'd-M-yyyy HH:mm',
        'yyyy/MM/dd HH:mm:ss',
        'yyyy/MM/dd HH:mm',
        'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-dd HH:mm',
        'dd/MM/yyyy hh:mm:ss a',
        'dd/MM/yyyy hh:mm a',
        'd/M/yyyy hh:mm:ss a',
        'd/M/yyyy hh:mm a',
        'dd-MM-yyyy hh:mm:ss a',
        'dd-MM-yyyy hh:mm a',
        'd-M-yyyy hh:mm:ss a',
        'd-M-yyyy hh:mm a',
        'M/d/yyyy h:mm:ss a',
        'M/d/yyyy h:mm a',
        'MM/dd/yyyy h:mm:ss a',
        'MM/dd/yyyy h:mm a',
        'M/d/yyyy, h:mm:ss a',
        'M/d/yyyy, h:mm a',
        'MM/dd/yyyy, h:mm:ss a',
        'MM/dd/yyyy, h:mm a',
      ];
      for (final pattern in patterns) {
        try {
          return DateFormat(pattern).parseLoose(raw).toLocal();
        } catch (_) {
          // Continue trying other patterns.
        }
      }

      return null;
    }

    if (value is Map) {
      const nestedKeys = [
        'date',
        'time',
        'at',
        'value',
        'timestamp',
        'createdAt',
        'updatedAt',
      ];
      for (final key in nestedKeys) {
        final nested = value[key];
        final parsed = _tryParseKitchenDateTime(nested);
        if (parsed != null) return parsed;
      }
      return null;
    }

    if (value is List) {
      for (final entry in value) {
        final parsed = _tryParseKitchenDateTime(entry);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  dynamic _readKitchenMapValueByAliases(Map map, List<String> aliases) {
    for (final alias in aliases) {
      if (map.containsKey(alias)) return map[alias];
    }

    final normalizedAliases = aliases.map(_normalizeKitchenDateKey).toSet();
    for (final entry in map.entries) {
      final rawKey = entry.key;
      if (rawKey is! String) continue;
      final normalizedKey = _normalizeKitchenDateKey(rawKey);
      if (normalizedAliases.contains(normalizedKey)) {
        return entry.value;
      }
    }

    return null;
  }

  DateTime? _extractKitchenTimestampFromMap(Map map, List<String> aliases) {
    final raw = _readKitchenMapValueByAliases(map, aliases);
    return _tryParseKitchenDateTime(raw);
  }

  DateTime? _extractKitchenStatusTimelineTimestamp(
    Map item,
    Set<String> targetStatuses,
  ) {
    const timelineAliases = [
      'statusHistory',
      'statusLogs',
      'history',
      'timeline',
      'events',
      'eventLogs',
      'activities',
      'activityLogs',
      'tracking',
      'trackings',
    ];
    const statusAliases = [
      'status',
      'state',
      'event',
      'action',
      'type',
      'toStatus',
      'nextStatus',
      'label',
      'name',
    ];
    const timeAliases = [
      'at',
      'time',
      'date',
      'timestamp',
      'createdAt',
      'updatedAt',
      'statusUpdatedAt',
    ];

    for (final alias in timelineAliases) {
      final timeline = _readKitchenMapValueByAliases(item, [alias]);
      if (timeline is! List) continue;

      for (final entry in timeline) {
        if (entry is! Map) continue;
        final rawStatus = _readKitchenMapValueByAliases(entry, statusAliases);
        final status = rawStatus?.toString().toLowerCase().trim() ?? '';
        if (!targetStatuses.contains(status)) continue;

        final parsed = _extractKitchenTimestampFromMap(entry, timeAliases);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  DateTime? _parseKitchenOrderOrderedAt(
    dynamic item, {
    dynamic fallbackStartedAt,
    bool allowBillingFallback = true,
  }) {
    if (item is! Map) {
      if (!allowBillingFallback) return null;
      return _tryParseKitchenDateTime(fallbackStartedAt);
    }

    const orderedAliases = [
      'itemStartedAt',
      'orderedAt',
      'orderedOn',
      'ordered_at',
      'orderAt',
      'orderOn',
      'order_at',
      'orderedTime',
      'orderTime',
      'createdAt',
      'addedAt',
      'timestamp',
    ];

    final direct = _extractKitchenTimestampFromMap(item, orderedAliases);
    if (direct != null) return direct;

    final timeline = _extractKitchenStatusTimelineTimestamp(item, {
      'ordered',
      'order',
      'pending',
      'new',
    });
    if (timeline != null) return timeline;

    if (!allowBillingFallback) return null;

    return _tryParseKitchenDateTime(item['billingCreatedAt']) ??
        _tryParseKitchenDateTime(item['orderCreatedAt']) ??
        _tryParseKitchenDateTime(fallbackStartedAt);
  }

  DateTime? _parseKitchenOrderStartedAt(
    dynamic item, {
    dynamic fallbackStartedAt,
    bool allowBillingFallback = true,
  }) {
    return _parseKitchenOrderOrderedAt(
          item,
          fallbackStartedAt: fallbackStartedAt,
          allowBillingFallback: allowBillingFallback,
        ) ??
        _tryParseKitchenDateTime(fallbackStartedAt);
  }

  DateTime? _parseKitchenOrderPreparedAt(dynamic item) {
    if (item is! Map) return null;

    final status = (item['status'] as String?)?.toLowerCase().trim() ?? '';
    if (status != 'prepared') return null;

    const preparedAliases = [
      'preparedAt',
      'preparedOn',
      'prepared_at',
      'preparedTime',
      'prepared_time',
      'prepareAt',
      'prepareOn',
      'prepare_at',
      'prepareTime',
    ];

    final direct = _extractKitchenTimestampFromMap(item, preparedAliases);
    if (direct != null) return direct;

    final timeline = _extractKitchenStatusTimelineTimestamp(item, {
      'prepared',
      'complete',
      'completed',
      'done',
    });
    if (timeline != null) return timeline;

    return _extractKitchenTimestampFromMap(item, [
      'statusUpdatedAt',
      'status_updated_at',
      'updatedAt',
      'updated_at',
    ]);
  }

  DateTime? _parseKitchenOrderFinalizedAt(dynamic item) {
    if (item is! Map) return null;

    final status = (item['status'] as String?)?.toLowerCase().trim() ?? '';
    final isPrepared = status == 'prepared';
    final isCancelled = status == 'cancelled' || status == 'canceled';
    if (!isPrepared && !isCancelled) return null;

    if (isPrepared) {
      final preparedAt = _parseKitchenOrderPreparedAt(item);
      if (preparedAt != null) return preparedAt;
    }

    if (isCancelled) {
      final cancelledAt = _extractKitchenTimestampFromMap(item, [
        'cancelledAt',
        'canceledAt',
        'cancelAt',
        'cancelledOn',
        'canceledOn',
        'cancelled_at',
        'canceled_at',
        'cancelledTime',
        'canceledTime',
      ]);
      if (cancelledAt != null) return cancelledAt;

      final cancelledTimeline = _extractKitchenStatusTimelineTimestamp(item, {
        'cancel',
        'cancelled',
        'canceled',
      });
      if (cancelledTimeline != null) return cancelledTimeline;
    }

    return _extractKitchenTimestampFromMap(item, [
      'statusUpdatedAt',
      'status_updated_at',
    ]);
  }

  int? _resolveKitchenElapsedSeconds(
    dynamic item, {
    dynamic fallbackStartedAt,
    bool allowBillingFallback = true,
  }) {
    if (item is Map) {
      final preparedMinutes = _extractKitchenIntMinutes(
        _readKitchenMapValueByAliases(item, [
          'preparedDurationMinutes',
          'prepared_duration_minutes',
          'preparationMinutes',
          'preparation_minutes',
        ]),
      );
      if (preparedMinutes != null && preparedMinutes >= 0) {
        return preparedMinutes * 60;
      }

      final status = (item['status'] as String?)?.toLowerCase().trim() ?? '';
      if (status != 'prepared') {
        final currentMinutes = _extractKitchenIntMinutes(
          _readKitchenMapValueByAliases(item, [
            'currentPreparationMinutes',
            'current_preparation_minutes',
          ]),
        );
        if (currentMinutes != null && currentMinutes >= 0) {
          return currentMinutes * 60;
        }
      }
    }

    final startedAt = _parseKitchenOrderOrderedAt(
      item,
      fallbackStartedAt: fallbackStartedAt,
      allowBillingFallback: allowBillingFallback,
    );
    if (startedAt == null) return null;

    var endAt = DateTime.now();
    final finalizedAt = _parseKitchenOrderFinalizedAt(item);
    if (finalizedAt != null && !finalizedAt.isBefore(startedAt)) {
      endAt = finalizedAt;
    }

    final totalSeconds = endAt.difference(startedAt).inSeconds;
    return totalSeconds < 0 ? 0 : totalSeconds;
  }

  String? _formatKitchenElapsedTime(
    dynamic item, {
    dynamic fallbackStartedAt,
    bool allowBillingFallback = true,
  }) {
    final safeSeconds = _resolveKitchenElapsedSeconds(
      item,
      fallbackStartedAt: fallbackStartedAt,
      allowBillingFallback: allowBillingFallback,
    );
    if (safeSeconds == null) return null;

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
    final safeSeconds = _resolveKitchenElapsedSeconds(
      item,
      fallbackStartedAt: fallbackStartedAt,
      allowBillingFallback: allowBillingFallback,
    );
    if (safeSeconds == null) return Colors.black.withValues(alpha: 0.72);
    final minutes = safeSeconds ~/ 60;

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
    final elapsedColor = itemStartedAt == null
        ? Colors.green[700]!
        : _getKitchenElapsedTimeColor({
            'createdAt': itemStartedAt.toIso8601String(),
          }, allowBillingFallback: false);
    final orderOverlayColor = _getKitchenOrderCardOverlayColor(itemStartedAt);
    final hasInstruction = instructionText != null;
    final status = (item['status'] as String?)?.toLowerCase().trim() ?? '';
    final isPrepared = status == 'prepared';
    final isCancelled = status == 'cancelled' || status == 'canceled';

    return GestureDetector(
      onTap: null,
      onDoubleTap: (isPrepared || isCancelled)
          ? null
          : () => _onKitchenItemTapped(item, requirePreselected: false),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
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
            if (orderOverlayColor != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: orderOverlayColor),
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

  void _selectKitchenItem(dynamic item) {
    final currentStatus =
        (item['status'] as String?)?.toLowerCase().trim() ?? 'ordered';
    if (currentStatus != 'ordered' && currentStatus != 'confirmed') {
      return;
    }

    final billingId = (item['billingId'] ?? '').toString();
    final selectionKey =
        (item is Map ? item['selectionKey']?.toString() : null) ??
        _buildKitchenSelectionKey(billingId, item);
    if (selectionKey.isEmpty || !mounted) return;

    setState(() {
      _selectedKitchenItemKeys
        ..clear()
        ..add(selectionKey);
    });
  }

  Future<void> _onKitchenItemTapped(
    dynamic item, {
    bool requirePreselected = true,
  }) async {
    final billingId = item['billingId'];
    final itemId = item['id'] ?? item['_id'];
    final currentStatus =
        (item['status'] as String?)?.toLowerCase().trim() ?? 'ordered';
    if (currentStatus != 'ordered' && currentStatus != 'confirmed') {
      return;
    }

    final selectionKey =
        (item is Map ? item['selectionKey']?.toString() : null) ??
        _buildKitchenSelectionKey(billingId.toString(), item);

    if (requirePreselected &&
        !_selectedKitchenItemKeys.contains(selectionKey)) {
      if (mounted) {
        setState(() {
          _selectedKitchenItemKeys
            ..clear()
            ..add(selectionKey);
        });
      }
      return;
    }

    if (!requirePreselected && mounted) {
      setState(() {
        _selectedKitchenItemKeys
          ..clear()
          ..add(selectionKey);
      });
    }

    final itemKeys = _buildNotificationItemKeys(billingId.toString(), item);
    if (itemId != null && itemId.toString().trim().isNotEmpty) {
      itemKeys.add('${billingId}_${itemId.toString().trim()}');
    }

    String nextStatus = '';
    String loadingMsg = '';
    String successMsg = '';
    Color successColor = Colors.blue;

    if (currentStatus == 'ordered' || currentStatus == 'confirmed') {
      nextStatus = 'prepared';
      loadingMsg = 'Marking as prepared...';
      successMsg = 'Item Prepared';
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

      Map<String, dynamic>? preparationPayload;
      if (itemId != null && itemId.toString().trim().isNotEmpty) {
        try {
          preparationPayload = await ApiService.instance
              .fetchBillingItemPreparationTime(
                billingId: billingId.toString(),
                itemId: itemId.toString().trim(),
              );
        } catch (e) {
          debugPrint(
            'DEBUG: Preparation time fetch failed after status update: $e',
          );
        }
      }

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

          final snapshot = preparationPayload == null
              ? null
              : _buildKitchenPreparationSnapshotFromApi(preparationPayload);
          if (snapshot != null) {
            _kitchenItemPrepApiByKey[selectionKey] = snapshot;
            _applyKitchenPreparationSnapshotToOrders(selectionKey, snapshot);

            final preparedAtIso = _tryParseKitchenDateTime(
              snapshot['preparedAt'],
            )?.toIso8601String();
            if (preparedAtIso != null && preparedAtIso.isNotEmpty) {
              _kitchenItemPreparedAtByKey[selectionKey] = preparedAtIso;
            }
          }
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
    final durationMs = ((loopWidth / _pixelsPerSecond) * 1000).round().clamp(
      3500,
      12000,
    );

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
