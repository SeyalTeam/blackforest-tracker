import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class ManagerClosingReplyScreen extends StatefulWidget {
  final String branchId;
  final String branchName;
  final List<dynamic> entries;
  final String? initialReplyType;
  final String? initialEntryId;

  const ManagerClosingReplyScreen({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.entries,
    this.initialReplyType,
    this.initialEntryId,
  });

  @override
  State<ManagerClosingReplyScreen> createState() => _ManagerClosingReplyScreenState();
}

class _ManagerClosingReplyScreenState extends State<ManagerClosingReplyScreen> {
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
    if (widget.initialReplyType != null) {
      _replyType = widget.initialReplyType!;
    }
    if (widget.initialEntryId != null) {
      _selectedEntryId = widget.initialEntryId;
    } else if (widget.entries.length == 1) {
      _selectedEntryId = widget.entries.first['id']?.toString() ?? widget.entries.first['_id']?.toString();
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
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const Text('x', style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _denominations[key],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Reply', style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.branchName} - Cash Denomination', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),

            if (widget.entries.length > 1) ...[
              const Text('Reply Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
              const SizedBox(height: 24),
            ],

            const Text('Message', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter your reply...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),

            const Text('Cash Denomination', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),

            _buildDenomRow('₹ 500', 'rs500'),
            _buildDenomRow('₹ 200', 'rs200'),
            _buildDenomRow('₹ 100', 'rs100'),
            _buildDenomRow('₹ 50', 'rs50'),
            _buildDenomRow('₹ 20', 'rs20'),
            _buildDenomRow('₹ 10', 'rs10'),
            _buildDenomRow('Coins', 'coins'),

            const Divider(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Amount', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(currencyFormat.format(_totalAmount), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.green[700])),
              ],
            ),
            const SizedBox(height: 32),
            
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Submit Reply', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
