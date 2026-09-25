import re

with open('lib/manager_dealer_report.dart', 'r') as f:
    code = f.read()

# Replace class names
code = code.replace('ManagerDealerReportScreen', 'ManagerExpenseReportScreen')
code = code.replace('_ManagerDealerReportScreenState', '_ManagerExpenseReportScreenState')
code = code.replace('BranchDealerDetailsScreen', 'BranchExpenseDetailsScreen')

# Replace API call
code = code.replace('fetchDealerReport', 'fetchExpenseReport')
code = code.replace('_dealerReport', '_expenseReport')

# Replace titles and text
code = code.replace("'Dealer Report'", "'Expense Report'")

# Replace import
code = code.replace("import 'branch_dealer_details.dart';", "import 'branch_expense_details.dart';")

# Rewrite the _buildBranchCard completely for expense
new_branch_card = """
  Widget _buildBranchCard(Map<String, dynamic> stat, NumberFormat format) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BranchExpenseDetailsScreen(
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
                  const Icon(Icons.receipt_long, color: Colors.blue),
                ],
              ),
              const Divider(height: 24),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOTAL EXPENSES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                      Text('${stat['count'] ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('TOTAL AMOUNT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                      Text(format.format(stat['total'] ?? 0), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.red[600])),
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

# Find the builder function and replace it
code = re.sub(r"Widget _buildBranchCard\(Map<String, dynamic> stat, NumberFormat format\) \{.*?  \}\n", new_branch_card, code, flags=re.DOTALL)

with open('lib/manager_expense_report.dart', 'w') as f:
    f.write(code)
