import re

with open('lib/manager_stock_order_report.dart', 'r') as f:
    code = f.read()

new_branch_card = """
  Widget _buildBranchCard(Map<String, dynamic> stat, NumberFormat format, List<dynamic> allDetails) {
    final branchName = stat['branchName']?.toString() ?? 'Unknown Branch';
    final branchDetails = allDetails.where((d) => d['branchName']?.toString() == branchName).toList();
    
    double orderValue = 0;
    double receivedValue = 0;
    String latestOrderTime = '';

    for (var d in branchDetails) {
      double price = (d['price'] ?? 0).toDouble();
      orderValue += ((d['ordQty'] ?? 0) as num).toDouble() * price;
      receivedValue += ((d['recQty'] ?? 0) as num).toDouble() * price;
      
      final ordTime = d['ordTime']?.toString() ?? '';
      if (ordTime.isNotEmpty) {
        if (latestOrderTime.isEmpty || ordTime.compareTo(latestOrderTime) > 0) {
          latestOrderTime = ordTime;
        }
      }
    }

    String timeStr = '--';
    if (latestOrderTime.isNotEmpty) {
      timeStr = DateFormat('MMM dd, hh:mm a').format(DateTime.parse(latestOrderTime).toLocal());
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BranchStockOrderDetailsScreen(
              branchName: branchName,
              details: branchDetails,
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
                      branchName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    timeStr,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const Divider(height: 24),
              
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ORDER COUNT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Text('${stat['totalOrders'] ?? 0}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ORDER VALUE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Text(format.format(orderValue), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('RECEIVED VALUE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Text(format.format(receivedValue), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green[700])),
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

code = re.sub(r"Widget _buildBranchCard\(Map<String, dynamic> stat, NumberFormat format, List<dynamic> allDetails\) \{.*?  \}\n", new_branch_card, code, flags=re.DOTALL)

with open('lib/manager_stock_order_report.dart', 'w') as f:
    f.write(code)
