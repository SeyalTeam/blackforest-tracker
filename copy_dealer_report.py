import re

with open('lib/manager_closing_report.dart', 'r') as f:
    code = f.read()

# Replace class names
code = code.replace('BranchClosingReportScreen', 'BranchDealerReportScreen')
code = code.replace('_BranchClosingReportScreenState', '_BranchDealerReportScreenState')
code = code.replace('ManagerClosingReportScreen', 'ManagerDealerReportScreen')
code = code.replace('_ManagerClosingReportScreenState', '_ManagerDealerReportScreenState')

# Replace API call
code = code.replace('fetchClosingEntryReport', 'fetchDealerReport')
code = code.replace('_closingReport', '_dealerReport')

# Replace titles and text
code = code.replace("'Closing Entry Report'", "'Dealer Report'")

# Replace import branch_closing_entries.dart with branch_dealer_details.dart
code = code.replace("import 'branch_closing_entries.dart';", "import 'branch_dealer_details.dart';")

# In the grouping logic _groupStatsByCompany, it uses _closingReport?['stats']
# Dealer uses _dealerReport?['groups']
code = code.replace("_dealerReport?['stats']", "_dealerReport?['groups']")

# Replace the default branch stats
default_stats = """
        grouped[cId]!.add({
          'branchName': bName,
          'total': 0.0,
          'count': 0,
          'items': [],
        });
"""
# Find and replace the default branch dict
code = re.sub(r"grouped\[cId\]!\.add\(\{\s*'branchName': bName,[^\}]+\}\);", default_stats.strip(), code, flags=re.MULTILINE)

# Sorting
code = re.sub(r"final amountA = \(a\['net'\].*?\)\.toDouble\(\);", "final amountA = (a['total'] ?? 0).toDouble();", code)
code = re.sub(r"final amountB = \(b\['net'\].*?\)\.toDouble\(\);", "final amountB = (b['total'] ?? 0).toDouble();", code)

# Rewrite the _buildBranchCard completely for dealer
new_branch_card = """
  Widget _buildBranchCard(Map<String, dynamic> stat, NumberFormat format) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BranchDealerDetailsScreen(
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
                  const Icon(Icons.local_shipping, color: Colors.blue),
                ],
              ),
              const Divider(height: 24),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOTAL BILLS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                      Text('${stat['count'] ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('TOTAL AMOUNT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                      Text(format.format(stat['total'] ?? 0), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blue[800])),
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

with open('lib/manager_dealer_report.dart', 'w') as f:
    f.write(code)
