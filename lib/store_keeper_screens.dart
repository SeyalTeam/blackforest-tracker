import 'package:flutter/material.dart';
import 'api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RawMaterialCategoryScreen extends StatefulWidget {
  const RawMaterialCategoryScreen({super.key});

  @override
  State<RawMaterialCategoryScreen> createState() =>
      _RawMaterialCategoryScreenState();
}

class _RawMaterialCategoryScreenState extends State<RawMaterialCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  List<dynamic> _categories = [];
  List<String> _companyIds = [];
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      // Fetch categories
      final categories = await ApiService.instance.fetchRawMaterialCategories();

      // Fetch secure storage to find storekeeper companies
      const storage = FlutterSecureStorage();
      final skCompaniesStr = await storage.read(key: 'userStorekeeperCompanies');

      List<String> companyIds = [];
      if (skCompaniesStr != null && skCompaniesStr.isNotEmpty) {
        companyIds = skCompaniesStr.split(',').where((id) => id.isNotEmpty).toList();
      }

      // Fallback to branch company if storekeeper_companies is empty
      if (companyIds.isEmpty) {
        final branchId = await storage.read(key: 'userBranchId');
        if (branchId != null && branchId.isNotEmpty) {
          final branches = await ApiService.instance.fetchBranches();
          final currentBranch = branches.firstWhere(
            (b) => b['id']?.toString() == branchId,
            orElse: () => null,
          );
          if (currentBranch != null) {
            final companyObj = currentBranch['company'];
            String? defaultCompanyId;
            if (companyObj is Map) {
              defaultCompanyId = companyObj['id']?.toString();
            } else if (companyObj is String) {
              defaultCompanyId = companyObj;
            }
            if (defaultCompanyId != null) {
              companyIds.add(defaultCompanyId);
            }
          }
        }
      }

      // Filter categories to only show categories belonging to the user's company/companies
      final filteredCategories = categories.where((cat) {
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
          _companyIds = companyIds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Failed to load categories: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_companyIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not resolve company for your profile/branch.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.instance.createRawMaterialCategory(
        name: _nameController.text.trim(),
        companyIds: _companyIds,
      );

      _nameController.clear();
      
      // Reload categories list
      final categories = await ApiService.instance.fetchRawMaterialCategories();

      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Raw Material Category created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Raw Material Categories'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isLoading && _categories.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadInitialData,
                          child: const Text('Retry'),
                        )
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Card(
                      margin: const EdgeInsets.all(16.0),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Form(
                          key: _formKey,
                          child: Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _nameController,
                                  decoration: InputDecoration(
                                    labelText: 'Category Name',
                                    hintText: 'e.g. Vegetables',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: _isLoading ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _categories.isEmpty
                          ? const Center(
                              child: Text(
                                'No categories found.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : Container(
                              color: Colors.white,
                              child: ListView.separated(
                                itemCount: _categories.length,
                                separatorBuilder: (context, index) => const Divider(
                                  height: 1,
                                  indent: 64,
                                  endIndent: 16,
                                  color: Colors.black12,
                                ),
                                itemBuilder: (context, index) {
                                  final cat = _categories[index];
                                  final name = cat['name'] ?? 'Unknown';
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                    leading: Container(
                                      width: 32,
                                      height: 32,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => CategoryProductsScreen(
                                            category: cat,
                                          ),
                                        ),
                                      );
                                    },
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

class CreateRawMaterialScreen extends StatefulWidget {
  const CreateRawMaterialScreen({super.key});

  @override
  State<CreateRawMaterialScreen> createState() =>
      _CreateRawMaterialScreenState();
}

class _CreateRawMaterialScreenState extends State<CreateRawMaterialScreen> {
  bool _isLoading = false;
  List<dynamic> _categories = [];
  List<dynamic> _products = [];
  List<dynamic> _dealers = [];
  String? _selectedFilterCategoryId = 'all';
  String? _selectedFilterDealerId = 'all';
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      // 1. Fetch categories
      final categories = await ApiService.instance.fetchRawMaterialCategories();

      // 2. Fetch secure storage to find storekeeper companies
      const storage = FlutterSecureStorage();
      final skCompaniesStr = await storage.read(key: 'userStorekeeperCompanies');

      List<String> companyIds = [];
      if (skCompaniesStr != null && skCompaniesStr.isNotEmpty) {
        companyIds = skCompaniesStr.split(',').where((id) => id.isNotEmpty).toList();
      }

      // Fallback to branch company if storekeeper_companies is empty
      if (companyIds.isEmpty) {
        final branchId = await storage.read(key: 'userBranchId');
        if (branchId != null && branchId.isNotEmpty) {
          final branches = await ApiService.instance.fetchBranches();
          final currentBranch = branches.firstWhere(
            (b) => b['id']?.toString() == branchId,
            orElse: () => null,
          );
          if (currentBranch != null) {
            final companyObj = currentBranch['company'];
            String? defaultCompanyId;
            if (companyObj is Map) {
              defaultCompanyId = companyObj['id']?.toString();
            } else if (companyObj is String) {
              defaultCompanyId = companyObj;
            }
            if (defaultCompanyId != null) {
              companyIds.add(defaultCompanyId);
            }
          }
        }
      }

      // Filter categories to only show categories belonging to the user's company/companies
      final filteredCategories = categories.where((cat) {
        final compList = cat['company'];
        if (compList is List) {
          return compList.any((comp) {
            final compId = (comp is Map ? comp['id'] : comp)?.toString();
            return compId != null && companyIds.contains(compId);
          });
        }
        return false;
      }).toList();

      // 3. Fetch all raw materials (products)
      final rawMaterials = await ApiService.instance.fetchRawMaterials();

      // Filter products to only show those belonging to the filtered categories
      final filteredProducts = rawMaterials.where((prod) {
        final catObj = prod['category'];
        final catId = (catObj is Map ? catObj['id'] : catObj)?.toString();
        return catId != null && filteredCategories.any((c) => c['id']?.toString() == catId);
      }).toList();

      // 4. Fetch all raw material dealers (without company filter)
      final filteredDealers = await ApiService.instance.fetchRawMaterialDealers();

      if (mounted) {
        setState(() {
          _categories = filteredCategories;
          _products = filteredProducts;
          _dealers = filteredDealers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Failed to load data: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _products.where((prod) {
      if (_selectedFilterCategoryId != null && _selectedFilterCategoryId != 'all') {
        final catObj = prod['category'];
        final catId = (catObj is Map ? catObj['id'] : catObj)?.toString();
        if (catId != _selectedFilterCategoryId) return false;
      }
      if (_selectedFilterDealerId != null && _selectedFilterDealerId != 'all') {
        final dealerObj = prod['dealer'];
        final dealerId = (dealerObj is Map ? dealerObj['id'] : dealerObj)?.toString();
        if (dealerId != _selectedFilterDealerId) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Raw Material Products'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isLoading && _products.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadInitialData,
                          child: const Text('Retry'),
                        )
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total: ${filteredProducts.length} products',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: Row(
                        children: [
                           Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_selectedFilterCategoryId),
                              initialValue: _selectedFilterCategoryId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: 'all',
                                  child: Text('All Categories'),
                                ),
                                ..._categories.map((cat) {
                                  return DropdownMenuItem<String>(
                                    value: cat['id']?.toString(),
                                    child: Text(cat['name'] ?? 'Unknown', overflow: TextOverflow.ellipsis),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedFilterCategoryId = val;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_selectedFilterDealerId),
                              initialValue: _selectedFilterDealerId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Dealer',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: 'all',
                                  child: Text('All Dealers'),
                                ),
                                ..._dealers.map((dl) {
                                  return DropdownMenuItem<String>(
                                    value: dl['id']?.toString(),
                                    child: Text(dl['companyName'] ?? 'Unknown Dealer', overflow: TextOverflow.ellipsis),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedFilterDealerId = val;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filteredProducts.isEmpty
                          ? const Center(
                              child: Text(
                                'No products found.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : Container(
                              color: Colors.white,
                              child: ListView.separated(
                                itemCount: filteredProducts.length,
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                separatorBuilder: (context, index) => const Divider(
                                  height: 1,
                                  indent: 68,
                                  endIndent: 16,
                                  color: Colors.black12,
                                ),
                                itemBuilder: (context, index) {
                                  final prod = filteredProducts[index];
                                  final name = prod['name'] ?? 'Unknown';
                                  final unit = prod['unit'] ?? '';
                                  final minStock = prod['minimumStockLevel']?.toString() ?? 'N/A';
                                  
                                  final catObj = prod['category'];
                                  final catName = (catObj is Map ? catObj['name'] : 'Unknown');

                                  final dealerObj = prod['dealer'];
                                  final dealerName = (dealerObj is Map ? dealerObj['companyName'] : null) ?? '';

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                    child: Row(
                                      children: [
                                        Container(
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
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              if (dealerName.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  dealerName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 13,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[200],
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      catName,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Min: $minStock $unit',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateRawMaterialFormScreen(
                categories: _categories,
                dealers: _dealers,
              ),
            ),
          );
          if (result == true) {
            _loadInitialData();
          }
        },
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CreateRawMaterialFormScreen extends StatefulWidget {
  final List<dynamic> categories;
  final List<dynamic> dealers;

  const CreateRawMaterialFormScreen({
    super.key,
    required this.categories,
    required this.dealers,
  });

  @override
  State<CreateRawMaterialFormScreen> createState() => _CreateRawMaterialFormScreenState();
}

class _CreateRawMaterialFormScreenState extends State<CreateRawMaterialFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _minStockController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedDealerId;
  String _selectedUnit = 'kg';
  bool _isSaving = false;

  final List<Map<String, String>> _unitOptions = [
    {'label': 'Pieces (pcs)', 'value': 'pcs'},
    {'label': 'Kilograms (kg)', 'value': 'kg'},
    {'label': 'Grams (g)', 'value': 'g'},
    {'label': 'Liters (l)', 'value': 'l'},
    {'label': 'Milliliters (ml)', 'value': 'ml'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.categories.isNotEmpty) {
      _selectedCategoryId = widget.categories.first['id']?.toString();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      double? minStock;
      if (_minStockController.text.trim().isNotEmpty) {
        minStock = double.tryParse(_minStockController.text.trim());
      }

      await ApiService.instance.createRawMaterial(
        name: _nameController.text.trim(),
        categoryId: _selectedCategoryId!,
        unit: _selectedUnit,
        minimumStockLevel: minStock,
        dealerId: _selectedDealerId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Raw Material Product created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _minStockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Add Raw Material Product'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Tomato',
                        fillColor: Colors.white,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 20),
                    const Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                     DropdownButtonFormField<String>(
                      key: ValueKey(_selectedCategoryId),
                      initialValue: _selectedCategoryId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        fillColor: Colors.white,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: widget.categories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat['id']?.toString(),
                          child: Text(cat['name'] ?? 'Unknown', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedCategoryId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text('Dealer (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      key: ValueKey(_selectedDealerId),
                      initialValue: _selectedDealerId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        fillColor: Colors.white,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None (Internal)'),
                        ),
                        ...widget.dealers.map((dl) {
                          return DropdownMenuItem<String?>(
                            value: dl['id']?.toString(),
                            child: Text(dl['companyName'] ?? 'Unknown Dealer', overflow: TextOverflow.ellipsis),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedDealerId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text('Unit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedUnit),
                      initialValue: _selectedUnit,
                      isExpanded: true,
                      decoration: InputDecoration(
                        fillColor: Colors.white,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: _unitOptions.map((opt) {
                        return DropdownMenuItem<String>(
                          value: opt['value'],
                          child: Text(opt['label'] ?? '', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedUnit = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text('Minimum Stock Level', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _minStockController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: 'e.g. 5.0',
                        fillColor: Colors.white,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          final num = double.tryParse(value.trim());
                          if (num == null) return 'Must be a number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Create Product', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class CreateRawMaterialDealerScreen extends StatefulWidget {
  const CreateRawMaterialDealerScreen({super.key});

  @override
  State<CreateRawMaterialDealerScreen> createState() => _CreateRawMaterialDealerScreenState();
}

class _CreateRawMaterialDealerScreenState extends State<CreateRawMaterialDealerScreen> {
  bool _isLoading = false;
  List<dynamic> _dealers = [];
  List<dynamic> _products = [];
  List<String> _companyIds = [];
  String? _errorMsg;
  String _selectedFilterProductId = 'all';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      const storage = FlutterSecureStorage();
      final skCompaniesStr = await storage.read(key: 'userStorekeeperCompanies');

      List<String> companyIds = [];
      if (skCompaniesStr != null && skCompaniesStr.isNotEmpty) {
        companyIds = skCompaniesStr.split(',').where((id) => id.isNotEmpty).toList();
      }

      if (companyIds.isEmpty) {
        final branchId = await storage.read(key: 'userBranchId');
        if (branchId != null && branchId.isNotEmpty) {
          final branches = await ApiService.instance.fetchBranches();
          final currentBranch = branches.firstWhere(
            (b) => b['id']?.toString() == branchId,
            orElse: () => null,
          );
          if (currentBranch != null) {
            final companyObj = currentBranch['company'];
            String? defaultCompanyId;
            if (companyObj is Map) {
              defaultCompanyId = companyObj['id']?.toString();
            } else if (companyObj is String) {
              defaultCompanyId = companyObj;
            }
            if (defaultCompanyId != null) {
              companyIds.add(defaultCompanyId);
            }
          }
        }
      }

      final filteredDealers = await ApiService.instance.fetchRawMaterialDealers();
      final products = await ApiService.instance.fetchRawMaterials();

      if (mounted) {
        setState(() {
          _dealers = filteredDealers;
          _products = products;
          _companyIds = companyIds;
          _isLoading = false;
        });
      }
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
    final filtered = _dealers.where((dealer) {
      if (_selectedFilterProductId != 'all') {
        final selectedProd = _products.firstWhere(
          (p) => p['id']?.toString() == _selectedFilterProductId,
          orElse: () => null,
        );
        if (selectedProd != null) {
          final prodDealer = selectedProd['dealer'];
          final prodDealerId = (prodDealer is Map ? prodDealer['id'] : prodDealer)?.toString();
          final dealerId = dealer['id']?.toString();
          if (dealerId != prodDealerId) return false;
        } else {
          return false;
        }
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Raw Material Dealers'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (!_isLoading && _dealers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: DropdownButtonFormField<String>(
                key: ValueKey(_selectedFilterProductId),
                initialValue: _selectedFilterProductId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Filter by Supplied Product',
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
          Expanded(
            child: _isLoading && _dealers.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _errorMsg != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadInitialData,
                                child: const Text('Retry'),
                              )
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No dealers found.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : Container(
                            color: Colors.white,
                            child: ListView.separated(
                              itemCount: filtered.length,
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              separatorBuilder: (context, index) => const Divider(
                                height: 1,
                                indent: 68,
                                endIndent: 16,
                                color: Colors.black12,
                              ),
                              itemBuilder: (context, index) {
                                final dl = filtered[index];
                                final companyName = dl['companyName'] ?? 'Unknown Company';
                                final address = dl['address'] ?? '';
                                final phone = dl['phoneNumber'] ?? '';
                                
                                final contactObj = dl['contactPerson'];
                                final contactName = contactObj is Map ? contactObj['name'] : 'N/A';

                          return InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RawMaterialDealerDetailScreen(dealer: dl),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
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
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          companyName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Contact: $contactName | Phone: $phone',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          address,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateRawMaterialDealerFormScreen(
                allowedCompanies: _companyIds,
              ),
            ),
          );
          if (result == true) {
            _loadInitialData();
          }
        },
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CreateRawMaterialDealerFormScreen extends StatefulWidget {
  final List<String> allowedCompanies;

  const CreateRawMaterialDealerFormScreen({
    super.key,
    required this.allowedCompanies,
  });

  @override
  State<CreateRawMaterialDealerFormScreen> createState() => _CreateRawMaterialDealerFormScreenState();
}

class _CreateRawMaterialDealerFormScreenState extends State<CreateRawMaterialDealerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // General fields
  final _companyNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();

  // Contact Person fields
  final _contactNameController = TextEditingController();
  final _contactDesignationController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();

  // GST & Compliance
  bool _isGSTRegistered = true;
  final _gstController = TextEditingController();
  final _panController = TextEditingController();
  final _fssaiController = TextEditingController();
  final _aadharController = TextEditingController();

  // Bank & Payment Details
  bool _hasBankAccount = true;
  String _preferredPaymentMethod = 'cash';
  final _bankNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _ifscCodeController = TextEditingController();
  final _bankBranchController = TextEditingController();

  bool _isSaving = false;

  final List<Map<String, String>> _paymentOptions = [
    {'label': 'Cash', 'value': 'cash'},
    {'label': 'UPI', 'value': 'upi'},
    {'label': 'Cheque', 'value': 'cheque'},
    {'label': 'Credit', 'value': 'credit'},
  ];

  // Regex definitions
  final _gstRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
  final _panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
  final _ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  final _aadharRegex = RegExp(r'^\d{12}$');

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.allowedCompanies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No company code associated with your account.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await ApiService.instance.createRawMaterialDealer(
        companyName: _companyNameController.text.trim(),
        address: _addressController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        contactName: _contactNameController.text.trim(),
        allowedCompanies: widget.allowedCompanies,
        isGSTRegistered: _isGSTRegistered,
        gst: _isGSTRegistered ? _gstController.text.trim().toUpperCase() : null,
        pan: _isGSTRegistered ? _panController.text.trim().toUpperCase() : null,
        fssai: _isGSTRegistered ? _fssaiController.text.trim() : null,
        aadhar: !_isGSTRegistered ? _aadharController.text.trim() : null,
        contactDesignation: _contactDesignationController.text.trim(),
        contactPhone: _contactPhoneController.text.trim(),
        contactEmail: _contactEmailController.text.trim(),
        notes: _notesController.text.trim(),
        hasBankAccount: _hasBankAccount,
        preferredPaymentMethod: !_hasBankAccount ? _preferredPaymentMethod : null,
        bankName: _hasBankAccount ? _bankNameController.text.trim() : null,
        accountNumber: _hasBankAccount ? _accountNumberController.text.trim() : null,
        ifscCode: _hasBankAccount ? _ifscCodeController.text.trim().toUpperCase() : null,
        bankBranch: _hasBankAccount ? _bankBranchController.text.trim() : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Raw Material Dealer created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _contactNameController.dispose();
    _contactDesignationController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _gstController.dispose();
    _panController.dispose();
    _fssaiController.dispose();
    _aadharController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _ifscCodeController.dispose();
    _bankBranchController.dispose();
    super.dispose();
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label + (required ? ' *' : ''),
          hintText: hint,
          fillColor: Colors.white,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        validator: (value) {
          if (required && (value == null || value.trim().isEmpty)) {
            return '$label is required';
          }
          if (validator != null) {
            return validator(value);
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Add Raw Material Dealer'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('General Details'),
                            _buildTextField(
                              controller: _companyNameController,
                              label: 'Company Name',
                              required: true,
                            ),
                            _buildTextField(
                              controller: _addressController,
                              label: 'Address',
                              required: true,
                              maxLines: 3,
                            ),
                            _buildTextField(
                              controller: _phoneController,
                              label: 'Phone Number',
                              required: true,
                              keyboardType: TextInputType.phone,
                            ),
                            _buildTextField(
                              controller: _emailController,
                              label: 'Email Address',
                              required: true,
                              keyboardType: TextInputType.emailAddress,
                              validator: (val) {
                                if (val != null && val.trim().isNotEmpty) {
                                  if (!val.contains('@') || !val.contains('.')) {
                                    return 'Invalid email address';
                                  }
                                }
                                return null;
                              },
                            ),
                            _buildTextField(
                              controller: _notesController,
                              label: 'Notes',
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('Contact Person Details'),
                            _buildTextField(
                              controller: _contactNameController,
                              label: 'Contact Person Name',
                              required: true,
                            ),
                            _buildTextField(
                              controller: _contactDesignationController,
                              label: 'Designation',
                            ),
                            _buildTextField(
                              controller: _contactPhoneController,
                              label: 'Contact Phone',
                              keyboardType: TextInputType.phone,
                            ),
                            _buildTextField(
                              controller: _contactEmailController,
                              label: 'Contact Email',
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'GST Registered?',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                Switch(
                                  value: _isGSTRegistered,
                                  onChanged: (val) {
                                    setState(() {
                                      _isGSTRegistered = val;
                                    });
                                  },
                                  activeTrackColor: Colors.black54,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_isGSTRegistered) ...[
                              _buildTextField(
                                controller: _gstController,
                                label: 'GST Number',
                                hint: 'e.g. 22AAAAA1111A1Z1',
                                required: true,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return null;
                                  if (!_gstRegex.hasMatch(val.trim().toUpperCase())) {
                                    return 'Invalid GSTIN format';
                                  }
                                  return null;
                                },
                              ),
                              _buildTextField(
                                controller: _panController,
                                label: 'PAN Number',
                                hint: 'e.g. ABCDE1234F',
                                required: false,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return null;
                                  if (!_panRegex.hasMatch(val.trim().toUpperCase())) {
                                    return 'Invalid PAN format';
                                  }
                                  return null;
                                },
                              ),
                              _buildTextField(
                                controller: _fssaiController,
                                label: 'FSSAI Number',
                              ),
                            ] else ...[
                              _buildTextField(
                                controller: _aadharController,
                                label: 'Aadhar Card Number',
                                hint: 'e.g. 123456789012',
                                required: true,
                                keyboardType: TextInputType.number,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return null;
                                  if (!_aadharRegex.hasMatch(val.trim())) {
                                    return 'Aadhar must be exactly 12 digits';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Has Bank Account?',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                Switch(
                                  value: _hasBankAccount,
                                  onChanged: (val) {
                                    setState(() {
                                      _hasBankAccount = val;
                                    });
                                  },
                                  activeTrackColor: Colors.black54,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_hasBankAccount) ...[
                              _buildTextField(
                                controller: _bankNameController,
                                label: 'Bank Name',
                                required: true,
                              ),
                              _buildTextField(
                                controller: _accountNumberController,
                                label: 'Account Number',
                                required: true,
                              ),
                              _buildTextField(
                                controller: _ifscCodeController,
                                label: 'IFSC Code',
                                hint: 'e.g. SBIN0001234',
                                required: true,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return null;
                                  if (!_ifscRegex.hasMatch(val.trim().toUpperCase())) {
                                    return 'Invalid IFSC Code format';
                                  }
                                  return null;
                                },
                              ),
                              _buildTextField(
                                controller: _bankBranchController,
                                label: 'Branch',
                              ),
                            ] else ...[
                              const Text(
                                'Preferred Payment Method',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                key: ValueKey(_preferredPaymentMethod),
                                initialValue: _preferredPaymentMethod,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  fillColor: Colors.white,
                                  filled: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                items: _paymentOptions.map((opt) {
                                  return DropdownMenuItem<String>(
                                    value: opt['value'],
                                    child: Text(opt['label']!),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _preferredPaymentMethod = val;
                                    });
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Create Dealer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class RawMaterialDealerDetailScreen extends StatelessWidget {
  final Map<String, dynamic> dealer;

  const RawMaterialDealerDetailScreen({
    super.key,
    required this.dealer,
  });

  Widget _buildDetailRow(String label, String? value, {IconData? icon}) {
    final displayValue = (value == null || value.trim().isEmpty) ? 'N/A' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Colors.black54),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  displayValue,
                  style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardSection({required String title, required List<Widget> children}) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const Divider(height: 24, thickness: 1),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyName = dealer['companyName'] ?? 'Unknown Company';
    final address = dealer['address'] ?? '';
    final phone = dealer['phoneNumber'] ?? '';
    final email = dealer['email'] ?? '';
    final notes = dealer['notes'] ?? '';

    // Contact details
    final contactObj = dealer['contactPerson'];
    final contactName = contactObj is Map ? contactObj['name'] : 'N/A';
    final contactDesignation = contactObj is Map ? contactObj['designation'] : '';
    final contactPhone = contactObj is Map ? contactObj['phone'] : '';
    final contactEmail = contactObj is Map ? contactObj['email'] : '';

    // Compliance details
    final isGST = dealer['isGSTRegistered'] ?? false;
    final gst = dealer['gst'] ?? '';
    final pan = dealer['pan'] ?? '';
    final fssai = dealer['fssai'] ?? '';
    final aadhar = dealer['aadhar'] ?? '';

    // Payment/Bank details
    final hasBank = dealer['hasBankAccount'] ?? false;
    final preferredPay = dealer['preferredPaymentMethod'] ?? '';
    final bankObj = dealer['bankDetails'];
    final bankName = bankObj is Map ? bankObj['bankName'] : '';
    final accountNum = bankObj is Map ? bankObj['accountNumber'] : '';
    final ifsc = bankObj is Map ? bankObj['ifscCode'] : '';
    final branch = bankObj is Map ? bankObj['branch'] : '';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Dealer Details'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Card(
              elevation: 1,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.business, size: 36, color: Colors.black),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            companyName,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Status: ${dealer['status']?.toString().toUpperCase() ?? 'ACTIVE'}',
                            style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // General Details
            _buildCardSection(
              title: 'General Info',
              children: [
                _buildDetailRow('Phone Number', phone, icon: Icons.phone),
                _buildDetailRow('Email Address', email, icon: Icons.email),
                _buildDetailRow('Address', address, icon: Icons.location_on),
                if (notes.isNotEmpty) _buildDetailRow('Notes', notes, icon: Icons.note),
              ],
            ),

            // Contact Person Details
            _buildCardSection(
              title: 'Contact Person Details',
              children: [
                _buildDetailRow('Name', contactName, icon: Icons.person),
                if (contactDesignation.isNotEmpty) _buildDetailRow('Designation', contactDesignation, icon: Icons.badge),
                if (contactPhone.isNotEmpty) _buildDetailRow('Phone', contactPhone, icon: Icons.phone_iphone),
                if (contactEmail.isNotEmpty) _buildDetailRow('Email', contactEmail, icon: Icons.mail_outline),
              ],
            ),

            // GST & Compliance
            _buildCardSection(
              title: 'Taxation & Compliance',
              children: [
                _buildDetailRow('GST Registered', isGST ? 'Yes' : 'No', icon: Icons.check_circle_outline),
                if (isGST) ...[
                  _buildDetailRow('GST Number', gst, icon: Icons.receipt_long),
                  _buildDetailRow('PAN Number', pan, icon: Icons.credit_card),
                  if (fssai.isNotEmpty) _buildDetailRow('FSSAI Number', fssai, icon: Icons.security),
                ] else ...[
                  _buildDetailRow('Aadhar Card Number', aadhar, icon: Icons.fingerprint),
                ],
              ],
            ),

            // Payment details
            _buildCardSection(
              title: 'Payment & Banking Details',
              children: [
                _buildDetailRow('Bank Account Linked', hasBank ? 'Yes' : 'No', icon: Icons.account_balance),
                if (hasBank) ...[
                  _buildDetailRow('Bank Name', bankName, icon: Icons.corporate_fare),
                  _buildDetailRow('Account Number', accountNum, icon: Icons.pin),
                  _buildDetailRow('IFSC Code', ifsc, icon: Icons.code),
                  if (branch.isNotEmpty) _buildDetailRow('Branch', branch, icon: Icons.location_city),
                ] else ...[
                  _buildDetailRow('Preferred Payment Method', preferredPay.toUpperCase(), icon: Icons.payments),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryProductsScreen extends StatefulWidget {
  final Map<String, dynamic> category;

  const CategoryProductsScreen({super.key, required this.category});

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  bool _isLoading = false;
  List<dynamic> _products = [];
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final rawMaterials = await ApiService.instance.fetchRawMaterials();
      final catId = widget.category['id']?.toString();
      final filtered = rawMaterials.where((prod) {
        final catObj = prod['category'];
        final pCatId = (catObj is Map ? catObj['id'] : catObj)?.toString();
        return pCatId == catId;
      }).toList();

      if (mounted) {
        setState(() {
          _products = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Failed to load products: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catName = widget.category['name'] ?? 'Category Products';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(catName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadProducts,
                          child: const Text('Retry'),
                        )
                      ],
                    ),
                  ),
                )
              : _products.isEmpty
                  ? const Center(
                      child: Text(
                        'No products found in this category.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : Container(
                      color: Colors.white,
                      child: ListView.separated(
                        itemCount: _products.length,
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        separatorBuilder: (context, index) => const Divider(
                          height: 1,
                          indent: 68,
                          endIndent: 16,
                          color: Colors.black12,
                        ),
                        itemBuilder: (context, index) {
                          final prod = _products[index];
                          final name = prod['name'] ?? 'Unknown';
                          final unit = prod['unit'] ?? '';
                          final minStock = prod['minimumStockLevel']?.toString() ?? 'N/A';
                          
                          final dealerObj = prod['dealer'];
                          final dealerName = (dealerObj is Map ? dealerObj['companyName'] : null) ?? '';

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Row(
                              children: [
                                Container(
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
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      if (dealerName.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          dealerName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 13,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              catName,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Min: $minStock $unit',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
