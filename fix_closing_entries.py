import re

with open('lib/branch_closing_entries.dart', 'r') as f:
    code = f.read()

# Replace the _submit logic
old_submit = """
      final baseUrl = ApiService.instance.baseUrl;
      final token = await ApiService.instance.getToken();
      
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

      final response = await http.post(
        Uri.parse('$baseUrl/manager-closing-replies'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
"""

new_submit = """
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

      if (true) {
"""

code = code.replace(old_submit.strip(), new_submit.strip())

# Fix dropdown initialValue warning
code = code.replace("value: _selectedEntryId,", "initialValue: _selectedEntryId,")

with open('lib/branch_closing_entries.dart', 'w') as f:
    f.write(code)

