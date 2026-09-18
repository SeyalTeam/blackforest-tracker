import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BranchDealerDetailsScreen extends StatelessWidget {
  final String branchName;
  final List<dynamic> items; // list of bills for this branch

  const BranchDealerDetailsScreen({
    super.key,
    required this.branchName,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('$branchName - Dealer Bills', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: items.isEmpty
          ? const Center(child: Text('No dealer bills found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                final dealerName = item['dealerName']?.toString() ?? 'Unknown Dealer';
                final amount = (item['amount'] ?? 0).toDouble();
                
                final status = item['status']?.toString() ?? 'pending';
                final time = item['time'] != null 
                    ? DateFormat('hh:mm a').format(DateTime.parse(item['time']).toLocal())
                    : '';

                Color statusColor = Colors.orange;
                if (status == 'paid') statusColor = Colors.green;
                else if (status == 'cancelled') statusColor = Colors.red;

                final products = item['products'] as List<dynamic>? ?? [];

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dealerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.access_time, size: 12, color: Colors.grey[500]),
                                    const SizedBox(width: 4),
                                    Text(time, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(format.format(amount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      children: [
                        if (products.isNotEmpty) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Products', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                                const SizedBox(height: 8),
                                ...products.map((p) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('${p['name']} x ${p['quantity'] ?? 1}', style: const TextStyle(fontSize: 13)),
                                        Text(format.format((p['totalAmount'] ?? 0).toDouble()), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
