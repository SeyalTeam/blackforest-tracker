import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BranchReturnOrderDetailsScreen extends StatelessWidget {
  final String branchName;
  final List<dynamic> items;

  const BranchReturnOrderDetailsScreen({
    super.key,
    required this.branchName,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: Text('$branchName - Return Order Details', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: items.isEmpty
          ? const Center(child: Text('No return orders found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                
                final product = item['product']?.toString() ?? 'Unknown Product';
                final reason = item['notes']?.toString() ?? 'No reason provided';
                final amount = (item['subtotal'] ?? 0).toDouble();
                final qty = item['quantity'] ?? 0;
                final status = item['status']?.toString() ?? 'pending';
                final time = item['time'] != null 
                    ? DateFormat('MMM dd, hh:mm a').format(DateTime.parse(item['time']).toLocal())
                    : '';
                
                final imageUrl = item['imageUrl']?.toString() ?? '';

                // Fix relative URLs
                String fullImageUrl = imageUrl;
                if (imageUrl.isNotEmpty && imageUrl.startsWith('/')) {
                  fullImageUrl = 'https://dev1-blacforest.vseyal.com$imageUrl';
                }

                Color statusColor = Colors.orange;
                if (status == 'accepted' || status == 'returned') statusColor = Colors.green;
                else if (status == 'cancelled') statusColor = Colors.red;

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: fullImageUrl.isEmpty ? null : () {
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          insetPadding: const EdgeInsets.all(16),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Stack(
                            children: [
                              InteractiveViewer(
                                child: Image.network(
                                  fullImageUrl,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    padding: const EdgeInsets.all(32),
                                    color: Colors.grey[100],
                                    child: const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.broken_image, size: 64, color: Colors.grey),
                                        SizedBox(height: 16),
                                        Text('Image not available', style: TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.black54),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(alpha: 0.8),
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
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
                                    Text('$product (x$qty)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text(reason, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(format.format(amount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.orange)),
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
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(time, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                              if (imageUrl.isNotEmpty)
                                Row(
                                  children: [
                                    const Icon(Icons.photo, size: 14, color: Colors.blue),
                                    const SizedBox(width: 4),
                                    const Text('Tap to view photo', style: TextStyle(fontSize: 11, color: Colors.blue)),
                                  ],
                                )
                              else
                                const Text('No photo', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
