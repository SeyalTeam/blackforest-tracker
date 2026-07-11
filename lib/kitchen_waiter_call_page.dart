import 'package:flutter/material.dart';
import 'api_service.dart';

class KitchenWaiterCallPage extends StatefulWidget {
  final String branchId;
  final String userRole;
  final List<dynamic> kitchenOrders;

  const KitchenWaiterCallPage({
    super.key,
    required this.branchId,
    required this.userRole,
    required this.kitchenOrders,
  });

  @override
  State<KitchenWaiterCallPage> createState() => _KitchenWaiterCallPageState();
}

class _KitchenWaiterCallPageState extends State<KitchenWaiterCallPage> {
  List<dynamic> _waiters = [];
  bool _isLoadingWaiters = true;
  String _errorMessage = '';
  String? _callingWaiterId;

  // Selected table state
  String _selectedTable = 'General Work (No Table)';

  @override
  void initState() {
    super.initState();
    _loadLiveWaiters();
  }

  Future<void> _loadLiveWaiters() async {
    if (!mounted) return;
    setState(() {
      _isLoadingWaiters = true;
      _errorMessage = '';
    });
    try {
      final list = await ApiService.instance.fetchLiveWaiters(branchId: widget.branchId);
      if (!mounted) return;
      setState(() {
        _waiters = list;
        _isLoadingWaiters = false;
        _errorMessage = list.isEmpty ? 'No waiters registered for this branch.' : '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingWaiters = false;
        _errorMessage = 'Failed to load waiters: $e';
      });
    }
  }

  Future<void> _callWaiter(Map<String, dynamic> waiter) async {
    final waiterId = (waiter['id'] ?? waiter['_id'])?.toString() ?? '';
    final waiterName = waiter['name']?.toString() ?? waiter['username']?.toString() ?? 'Waiter';

    setState(() {
      _callingWaiterId = waiterId;
    });

    try {
      final tableNumber = _selectedTable == 'General Work (No Table)'
          ? '0'
          : _selectedTable.replaceAll('Table ', '');

      final sectionName = _selectedTable == 'General Work (No Table)'
          ? 'General'
          : 'Table Call';

      // 1. Try to find from kitchenOrders parameter
      final targetBill = widget.kitchenOrders.firstWhere(
        (order) => order['tableDetails']?['tableNumber']?.toString() == tableNumber,
        orElse: () => null,
      );

      final billId = targetBill != null ? (targetBill['id'] ?? targetBill['_id'])?.toString() : '';
      final resolvedSectionName = targetBill?['tableDetails']?['section']?.toString() ?? sectionName;
      final callerName = widget.userRole.toLowerCase() == 'chef'
          ? 'Chef'
          : (widget.userRole.toLowerCase() == 'supervisor' ? 'Supervisor' : 'Kitchen Staff');

      await ApiService.instance.callWaiter(
        branchId: widget.branchId,
        billId: billId,
        tableNumber: tableNumber,
        section: resolvedSectionName,
        waiterId: waiterId,
        callerName: callerName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully called $waiterName!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to call waiter: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _callingWaiterId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Collect active tables from kitchen orders
    final activeTables = <String>{};
    for (var order in widget.kitchenOrders) {
      final tableNum = order['tableDetails']?['tableNumber']?.toString() ?? '';
      if (tableNum.isNotEmpty) {
        activeTables.add('Table $tableNum');
      }
    }
    final sortedTables = activeTables.toList()
      ..sort((a, b) {
        final ia = int.tryParse(a.replaceAll('Table ', '')) ?? 0;
        final ib = int.tryParse(b.replaceAll('Table ', '')) ?? 0;
        return ia.compareTo(ib);
      });

    final dropdownOptions = ['General Work (No Table)', ...sortedTables];

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Call Waiter',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLiveWaiters,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card displaying calling info
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.blue.shade50,
                      child: Icon(Icons.phone_in_talk_rounded, color: Colors.blue.shade600, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Branch ID: ${widget.branchId}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Calling as: ${widget.userRole.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Table Selection Section
            const Text(
              'TABLE NUMBER',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Color(0xFF4B5563),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: DropdownButtonFormField<String>(
                  value: _selectedTable,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    icon: Icon(Icons.table_restaurant_rounded, color: Colors.grey),
                  ),
                  items: dropdownOptions.map((opt) {
                    return DropdownMenuItem<String>(
                      value: opt,
                      child: Text(
                        opt,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedTable = val;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Live Waiters Section
            const Text(
              'BRANCH WAITERS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Color(0xFF4B5563),
              ),
            ),
            const SizedBox(height: 8),

            if (_isLoadingWaiters)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_errorMessage.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40.0),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _waiters.length,
                itemBuilder: (context, index) {
                  final waiter = _waiters[index];
                  final waiterId = (waiter['id'] ?? waiter['_id'])?.toString() ?? '';
                  final waiterName = waiter['name']?.toString() ?? waiter['username']?.toString() ?? 'Waiter';
                  final email = waiter['email']?.toString() ?? '';
                  final isCalling = _callingWaiterId == waiterId;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey[200]!),
                    ),
                    color: Colors.white,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.grey[100],
                        child: Text(
                          waiterName.isNotEmpty ? waiterName[0].toUpperCase() : 'W',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ),
                      title: Text(
                        waiterName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Text(
                        email.isNotEmpty ? email : 'Branch Waiter',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                      trailing: isCalling
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              onPressed: () => _callWaiter(waiter),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.phone_rounded, size: 16),
                                  SizedBox(width: 6),
                                  Text('Call'),
                                ],
                              ),
                            ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
