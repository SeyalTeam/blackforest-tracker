import re

with open('lib/branch_closing_entries.dart', 'r') as f:
    code = f.read()

# Fix parameter name in fetchManagerClosingReplies
code = code.replace("date: queryDate", "dateStr: queryDate")

# Remove _showReplyBottomSheet entirely
show_reply_pattern = r'void _showReplyBottomSheet.*?_fetchReplies\(\); // Refresh replies after closing the bottom sheet\s*\}'
code = re.sub(show_reply_pattern, '', code, flags=re.DOTALL)

with open('lib/branch_closing_entries.dart', 'w') as f:
    f.write(code)

with open('lib/manager_closing_reply_screen.dart', 'r') as f:
    code = f.read()

# Fix initialValue/value radio warnings in manager_closing_reply_screen.dart
# The warnings are about Radio groupValue and onChanged. Flutter 3.32 deprecated Radio's value/groupValue in favor of RadioGroup. Wait, actually Radio<T> requires value, groupValue, and onChanged. If they are deprecated, it's just a warning. Let's ignore or fix if possible. I'll just ignore info/warnings.

