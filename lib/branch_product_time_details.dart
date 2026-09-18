import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class BranchProductTimeDetailsScreen extends StatefulWidget {
  final String branchName;
  final List<dynamic> items;

  const BranchProductTimeDetailsScreen({
    super.key,
    required this.branchName,
    required this.items,
  });

  @override
  State<BranchProductTimeDetailsScreen> createState() => _BranchProductTimeDetailsScreenState();
}

class _BranchProductTimeDetailsScreenState extends State<BranchProductTimeDetailsScreen> {
  bool _isLoadingImages = true;
  final Map<String, String> _productImageUrls = {};

  @override
  void initState() {
    super.initState();
    _fetchProductPhotos();
  }

  Future<void> _fetchProductPhotos() async {
    try {
      final productIds = widget.items
          .map((item) => item['productId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (productIds.isNotEmpty) {
        final api = ApiService.instance;
        final products = await api.fetchProductsByIds(productIds, depth: 1);

        for (var p in products) {
          final id = p['id']?.toString() ?? p['_id']?.toString() ?? '';
          if (id.isNotEmpty) {
            String imageUrl = '';
            if (p['image'] != null) {
              if (p['image'] is Map) {
                imageUrl = p['image']['url']?.toString() ?? '';
              } else if (p['imageUrl'] != null) {
                imageUrl = p['imageUrl']?.toString() ?? '';
              }
            }
            if (imageUrl.isNotEmpty) {
              if (imageUrl.startsWith('/')) {
                imageUrl = 'https://dev1-blacforest.vseyal.com$imageUrl';
              }
              _productImageUrls[id] = imageUrl;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching product photos: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingImages = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.branchName} - Product Time Details', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: widget.items.isEmpty
          ? const Center(child: Text('No details found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                
                final productId = item['productId']?.toString() ?? '';
                final productName = item['productName']?.toString() ?? 'Unknown Product';
                final billNumber = item['billNumber']?.toString() ?? 'N/A';
                final amount = ((item['amount'] ?? 0) as num).toDouble();
                final qty = item['quantity'] ?? 0;
                final status = item['status']?.toString() ?? 'unknown';
                final chefName = item['chefName']?.toString() ?? 'Unknown Chef';
                final prepTime = item['chefPreparationTime'] ?? item['preparationTime'] ?? 0;
                
                String time = '';
                if (item['orderedAt'] != null && item['orderedAt'].toString().isNotEmpty) {
                  final str = item['orderedAt'].toString();
                  final parsed = DateTime.tryParse(str);
                  if (parsed != null) {
                    time = DateFormat('hh:mm a').format(parsed.toLocal());
                  } else {
                    try {
                      final timeDate = DateFormat('HH:mm:ss').parse(str);
                      time = DateFormat('hh:mm a').format(timeDate);
                    } catch (_) {
                      time = str;
                    }
                  }
                }
                
                final imageUrl = _productImageUrls[productId] ?? '';

                Color statusColor = Colors.grey;
                if (status == 'lower') {
                  statusColor = Colors.green;
                } else if (status == 'exceeded') {
                  statusColor = Colors.red;
                } else if (status == 'neutral') {
                  statusColor = Colors.orange;
                }

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: imageUrl.isEmpty ? null : () {
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
                                  imageUrl,
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
                                    Text('$productName (x$qty)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text('Bill: $billNumber', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                    Text('Chef: $chefName', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(format.format(amount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.indigo)),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Ordered: $time • Prep Time: ${prepTime}m', style: TextStyle(fontSize: 11, color: Colors.grey[800], fontWeight: FontWeight.bold)),
                              if (_isLoadingImages)
                                const SizedBox(
                                  width: 12, height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else if (imageUrl.isNotEmpty)
                                Row(
                                  children: [
                                    const Icon(Icons.image, size: 14, color: Colors.indigo),
                                    const SizedBox(width: 4),
                                    const Text('Tap to view photo', style: TextStyle(fontSize: 11, color: Colors.indigo)),
                                  ],
                                )
                              else
                                const Text('No photo', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
