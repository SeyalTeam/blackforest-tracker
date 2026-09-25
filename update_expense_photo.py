import re

with open('lib/branch_expense_details.dart', 'r') as f:
    code = f.read()

# I will replace the Card return with an updated version.

new_card = """
                // Fix relative URLs
                String fullImageUrl = imageUrl;
                if (imageUrl.isNotEmpty && imageUrl.startsWith('/')) {
                  fullImageUrl = 'https://dev1-blacforest.vseyal.com$imageUrl';
                }

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: fullImageUrl.isEmpty ? null : () {
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          insetPadding: const EdgeInsets.all(16),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Stack(
                            children: [
                              InteractiveViewer(
                                child: Image.network(
                                  fullImageUrl,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    padding: const EdgeInsets.all(32),
                                    color: Colors.grey[100],
                                    child: const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.broken_image, size: 64, color: Colors.grey),
                                        SizedBox(height: 16),
                                        Text('Image not available', style: TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.black54),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(alpha: 0.8),
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text(reason, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(format.format(amount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.red)),
                                  const SizedBox(height: 4),
                                  Text(time, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                ],
                              ),
                            ],
                          ),
                          if (imageUrl.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.receipt_long, size: 16, color: Colors.blue),
                                    const SizedBox(width: 6),
                                    Text('Receipt attached', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Text('Tap to view', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ]
                        ],
                      ),
                    ),
                  ),
                );
"""

code = re.sub(r"return Card\(.*?,\n                  \),\n                \);", new_card.strip(), code, flags=re.DOTALL)

with open('lib/branch_expense_details.dart', 'w') as f:
    f.write(code)

