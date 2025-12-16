import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'api_service.dart';
import 'stockorder_report.dart';
import 'package:intl/intl.dart';

class CategoryListPage extends StatefulWidget {
  final String? departmentId;
  final String? pageTitle;

  const CategoryListPage({super.key, this.departmentId, this.pageTitle});

  @override
  State<CategoryListPage> createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<dynamic> _categories = [];
  List<dynamic> _filteredCategories = []; // Displayed categories
  Map<String, Map<String, dynamic>> _categoryStats = {}; // {catId: {'ord': 0, 'snt': 0, 'lastCreated': DateTime?, 'liveOrderCount': 0}}
  String? _error;
  
  // Filter States
  DateTime _selectedDate = DateTime.now();
  String _selectedBranchId = 'ALL';
  List<Map<String, dynamic>> _activeBranches = []; // [{'id': 'ALL', 'name': 'All'}, ...]
  List<dynamic> _rawOrders = []; // Store fetched orders to re-filter locally if needed

  // Stats aggregation
  int _overallOrd = 0;
  int _overallSnt = 0;
  int _overallLiveCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Fetch Categories
      final cats = await _api.fetchCategories(onlyStock: true, departmentId: widget.departmentId);
      
      // 2. Fetch Orders for Selected Date
      // Using fetchStockOrders with precise date range for the selected day
      final orders = await _api.fetchStockOrders(fromDate: _selectedDate, toDate: _selectedDate);
      
      _rawOrders = orders;
      _categories = cats;
      
      // 3. Derive Active Branches from Orders
      final Set<String> branchIds = {};
      final List<Map<String, dynamic>> branchList = [{'id': 'ALL', 'name': 'All'}];
      
      for (var o in orders) {
         final b = o['branch'];
         if (b is Map) {
            final bid = b['id'] ?? b['_id'];
            final bname = b['name'] ?? 'Unknown';
            if (bid != null && !branchIds.contains(bid)) {
               branchIds.add(bid);
               branchList.add({'id': bid, 'name': bname});
            }
         }
      }
      // Sort branches by name (keeping ALL at top)
      if (branchList.length > 1) {
         final others = branchList.sublist(1);
         others.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
         _activeBranches = [branchList[0], ...others];
      } else {
         _activeBranches = branchList;
      }

      // Ensure selected branch is still valid
      if (_selectedBranchId != 'ALL' && !branchIds.contains(_selectedBranchId)) {
         _selectedBranchId = 'ALL';
      }

      // 4. Calculate Stats & Filter Categories
      _calculateStats();

    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _calculateStats() {
    final Map<String, Map<String, dynamic>> newStats = {};
    int totalOrd = 0;
    int totalSnt = 0;
    
    // Filter orders if a specific branch is selected
    final filteredOrders = _selectedBranchId == 'ALL'
        ? _rawOrders
        : _rawOrders.where((o) {
            final b = o['branch'];
            final bid = b is Map ? (b['id'] ?? b['_id']) : null;
            return bid == _selectedBranchId;
          }).toList();

    for (var order in filteredOrders) {
         final items = (order['items'] as List?) ?? [];
         
         // Logic for Live Order Counter (Checks if created TODAY)
         final created = DateTime.tryParse(order['createdAt'] ?? '');
         bool isCreatedToday = false;
         if (created != null) {
            final now = DateTime.now();
            isCreatedToday = created.year == now.year && created.month == now.month && created.day == now.day;
         }
         
         final Set<String> distinctCatsInOrder = {};

         for (var item in items) {
            // Get Category ID
            final product = item['product'];
            final pMap = product is Map ? product : {};
            dynamic catObj = pMap['category'];
            String catId = '';
            if (catObj is Map) {
              catId = catObj['id'] ?? catObj['_id'] ?? '';
            } else if (catId.isEmpty) {
              catId = catObj?.toString() ?? '';
            }
            
            if (catId.isNotEmpty) {
                 if (!newStats.containsKey(catId)) {
                    newStats[catId] = {'ord': 0, 'snt': 0, 'liveOrderCount': 0};
                 }
                 final num req = item['requiredQty'] ?? 0;
                 final num snt = item['sendingQty'] ?? 0;
                 
                 newStats[catId]!['ord'] = (newStats[catId]!['ord'] ?? 0) + req.toInt();
                 newStats[catId]!['snt'] = (newStats[catId]!['snt'] ?? 0) + snt.toInt();
                 
                 // Track max created date for the "Last Created" timestamp on card
                 if (created != null) {
                    final DateTime? currentMax = newStats[catId]!['lastCreated'];
                    if (currentMax == null || created.isAfter(currentMax)) {
                       newStats[catId]!['lastCreated'] = created;
                    }
                 }
                 
                 distinctCatsInOrder.add(catId);
            }
         }
         
         if (isCreatedToday) {
            for (final catId in distinctCatsInOrder) {
               if (newStats.containsKey(catId)) {
                  newStats[catId]!['liveOrderCount'] = (newStats[catId]!['liveOrderCount'] ?? 0) + 1;
               }
            }
         }
    }

    // Filter Categories to display
    // If Branch is ALL, show all categories.
    // If Branch is selected, show only categories that are present in newStats (checked above).
    List<dynamic> visibleCats;
    if (_selectedBranchId == 'ALL') {
       visibleCats = List.from(_categories);
    } else {
       visibleCats = _categories.where((c) => newStats.containsKey(c['id'])).toList();
    }
    
    if (mounted) {
      setState(() {
        _categoryStats = newStats;
        _filteredCategories = visibleCats;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchData(); // Refetch orders for new date
    }
  }

  String _getDepartmentName(dynamic category) {
    // Check if department is populated (Map) or ID (String)
    final dept = category['department'];
    if (dept is Map) {
      return dept['name'] ?? '';
    }
    return ''; // Or return empty if not populated
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: widget.pageTitle ?? 'Categories (Stock)',
      body: Column(
        children: [
           // 1. Date Selector
           _buildDateSelector(),
           
           // 2. Branch Chips (Only show if we have orders, or just always show ALL)
           if (!_loading && _error == null)
             _buildBranchChips(),

           // 3. Main Content
           Expanded(
             child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : Column(
                        children: [
                            // 3. Overall Card (Top of the List)
                            
                            // 4. Grid
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: GridView.builder(
                                  padding: const EdgeInsets.only(top: 8, bottom: 20),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: widget.departmentId != null ? 2 : 3,
                                    crossAxisSpacing: 16.0,
                                    mainAxisSpacing: 16.0,
                                  ),
                                  itemCount: _filteredCategories.length,
                                  itemBuilder: (context, index) {
                                    final cat = _filteredCategories[index];
                                    final catName = cat['name'] ?? 'Unknown';
                                    final deptName = _getDepartmentName(cat);

                                    return _buildCategoryCard(_filteredCategories[index]);
                                  },
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

  Widget _buildCategoryCard(dynamic cat) {
     final catName = cat['name'] ?? 'Unknown';
     final deptName = _getDepartmentName(cat);
     return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StockOrderReportPage(
                  categoryId: cat['id'],
                  categoryName: catName,
                  initialFromDate: _selectedDate,
                  initialToDate: _selectedDate,
                  initialBranchId: _selectedBranchId,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0).copyWith(bottom: 24),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                           final stats = _categoryStats[cat['id']] ?? {};
                           final liveCount = stats['liveOrderCount'] as int? ?? 0;
                           if (liveCount > 0) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'LIVE ORDER : $liveCount',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                                ),
                              );
                           }
                           return const SizedBox.shrink();
                        }
                      ),
                      Text(
                        catName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      if (deptName.isNotEmpty && widget.departmentId == null) ...[
                        const SizedBox(height: 4),
                        Text(
                          deptName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                           final stats = _categoryStats[cat['id']] ?? {'ord': 0, 'snt': 0};
                           return Row(
                             mainAxisAlignment: MainAxisAlignment.center,
                             children: [
                                Text('${stats['ord']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
                                const SizedBox(width: 16),
                                Text('${stats['snt']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                             ],
                           );
                        }
                      ),
                    ],
                  ),
                ),
              ),
              
              Positioned(
                bottom: 8,
                left: 8,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                     final stats = _categoryStats[cat['id']] ?? {};
                     final lastCreated = stats['lastCreated'] as DateTime?;
                     if (lastCreated == null) return const SizedBox.shrink();
                     
                     final formattedDate = DateFormat('MMM d, h:mm a').format(lastCreated.add(const Duration(hours: 5, minutes: 30)));
                     return Text(
                        formattedDate,
                        style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
                     );
                  }
                ),
              ),
            ],
          ),
        ),
      );
  }

  Widget _buildDateSelector() {
     return Container(
        color: Colors.grey[100],
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
              const Text('Delivery Date:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              InkWell(
                 onTap: _pickDate,
                 child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                       color: Colors.white,
                       borderRadius: BorderRadius.circular(8),
                       border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                          Text(
                             DateFormat('EEE, MMM d, y').format(_selectedDate),
                             style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                       ],
                    ),
                 ),
              )
           ],
        ),
     );
  }
  
  Widget _buildBranchChips() {
     if (_activeBranches.isEmpty) return const SizedBox.shrink();

     return Container(
        width: double.infinity,
        color: Colors.white, 
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
           scrollDirection: Axis.horizontal,
           padding: const EdgeInsets.symmetric(horizontal: 16),
           child: Row(
              children: _activeBranches.map((b) {
                 final isSelected = _selectedBranchId == b['id'];
                 final name = b['name'] as String;
                 final code = name.length > 3 && name != 'All' ? name.substring(0, 3).toUpperCase() : name.toUpperCase();
                 
                 return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                       label: Text(code),
                       selected: isSelected,
                       onSelected: (val) {
                          if (val) {
                             setState(() {
                                _selectedBranchId = b['id'];
                                _calculateStats();
                             });
                          }
                       },
                       showCheckmark: false,
                       selectedColor: Colors.red,
                       backgroundColor: const Color(0xFF260206), // Dark Brown
                       labelStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12
                       ),
                       shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Colors.transparent),
                       ),
                    ),
                 );
              }).toList(),
           ),
        ),
     );
  }
}
