import re

with open('lib/manager_dealer_report.dart', 'r') as f:
    code = f.read()

# Replace class names
code = code.replace('ManagerDealerReportScreen', 'ManagerStockOrderReportScreen')
code = code.replace('_ManagerDealerReportScreenState', '_ManagerStockOrderReportScreenState')
code = code.replace('BranchDealerDetailsScreen', 'BranchStockOrderDetailsScreen')

# Replace API call
code = code.replace('fetchDealerReport', 'fetchStockOrderReport')
code = code.replace('_dealerReport', '_stockOrderReport')

# Replace titles and text
code = code.replace("'Dealer Report'", "'Stock Order Report'")

# Replace import branch_dealer_details.dart with branch_stock_order_details.dart
code = code.replace("import 'branch_dealer_details.dart';", "import 'branch_stock_order_details.dart';")

# In the grouping logic _groupStatsByCompany, it uses _dealerReport?['groups']
# Stock Order uses _stockOrderReport?['stats']
code = code.replace("_stockOrderReport?['groups']", "_stockOrderReport?['stats']")

# Replace the filter field inside _groupStatsByCompany
code = code.replace("stat['count']", "stat['totalOrders']")

# Sorting
code = code.replace("stat['total']", "stat['totalOrders']")

# Rewrite the _buildBranchCard completely for stock order
new_branch_card = """
  Widget _buildBranchCard(Map<String, dynamic> stat, NumberFormat format, List<dynamic> allDetails) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BranchStockOrderDetailsScreen(
              branchName: stat['branchName']?.toString() ?? 'Unknown Branch',
              details: allDetails,
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
                  const Icon(Icons.inventory_2, color: Colors.blue),
                ],
              ),
              const Divider(height: 24),
              
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TOTAL ORDERS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Text('${stat['totalOrders'] ?? 0}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LIVE ORDERS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Text('${stat['liveOrders'] ?? 0}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green[700])),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CLOSED ORDERS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Text('${stat['stockOrders'] ?? 0}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                      ],
                    ),
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

# Add allDetails to the call
code = code.replace("return _buildBranchCard(stat, currencyFormat);", "final allDetails = (_stockOrderReport?['details'] as List<dynamic>? ?? []);\\n                    return _buildBranchCard(stat, currencyFormat, allDetails);")

with open('lib/manager_stock_order_report.dart', 'w') as f:
    f.write(code)
