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
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
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
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '#$reqNo',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.person, size: 16, color: Colors.blueGrey),
                                const SizedBox(width: 6),
                                Text(chefName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 6),
                                Text(formattedDate, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(),
                            ),
                            Text('${items.length} items requested', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal)),
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
      double initialSendingCount = (item['sendingCount'] ?? 0).toDouble();
      final currentStatus = item['status'] ?? 'pending';
      
      if (initialSendingCount == 0 && currentStatus == 'pending') {
        initialSendingCount = (item['requestCount'] ?? 0).toDouble();
      }

      // If it was ALREADY saved as 'sent', lock it
      final isLocked = (item['status'] == 'sent');

      return {
        'id': item['id'],
        'rawMaterial': item['rawMaterial'],
        'requestCount': item['requestCount'] ?? 0,
        'sendingCount': initialSendingCount,
        'status': currentStatus,
        '_isLocked': isLocked,
        '_controller': TextEditingController(text: initialSendingCount.toString()),
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
          final isLocked = item['_isLocked'] == true;
          
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
                                enabled: !isLocked,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                  border: const OutlineInputBorder(),
                                  fillColor: isLocked ? Colors.grey[200] : null,
                                  filled: isLocked,
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
                        onChanged: isLocked ? null : (val) {
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

class ChefProductionRequestsScreen extends StatefulWidget {
  const ChefProductionRequestsScreen({super.key});

  @override
  State<ChefProductionRequestsScreen> createState() => _ChefProductionRequestsScreenState();
}

class _ChefProductionRequestsScreenState extends State<ChefProductionRequestsScreen> {
  bool _isLoading = true;
  List<dynamic> _requests = [];
  String _currentUserId = '';

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    try {
      final profile = await ApiService.instance.fetchUserProfile();
      _currentUserId = profile['id']?.toString() ?? '';
      _loadRequests();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final requests = await ApiService.instance.fetchProductionRequests();
      // Filter requests by current user (chef)
      final myRequests = requests.where((req) {
        final createdBy = req['createdBy'];
        final cId = createdBy is Map ? createdBy['id']?.toString() : createdBy?.toString();
        return cId == _currentUserId;
      }).toList();
      setState(() => _requests = myRequests);
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
        title: const Text('My Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
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
              ? const Center(child: Text('No requests found.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final req = _requests[index];
                    final reqNo = req['requestNumber'] ?? req['id'];
                    final dateStr = req['date'];
                    final date = dateStr != null ? DateTime.tryParse(dateStr.toString()) : null;
                    final formattedDate = date != null ? DateFormat('MMM dd, yyyy h:mm a').format(date.toLocal()) : 'Unknown Date';
                    final items = req['rawMaterialsList'] as List? ?? [];
                    final status = (req['status'] ?? 'pending').toString().toUpperCase();

                    Color statusColor = Colors.orange;
                    if (status == 'FULFILLED' || status == 'SENT') statusColor = Colors.green;
                    if (status == 'CANCELLED') statusColor = Colors.red;

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChefProductionRequestDetailScreen(request: req),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '#$reqNo',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 6),
                                Text(formattedDate, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(),
                            ),
                            Text('${items.length} items requested', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class ChefProductionRequestDetailScreen extends StatelessWidget {
  final Map<String, dynamic> request;
  const ChefProductionRequestDetailScreen({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    final reqNo = request['requestNumber'] ?? request['id'];
    final items = request['rawMaterialsList'] as List? ?? [];
    
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Request #$reqNo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final rawMaterial = item['rawMaterial'];
          final name = rawMaterial is Map ? (rawMaterial['name'] ?? 'Unknown') : 'Product ID: $rawMaterial';
          final unit = rawMaterial is Map ? (rawMaterial['unit'] ?? '') : '';
          final status = item['status'] as String? ?? 'pending';
          final isSent = status == 'sent';
          final reqQty = item['requestCount'] ?? 0;
          final sendQty = item['sendingCount'] ?? 0;
          
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
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)),
                              child: Text('Requested: $reqQty $unit', style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
                            if (isSent)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                child: Text('Sent: $sendQty $unit', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isSent)
                    const Icon(Icons.check_circle, color: Colors.green, size: 28)
                  else
                    const Icon(Icons.access_time_filled, color: Colors.orange, size: 28),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
