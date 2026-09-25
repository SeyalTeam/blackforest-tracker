import re

with open('lib/manager_closing_reply_screen.dart', 'r') as f:
    code = f.read()

old_submit_start = """
    try {
      int getValue(String key) => int.tryParse(_denominations[key]!.text) ?? 0;

      final body = {
"""

new_submit_start = """
    try {
      // Validate duplicate replies before submitting
      String queryDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (widget.entries.isNotEmpty) {
        final createdAtStr = widget.entries.first['createdAt']?.toString() ?? '';
        final createdAt = DateTime.tryParse(createdAtStr)?.toLocal();
        if (createdAt != null) {
          queryDate = DateFormat('yyyy-MM-dd').format(createdAt);
        }
      }

      final existingReplies = await ApiService.instance.fetchManagerClosingReplies(
        branchId: widget.branchId, 
        dateStr: queryDate,
      );

      final typeToSubmit = widget.entries.length > 1 ? _replyType : 'common';
      
      if (typeToSubmit == 'common') {
        final hasCommon = existingReplies.any((r) => r['type'] == 'common');
        if (hasCommon) {
          throw Exception('A common reply already exists for this day.');
        }
      } else {
        final hasIndividual = existingReplies.any((r) {
           if (r['type'] != 'individual') return false;
           final ce = r['closingEntry'];
           final ceId = (ce is Map ? (ce['id'] ?? ce['_id']) : ce)?.toString();
           return ceId == _selectedEntryId;
        });
        if (hasIndividual) {
          throw Exception('A reply already exists for this specific entry.');
        }
      }

      int getValue(String key) => int.tryParse(_denominations[key]!.text) ?? 0;

      final body = {
"""

code = code.replace(old_submit_start.strip(), new_submit_start.strip())

with open('lib/manager_closing_reply_screen.dart', 'w') as f:
    f.write(code)

