import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'common_scaffold.dart';
import 'api_service.dart';
import 'stockorder_report.dart';

class BranchListPage extends StatefulWidget {
  const BranchListPage({super.key});

  @override
  State<BranchListPage> createState() => _BranchListPageState();
}

class _BranchListPageState extends State<BranchListPage> {
  // final ApiService _api = ApiService();
  final _storage = const FlutterSecureStorage();
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _branches = [];
  String _selectedDepartmentFilter = 'ALL';
  String _selectedBranch = 'ALL';
  List<dynamic> _recentOrders = [];
  bool _isLoading = true;
  String _userRole = '';
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _fetchUserRole();
    await _fetchDepartments();
    // Cache Check logic same as Home
    await _fetchCounts();
    await _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    try {
      final branches = await ApiService.instance.fetchBranches();
      if (mounted) {
        setState(() {
          _branches = branches.cast<Map<String, dynamic>>();
          _branches.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        });
      }
    } catch (e) {
      debugPrint('Error fetching branches: $e');
    }
  }

  Future<void> _fetchUserRole() async {
    final role = await _storage.read(key: 'userRole');
    if (mounted) {
      setState(() {
        _userRole = role?.toLowerCase() ?? '';
      });
    }
  }

  Future<void> _fetchCounts({bool forceRefresh = false}) async {
    try {
      // Only show global loading if we have no data or forced
      if (forceRefresh || _recentOrders.isEmpty) {
         if (mounted) setState(() => _isLoading = true);
      }
      
      // Use _selectedDate for filtering
      final from = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final to = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
      
      final orders = await ApiService.instance.fetchStockOrders(fromDate: from, toDate: to, forceRefresh: forceRefresh);
      
      List<dynamic> validOrders = [];

      for (var o in orders) {
        final cDate = DateTime.tryParse(o['createdAt'] ?? '')?.toLocal();
        final dDate = DateTime.tryParse(o['deliveryDate'] ?? '')?.toLocal();

        if (cDate != null && dDate != null) {
          bool isOrderedOnFilterDate = cDate.year == _selectedDate.year && cDate.month == _selectedDate.month && cDate.day == _selectedDate.day;
          bool isDeliveryOnFilterDate = dDate.year == _selectedDate.year && dDate.month == _selectedDate.month && dDate.day == _selectedDate.day;
          
          bool isLive = isOrderedOnFilterDate && isDeliveryOnFilterDate;

          // FILTER: ONLY SHOW LIVE ORDERS (Same Day)
          if (!isLive) continue;

          // Role-Based Visibility Logic
          final items = (o['items'] as List?) ?? [];
          bool shouldShow = false;
          
          if (_userRole == 'chef') {
             shouldShow = items.any((item) {
                final s = (item['status'] as String?)?.toLowerCase() ?? 'pending';
                return s == 'ordered' || s == 'pending' || s == 'sending';
             });
          } else if (_userRole == 'supervisor') {
             shouldShow = items.any((item) {
                final s = (item['status'] as String?)?.toLowerCase() ?? 'sending';
                return s == 'sending' || s == 'confirmed';
             });
          } else if (_userRole == 'driver') {
             shouldShow = items.any((item) {
                 final s = (item['status'] as String?)?.toLowerCase() ?? 'confirmed';
                 return s == 'confirmed' || s == 'picked';
             });
          } else {
              bool isOpened = items.any((item) {
                final s = (item['status'] as String?)?.toLowerCase() ?? 'pending';
                return s != 'ordered' && s != 'pending';
              });
              shouldShow = !isOpened;
          }

          if (shouldShow) {
            validOrders.add(o);
          }
        }
      }

      
      // Generate Short Codes
      final Map<String, List<Map<String, dynamic>>> ordersByBranch = {};
      for (var o in validOrders) {
        final bName = (o['branch'] is Map ? o['branch']['name'] : 'UNK').toString();
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

        final codePrefix = bName.length > 3 ? bName.substring(0, 3).toUpperCase() : bName.toUpperCase();
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

  Future<void> _fetchDepartments() async {
    try {
      final docs = await ApiService.instance.fetchDepartments();
      if (mounted) {
        setState(() {
           _departments = docs.cast<Map<String, dynamic>>();
           _departments.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
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
       badgeColor = Colors.yellow[700]!; 
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
                      fontWeight: FontWeight.bold
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
    final dateStr = DateFormat('MMM dd').format(_selectedDate).toUpperCase();

    // Calculate Counts
    int newCount = 0;
    int workingCount = 0;
    int completedCount = 0;

    for (var order in _recentOrders) {
       // Branch Filter Check
       if (_selectedBranch != 'ALL') {
          final bId = (order['branch'] is Map ? (order['branch']['id'] ?? order['branch']['_id']) : null)?.toString() ?? '';
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
          final bId = (order['branch'] is Map ? (order['branch']['id'] ?? order['branch']['_id']) : null)?.toString() ?? '';
          if (bId != _selectedBranch) return false;
        }

        if (_selectedDepartmentFilter != 'ALL') {
           return _doesOrderContainDepartment(order, _selectedDepartmentFilter);
        }
        return true;
    }).toList();

    return CommonScaffold(
      title: 'Live Orders',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            setState(() {
              _isLoading = true;
            });
            _fetchCounts(forceRefresh: true);
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
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              height: 48,
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  const Icon(Icons.calendar_today, size: 16, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    dateStr,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
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
                                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                                isExpanded: true,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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

                  // TABS (Left Aligned)
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
                       child: Center(child: Text('No live orders found.', style: TextStyle(color: Colors.grey))),
                     )
                  else
                    ...filteredOrders.map(_buildTicketItem),
                ],
              ),
              ),
      bottomNavigationBar: _buildDepartmentFooter(),
    );
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
                return true;
           }
        } else if (deptId == 'OTHERS') {
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
                    fontWeight: FontWeight.bold
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
         if (product['defaultPriceDetails'] != null && product['defaultPriceDetails'] is Map) {
             price = ((product['defaultPriceDetails']['price'] ?? 0) as num).toDouble();
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

    if (billStatus == 'PENDING') billStatus = 'ORDERED';
    
    // Determine Amounts to Display based on Role
    String label1 = 'Ord';
    double val1 = totalOrdered;
    Color color1 = Colors.blueGrey;
    
    String label2 = 'Snt';
    double val2 = totalSending;
    Color color2 = Colors.green;
    
    if (_userRole == 'chef') {
       label1 = 'Ord'; val1 = totalOrdered;
       label2 = 'Snt'; val2 = totalSending;
    } else if (_userRole == 'supervisor') {
       label1 = 'Snt'; val1 = totalSending; color1 = Colors.red;
       label2 = 'Con'; val2 = totalConfirmed; color2 = Colors.green;
    } else if (_userRole == 'driver') {
       label1 = 'Con'; val1 = totalConfirmed; color1 = Colors.red;
       label2 = 'Pic'; val2 = totalPicked; color2 = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
           // Role Check
           if (['chef', 'supervisor', 'driver', 'factory'].contains(_userRole)) {
              final branchId = (order['branch'] is Map ? (order['branch']['id'] ?? order['branch']['_id']) : null)?.toString();
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
                    onlyTodayOrdered: true,
                  ),
                ),
              );
           } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('You are not authorized to update orders.'), duration: Duration(milliseconds: 1000)),
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Live',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    billStatus,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 14),
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
                        Text('Ord: ${dateFormat.format(cDate)}', style: const TextStyle(fontSize: 12)),
                      if (dDate != null)
                        Text('Del: ${dateFormat.format(dDate)}', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                          'Inv: $invoiceNo',
                          style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$label1: ${currencyFormat.format(val1)}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color1),
                      ),
                      Text(
                        '$label2: ${currencyFormat.format(val2)}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color2),
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
}
