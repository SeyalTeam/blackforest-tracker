import re

with open('lib/manager_closing_report.dart', 'r') as f:
    code = f.read()

# I need to insert the button after the STATUS block in _buildBranchCard.
# Let's locate the STATUS block.
status_block = """
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('STATUS', style: TextStyle(fontSize: 12, color: diffColor, fontWeight: FontWeight.bold)),
                          Text(diffText, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: diffColor)),
                        ],
                      ),
                    ],
                  ),
                );
              }
            ),
"""

new_button = """
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManagerClosingReplyScreen(
                        branchId: stat['branchId']?.toString() ?? '',
                        branchName: stat['branchName']?.toString() ?? '',
                        entries: stat['entries'] as List<dynamic>? ?? [],
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.reply, size: 18),
                label: const Text('Add Manager Reply', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
"""

code = code.replace(status_block, status_block + new_button)

# Also need to add the import at the top of the file
import_statement = "import 'branch_closing_entries.dart';"
new_imports = import_statement + "\nimport 'manager_closing_reply_screen.dart';"
code = code.replace(import_statement, new_imports)

with open('lib/manager_closing_report.dart', 'w') as f:
    f.write(code)

