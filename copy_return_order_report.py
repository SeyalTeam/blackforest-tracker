import re

with open('lib/manager_expense_report.dart', 'r') as f:
    code = f.read()

# Replace class names
code = code.replace('ManagerExpenseReportScreen', 'ManagerReturnOrderReportScreen')
code = code.replace('_ManagerExpenseReportScreenState', '_ManagerReturnOrderReportScreenState')
code = code.replace('BranchExpenseDetailsScreen', 'BranchReturnOrderDetailsScreen')

# Replace API call
code = code.replace('fetchExpenseReport', 'fetchReturnOrderReport')
code = code.replace('_expenseReport', '_returnOrderReport')

# Replace titles and text
code = code.replace("'Expense Report'", "'Return Order Report'")

# Replace import
code = code.replace("import 'branch_expense_details.dart';", "import 'branch_return_order_details.dart';")

# Replace sorting and group variable mapping
code = code.replace("stat['total']", "stat['totalAmount']")

new_branch_card = """
  Widget _buildBranchCard(Map<String, dynamic> stat, NumberFormat format) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BranchReturnOrderDetailsScreen(
              branchName: stat['branchName']?.toString() ?? 'Unknown Branch',
              items: stat['items'] as List<dynamic>? ?? [],
            ),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      stat['branchName']?.toString() ?? 'Unknown Branch',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.assignment_return, color: Colors.blue),
                ],
              ),
              const Divider(height: 24),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ITEMS RETURNED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                      Text('${stat['totalQuantity'] ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('TOTAL AMOUNT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                      Text(format.format(stat['totalAmount'] ?? 0), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.orange[800])),
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
"""

code = re.sub(r"Widget _buildBranchCard\(Map<String, dynamic> stat, NumberFormat format\) \{.*?  \}\n", new_branch_card, code, flags=re.DOTALL)

with open('lib/manager_return_order_report.dart', 'w') as f:
    f.write(code)

