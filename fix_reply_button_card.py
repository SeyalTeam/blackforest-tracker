import re

with open('lib/branch_closing_entries.dart', 'r') as f:
    code = f.read()

old_button = """
                    // Add reply button for this specific entry
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
                      child: TextButton.icon(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ManagerClosingReplyScreen(
                                branchId: branchId,
                                branchName: branchName,
                                entries: entries,
                                initialReplyType: 'individual',
                                initialEntryId: entryId,
                              ),
                            ),
                          );
                          _fetchReplies(); // Refresh after adding
                        },
                        icon: const Icon(Icons.reply, size: 16),
                        label: const Text('Add Reply to this Entry'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue[700],
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
"""

new_button = """
                    // Add reply button for this specific entry in a separate card
                    Card(
                      margin: const EdgeInsets.only(bottom: 24),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      color: Colors.blue.withValues(alpha: 0.05),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ManagerClosingReplyScreen(
                                branchId: branchId,
                                branchName: branchName,
                                entries: entries,
                                initialReplyType: 'individual',
                                initialEntryId: entryId,
                              ),
                            ),
                          );
                          _fetchReplies(); // Refresh after adding
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.reply, size: 18, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              Text(
                                'Add Reply to this Entry',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
"""

code = code.replace(old_button.strip(), new_button.strip())

with open('lib/branch_closing_entries.dart', 'w') as f:
    f.write(code)

