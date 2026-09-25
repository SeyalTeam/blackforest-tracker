import re

with open('lib/manager_closing_report.dart', 'r') as f:
    code = f.read()

# Replace stat['branchId'] with (stat['branchId'] ?? stat['_id'])
old_code = "branchId: stat['branchId']?.toString() ?? '',"
new_code = "branchId: (stat['branchId'] ?? stat['_id'])?.toString() ?? '',"
code = code.replace(old_code, new_code)

with open('lib/manager_closing_report.dart', 'w') as f:
    f.write(code)

