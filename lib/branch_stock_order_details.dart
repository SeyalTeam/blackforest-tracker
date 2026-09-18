import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BranchStockOrderDetailsScreen extends StatelessWidget {
  final String branchName;
  final List<dynamic> details; // pre-filtered branch details

  const BranchStockOrderDetailsScreen({
    super.key,
    required this.branchName,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: Text('$branchName - Stock Order Details', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: details.isEmpty
          ? const Center(child: Text('No stock order details found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: details.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = details[index];
                
                final productName = item['productName']?.toString() ?? 'Unknown Product';
                final deptName = item['departmentName']?.toString() ?? '';
                final catName = item['categoryName']?.toString() ?? '';
                
                final price = (item['price'] ?? 0).toDouble();
                final invoice = item['invoiceNumber']?.toString() ?? 'N/A';
                
                final ordQty = item['ordQty'] ?? 0;
                final picQty = item['picQty'] ?? 0;
                final recQty = item['recQty'] ?? 0;

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text('$deptName • $catName', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(format.format(price), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text('Inv: $invoice', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildQtyBox('Ordered', ordQty, Colors.blue),
                            _buildQtyBox('Picked (Driver)', picQty, Colors.orange),
                            _buildQtyBox('Received', recQty, Colors.green),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildQtyBox(String label, dynamic qty, MaterialColor color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.shade200),
          ),
          child: Text('$qty', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade700)),
        ),
      ],
    );
  }
}
