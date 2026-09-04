import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class StoreKeeperProductionRequestsScreen extends StatefulWidget {
  const StoreKeeperProductionRequestsScreen({super.key});

  @override
  State<StoreKeeperProductionRequestsScreen> createState() => _StoreKeeperProductionRequestsScreenState();
}

class _StoreKeeperProductionRequestsScreenState extends State<StoreKeeperProductionRequestsScreen> {
  bool _isLoading = true;
  List<dynamic> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final requests = await ApiService.instance.fetchProductionRequests();
      setState(() => _requests = requests);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load requests: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Production Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRequests),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text('No production requests found.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final req = _requests[index];
                    final reqNo = req['requestNumber'] ?? req['id'];
                    final chefName = req['createdByName'] ?? 'Chef';
                    final dateStr = req['date'];
                    final date = dateStr != null ? DateTime.tryParse(dateStr.toString()) : null;
                    final formattedDate = date != null ? DateFormat('MMM dd, yyyy h:mm a').format(date.toLocal()) : 'Unknown Date';
                    final items = req['rawMaterialsList'] as List? ?? [];
                    final status = (req['status'] ?? 'pending').toString().toUpperCase();

                    Color statusColor = Colors.orange;
                    if (status == 'FULFILLED' || status == 'SENT') statusColor = Colors.green;
                    if (status == 'CANCELLED') statusColor = Colors.red;

                    return GestureDetector(
                      onTap: () async {
                        final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoreKeeperProductionRequestDetailScreen(request: req),
                          ),
                        );
                        if (updated == true) {
                          _loadRequests();
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '#$reqNo',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(chefName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
                            const SizedBox(height: 4),
                            Text(formattedDate, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            const Spacer(),
                            const Divider(),
                            Text('${items.length} items requested', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class StoreKeeperProductionRequestDetailScreen extends StatefulWidget {
  final Map<String, dynamic> request;
  const StoreKeeperProductionRequestDetailScreen({super.key, required this.request});

  @override
  State<StoreKeeperProductionRequestDetailScreen> createState() => _StoreKeeperProductionRequestDetailScreenState();
}

class _StoreKeeperProductionRequestDetailScreenState extends State<StoreKeeperProductionRequestDetailScreen> {
  bool _isSaving = false;
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    final rawItems = widget.request['rawMaterialsList'] as List? ?? [];
    _items = rawItems.map((item) {
      return {
        'id': item['id'],
        'rawMaterial': item['rawMaterial'],
        'requestCount': item['requestCount'] ?? 0,
        'sendingCount': item['sendingCount'] ?? 0,
        'status': item['status'] ?? 'pending',
        '_controller': TextEditingController(text: (item['sendingCount'] ?? 0).toString()),
      };
    }).toList();
  }

  @override
  void dispose() {
    for (var item in _items) {
      (item['_controller'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final updatedList = _items.map((item) {
        return {
          'id': item['id'],
          'rawMaterial': item['rawMaterial'] is Map ? item['rawMaterial']['id'] : item['rawMaterial'],
          'requestCount': item['requestCount'],
          'sendingCount': double.tryParse((item['_controller'] as TextEditingController).text) ?? 0,
          'status': item['status'],
        };
      }).toList();

      final payload = {
        'rawMaterialsList': updatedList,
      };

      await ApiService.instance.updateProductionRequest(widget.request['id']?.toString() ?? '', payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request updated successfully!'), backgroundColor: Colors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reqNo = widget.request['requestNumber'] ?? widget.request['id'];
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Request #$reqNo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          _isSaving
              ? const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  icon: const Icon(Icons.save, color: Colors.teal),
                  onPressed: _saveChanges,
                ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          final rawMaterial = item['rawMaterial'];
          final name = rawMaterial is Map ? (rawMaterial['name'] ?? 'Unknown') : 'Product ID: $rawMaterial';
          final unit = rawMaterial is Map ? (rawMaterial['unit'] ?? '') : '';
          final status = item['status'] as String;
          final isSent = status == 'sent';
          
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 6),
                        Text('Req Qty: ${item['requestCount']} $unit', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Sending Qty: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            SizedBox(
                              width: 80,
                              height: 35,
                              child: TextField(
                                controller: item['_controller'] as TextEditingController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      const Text('Sent', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Checkbox(
                        value: isSent,
                        activeColor: Colors.teal,
                        onChanged: (val) {
                          setState(() {
                            item['status'] = (val == true) ? 'sent' : 'pending';
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
