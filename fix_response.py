import re

with open('lib/branch_closing_entries.dart', 'r') as f:
    code = f.read()

old_block = """
      if (true) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply submitted successfully')));
        }
      } else {
        throw Exception('Failed to submit: ${response.statusCode}');
      }
"""

new_block = """
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply submitted successfully')));
      }
"""

code = code.replace(old_block.strip(), new_block.strip())

# Also fix initialValue warning on DropdownButtonFormField, initialValue doesn't work for changing values dynamically if it rebuilds, value is correct. Wait, the warning said "Use initialValue instead." but DropdownButtonFormField in Flutter uses value? Actually, I should use 'value' in standard DropdownButton, but DropdownButtonFormField uses both depending on the version. Let's just suppress the deprecated warning or use value because it's a dropdown. Wait, let me revert initialValue to value.

code = code.replace("initialValue: _selectedEntryId,", "value: _selectedEntryId,")

with open('lib/branch_closing_entries.dart', 'w') as f:
    f.write(code)

