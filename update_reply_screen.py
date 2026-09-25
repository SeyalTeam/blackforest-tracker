import re

with open('lib/manager_closing_reply_screen.dart', 'r') as f:
    code = f.read()

# Add initial parameters
old_constructor = """
class ManagerClosingReplyScreen extends StatefulWidget {
  final String branchId;
  final String branchName;
  final List<dynamic> entries;

  const ManagerClosingReplyScreen({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.entries,
  });
"""

new_constructor = """
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
"""

code = code.replace(old_constructor.strip(), new_constructor.strip())

# Update initState
old_init = """
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
"""

new_init = """
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
"""

code = code.replace(old_init.strip(), new_init.strip())

with open('lib/manager_closing_reply_screen.dart', 'w') as f:
    f.write(code)

