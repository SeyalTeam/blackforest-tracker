import 'package:flutter/material.dart';
import 'manager_dashboard.dart';
import 'manager_closing_report.dart';
import 'manager_attendance_report.dart';
import 'manager_dealer_report.dart';
import 'manager_stock_order_report.dart';
import 'manager_expense_report.dart';
import 'manager_return_order_report.dart';
import 'manager_product_time_report.dart';
import 'manager_employee_list.dart';

class ManagerHomeGrid extends StatelessWidget {
  final List<String> managerCompanyIds;

  const ManagerHomeGrid({super.key, required this.managerCompanyIds});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manager Features',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildGridItem(
                context,
                title: 'Billing',
                icon: Icons.receipt_long,
                color: Colors.blue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManagerBillingReportScreen(
                        managerCompanyIds: managerCompanyIds,
                      ),
                    ),
                  );
                },
              ),
              _buildGridItem(
                context,
                title: 'Closing Entry',
                icon: Icons.account_balance_wallet,
                color: Colors.green,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManagerClosingReportScreen(
                        managerCompanyIds: managerCompanyIds,
                      ),
                    ),
                  );
                },
              ),
              _buildGridItem(
                context,
                title: 'Attendance Report',
                icon: Icons.people_alt,
                color: Colors.orange,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManagerAttendanceReportScreen(
                        managerCompanyIds: managerCompanyIds,
                      ),
                    ),
                  );
                },
              ),
              _buildGridItem(
                context,
                title: 'Dealer Report',
                icon: Icons.local_shipping,
                color: Colors.purple,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManagerDealerReportScreen(
                        managerCompanyIds: managerCompanyIds,
                      ),
                    ),
                  );
                },
              ),
              _buildGridItem(
                context,
                title: 'Stock Order Report',
                icon: Icons.inventory,
                color: Colors.brown,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManagerStockOrderReportScreen(
                        managerCompanyIds: managerCompanyIds,
                      ),
                    ),
                  );
                },
              ),
              _buildGridItem(
                context,
                title: 'Expense Report',
                icon: Icons.receipt_long,
                color: Colors.red,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManagerExpenseReportScreen(
                        managerCompanyIds: managerCompanyIds,
                      ),
                    ),
                  );
                },
              ),
              _buildGridItem(
                context,
                title: 'Return Order Report',
                icon: Icons.assignment_return,
                color: Colors.teal,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManagerReturnOrderReportScreen(
                        managerCompanyIds: managerCompanyIds,
                      ),
                    ),
                  );
                },
              ),
              _buildGridItem(
                context,
                title: 'Product Time Report',
                icon: Icons.timer,
                color: Colors.indigo,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManagerProductTimeReportScreen(
                        managerCompanyIds: managerCompanyIds,
                      ),
                    ),
                  );
                },
              ),

              _buildGridItem(
                context,
                title: 'Manage Employees',
                icon: Icons.people,
                color: Colors.blueGrey,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManagerEmployeeListScreen(),
                    ),
                  );
                },
              ),
              // More features can be added here step by step
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
