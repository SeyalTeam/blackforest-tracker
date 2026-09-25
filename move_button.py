import re

with open('lib/branch_closing_entries.dart', 'r') as f:
    code = f.read()

# First, extract the new button and individual replies block from OUTSIDE the Card
# and remove them.
# The Card ends with:
#                                   ],
#                                 );
#                               }
#                             ),
#                           ],
#                         ),
#                       ),
#                     ),
#                     
#                     // Display individual replies for this entry
#                     if (individualReplies.isNotEmpty)

old_ending_block = """
                              }
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Display individual replies for this entry
                    if (individualReplies.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                        child: Column(
                          children: individualReplies.map((r) => _buildReplyCard(r, isCommon: false)).toList(),
                        ),
                      ),

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
                  ],
                );
"""

new_ending_block = """
                              }
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Display individual replies for this entry inside the card
                            if (individualReplies.isNotEmpty)
                              Column(
                                children: individualReplies.map((r) => _buildReplyCard(r, isCommon: false)).toList(),
                              ),

                            // Add reply button under total declared
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
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
                                icon: const Icon(Icons.reply, size: 18),
                                label: const Text('Add Manager Reply', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.withValues(alpha: 0.05),
                                  foregroundColor: Colors.blue[700],
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
"""

code = code.replace(old_ending_block.strip(), new_ending_block.strip())

with open('lib/branch_closing_entries.dart', 'w') as f:
    f.write(code)

