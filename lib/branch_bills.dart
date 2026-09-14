import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class BranchBillsScreen extends StatefulWidget {
  final String branchId;
  final String branchName;
  final DateTime date;

  const BranchBillsScreen({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.date,
  });

  @override
  State<BranchBillsScreen> createState() => _BranchBillsScreenState();
}

class _BranchBillsScreenState extends State<BranchBillsScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  List<dynamic> _bills = [];

  @override
  void initState() {
    super.initState();
    _fetchBills();
  }

  Future<void> _fetchBills() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final bills = await ApiService.instance.fetchBranchBills(
        branchId: widget.branchId,
        date: widget.date,
      );

      setState(() {
        _bills = bills;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load bills: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    if (_isLoading) {
      bodyContent = const Center(child: CircularProgressIndicator());
    } else if (_errorMessage.isNotEmpty) {
      bodyContent = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchBills, child: const Text('Retry')),
          ],
        ),
      );
    } else if (_bills.isEmpty) {
      bodyContent = const Center(
        child: Text('No bills found for this date.', style: TextStyle(color: Colors.grey)),
      );
    } else {
      final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
      final timeFormat = DateFormat('hh:mm a');

      bodyContent = RefreshIndicator(
        onRefresh: _fetchBills,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _bills.length,
          separatorBuilder: (context, index) => const Divider(height: 24),
          itemBuilder: (context, index) {
            final bill = _bills[index];
            final billNo = bill['invoiceNumber']?.toString() ?? 'N/A';
            
            DateTime? createdAt;
            if (bill['createdAt'] != null) {
              createdAt = DateTime.tryParse(bill['createdAt'].toString())?.toLocal();
            }
            final timeStr = createdAt != null ? timeFormat.format(createdAt) : 'Unknown time';
            
            final amount = (bill['totalAmount'] ?? 0).toDouble();
            final paymentMethod = bill['paymentMethod']?.toString().toUpperCase() ?? 'UNKNOWN';

            return Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.receipt, color: Colors.blue),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        billNo,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeStr,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currencyFormat.format(amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        paymentMethod,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    final dateDisplay = DateFormat('dd MMM yyyy').format(widget.date);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.branchName, style: const TextStyle(fontSize: 16)),
            Text(
              dateDisplay,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: bodyContent,
    );
  }
}
