import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class RawMaterialBillingsListScreen extends StatefulWidget {
  const RawMaterialBillingsListScreen({super.key});

  @override
  State<RawMaterialBillingsListScreen> createState() => _RawMaterialBillingsListScreenState();
}

class _RawMaterialBillingsListScreenState extends State<RawMaterialBillingsListScreen> {
  List<dynamic> _billings = [];
  bool _isLoading = true;
  String _errorMsg = '';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBillings();
  }

  Future<void> _loadBillings() async {
    setState(() {
      _isLoading = true;
      _errorMsg = '';
    });
    try {
      final bills = await ApiService.instance.fetchRawMaterialBillings();
      if (mounted) {
        setState(() {
          _billings = bills;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Failed to load billings: $e';
          _isLoading = false;
        });
      }
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _billings.where((bill) {
      final dealer = bill['dealer'];
      final dealerName = (dealer is Map ? dealer['companyName'] : 'Unknown Dealer').toString().toLowerCase();
      return dealerName.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills Log'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBillings,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by dealer company name...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10.0)),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMsg.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_errorMsg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadBillings,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? const Center(child: Text('No bills found.'))
                        : RefreshIndicator(
                            onRefresh: _loadBillings,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final bill = filtered[index];
                                final dealerObj = bill['dealer'];
                                final dealerName = dealerObj is Map ? (dealerObj['companyName'] ?? 'Unknown') : 'Unknown';
                                final total = bill['total'] ?? 0.0;
                                final status = bill['status'] ?? 'pending';
                                
                                String dateStr = '';
                                if (bill['date'] != null) {
                                  try {
                                    final parsed = DateTime.parse(bill['date']);
                                    dateStr = DateFormat('MMM dd, yyyy hh:mm a').format(parsed.toLocal());
                                  } catch (_) {}
                                }

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    title: Text(
                                      dealerName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 6.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Total: ₹${total.toStringAsFixed(2)}',
                                            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            dateStr,
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(status).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: _getStatusColor(status).withOpacity(0.5)),
                                      ),
                                      child: Text(
                                        status.toString().toUpperCase(),
                                        style: TextStyle(
                                          color: _getStatusColor(status),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => RawMaterialBillingDetailScreen(bill: bill),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class RawMaterialBillingDetailScreen extends StatelessWidget {
  final Map<String, dynamic> bill;

  const RawMaterialBillingDetailScreen({super.key, required this.bill});

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _viewFullScreenImage(BuildContext context, String imageUrl, String tag) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(tag),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Container(
            color: Colors.black,
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('Failed to load image', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoThumbnail(BuildContext context, String label, dynamic mediaObj) {
    if (mediaObj == null) return const SizedBox.shrink();
    
    String? mediaUrl;
    if (mediaObj is Map) {
      mediaUrl = mediaObj['url'];
    } else if (mediaObj is String) {
      mediaUrl = mediaObj;
    }

    if (mediaUrl == null || mediaUrl.isEmpty) return const SizedBox.shrink();

    final fullUrl = mediaUrl.startsWith('http') ? mediaUrl : '${ApiService.baseUrl}$mediaUrl';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
              child: GestureDetector(
                onTap: () => _viewFullScreenImage(context, fullUrl, label),
                child: Image.network(
                  fullUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 40, color: Colors.grey)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dealerObj = bill['dealer'];
    final dealerName = dealerObj is Map ? (dealerObj['companyName'] ?? 'Unknown') : 'Unknown';
    final dealerEmail = dealerObj is Map ? (dealerObj['email'] ?? 'N/A') : 'N/A';
    final dealerPhone = dealerObj is Map ? (dealerObj['phoneNumber'] ?? 'N/A') : 'N/A';
    final dealerContact = dealerObj is Map ? (dealerObj['contactName'] ?? 'N/A') : 'N/A';
    
    final status = bill['status'] ?? 'pending';
    final total = bill['total'] ?? 0.0;
    
    final billsList = bill['bills'] as List? ?? [];
    final rawMaterialsList = bill['rawMaterialsList'] as List? ?? [];

    String dateStr = 'N/A';
    if (bill['date'] != null) {
      try {
        final parsed = DateTime.parse(bill['date']);
        dateStr = DateFormat('MMM dd, yyyy hh:mm a').format(parsed.toLocal());
      } catch (_) {}
    }

    final billCopyPhotoObj = bill['billCopyPhoto'];
    final deliveryPersonPhotoObj = bill['deliveryPersonPhoto'];
    final productsPhotoListObj = bill['productsPhoto'] as List? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Details'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and Date Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SUBMITTED ON', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(dateStr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _getStatusColor(status).withOpacity(0.5)),
                  ),
                  child: Text(
                    status.toString().toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(status),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),

            // Dealer Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.business, color: Colors.blueAccent),
                        SizedBox(width: 8),
                        Text('Dealer Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildDetailRow('Company Name', dealerName),
                    _buildDetailRow('Contact Person', dealerContact),
                    _buildDetailRow('Phone Number', dealerPhone),
                    _buildDetailRow('Email Address', dealerEmail),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Purchased Materials Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, color: Colors.orangeAccent),
                        SizedBox(width: 8),
                        Text('Purchased Raw Materials', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const Divider(height: 24),
                    if (rawMaterialsList.isEmpty)
                      const Text('No items specified.', style: TextStyle(color: Colors.grey))
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: rawMaterialsList.length,
                        separatorBuilder: (_, __) => const Divider(height: 12),
                        itemBuilder: (context, index) {
                          final item = rawMaterialsList[index];
                          final materialObj = item['rawMaterial'];
                          final materialName = materialObj is Map ? (materialObj['name'] ?? 'Unknown') : 'Unknown';
                          final quantity = item['quantity'] ?? 0.0;
                          
                          String unit = 'Units';
                          if (materialObj is Map && materialObj['unit'] != null) {
                            unit = materialObj['unit'].toString().toUpperCase();
                          }

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(materialName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                              ),
                              Text(
                                '$quantity $unit',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Financial Summary Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.receipt, color: Colors.teal),
                        SizedBox(width: 8),
                        Text('Financial Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const Divider(height: 24),
                    if (billsList.isNotEmpty) ...[
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: billsList.length,
                        itemBuilder: (context, idx) {
                          final amt = billsList[idx]['amount'] ?? 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Bill Slip ${idx + 1}', style: const TextStyle(color: Colors.black54)),
                                Text('₹${amt.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w500)),
                              ],
                            ),
                          );
                        },
                      ),
                      const Divider(height: 20),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Grand Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        Text(
                          '₹${total.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.teal),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Photo Capture Previews
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text('Photos Captured', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: [
                if (billCopyPhotoObj != null)
                  _buildPhotoThumbnail(context, 'Bill Copy', billCopyPhotoObj),
                if (deliveryPersonPhotoObj != null)
                  _buildPhotoThumbnail(context, 'Delivery Person', deliveryPersonPhotoObj),
                ...List.generate(productsPhotoListObj.length, (idx) {
                  return _buildPhotoThumbnail(context, 'Product Photo ${idx + 1}', productsPhotoListObj[idx]);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 14)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
