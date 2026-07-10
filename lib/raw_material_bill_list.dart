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
  List<dynamic> _dealers = [];
  List<dynamic> _products = [];
  bool _isLoading = true;
  String _errorMsg = '';
  String _selectedFilterDealerId = 'all';
  String _selectedFilterProductId = 'all';
  DateTime? _selectedDateFilter;

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
      final dealers = await ApiService.instance.fetchRawMaterialDealers();
      final products = await ApiService.instance.fetchRawMaterials();
      if (mounted) {
        setState(() {
          _billings = bills;
          _dealers = dealers;
          _products = products;
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

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateFilter ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedDateFilter = picked;
      });
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
      if (_selectedFilterDealerId != 'all') {
        final dealer = bill['dealer'];
        final dealerId = (dealer is Map ? dealer['id'] : dealer)?.toString();
        if (dealerId != _selectedFilterDealerId) return false;
      }
      if (_selectedFilterProductId != 'all') {
        final list = bill['rawMaterialsList'] as List? ?? [];
        final hasProduct = list.any((item) {
          final prodObj = item['rawMaterial'];
          final prodId = (prodObj is Map ? prodObj['id'] : prodObj)?.toString();
          return prodId == _selectedFilterProductId;
        });
        if (!hasProduct) return false;
      }
      if (_selectedDateFilter != null) {
        if (bill['date'] == null) return false;
        try {
          final billDate = DateTime.parse(bill['date']).toLocal();
          final filterDate = _selectedDateFilter!;
          if (billDate.year != filterDate.year ||
              billDate.month != filterDate.month ||
              billDate.day != filterDate.day) {
            return false;
          }
        } catch (_) {
          return false;
        }
      }
      return true;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, color: Colors.black54, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedDateFilter == null
                                      ? 'All Dates'
                                      : DateFormat('MMM dd').format(_selectedDateFilter!),
                                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_selectedDateFilter != null)
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedDateFilter = null;
                                    });
                                  },
                                  child: const Icon(Icons.close, color: Colors.black54, size: 18),
                                )
                              else
                                const Icon(Icons.arrow_drop_down, color: Colors.black54),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_selectedFilterProductId),
                        initialValue: _selectedFilterProductId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Filter Product',
                          prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: 'all',
                            child: Text('All Products'),
                          ),
                          ..._products.map((p) {
                            return DropdownMenuItem<String>(
                              value: p['id']?.toString(),
                              child: Text(p['name'] ?? 'Unknown Product', overflow: TextOverflow.ellipsis),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedFilterProductId = val ?? 'all';
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(_selectedFilterDealerId),
                  initialValue: _selectedFilterDealerId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Filter Dealer',
                    prefixIcon: const Icon(Icons.business_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('All Dealers'),
                    ),
                    ..._dealers.map((dl) {
                      final dealerName = dl['companyName']?.toString() ?? dl['name']?.toString() ?? 'Unknown Dealer';
                      return DropdownMenuItem<String>(
                        value: dl['id']?.toString(),
                        child: Text(dealerName, overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedFilterDealerId = val ?? 'all';
                    });
                  },
                ),
              ],
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
                            child: Container(
                              color: Colors.white,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: filtered.length,
                                separatorBuilder: (context, index) => const Divider(
                                  height: 1,
                                  indent: 68,
                                  endIndent: 16,
                                  color: Colors.black12,
                                ),
                                itemBuilder: (context, index) {
                                  final bill = filtered[index];
                                  final dealerObj = bill['dealer'];
                                  final dealerName = dealerObj is Map ? (dealerObj['companyName'] ?? 'Unknown') : 'Unknown';
                                  final total = bill['total'] ?? 0.0;
                                  final paidAmount = bill['paidAmount'] ?? 0.0;
                                  String status = bill['status'] ?? 'pending';
                                  if (paidAmount >= total && total > 0) {
                                    status = 'paid';
                                  }
                                  
                                  String dateStr = '';
                                  if (bill['date'] != null) {
                                    try {
                                      final parsed = DateTime.parse(bill['date']);
                                      dateStr = DateFormat('MMM dd, yyyy hh:mm a').format(parsed.toLocal());
                                    } catch (_) {}
                                  }

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
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
                                  );
                                },
                              ),
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
    
    final total = bill['total'] ?? 0.0;
    final paidAmount = bill['paidAmount'] ?? 0.0;
    final pendingAmount = total - paidAmount;
    String status = bill['status'] ?? 'pending';
    if (paidAmount >= total && total > 0) {
      status = 'paid';
    }
    
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
                                Text('Inv No: ${billsList[idx]['invoiceNumber'] ?? 'N/A'}', style: const TextStyle(color: Colors.black54)),
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
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Paid Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        Text(
                          '₹${paidAmount.toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green.shade700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pending Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        Text(
                          '₹${pendingAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: pendingAmount > 0 ? Colors.orange.shade800 : Colors.grey,
                          ),
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
