import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BranchExpenseDetailsScreen extends StatelessWidget {
  final String branchName;
  final List<dynamic> items;

  const BranchExpenseDetailsScreen({
    super.key,
    required this.branchName,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('$branchName - Expense Details', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: items.isEmpty
          ? const Center(child: Text('No expenses found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                final category = item['category']?.toString() ?? 'Unknown Category';
                final reason = item['reason']?.toString() ?? 'No reason provided';
                final amount = (item['amount'] ?? 0).toDouble();
                final time = item['time'] != null 
                    ? DateFormat('MMM dd, hh:mm a').format(DateTime.parse(item['time']).toLocal())
                    : '';
                
                final imageUrl = item['imageUrl']?.toString() ?? '';

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
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
                                  Text(category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text(reason, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(format.format(amount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.red)),
                                const SizedBox(height: 4),
                                Text(time, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                              ],
                            ),
                          ],
                        ),
                        if (imageUrl.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.receipt_long, size: 16, color: Colors.blue),
                              const SizedBox(width: 6),
                              Text('Receipt attached', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
