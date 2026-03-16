import 'package:flutter/material.dart';

class KitchenNotificationsPage extends StatefulWidget {
  final List<Map<String, dynamic>> notifications;
  final Function(String) onMarkAsRead;
  final VoidCallback onRefresh;

  const KitchenNotificationsPage({
    super.key,
    required this.notifications,
    required this.onMarkAsRead,
    required this.onRefresh,
  });

  @override
  State<KitchenNotificationsPage> createState() =>
      _KitchenNotificationsPageState();
}

class _KitchenNotificationsPageState extends State<KitchenNotificationsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Kitchen Notifications',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: widget.notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No new ready items.',
                    style: TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.notifications.length,
              itemBuilder: (context, index) {
                final item = widget.notifications[index];
                final String productName = item['productName'] ?? 'Unknown';
                final String qtyText = (item['quantity'] ?? 0).toString();
                final String tableName = item['tableName'] ?? 'N/A';
                final String kotNo = item['kotNumber'] ?? 'N/A';
                final String status = (item['status'] ?? 'READY')
                    .toString()
                    .toUpperCase();

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[200]!),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            productName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status,
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Table: $tableName | KOT: $kotNo | Qty: $qtyText',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    onTap: () {
                      widget.onMarkAsRead(item['id']);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Marked as read')),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        onPressed: widget.onRefresh,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
