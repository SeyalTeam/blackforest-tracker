import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'api_service.dart';
import 'stockorder_report.dart';

class BranchListPage extends StatefulWidget {
  const BranchListPage({super.key});

  @override
  State<BranchListPage> createState() => _BranchListPageState();
}

class _BranchListPageState extends State<BranchListPage> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<dynamic> _branches = [];
  String? _error;
  int _totalTodayOrderCount = 0;
  Map<String, int> _branchCounts = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final now = DateTime.now();
      // Fetch branches and stock orders in parallel
      final results = await Future.wait([
        _api.fetchBranches(),
        _api.fetchStockOrders(fromDate: now, toDate: now),
      ]);

      final branchData = results[0] as List<dynamic>;
      final orderData = results[1] as List<dynamic>;

      // Count same-day orders (Ordered Today & Delivery Today)
      int totalCount = 0;
      Map<String, int> branchCounts = {};

      for (var o in orderData) {
        final cDate = DateTime.tryParse(o['createdAt'] ?? '')?.toLocal();
        final dDate = DateTime.tryParse(o['deliveryDate'] ?? '')?.toLocal();

        if (cDate != null && dDate != null) {
          bool isOrderedToday = cDate.year == now.year && cDate.month == now.month && cDate.day == now.day;
          bool isDeliveryToday = dDate.year == now.year && dDate.month == now.month && dDate.day == now.day;
          
          if (isOrderedToday && isDeliveryToday) {
            totalCount++;
            final branch = o['branch'];
            final bid = branch is Map ? (branch['id'] ?? branch['_id']) : null;
            if (bid != null) {
              branchCounts[bid] = (branchCounts[bid] ?? 0) + 1;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          List sortedData = List.from(branchData);
          sortedData.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
          _branches = [
            {'id': 'ALL', 'name': 'All Branches'},
            ...sortedData
          ];
          _totalTodayOrderCount = totalCount;
          _branchCounts = branchCounts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Branches',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 16.0,
                      mainAxisSpacing: 16.0,
                    ),
                    itemCount: _branches.length,
                    itemBuilder: (context, index) {
                      final branch = _branches[index];
                      final isAll = branch['id'] == 'ALL';
                      final count = isAll ? _totalTodayOrderCount : (_branchCounts[branch['id']] ?? 0);

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => StockOrderReportPage(
                                      initialBranchId: branch['id'],
                                      onlyTodayOrdered: true,
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    () {
                                      final name = (branch['name'] ?? 'Unknown').toString();
                                      return name.length > 3 
                                          ? name.substring(0, 3).toUpperCase() 
                                          : name.toUpperCase();
                                    }(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
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
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
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
                    },
                  ),
                ),
    );
  }
}
