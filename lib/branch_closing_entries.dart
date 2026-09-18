
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';
import 'manager_closing_reply_screen.dart';

class BranchClosingEntriesScreen extends StatefulWidget {
  final Map<String, dynamic> stat;

  const BranchClosingEntriesScreen({super.key, required this.stat});

  @override
  State<BranchClosingEntriesScreen> createState() => _BranchClosingEntriesScreenState();
}

class _BranchClosingEntriesScreenState extends State<BranchClosingEntriesScreen> {
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  List<dynamic> _replies = [];
  bool _isLoadingReplies = false;

  @override
  void initState() {
    super.initState();
    _fetchReplies();
  }

  Future<void> _fetchReplies() async {
    final branchId = widget.stat['branchId']?.toString() ?? widget.stat['_id']?.toString() ?? '';
    if (branchId.isEmpty) return;

    final entries = widget.stat['entries'] as List<dynamic>? ?? [];
    String queryDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    if (entries.isNotEmpty) {
      final createdAtStr = entries.first['createdAt']?.toString() ?? '';
      final createdAt = DateTime.tryParse(createdAtStr)?.toLocal();
      if (createdAt != null) {
        queryDate = DateFormat('yyyy-MM-dd').format(createdAt);
      }
    }

    setState(() {
      _isLoadingReplies = true;
    });

    try {
      final replies = await ApiService.instance.fetchManagerClosingReplies(branchId: branchId, dateStr: queryDate);
      if (mounted) {
        setState(() {
          _replies = replies;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingReplies = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.stat['entries'] as List<dynamic>? ?? [];
    final branchName = widget.stat['branchName']?.toString() ?? 'Branch';
    final branchId = widget.stat['branchId']?.toString() ?? widget.stat['_id']?.toString() ?? '';
    
    final commonReplies = _replies.where((r) => r['type'] == 'common').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('$branchName - Closing Entries', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        onRefresh: _fetchReplies,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (commonReplies.isNotEmpty) ...[
              const Text('Common Replies', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ...commonReplies.map((r) => _buildReplyCard(r, isCommon: true)),
              const SizedBox(height: 24),
            ],
            
            if (entries.isEmpty)
              const Center(child: Text('No closing entries found.'))
            else
              ...entries.map((entry) {
                final entryId = entry['id']?.toString() ?? entry['_id']?.toString() ?? '';
                final closingNumber = entry['closingNumber']?.toString() ?? 'N/A';
                final createdAtStr = entry['createdAt']?.toString() ?? '';
                final createdAt = DateTime.tryParse(createdAtStr)?.toLocal();
                final dateStr = createdAt != null ? DateFormat('MMM dd, hh:mm a').format(createdAt) : '';

                final individualReplies = _replies.where((r) {
                  if (r['type'] != 'individual') return false;
                  final ce = r['closingEntry'];
                  final ceId = (ce is Map ? (ce['id'] ?? ce['_id']) : ce)?.toString() ?? '';
                  return ceId == entryId;
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1,
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
                                Expanded(child: _buildItem('System Sales', entry['systemSales'], _currencyFormat)),
                                Expanded(child: _buildItem('Manual Sales', entry['manualSales'], _currencyFormat)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _buildItem('Online Sales', entry['onlineSales'], _currencyFormat)),
                                Expanded(child: _buildItem('Total Sales', entry['totalSales'], _currencyFormat, isBold: true)),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                Expanded(child: _buildItem('Expenses', entry['expenses'], _currencyFormat, color: Colors.red)),
                                Expanded(child: _buildItem('Net Sales (Total - Exp)', entry['net'], _currencyFormat, isBold: true)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _buildItem('Cash', entry['cash'], _currencyFormat)),
                                Expanded(child: _buildItem('UPI', entry['upi'], _currencyFormat)),
                              ],
                            ),
                            const Divider(height: 24),
                            Builder(
                              builder: (context) {
                                final net = (entry['net'] ?? entry['totalSales'] ?? 0).toDouble();
                                final cash = (entry['cash'] ?? 0).toDouble();
                                final upi = (entry['upi'] ?? 0).toDouble();
                                final card = (entry['card'] ?? 0).toDouble();
                                
                                final totalCollection = cash + upi + card;
                                final difference = totalCollection - net;

                                String diffText = '';
                                Color diffColor = Colors.grey;
                                if (difference > 0) {
                                  diffText = '+${_currencyFormat.format(difference)} (Excess)';
                                  diffColor = Colors.green;
                                } else if (difference < 0) {
                                  diffText = '${_currencyFormat.format(difference)} (Short)';
                                  diffColor = Colors.red;
                                } else {
                                  diffText = 'Matched';
                                  diffColor = Colors.blue;
                                }

                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Total Declared', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                        Text(_currencyFormat.format(totalCollection), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: diffColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        diffText,
                                        style: TextStyle(fontWeight: FontWeight.bold, color: diffColor, fontSize: 14),
                                      ),
                                    ),
                                  ],
                                );
                              }
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Display individual replies for this entry inside the card
                            if (individualReplies.isNotEmpty)
                              Column(
                                children: individualReplies.map((r) => _buildReplyCard(r, isCommon: false)).toList(),
                              ),

                            // Add reply button under total declared
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ManagerClosingReplyScreen(
                                        branchId: branchId,
                                        branchName: branchName,
                                        entries: entries,
                                        initialReplyType: 'individual',
                                        initialEntryId: entryId,
                                      ),
                                    ),
                                  );
                                  _fetchReplies(); // Refresh after adding
                                },
                                icon: const Icon(Icons.reply, size: 18),
                                label: const Text('Add Manager Reply', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.withValues(alpha: 0.05),
                                  foregroundColor: Colors.blue[700],
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyCard(Map<String, dynamic> reply, {bool isCommon = false}) {
    final msg = reply['message']?.toString() ?? '';
    final totalAmount = (reply['totalAmount'] ?? 0).toDouble();
    final typeLabel = isCommon ? 'Common Reply' : 'Individual Reply';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.comment, size: 14, color: Colors.blue),
              const SizedBox(width: 8),
              Text(typeLabel, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800], fontSize: 12)),
              const Spacer(),
              Text(_currencyFormat.format(totalAmount), style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green[700])),
            ],
          ),
          const SizedBox(height: 8),
          Text(msg, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildItem(String label, dynamic amount, NumberFormat format, {bool isBold = false, Color? color}) {
    final val = (amount ?? 0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(
          format.format(val),
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
