import re

with open('lib/branch_closing_entries.dart', 'r') as f:
    code = f.read()

# I will just write a clean new version of branch_closing_entries.dart 
# Actually, I can just truncate everything after `class _ManagerReplyForm extends StatefulWidget`
match = re.search(r'class _ManagerReplyForm extends StatefulWidget \{', code)
if match:
    code = code[:match.start()]

# And remove the floating action button from Scaffold
fab_pattern = r'floatingActionButton: entries\.isNotEmpty.*?null,'
code = re.sub(fab_pattern, '', code, flags=re.DOTALL)

# And remove `void _showReplyBottomSheet` method
show_reply_pattern = r'void _showReplyBottomSheet\(List<dynamic> entries, String branchId\).*?\}\);.*?\}'
code = re.sub(show_reply_pattern, '', code, flags=re.DOTALL)

with open('lib/branch_closing_entries.dart', 'w') as f:
    f.write(code)

