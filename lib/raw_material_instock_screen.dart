import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

// Helper to resolve media URLs across local and remote instances
String? resolveRawMaterialImageUrl(dynamic mediaObj) {
  if (mediaObj == null) return null;
  String? url;
  if (mediaObj is String) {
    url = mediaObj;
  } else if (mediaObj is Map) {
    url = mediaObj['url']?.toString();
  }
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final root = ApiService.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
  return '$root${url.startsWith('/') ? '' : '/'}$url';
}

String? getProductImageUrl(dynamic prod) {
  if (prod is Map && prod['images'] is List && (prod['images'] as List).isNotEmpty) {
    final first = (prod['images'] as List).first;
    if (first is Map) {
      if (first['image'] != null) {
        return resolveRawMaterialImageUrl(first['image']);
      }
      return resolveRawMaterialImageUrl(first);
    }
  }
  return null;
}

// ============================================================================
// 1. CATEGORY SELECTION SCREEN (Mirroring branch CategoriesPage for instock)
// ============================================================================
class RawMaterialInstockCategoryScreen extends StatefulWidget {
  const RawMaterialInstockCategoryScreen({super.key});

  @override
  State<RawMaterialInstockCategoryScreen> createState() =>
      _RawMaterialInstockCategoryScreenState();
}

class _RawMaterialInstockCategoryScreenState
    extends State<RawMaterialInstockCategoryScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _categories = [];
  List<dynamic> _allRawMaterials = [];
  List<String> _companyIds = [];

  // Active in-stock cart state shared across category navigations
  final Map<String, double> _inStockQuery = {}; // rawMaterialId -> quantity

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      const storage = FlutterSecureStorage();
      final skCompaniesStr = await storage.read(key: 'userStorekeeperCompanies');

      List<String> companyIds = [];
      if (skCompaniesStr != null && skCompaniesStr.isNotEmpty) {
        companyIds =
            skCompaniesStr.split(',').where((id) => id.isNotEmpty).toList();
      }

      // Fallback: check branch company
      if (companyIds.isEmpty) {
        final branchId = await storage.read(key: 'userBranchId');
        if (branchId != null && branchId.isNotEmpty) {
          final branches = await ApiService.instance.fetchBranches();
          final currentBranch = branches.firstWhere(
            (b) => b['id']?.toString() == branchId,
            orElse: () => null,
          );
          if (currentBranch != null) {
            final compObj = currentBranch['company'];
            final defaultCompanyId =
                compObj is Map ? compObj['id']?.toString() : compObj?.toString();
            if (defaultCompanyId != null) {
              companyIds.add(defaultCompanyId);
            }
          }
        }
      }

      // Fetch all raw material categories and raw materials
      final categories = await ApiService.instance.fetchRawMaterialCategories();
      final rawMaterials = await ApiService.instance.fetchRawMaterials(depth: 2);

      // Filter categories by user company
      final filteredCategories = categories.where((cat) {
        if (companyIds.isEmpty) return true; // Show all if no company restriction
        final compList = cat['company'];
        if (compList is List) {
          return compList.any((comp) {
            final compId = (comp is Map ? comp['id'] : comp)?.toString();
            return compId != null && companyIds.contains(compId);
          });
        }
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _categories = filteredCategories;
          _allRawMaterials = rawMaterials;
          _companyIds = companyIds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load categories: $e';
          _isLoading = false;
        });
      }
    }
  }

  int _countProductsForCategory(String catId) {
    return _allRawMaterials.where((prod) {
      final cObj = prod['category'];
      final cId = (cObj is Map ? cObj['id'] : cObj)?.toString();
      return cId == catId;
    }).length;
  }

  void _openProductsGrid(dynamic category) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RawMaterialInstockProductsScreen(
          category: category,
          allCategories: _categories,
          allRawMaterials: _allRawMaterials,
          inStockQuery: _inStockQuery,
          companyIds: _companyIds,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _openCart() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RawMaterialInstockCartScreen(
          allRawMaterials: _allRawMaterials,
          inStockQuery: _inStockQuery,
          companyIds: _companyIds,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          'Instock Categories',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                tooltip: 'Instock Cart',
                onPressed: _inStockQuery.isEmpty ? null : _openCart,
              ),
              if (_inStockQuery.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF11998E),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '${_inStockQuery.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitialData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.black))
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadInitialData,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Retry'),
                          )
                        ],
                      ),
                    ),
                  )
                : _categories.isEmpty
                    ? const Center(
                        child: Text(
                          'No raw material categories found.',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : _buildCategoryGrid(),
      ),
      bottomNavigationBar: _inStockQuery.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_inStockQuery.length} Items Selected',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        const Text(
                          'Ready to confirm instock',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _openCart,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('View Cart'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF11998E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildCategoryGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 5 : 3;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.75,
          ),
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final cat = _categories[index];
            final catId = (cat['id'] ?? cat['_id'])?.toString() ?? '';
            final catName = cat['name'] ?? 'Unknown';
            final count = _countProductsForCategory(catId);
            final imageUrl = resolveRawMaterialImageUrl(cat['image']);

            return GestureDetector(
              onTap: () => _openProductsGrid(cat),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Expanded(
                      flex: 8,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                        child: imageUrl != null
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey[100],
                                  child: const Icon(
                                    Icons.category_rounded,
                                    size: 40,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            : Container(
                                color: Colors.grey[100],
                                child: const Icon(
                                  Icons.category_rounded,
                                  size: 40,
                                  color: Colors.grey,
                                ),
                              ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(8),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              catName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Text(
                              '$count items',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// 2. PRODUCTS GRID SCREEN (Mirroring branch InstockProductsPage)
// ============================================================================
class RawMaterialInstockProductsScreen extends StatefulWidget {
  final dynamic category;
  final List<dynamic> allCategories;
  final List<dynamic> allRawMaterials;
  final Map<String, double> inStockQuery;
  final List<String> companyIds;

  const RawMaterialInstockProductsScreen({
    super.key,
    required this.category,
    required this.allCategories,
    required this.allRawMaterials,
    required this.inStockQuery,
    required this.companyIds,
  });

  @override
  State<RawMaterialInstockProductsScreen> createState() =>
      _RawMaterialInstockProductsScreenState();
}

class _RawMaterialInstockProductsScreenState
    extends State<RawMaterialInstockProductsScreen> {
  late dynamic _currentCategory;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentCategory = widget.category;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<dynamic> get _filteredProducts {
    final currentCatId =
        (_currentCategory['id'] ?? _currentCategory['_id'])?.toString() ?? '';
    final query = _searchQuery.trim().toLowerCase();

    return widget.allRawMaterials.where((prod) {
      final cObj = prod['category'];
      final cId = (cObj is Map ? cObj['id'] : cObj)?.toString();
      if (currentCatId.isNotEmpty && cId != currentCatId) return false;

      if (query.isNotEmpty) {
        final name = (prod['name'] ?? '').toString().toLowerCase();
        return name.contains(query);
      }
      return true;
    }).toList();
  }

  Future<void> _toggleProductSelection(dynamic product) async {
    final String id = (product['id'] ?? product['_id'])?.toString() ?? '';
    final String unit = (product['unit'] ?? 'kg').toString();
    final double currentStock = widget.inStockQuery[id] ?? 0.0;

    final TextEditingController qtyCtrl = TextEditingController(
      text: currentStock > 0
          ? (currentStock % 1 == 0
              ? currentStock.toInt().toString()
              : currentStock.toString())
          : '',
    );

    final enteredQty = await showDialog<double?>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, color: Color(0xFF11998E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      product['name'] ?? 'Raw Material',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unit: $unit',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Instock Quantity ($unit)',
                      hintText: 'e.g. 10 or 2.5',
                      border: const OutlineInputBorder(),
                      suffixText: unit,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Quick add increment buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [1, 5, 10, 25, 50].map((step) {
                      return ActionChip(
                        label: Text('+$step'),
                        onPressed: () {
                          final current =
                              double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
                          final updated = current + step;
                          qtyCtrl.text = updated % 1 == 0
                              ? updated.toInt().toString()
                              : updated.toString();
                          setDialogState(() {});
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                if (currentStock > 0)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, 0.0), // Remove
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Remove'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final val = double.tryParse(qtyCtrl.text.trim());
                    Navigator.pop(dialogCtx, val);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF11998E),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (enteredQty != null) {
      setState(() {
        if (enteredQty > 0) {
          widget.inStockQuery[id] = enteredQty;
        } else {
          widget.inStockQuery.remove(id);
        }
      });
    }
  }

  void _openCart() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RawMaterialInstockCartScreen(
          allRawMaterials: widget.allRawMaterials,
          inStockQuery: widget.inStockQuery,
          companyIds: widget.companyIds,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final catName = _currentCategory['name'] ?? 'Raw Materials';
    final products = _filteredProducts;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text(
          'Instock: $catName',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                tooltip: 'Instock Cart',
                onPressed: widget.inStockQuery.isEmpty ? null : _openCart,
              ),
              if (widget.inStockQuery.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF11998E),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '${widget.inStockQuery.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Category quick selector pill bar
          if (widget.allCategories.isNotEmpty)
            Container(
              height: 44,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: widget.allCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final cat = widget.allCategories[idx];
                  final isSelected =
                      (cat['id'] ?? cat['_id']) ==
                      (_currentCategory['id'] ?? _currentCategory['_id']);

                  return ChoiceChip(
                    label: Text(cat['name'] ?? ''),
                    selected: isSelected,
                    selectedColor: Colors.black,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _currentCategory = cat;
                        });
                      }
                    },
                  );
                },
              ),
            ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search in this category...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),

          // Grid View
          Expanded(
            child: products.isEmpty
                ? const Center(
                    child: Text(
                      'No raw materials found.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : _buildGrid(products),
          ),
        ],
      ),
      bottomNavigationBar: widget.inStockQuery.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.inStockQuery.length} Items Selected',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        const Text(
                          'Tap cart to review & confirm',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _openCart,
                      icon: const Icon(Icons.shopping_cart_checkout, size: 18),
                      label: const Text('Review Cart'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF11998E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildGrid(List<dynamic> products) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 5 : 3;

        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.75, // Matching branch app aspect ratio
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            final String id =
                (product['id'] ?? product['_id'])?.toString() ?? '';
            final String name = product['name'] ?? 'Unknown';
            final String unit = (product['unit'] ?? 'kg').toString();
            final minStock = product['minimumStockLevel']?.toString();
            final imageUrl = getProductImageUrl(product);

            final currentStock = widget.inStockQuery[id] ?? 0.0;
            final isSelected = currentStock > 0;

            String qtyText = '';
            if (isSelected) {
              qtyText = currentStock % 1 == 0
                  ? currentStock.toInt().toString()
                  : currentStock.toStringAsFixed(2);
            }

            return GestureDetector(
              onTap: () => _toggleProductSelection(product),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: Colors.blue, width: 4) // Blue border
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.12),
                      spreadRadius: 2,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        // Image section
                        Expanded(
                          flex: 8,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                            child: imageUrl != null
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey[100],
                                      child: const Icon(
                                        Icons.inventory_2_rounded,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  )
                                : Container(
                                    color: Colors.grey[100],
                                    child: const Icon(
                                      Icons.inventory_2_rounded,
                                      size: 40,
                                      color: Colors.grey,
                                    ),
                                  ),
                          ),
                        ),
                        // Bottom black title bar
                        Expanded(
                          flex: 2,
                          child: Container(
                            width: double.infinity,
                            decoration: const BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(8),
                              ),
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Top Left: Min stock badge
                    if (minStock != null && minStock.isNotEmpty)
                      Positioned(
                        top: 2,
                        left: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Min: $minStock',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),

                    // Top Right: Unit badge
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          unit,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),

                    // Center overlay when selected (mirroring branch app)
                    if (isSelected)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.center,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              border: Border.all(color: Colors.white, width: 1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              '$qtyText $unit',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// 3. CART / REVIEW SCREEN (Mirroring branch CartPage for instock confirmation)
// ============================================================================
class RawMaterialInstockCartScreen extends StatefulWidget {
  final List<dynamic> allRawMaterials;
  final Map<String, double> inStockQuery;
  final List<String> companyIds;

  const RawMaterialInstockCartScreen({
    super.key,
    required this.allRawMaterials,
    required this.inStockQuery,
    required this.companyIds,
  });

  @override
  State<RawMaterialInstockCartScreen> createState() =>
      _RawMaterialInstockCartScreenState();
}

class _RawMaterialInstockCartScreenState
    extends State<RawMaterialInstockCartScreen> {
  bool _isSubmitting = false;
  final TextEditingController _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  dynamic _findProduct(String id) {
    return widget.allRawMaterials.firstWhere(
      (p) => (p['id'] ?? p['_id'])?.toString() == id,
      orElse: () => null,
    );
  }

  void _updateQuantity(String id, double delta) {
    final current = widget.inStockQuery[id] ?? 0.0;
    final updated = current + delta;
    setState(() {
      if (updated > 0) {
        widget.inStockQuery[id] = updated;
      } else {
        widget.inStockQuery.remove(id);
      }
    });
  }

  Future<void> _editQuantityDirectly(String id) async {
    final product = _findProduct(id);
    final unit = product?['unit'] ?? 'kg';
    final current = widget.inStockQuery[id] ?? 0.0;
    final ctrl = TextEditingController(
      text: current % 1 == 0 ? current.toInt().toString() : current.toString(),
    );

    final entered = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Quantity ($unit)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity ($unit)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0.0),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, val);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF11998E),
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (entered != null) {
      setState(() {
        if (entered > 0) {
          widget.inStockQuery[id] = entered;
        } else {
          widget.inStockQuery.remove(id);
        }
      });
    }
  }

  Future<void> _submitInstock() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (_isSubmitting) return;
    if (widget.inStockQuery.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No items to submit')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      const storage = FlutterSecureStorage();
      String? companyId;
      if (widget.companyIds.isNotEmpty) {
        companyId = widget.companyIds.first;
      }

      if (companyId == null) {
        final branchId = await storage.read(key: 'userBranchId');
        if (branchId != null && branchId.isNotEmpty) {
          final branches = await ApiService.instance.fetchBranches();
          final currentBranch = branches.firstWhere(
            (b) => b['id']?.toString() == branchId,
            orElse: () => null,
          );
          if (currentBranch != null) {
            final compObj = currentBranch['company'];
            companyId = compObj is Map ? compObj['id']?.toString() : compObj?.toString();
          }
        }
      }

      final branchId = await storage.read(key: 'userBranchId');
      final userId = await storage.read(key: 'userId');
      final userName = await storage.read(key: 'userName');

      final List<Map<String, dynamic>> items = [];
      widget.inStockQuery.forEach((id, qty) {
        final prod = _findProduct(id);
        String? dealerId;
        if (prod != null && prod['dealer'] != null) {
          final d = prod['dealer'];
          if (d is List && d.isNotEmpty) {
            dealerId = (d.first is Map ? d.first['id'] : d.first)?.toString();
          } else if (d is Map) {
            dealerId = d['id']?.toString();
          } else if (d is String) {
            dealerId = d;
          }
        }

        items.add({
          'rawMaterial': id,
          'instock': qty,
          'unit': prod?['unit'] ?? 'kg',
          if (dealerId != null && dealerId.isNotEmpty) 'dealer': dealerId,
          'status': 'waiting',
        });
      });

      final payload = {
        if (companyId != null) 'company': companyId,
        if (branchId != null && branchId.isNotEmpty) 'branch': branchId,
        'date': DateTime.now().toUtc().toIso8601String(),
        'items': items,
        'status': 'waiting',
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        if (userId != null) 'storeKeeperId': userId,
        if (userName != null) 'storeKeeperName': userName,
      };

      await ApiService.instance.createRawMaterialInstockEntry(payload);

      widget.inStockQuery.clear();

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Raw Material Instock Updated Successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Pop back to category view
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to submit instock: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemIds = widget.inStockQuery.keys.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          'Confirm Instock Cart',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (itemIds.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  widget.inStockQuery.clear();
                });
              },
              child: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
      body: itemIds.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.remove_shopping_cart_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No items in your instock cart.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: itemIds.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final id = itemIds[index];
                      final qty = widget.inStockQuery[id] ?? 0.0;
                      final prod = _findProduct(id);
                      final name = prod?['name'] ?? 'Unknown Material';
                      final unit = prod?['unit'] ?? 'kg';
                      final catName = prod?['category'] is Map
                          ? prod['category']['name']
                          : null;
                      final imageUrl = getProductImageUrl(prod);

                      final qtyDisplay = qty % 1 == 0
                          ? qty.toInt().toString()
                          : qty.toStringAsFixed(2);

                      return Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  color: Colors.grey.shade100,
                                  child: imageUrl != null
                                      ? Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.inventory_2),
                                        )
                                      : const Icon(Icons.inventory_2),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (catName != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        catName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 2),
                                    Text(
                                      'Unit: $unit',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Quantity adjuster
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 22,
                                    ),
                                    onPressed: () => _updateQuantity(id, -1),
                                  ),
                                  GestureDetector(
                                    onTap: () => _editQuantityDirectly(id),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        qtyDisplay,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      size: 22,
                                    ),
                                    onPressed: () => _updateQuantity(id, 1),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        widget.inStockQuery.remove(id);
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
                ),

                // Notes / Remarks field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _notesCtrl,
                    decoration: InputDecoration(
                      hintText: 'Notes / Remarks (optional)...',
                      prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ),

                // Bottom submit button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF11998E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isSubmitting || itemIds.isEmpty
                            ? null
                            : _submitInstock,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Confirm Instock (${itemIds.length} items)',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
