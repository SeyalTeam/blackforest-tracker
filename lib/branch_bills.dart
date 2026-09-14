import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class BranchBillsScreen extends StatefulWidget {
  final String branchId;
  final String branchName;
  final DateTime date;

  const BranchBillsScreen({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.date,
  });

  @override
  State<BranchBillsScreen> createState() => _BranchBillsScreenState();
}

class _BranchBillsScreenState extends State<BranchBillsScreen> {
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String _errorMessage = '';
  List<dynamic> _allBills = [];
  List<dynamic> _filteredBills = [];

  final ScrollController _scrollController = ScrollController();

  // Filters
  String _selectedOrderType = 'All'; // 'All', 'Table Order', 'Counter Bill'
  String? _selectedWaiterId;
  String _selectedStatus = 'All'; // 'All', 'Ordered', 'Completed', 'Settled', 'Cancelled'
  Map<String, String> _waiterMap = {}; // id -> name

  @override
  void initState() {
    super.initState();
    _fetchBills();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isFetchingMore && _hasMore) {
        _fetchMoreBills();
      }
    }
  }

  Future<void> _fetchBills() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _currentPage = 1;
        _allBills.clear();
        _hasMore = true;
      });

      final response = await ApiService.instance.fetchBranchBills(
        branchId: widget.branchId,
        date: widget.date,
        page: _currentPage,
      );

      final bills = response['docs'] as List<dynamic>;
      final hasNextPage = response['hasNextPage'] as bool;

      _processBillsData(bills, hasNextPage: hasNextPage, isRefresh: true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load bills: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchMoreBills() async {
    try {
      setState(() {
        _isFetchingMore = true;
      });

      _currentPage++;
      final response = await ApiService.instance.fetchBranchBills(
        branchId: widget.branchId,
        date: widget.date,
        page: _currentPage,
      );

      final bills = response['docs'] as List<dynamic>;
      final hasNextPage = response['hasNextPage'] as bool;

      _processBillsData(bills, hasNextPage: hasNextPage, isRefresh: false);
    } catch (e) {
      setState(() {
        _isFetchingMore = false;
        // Optionally show a toast for load more failure
      });
    }
  }

  void _processBillsData(List<dynamic> bills, {required bool hasNextPage, required bool isRefresh}) {
    final Map<String, String> waiters = isRefresh ? {} : Map.from(_waiterMap);
    
    for (var bill in bills) {
      final createdBy = bill['createdBy'];
      if (createdBy != null) {
        if (createdBy is Map) {
          final id = (createdBy['id'] ?? createdBy['_id'])?.toString() ?? '';
          final name = createdBy['name']?.toString() ?? 'Unknown Waiter';
          if (id.isNotEmpty) waiters[id] = name;
        } else if (createdBy is String) {
          waiters[createdBy] = 'Waiter ($createdBy)';
        }
      }
    }

    setState(() {
      if (isRefresh) {
        _allBills = bills;
      } else {
        _allBills.addAll(bills);
      }
      
      _hasMore = hasNextPage;
      _waiterMap = waiters;
      _isLoading = false;
      _isFetchingMore = false;
      _applyFilters();
    });
  }

  void _applyFilters() {
    setState(() {
      _filteredBills = _allBills.where((bill) {
        // Filter by Status
        if (_selectedStatus != 'All') {
          final status = bill['status']?.toString().toUpperCase() ?? 'UNKNOWN';
          if (status != _selectedStatus.toUpperCase()) return false;
        }

        // Filter by Order Type
        bool isTableOrder = false;
        final tableDetails = bill['tableDetails'];
        if (tableDetails != null && tableDetails is Map) {
          final tableNumber = tableDetails['tableNumber']?.toString() ?? '';
          if (tableNumber.isNotEmpty) isTableOrder = true;
        }

        if (_selectedOrderType == 'Table Order' && !isTableOrder) return false;
        if (_selectedOrderType == 'Counter Bill' && isTableOrder) return false;

        // Filter by Waiter
        if (_selectedWaiterId != null && _selectedWaiterId!.isNotEmpty) {
          final createdBy = bill['createdBy'];
          String billWaiterId = '';
          if (createdBy is Map) {
            billWaiterId = (createdBy['id'] ?? createdBy['_id'])?.toString() ?? '';
          } else if (createdBy is String) {
            billWaiterId = createdBy;
          }
          if (billWaiterId != _selectedWaiterId) return false;
        }

        return true;
      }).toList();
    });
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter Bills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  const Text('Order Type', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedOrderType,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: ['All', 'Table Order', 'Counter Bill'].map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                    onChanged: (val) {
                      setModalState(() {
                        _selectedOrderType = val!;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text('Waiter', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: _selectedWaiterId,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Waiters')),
                      ..._waiterMap.entries.map((entry) {
                        return DropdownMenuItem(value: entry.key, child: Text(entry.value));
                      }),
                    ],
                    onChanged: (val) {
                      setModalState(() {
                        _selectedWaiterId = val;
                      });
                    },
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _applyFilters();
                      },
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Apply Filters'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    if (_isLoading) {
      bodyContent = const Center(child: CircularProgressIndicator());
    } else if (_errorMessage.isNotEmpty) {
      bodyContent = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchBills, child: const Text('Retry')),
          ],
        ),
      );
    } else if (_filteredBills.isEmpty) {
      bodyContent = const Center(
        child: Text('No bills found matching filters.', style: TextStyle(color: Colors.grey)),
      );
    } else {
      final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
      final timeFormat = DateFormat('hh:mm a');

      bodyContent = RefreshIndicator(
        onRefresh: _fetchBills,
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: _filteredBills.length + (_isFetchingMore ? 1 : 0),
          separatorBuilder: (context, index) => const Divider(height: 24),
          itemBuilder: (context, index) {
            if (index == _filteredBills.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final bill = _filteredBills[index];
            final billNoRaw = bill['invoiceNumber']?.toString() ?? 'N/A';
            
            // Shorten invoice number (e.g., KMC-20260914-001 -> KMC-001)
            String billNo = billNoRaw;
            final parts = billNoRaw.split('-');
            if (parts.length >= 3 && parts[1].length == 8) {
              billNo = '${parts[0]}-${parts.sublist(2).join('-')}';
            }
            
            DateTime? createdAt;
            if (bill['createdAt'] != null) {
              createdAt = DateTime.tryParse(bill['createdAt'].toString())?.toLocal();
            }
            final timeStr = createdAt != null ? timeFormat.format(createdAt) : 'Unknown time';
            
            final amount = (bill['totalAmount'] ?? 0).toDouble();
            final paymentMethod = bill['paymentMethod']?.toString().toUpperCase() ?? 'UNKNOWN';
            final status = bill['status']?.toString().toUpperCase() ?? 'UNKNOWN';

            Color statusColor = Colors.grey;
            if (status == 'SETTLED' || status == 'COMPLETED') statusColor = Colors.green;
            if (status == 'ORDERED') statusColor = Colors.orange;
            if (status == 'CANCELLED') statusColor = Colors.red;

            // Waiter & Table Info
            String subtitle = timeStr;
            final createdBy = bill['createdBy'];
            if (createdBy != null) {
               if (createdBy is Map) {
                 subtitle += ' • ${createdBy['name'] ?? 'Waiter'}';
               } else if (createdBy is String) {
                 subtitle += ' • Waiter (${createdBy.substring(0, 4)})';
               }
            }

            final tableDetails = bill['tableDetails'];
            if (tableDetails != null && tableDetails is Map) {
              final tableNumber = tableDetails['tableNumber']?.toString() ?? '';
              final section = tableDetails['section']?.toString() ?? '';
              if (tableNumber.isNotEmpty) {
                subtitle += ' • Table $tableNumber';
                if (section.isNotEmpty) subtitle += ' ($section)';
              }
            }

            return Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.receipt, color: Colors.blue),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            billNo,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currencyFormat.format(amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        paymentMethod,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    final dateDisplay = DateFormat('dd MMM yyyy').format(widget.date);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.branchName, style: const TextStyle(fontSize: 16)),
            Text(
              dateDisplay,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.blue),
            onPressed: _showFilterSheet,
            tooltip: 'Filter Bills',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: ['All', 'Ordered', 'Completed', 'Settled', 'Cancelled'].map((status) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(status, style: TextStyle(fontSize: 12, color: _selectedStatus == status ? Colors.white : Colors.black87)),
                    selected: _selectedStatus == status,
                    selectedColor: Colors.blue,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedStatus = status;
                          _applyFilters();
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          if (_selectedOrderType != 'All' || _selectedWaiterId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue[50],
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing: $_selectedOrderType' + (_selectedWaiterId != null ? ' • ${_waiterMap[_selectedWaiterId!]}' : ''),
                      style: TextStyle(fontSize: 12, color: Colors.blue[800], fontWeight: FontWeight.w600),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedOrderType = 'All';
                        _selectedWaiterId = null;
                        _applyFilters();
                      });
                    },
                    child: Text('CLEAR', style: TextStyle(fontSize: 12, color: Colors.blue[800], fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          Expanded(child: bodyContent),
        ],
      ),
    );
  }
}
