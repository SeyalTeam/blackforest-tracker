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
                          : ListView.builder(
                              itemCount: _categories.length,
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              itemBuilder: (context, index) {
                                final cat = _categories[index];
                                final name = cat['name'] ?? 'Unknown';
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8.0),
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.category_outlined,
                                      color: Colors.black54,
                                    ),
                                    title: Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                );
                              },
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
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _minStockController = TextEditingController();
  
  bool _isLoading = false;
  List<dynamic> _categories = [];
  List<dynamic> _products = [];
  List<dynamic> _dealers = [];
  String? _selectedCategoryId;
  String? _selectedDealerId;
  String _selectedUnit = 'kg';
  String? _errorMsg;

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

      // 4. Fetch and filter dealers
      final dealers = await ApiService.instance.fetchDealers();
      final filteredDealers = dealers.where((dl) {
        final allowedComps = dl['allowedCompanies'] as List?;
        if (allowedComps == null) return false;
        return allowedComps.any((c) {
          final cId = (c is Map ? c['id'] : c)?.toString();
          return cId != null && companyIds.contains(cId);
        });
      }).toList();

      if (mounted) {
        setState(() {
          _categories = filteredCategories;
          _products = filteredProducts;
          _dealers = filteredDealers;
          if (_categories.isNotEmpty) {
            _selectedCategoryId = _categories.first['id']?.toString();
          }
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
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

      // Clear input fields
      _nameController.clear();
      _minStockController.clear();
      _selectedDealerId = null;
      
      // Reload products list
      final rawMaterials = await ApiService.instance.fetchRawMaterials();
      final filteredProducts = rawMaterials.where((prod) {
        final catObj = prod['category'];
        final catId = (catObj is Map ? catObj['id'] : catObj)?.toString();
        return catId != null && _categories.any((c) => c['id']?.toString() == catId);
      }).toList();

      if (mounted) {
        setState(() {
          _products = filteredProducts;
          _isLoading = false;
        });
        Navigator.of(context).pop(); // dismiss the dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Raw Material Product created successfully!'),
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

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Product'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: 'e.g. Tomato',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Category', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCategoryId,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: _categories.map((cat) {
                          return DropdownMenuItem<String>(
                            value: cat['id']?.toString(),
                            child: Text(cat['name'] ?? 'Unknown'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            _selectedCategoryId = val;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Dealer (Optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedDealerId,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('None (Internal)'),
                          ),
                          ..._dealers.map((dl) {
                            return DropdownMenuItem<String>(
                              value: dl['id']?.toString(),
                              child: Text(dl['companyName'] ?? 'Unknown Dealer'),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setDialogState(() {
                            _selectedDealerId = val;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Unit', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedUnit,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: _unitOptions.map((opt) {
                          return DropdownMenuItem<String>(
                            value: opt['value'],
                            child: Text(opt['label']!),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              _selectedUnit = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Minimum Stock Level', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _minStockController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          hintText: 'e.g. 5.0',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final num = double.tryParse(value.trim());
                            if (num == null) return 'Must be a number';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
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
              : _products.isEmpty
                  ? const Center(
                      child: Text(
                        'No products found.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _products.length,
                      padding: const EdgeInsets.all(16.0),
                      itemBuilder: (context, index) {
                        final prod = _products[index];
                        final name = prod['name'] ?? 'Unknown';
                        final unit = prod['unit'] ?? '';
                        final minStock = prod['minimumStockLevel']?.toString() ?? 'N/A';
                        
                        final catObj = prod['category'];
                        final catName = (catObj is Map ? catObj['name'] : 'Unknown');

                        final dealerObj = prod['dealer'];
                        final dealerName = (dealerObj is Map ? dealerObj['companyName'] : null) ?? '';
                        final displayName = name + (dealerName.isNotEmpty ? ' with $dealerName' : '');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12.0),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.inventory_2_outlined,
                                    color: Colors.black54,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
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
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CreateDealerScreen extends StatefulWidget {
  const CreateDealerScreen({super.key});

  @override
  State<CreateDealerScreen> createState() => _CreateDealerScreenState();
}

class _CreateDealerScreenState extends State<CreateDealerScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _companyNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _gstController = TextEditingController();
  final _panController = TextEditingController();

  bool _isLoading = false;
  List<dynamic> _dealers = [];
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
      // 1. Resolve store keeper's allowed companies
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

      // 2. Fetch all dealers
      final dealers = await ApiService.instance.fetchDealers();

      // Filter dealers to only those allowed for the storekeeper's companies
      final filteredDealers = dealers.where((dl) {
        final allowedComps = dl['allowedCompanies'] as List?;
        if (allowedComps == null) return false;
        return allowedComps.any((c) {
          final cId = (c is Map ? c['id'] : c)?.toString();
          return cId != null && companyIds.contains(cId);
        });
      }).toList();

      if (mounted) {
        setState(() {
          _dealers = filteredDealers;
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_companyIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not resolve company for your branch/profile.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.instance.createDealer(
        companyName: _companyNameController.text.trim(),
        address: _addressController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        contactName: _contactNameController.text.trim(),
        allowedCompanies: _companyIds,
        gst: _gstController.text.trim().isNotEmpty ? _gstController.text.trim() : null,
        pan: _panController.text.trim().isNotEmpty ? _panController.text.trim() : null,
      );

      // Clear form inputs
      _companyNameController.clear();
      _addressController.clear();
      _phoneController.clear();
      _emailController.clear();
      _contactNameController.clear();
      _gstController.clear();
      _panController.clear();

      // Reload dealers
      final dealers = await ApiService.instance.fetchDealers();
      final filteredDealers = dealers.where((dl) {
        final allowedComps = dl['allowedCompanies'] as List?;
        if (allowedComps == null) return false;
        return allowedComps.any((c) {
          final cId = (c is Map ? c['id'] : c)?.toString();
          return cId != null && _companyIds.contains(cId);
        });
      }).toList();

      if (mounted) {
        setState(() {
          _dealers = filteredDealers;
          _isLoading = false;
        });
        Navigator.of(context).pop(); // dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dealer created successfully!'),
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
            content: Text('Error creating dealer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Dealer'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Company Name', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _companyNameController,
                    decoration: InputDecoration(
                      hintText: 'e.g. ABC Distributors',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('Address', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _addressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Enter full address',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'e.g. 9876543210',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('Email Address', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'e.g. info@abc.com',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Required';
                      if (!value.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Contact Person Name', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _contactNameController,
                    decoration: InputDecoration(
                      hintText: 'e.g. John Doe',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('GST (Optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _gstController,
                    decoration: InputDecoration(
                      hintText: 'e.g. 22AAAAA0000A1Z5',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('PAN (Optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _panController,
                    decoration: InputDecoration(
                      hintText: 'e.g. ABCDE1234F',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _contactNameController.dispose();
    _gstController.dispose();
    _panController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Dealers'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isLoading && _dealers.isEmpty
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
              : _dealers.isEmpty
                  ? const Center(
                      child: Text(
                        'No dealers found.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _dealers.length,
                      padding: const EdgeInsets.all(16.0),
                      itemBuilder: (context, index) {
                        final dl = _dealers[index];
                        final companyName = dl['companyName'] ?? 'Unknown Company';
                        final address = dl['address'] ?? '';
                        final phone = dl['phoneNumber'] ?? '';
                        
                        final contactObj = dl['contactPerson'];
                        final contactName = contactObj is Map ? contactObj['name'] : 'N/A';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12.0),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.business_outlined,
                                    color: Colors.black54,
                                    size: 24,
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
