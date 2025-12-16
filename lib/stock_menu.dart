import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'stockorder_report.dart';
import 'department_list.dart';
import 'category_list.dart';

class StockMenuPage extends StatelessWidget {
  const StockMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Stock Menu',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
          children: [
            _buildGridItem(context, 'Department', Icons.business, () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DepartmentListPage()),
              );
            }),
            _buildGridItem(context, 'Category', Icons.category, () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CategoryListPage()),
              );
            }),
            _buildGridItem(context, 'All', Icons.list_alt, () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StockOrderReportPage()),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.black),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
