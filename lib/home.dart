import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'department_list.dart';
import 'branch_list.dart';
import 'api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  int _stockCount = 0;
  int _branchCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCounts();
  }

  Future<void> _fetchCounts() async {
    try {
      final now = DateTime.now();
      final orders = await _api.fetchStockOrders(fromDate: now, toDate: now);
      
      int stockCount = 0;
      int branchCount = 0;

      for (var o in orders) {
        final cDate = DateTime.tryParse(o['createdAt'] ?? '')?.toLocal();
        final dDate = DateTime.tryParse(o['deliveryDate'] ?? '')?.toLocal();

        if (cDate != null && dDate != null) {
          bool isOrderedToday = cDate.year == now.year && cDate.month == now.month && cDate.day == now.day;
          bool isDeliveryToday = dDate.year == now.year && dDate.month == now.month && dDate.day == now.day;
          
          if (isOrderedToday && isDeliveryToday) {
            branchCount++;
          } else if (isDeliveryToday) {
            stockCount++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _stockCount = stockCount;
          _branchCount = branchCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Home',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 3,
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
          children: [
            _buildGridItem(context, 'Stock', Icons.inventory, _stockCount),
            _buildGridItem(context, 'Branch', Icons.store, _branchCount),
            _buildGridItem(context, 'Return', Icons.assignment_return, 0),
          ],
        ),
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, String title, IconData icon, int count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox.expand(
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () {
                if (title == 'Stock') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DepartmentListPage()),
                  );
                } else if (title == 'Branch') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const BranchListPage()),
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
  }
}
