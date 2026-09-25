import re

with open('lib/manager_closing_report.dart', 'r') as f:
    code = f.read()

# I need to add branchId and _id to the 0-value template.
old_template = """
        // Add a 0-value template for this branch
        grouped[cId]!.add({
          'branchName': bName,
          'totalEntries': 0,
          'cash': 0.0,
"""

new_template = """
        // Add a 0-value template for this branch
        grouped[cId]!.add({
          '_id': b['id'] ?? b['_id'],
          'branchId': b['id'] ?? b['_id'],
          'branchName': bName,
          'totalEntries': 0,
          'cash': 0.0,
"""

code = code.replace(old_template.strip(), new_template.strip())

with open('lib/manager_closing_report.dart', 'w') as f:
    f.write(code)

