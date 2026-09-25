import re

with open('lib/branch_closing_entries.dart', 'r') as f:
    code = f.read()

# I will add state for fetching replies
new_state_vars = """
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
"""

# Insert state vars after _currencyFormat
code = re.sub(r'(final NumberFormat _currencyFormat = NumberFormat.currency\(symbol: \'₹\', decimalDigits: 0\);)', r'\1\n' + new_state_vars, code)

# Change _showReplyBottomSheet to refresh after pop
old_bottom_sheet = """
  void _showReplyBottomSheet(List<dynamic> entries, String branchId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ManagerReplyForm(entries: entries, branchId: branchId);
      },
    );
  }
"""

new_bottom_sheet = """
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
"""
code = code.replace(old_bottom_sheet.strip(), new_bottom_sheet.strip())


# Now inject the display widget for a reply
reply_widget_method = """
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
"""

code = code.replace("Widget _buildItem", reply_widget_method + "\n  Widget _buildItem")

# Now update the build method to show replies under cards
old_listview = "itemBuilder: (context, index) {"

new_listview = """
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
"""
code = code.replace(old_listview, new_listview)

# Fix itemCount
old_item_count = "itemCount: entries.length,"
new_item_count = "itemCount: entries.length + (_replies.any((r) => r['type'] == 'common') ? _replies.where((r) => r['type'] == 'common').length + 1 : 0),"
code = code.replace(old_item_count, new_item_count)

# Add individual replies under the card
old_card_end = """
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                );
"""
new_card_end = """
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
"""
code = code.replace(old_card_end.strip(), new_card_end.strip())

with open('lib/branch_closing_entries.dart', 'w') as f:
    f.write(code)

