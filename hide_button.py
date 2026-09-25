import re

with open('lib/branch_closing_entries.dart', 'r') as f:
    code = f.read()

# Replace the "Add reply button under total declared" block so it's wrapped in `if (individualReplies.isEmpty)`
old_button_block = """
                            // Add reply button under total declared
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: () async {
"""

new_button_block = """
                            // Add reply button under total declared
                            if (individualReplies.isEmpty)
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
"""

code = code.replace(old_button_block.strip(), new_button_block.strip())

with open('lib/branch_closing_entries.dart', 'w') as f:
    f.write(code)

