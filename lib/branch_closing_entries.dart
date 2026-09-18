
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

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
    final entries = widget.stat['entries'] as List<dynamic>? ?? [];
    final branchId = widget.stat['branchId']?.toString() ?? '';
    if (branchId.isEmpty) return;

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
      final replies = await ApiService.instance.fetchManagerClosingReplies(branchId: branchId, date: queryDate);
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


  void _showReplyBottomSheet(List<dynamic> entries, String branchId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ManagerReplyForm(entries: entries, branchId: branchId);
      },
    );
    _fetchReplies(); // Refresh replies after closing the bottom sheet
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.stat['entries'] as List<dynamic>? ?? [];
    final branchName = widget.stat['branchName']?.toString() ?? 'Branch';
    final branchId = widget.stat['branchId']?.toString() ?? '';

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
              itemCount: entries.length + (_replies.any((r) => r['type'] == 'common') ? _replies.where((r) => r['type'] == 'common').length + 1 : 0),
              separatorBuilder: (context, index) => const Divider(height: 24),
              
itemBuilder: (context, index) {
                // If this is past the entries length, it's the common replies section
                if (index >= entries.length) {
                  final commonReplies = _replies.where((r) => r['type'] == 'common').toList();
                  final commonIndex = index - entries.length;
                  if (commonIndex == 0 && commonReplies.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: const Text('Common Replies', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    );
                  }
                  final replyIndex = commonReplies.isNotEmpty ? commonIndex - 1 : -1;
                  if (replyIndex >= 0 && replyIndex < commonReplies.length) {
                    return _buildReplyCard(commonReplies[replyIndex], isCommon: true);
                  }
                  return const SizedBox.shrink();
                }
                

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
                        // INJECT INDIVIDUAL REPLY HERE
                        ..._replies
                            .where((r) => r['type'] == 'individual' && r['closingEntry'] != null)
                            .where((r) {
                              final ce = r['closingEntry'];
                              final ceId = ce is Map ? (ce['id'] ?? ce['_id']) : ce;
                              final entryId = entry['id'] ?? entry['_id'];
                              return ceId?.toString() == entryId?.toString();
                            })
                            .map((r) => _buildReplyCard(r, isCommon: false)),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: entries.isNotEmpty && branchId.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showReplyBottomSheet(entries, branchId),
              icon: const Icon(Icons.reply),
              label: const Text('Manager Reply'),
              backgroundColor: Colors.indigo,
            )
          : null,
    );
  }

  
  Widget _buildReplyCard(Map<String, dynamic> reply, {bool isCommon = false}) {
    final msg = reply['message']?.toString() ?? '';
    final totalAmount = (reply['totalAmount'] ?? 0).toDouble();
    final typeLabel = isCommon ? 'Common Manager Reply' : 'Manager Reply';
    
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.05),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.reply, size: 16, color: Colors.indigo),
              const SizedBox(width: 8),
              Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
              const Spacer(),
              Text(_currencyFormat.format(totalAmount), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.indigo)),
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

class _ManagerReplyForm extends StatefulWidget {
  final List<dynamic> entries;
  final String branchId;

  const _ManagerReplyForm({required this.entries, required this.branchId});

  @override
  State<_ManagerReplyForm> createState() => _ManagerReplyFormState();
}

class _ManagerReplyFormState extends State<_ManagerReplyForm> {
  String _replyType = 'common';
  String? _selectedEntryId;
  final TextEditingController _messageController = TextEditingController();

  final Map<String, TextEditingController> _denominations = {
    'rs500': TextEditingController(),
    'rs200': TextEditingController(),
    'rs100': TextEditingController(),
    'rs50': TextEditingController(),
    'rs20': TextEditingController(),
    'rs10': TextEditingController(),
    'coins': TextEditingController(),
  };

  int _totalAmount = 0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.entries.length == 1) {
      _selectedEntryId = widget.entries.first['id']?.toString();
    }
    for (var controller in _denominations.values) {
      controller.addListener(_calculateTotal);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    for (var controller in _denominations.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _calculateTotal() {
    int total = 0;
    int getValue(String key) => int.tryParse(_denominations[key]!.text) ?? 0;

    total += getValue('rs500') * 500;
    total += getValue('rs200') * 200;
    total += getValue('rs100') * 100;
    total += getValue('rs50') * 50;
    total += getValue('rs20') * 20;
    total += getValue('rs10') * 10;
    total += getValue('coins');

    setState(() {
      _totalAmount = total;
    });
  }

  Future<void> _submit() async {
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a message')));
      return;
    }

    if (widget.entries.length > 1 && _replyType == 'individual' && _selectedEntryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a closing entry')));
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      int getValue(String key) => int.tryParse(_denominations[key]!.text) ?? 0;

      final body = {
        'branch': widget.branchId,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'type': widget.entries.length > 1 ? _replyType : 'common',
        'closingEntry': _replyType == 'individual' ? _selectedEntryId : null,
        'message': _messageController.text.trim(),
        'denominations': {
          'rs500': getValue('rs500'),
          'rs200': getValue('rs200'),
          'rs100': getValue('rs100'),
          'rs50': getValue('rs50'),
          'rs20': getValue('rs20'),
          'rs10': getValue('rs10'),
          'coins': getValue('coins'),
        },
        'totalAmount': _totalAmount,
      };

      await ApiService.instance.submitManagerClosingReply(body);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply submitted successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildDenomRow(String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Text('x', style: TextStyle(color: Colors.grey)),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _denominations[key],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Manager Reply & Denomination', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            if (widget.entries.length > 1) ...[
              const Text('Reply Type', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Radio<String>(
                    value: 'common',
                    groupValue: _replyType,
                    onChanged: (val) {
                      setState(() {
                        _replyType = val!;
                      });
                    },
                  ),
                  const Text('Common'),
                  const SizedBox(width: 16),
                  Radio<String>(
                    value: 'individual',
                    groupValue: _replyType,
                    onChanged: (val) {
                      setState(() {
                        _replyType = val!;
                      });
                    },
                  ),
                  const Text('Individual'),
                ],
              ),
              if (_replyType == 'individual') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedEntryId,
                  hint: const Text('Select Closing Entry'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: widget.entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry['id']?.toString(),
                      child: Text('Entry: ${entry['closingNumber'] ?? 'Unknown'}'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedEntryId = val;
                    });
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],

            const Text('Message', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter your reply...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            const Text('Cash Denomination', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),

            _buildDenomRow('₹ 500', 'rs500'),
            _buildDenomRow('₹ 200', 'rs200'),
            _buildDenomRow('₹ 100', 'rs100'),
            _buildDenomRow('₹ 50', 'rs50'),
            _buildDenomRow('₹ 20', 'rs20'),
            _buildDenomRow('₹ 10', 'rs10'),
            _buildDenomRow('Coins', 'coins'),

            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(currencyFormat.format(_totalAmount), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.green[700])),
              ],
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Submit Reply', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
