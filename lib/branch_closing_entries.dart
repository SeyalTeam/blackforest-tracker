import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BranchClosingEntriesScreen extends StatelessWidget {
  final Map<String, dynamic> stat;

  const BranchClosingEntriesScreen({super.key, required this.stat});

  @override
  Widget build(BuildContext context) {
    final entries = stat['entries'] as List<dynamic>? ?? [];
    final branchName = stat['branchName']?.toString() ?? 'Branch';
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: Text('$branchName - Closing Entries', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: entries.isEmpty
          ? const Center(child: Text('No closing entries found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const Divider(height: 24),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final closingNumber = entry['closingNumber']?.toString() ?? 'N/A';
                final createdAtStr = entry['createdAt']?.toString() ?? '';
                final createdAt = DateTime.tryParse(createdAtStr)?.toLocal();
                final dateStr = createdAt != null ? DateFormat('MMM dd, hh:mm a').format(createdAt) : '';

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              closingNumber,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              dateStr,
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(child: _buildItem('System Sales', entry['systemSales'], currencyFormat)),
                            Expanded(child: _buildItem('Manual Sales', entry['manualSales'], currencyFormat)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildItem('Online Sales', entry['onlineSales'], currencyFormat)),
                            Expanded(child: _buildItem('Total Sales', entry['totalSales'], currencyFormat, isBold: true)),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(child: _buildItem('Expenses', entry['expenses'], currencyFormat, color: Colors.red)),
                            Expanded(child: _buildItem('Net Amount', entry['net'], currencyFormat, isBold: true, color: Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildItem('Cash', entry['cash'], currencyFormat)),
                            Expanded(child: _buildItem('UPI', entry['upi'], currencyFormat)),
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

  Widget _buildItem(String label, dynamic value, NumberFormat format, {bool isBold = false, Color? color}) {
    final numValue = (value ?? 0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Text(
          format.format(numValue),
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
