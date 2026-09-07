import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as flutter_secure_storage;
import 'api_service.dart';

class DealerOrderSelectionScreen extends StatefulWidget {
  const DealerOrderSelectionScreen({super.key});

  @override
  State<DealerOrderSelectionScreen> createState() => _DealerOrderSelectionScreenState();
}

class _DealerOrderSelectionScreenState extends State<DealerOrderSelectionScreen> {
  bool _isLoading = false;
  List<dynamic> _dealers = [];
  String? _errorMsg;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDealers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDealers() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final dealers = await ApiService.instance.fetchDealers();
      setState(() {
        _dealers = dealers;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Failed to load dealers: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final displayedDealers = _dealers.where((dl) {
      if (query.isEmpty) return true;
      final companyName = (dl['companyName'] ?? '').toString().toLowerCase();
      final phone = (dl['phoneNumber'] ?? '').toString().toLowerCase();
      return companyName.contains(query) || phone.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Select Dealer for Order', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg != null
              ? Center(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search dealer...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: displayedDealers.isEmpty
                          ? const Center(child: Text('No dealers found.', style: TextStyle(color: Colors.grey)))
                          : RefreshIndicator(
                              onRefresh: _loadDealers,
                              child: ListView.builder(
                                itemCount: displayedDealers.length,
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                itemBuilder: (context, index) {
                                  final dealer = displayedDealers[index];
                                  final companyName = dealer['companyName'] ?? 'Unknown Dealer';
                                  final phone = dealer['phoneNumber'] ?? 'No Phone';
                                  final id = dealer['id']?.toString() ?? '';

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12.0),
                                    child: Material(
                                      color: Colors.white,
                                      elevation: 1,
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => DealerOrderScreen(dealerId: id, dealerName: companyName),
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 40, height: 40,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
                                                child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(companyName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                    const SizedBox(height: 4),
                                                    Text('Phone: $phone', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                                  ],
                                                ),
                                              ),
                                              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                            ],
                                          ),
                                        ),
                                      ),
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

class DealerOrderScreen extends StatefulWidget {
  final String dealerId;
  final String dealerName;
  const DealerOrderScreen({super.key, required this.dealerId, required this.dealerName});

  @override
  State<DealerOrderScreen> createState() => _DealerOrderScreenState();
}

class _DealerOrderScreenState extends State<DealerOrderScreen> {
  bool _isLoading = false;
  bool _isSubmitting = false;
  List<dynamic> _products = [];
  
  // Controllers for quantities
  final Map<String, TextEditingController> _qtyControllers = {};

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  @override
  void dispose() {
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoading = true);
    try {
      final rawMaterials = await ApiService.instance.fetchRawMaterials();
      
      final dealerProducts = rawMaterials.where((p) {
        final assignedDealers = p['dealers'] as List? ?? [];
        return assignedDealers.any((d) {
          if (d is Map) return d['id']?.toString() == widget.dealerId;
          return d.toString() == widget.dealerId;
        });
      }).toList();

      setState(() {
        _products = dealerProducts;
      });

      for (var p in dealerProducts) {
        final id = p['id'] as String;
        _qtyControllers[id] = TextEditingController();
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load products: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _placeOrder() async {
    final List<Map<String, dynamic>> items = [];
    
    for (var p in _products) {
      final id = p['id'] as String;
      final ctrl = _qtyControllers[id];
      if (ctrl != null && ctrl.text.trim().isNotEmpty) {
        final qty = double.tryParse(ctrl.text.trim());
        if (qty != null && qty > 0) {
          items.add({
            'rawMaterial': id,
            'requestCount': qty,
            'status': 'pending',
          });
        }
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter quantity for at least one product.')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      String? companyId;
      final skCompaniesStr = await const flutter_secure_storage.FlutterSecureStorage().read(key: 'storeKeeperCompanies');
      if (skCompaniesStr != null && skCompaniesStr.isNotEmpty) {
        final companyIds = skCompaniesStr.split(',').where((id) => id.isNotEmpty).toList();
        if (companyIds.isNotEmpty) companyId = companyIds.first;
      }
      if (companyId == null) {
        final branchId = await const flutter_secure_storage.FlutterSecureStorage().read(key: 'userBranchId');
        if (branchId != null && branchId.isNotEmpty) {
          final branches = await ApiService.instance.fetchBranches();
          final currentBranch = branches.firstWhere((b) => (b['id'] ?? b['_id']).toString() == branchId, orElse: () => null);
          if (currentBranch != null && currentBranch['company'] != null) {
            final c = currentBranch['company'];
            companyId = (c is Map) ? c['id']?.toString() : c.toString();
          }
        }
      }

      if (companyId == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not determine company. Cannot place order.')));
        setState(() => _isSubmitting = false);
        return;
      }

      final payload = {
        'company': companyId,
        'dealer': widget.dealerId,
        'rawMaterialsList': items,
        'date': DateTime.now().toUtc().toIso8601String(),
        'status': 'pending',
      };

      await ApiService.instance.createDealerOrder(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order placed successfully!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        Navigator.pop(context); // Go back to dealer list
        Navigator.pop(context); // Go back to home
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to place order: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Order: ${widget.dealerName}', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? const Center(child: Text('No products assigned to this dealer.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    final id = product['id'] as String;
                    final name = product['name'] ?? 'Unknown';
                    final unit = product['unit'] ?? '';

                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  if (unit.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text('Unit: $unit', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                  ]
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 100,
                              child: TextField(
                                controller: _qtyControllers[id],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Qty',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: _products.isNotEmpty
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, -4), blurRadius: 10)],
                ),
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _placeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('PLACE ORDER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          : null,
    );
  }
}
