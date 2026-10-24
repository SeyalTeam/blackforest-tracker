import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

enum ChefCategoryMode { kitchen, stock }

class ChefCategoryManagementScreen extends StatefulWidget {
  final ChefCategoryMode mode;
  final String? kitchenId;
  final String? kitchenName;

  const ChefCategoryManagementScreen({
    super.key,
    required this.mode,
    this.kitchenId,
    this.kitchenName,
  });

  @override
  State<ChefCategoryManagementScreen> createState() =>
      _ChefCategoryManagementScreenState();
}

class _ChefCategoryManagementScreenState
    extends State<ChefCategoryManagementScreen> {
  static const _storage = FlutterSecureStorage();

  bool _isLoading = true;
  bool _isSaving = false;
  String _errorMessage = '';

  String _userId = '';
  String _activeKitchenId = '';
  String _activeKitchenName = '';

  List<Map<String, dynamic>> _allCategories = [];
  Set<String> _selectedCategoryIds = {};
  Map<String, List<String>> _categoryToOtherChefsMap = {};

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      _userId = (await _storage.read(key: 'userId')) ??
          (await _storage.read(key: 'user_id')) ??
          '';

      if (widget.mode == ChefCategoryMode.kitchen) {
        await _loadKitchenModeData();
      } else {
        await _loadStockModeData();
      }
    } catch (e) {
      debugPrint('Error loading category management data: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadKitchenModeData() async {
    // 1. Resolve Kitchen ID & Name
    String kId = widget.kitchenId?.trim() ?? '';
    String kName = widget.kitchenName?.trim() ?? '';

    if (kId.isEmpty) {
      kId = (await _storage.read(key: 'userKitchenId'))?.trim() ?? '';
    }
    if (kName.isEmpty) {
      kName = (await _storage.read(key: 'userKitchenName'))?.trim() ?? '';
    }

    if (kId.isEmpty || _userId.isEmpty) {
      try {
        final profile = await ApiService.instance.fetchUserProfile();
        if (_userId.isEmpty) {
          _userId = (profile['id'] ?? profile['_id'])?.toString() ?? '';
          if (_userId.isNotEmpty) {
            await _storage.write(key: 'userId', value: _userId);
          }
        }
        if (kId.isEmpty) {
          final kitchenObj = profile['kitchen'];
          if (kitchenObj is List && kitchenObj.isNotEmpty) {
            final firstK = kitchenObj.first;
            if (firstK is Map) {
              kId = (firstK['id'] ?? firstK['_id'])?.toString() ?? '';
              if (kName.isEmpty && firstK['name'] != null) {
                kName = firstK['name'].toString();
              }
            } else if (firstK is String) {
              kId = firstK;
            }
          } else if (kitchenObj is Map) {
            kId = (kitchenObj['id'] ?? kitchenObj['_id'])?.toString() ?? '';
            if (kName.isEmpty && kitchenObj['name'] != null) {
              kName = kitchenObj['name'].toString();
            }
          } else if (kitchenObj is String) {
            kId = kitchenObj;
          }
        }
      } catch (e) {
        debugPrint('Failed to resolve profile in kitchen mode: $e');
      }
    }

    _activeKitchenId = kId;
    _activeKitchenName = kName;

    if (_activeKitchenId.isEmpty) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'No kitchen is assigned to your profile. Please contact an administrator.';
          _isLoading = false;
        });
      }
      return;
    }

    // 2. Fetch Kitchen Details to get its assigned categories
    final kitchenDetails =
        await ApiService.instance.fetchKitchenDetails(_activeKitchenId);
    if (kName.isEmpty && kitchenDetails['name'] != null) {
      _activeKitchenName = kitchenDetails['name'].toString();
    }

    final rawKitchenCats = (kitchenDetails['categories'] as List?) ?? [];
    List<Map<String, dynamic>> resolvedCats = [];

    // Check if categories are populated objects or just IDs
    bool needsFullFetch = rawKitchenCats.any((c) => c is! Map || c['name'] == null);
    if (needsFullFetch) {
      final allCats = await ApiService.instance.fetchCategories(forceRefresh: true);
      final Set<String> kitchenCatIds = rawKitchenCats.map((c) {
        return (c is Map ? (c['id'] ?? c['_id']) : c)?.toString().trim() ?? '';
      }).where((id) => id.isNotEmpty).toSet();

      for (var cat in allCats) {
        final id = (cat is Map ? (cat['id'] ?? cat['_id']) : cat)?.toString().trim() ?? '';
        if (kitchenCatIds.contains(id) && cat is Map) {
          resolvedCats.add(Map<String, dynamic>.from(cat));
        }
      }
    } else {
      for (var c in rawKitchenCats) {
        if (c is Map) {
          resolvedCats.add(Map<String, dynamic>.from(c));
        }
      }
    }

    // Sort categories alphabetically
    resolvedCats.sort((a, b) =>
        (a['name']?.toString() ?? '').toLowerCase().compareTo(
            (b['name']?.toString() ?? '').toLowerCase()));

    // 3. Load Current Chef's Kitchen Category Selections
    final rawSaved = await _storage.read(key: 'userKitchenCategoryIds');
    final Set<String> savedSelected = rawSaved != null && rawSaved.isNotEmpty
        ? rawSaved.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()
        : {};

    // 4. Fetch All Chefs to map who else handles these categories
    final allChefs = await ApiService.instance.fetchChefs();
    final Map<String, List<String>> otherChefsMap = {};

    for (var cDoc in allChefs) {
      final chefId = (cDoc['id'] ?? cDoc['_id'])?.toString() ?? '';
      if (chefId == _userId) continue;
      final chefName = (cDoc['name'] ?? cDoc['username'] ?? 'Chef').toString();
      final cCats = (cDoc['categories'] as List?) ?? [];
      for (var cat in cCats) {
        final catId = (cat is Map ? (cat['id'] ?? cat['_id']) : cat)?.toString() ?? '';
        if (catId.isNotEmpty) {
          otherChefsMap.putIfAbsent(catId, () => []).add(chefName);
        }
      }
    }

    if (mounted) {
      setState(() {
        _allCategories = resolvedCats;
        _selectedCategoryIds = savedSelected;
        _categoryToOtherChefsMap = otherChefsMap;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStockModeData() async {
    // 1. Fetch All Stock Categories (isStock: true)
    final allCats = await ApiService.instance.fetchCategories(
      onlyStock: true,
      forceRefresh: true,
    );

    List<Map<String, dynamic>> resolvedCats = [];
    for (var cat in allCats) {
      if (cat is Map) {
        resolvedCats.add(Map<String, dynamic>.from(cat));
      }
    }

    resolvedCats.sort((a, b) =>
        (a['name']?.toString() ?? '').toLowerCase().compareTo(
            (b['name']?.toString() ?? '').toLowerCase()));

    // 2. Load Current Chef's Stock Category Selections
    final rawSaved = await _storage.read(key: 'userStockCategoryIds');
    final Set<String> savedSelected = rawSaved != null && rawSaved.isNotEmpty
        ? rawSaved.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()
        : {};

    // 3. Fetch All Chefs to map who handles these stock categories
    final allChefs = await ApiService.instance.fetchChefs();
    final Map<String, List<String>> otherChefsMap = {};

    for (var cDoc in allChefs) {
      final chefId = (cDoc['id'] ?? cDoc['_id'])?.toString() ?? '';
      if (chefId == _userId) continue;
      final chefName = (cDoc['name'] ?? cDoc['username'] ?? 'Chef').toString();
      final sCats = (cDoc['stockCategories'] as List?) ?? [];
      for (var cat in sCats) {
        final catId = (cat is Map ? (cat['id'] ?? cat['_id']) : cat)?.toString() ?? '';
        if (catId.isNotEmpty) {
          otherChefsMap.putIfAbsent(catId, () => []).add(chefName);
        }
      }
    }

    if (mounted) {
      setState(() {
        _allCategories = resolvedCats;
        _selectedCategoryIds = savedSelected;
        _categoryToOtherChefsMap = otherChefsMap;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAssignments() async {
    if (_userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User session not found. Please log in again.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final selectedList = _selectedCategoryIds.toList();

      if (widget.mode == ChefCategoryMode.kitchen) {
        if (_activeKitchenId.isEmpty) {
          throw Exception('No kitchen ID found for KOT assignments');
        }

        await ApiService.instance.updateUserCategories(
          userId: _userId,
          kitchenId: _activeKitchenId,
          categoryIds: selectedList,
        );

        await _storage.write(key: 'userKitchenId', value: _activeKitchenId);
        await _storage.write(key: 'userKitchenCategoryIds', value: selectedList.join(','));

        // Resolve names for profile & headers
        final selectedNames = _allCategories
            .where((cat) => selectedList.contains((cat['id'] ?? cat['_id'])?.toString()))
            .map((cat) => (cat['name'] ?? '').toString())
            .where((name) => name.isNotEmpty)
            .toList();

        await _storage.write(key: 'userKitchenCategoryNames', value: selectedNames.join(','));
        await _storage.write(key: 'userKitchenOnlyCategoryNames', value: selectedNames.join(','));
      } else {
        await ApiService.instance.updateUserStockCategories(
          userId: _userId,
          stockCategoryIds: selectedList,
        );

        await _storage.write(key: 'userStockCategoryIds', value: selectedList.join(','));

        final selectedNames = _allCategories
            .where((cat) => selectedList.contains((cat['id'] ?? cat['_id'])?.toString()))
            .map((cat) => (cat['name'] ?? '').toString())
            .where((name) => name.isNotEmpty)
            .toList();

        await _storage.write(key: 'userStockCategoryNames', value: selectedNames.join(','));
        await _storage.write(key: 'userStockOnlyCategoryNames', value: selectedNames.join(','));
      }

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.mode == ChefCategoryMode.kitchen
                  ? 'KOT categories updated successfully!'
                  : 'Stock order categories updated successfully!',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Failed to save category assignments: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save categories: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedCategoryIds.length == _allCategories.length) {
        _selectedCategoryIds.clear();
      } else {
        _selectedCategoryIds = _allCategories
            .map((c) => (c['id'] ?? c['_id'])?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isKitchen = widget.mode == ChefCategoryMode.kitchen;
    final primaryColor = isKitchen ? Colors.indigo : Colors.teal;

    final filteredCategories = _allCategories.where((cat) {
      if (_searchQuery.isEmpty) return true;
      final name = (cat['name']?.toString() ?? '').toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isKitchen ? 'KOT Categories' : 'Stock Order Categories',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              isKitchen
                  ? (_activeKitchenName.isNotEmpty
                      ? 'Kitchen: $_activeKitchenName'
                      : 'Kitchen Order Management')
                  : 'Stock Fulfillment Categories',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.85),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          if (!_isLoading && _allCategories.isNotEmpty)
            TextButton.icon(
              onPressed: _toggleSelectAll,
              icon: Icon(
                _selectedCategoryIds.length == _allCategories.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
                color: Colors.white,
                size: 18,
              ),
              label: Text(
                _selectedCategoryIds.length == _allCategories.length
                    ? 'Clear'
                    : 'Select All',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? _buildErrorView(primaryColor)
              : Column(
                  children: [
                    _buildHeaderBanner(primaryColor),
                    _buildSearchBar(),
                    Expanded(
                      child: filteredCategories.isEmpty
                          ? _buildEmptyState()
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              itemCount: filteredCategories.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final cat = filteredCategories[index];
                                final catId =
                                    (cat['id'] ?? cat['_id'])?.toString() ?? '';
                                final catName =
                                    cat['name']?.toString() ?? 'Category';
                                final isSelected =
                                    _selectedCategoryIds.contains(catId);
                                final otherChefs =
                                    _categoryToOtherChefsMap[catId] ?? [];

                                return _buildCategoryCard(
                                  catId: catId,
                                  catName: catName,
                                  catData: cat,
                                  isSelected: isSelected,
                                  otherChefs: otherChefs,
                                  primaryColor: primaryColor,
                                );
                              },
                            ),
                    ),
                    _buildBottomBar(primaryColor),
                  ],
                ),
    );
  }

  Widget _buildHeaderBanner(Color primaryColor) {
    final count = _selectedCategoryIds.length;
    final total = _allCategories.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.08),
        border: Border(
          bottom: BorderSide(color: primaryColor.withOpacity(0.15)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                widget.mode == ChefCategoryMode.kitchen
                    ? Icons.restaurant_rounded
                    : Icons.inventory_2_rounded,
                color: primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                widget.mode == ChefCategoryMode.kitchen
                    ? 'Assigned Kitchen Categories'
                    : 'All Available Stock Categories',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: primaryColor.withOpacity(0.95),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count of $total Selected',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search categories...',
          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (val) {
          setState(() => _searchQuery = val.trim());
        },
      ),
    );
  }

  Widget _buildCategoryCard({
    required String catId,
    required String catName,
    required Map<String, dynamic> catData,
    required bool isSelected,
    required List<String> otherChefs,
    required Color primaryColor,
  }) {
    String chefAssignmentText;
    Color chefBadgeBg;
    Color chefBadgeText;
    IconData chefBadgeIcon;

    if (isSelected && otherChefs.isNotEmpty) {
      chefAssignmentText = 'Assigned to You & ${otherChefs.join(", ")}';
      chefBadgeBg = Colors.green.shade50;
      chefBadgeText = Colors.green.shade800;
      chefBadgeIcon = Icons.groups_rounded;
    } else if (isSelected) {
      chefAssignmentText = 'Assigned to You';
      chefBadgeBg = Colors.green.shade50;
      chefBadgeText = Colors.green.shade800;
      chefBadgeIcon = Icons.check_circle_rounded;
    } else if (otherChefs.isNotEmpty) {
      chefAssignmentText = 'Assigned to: ${otherChefs.join(", ")}';
      chefBadgeBg = Colors.orange.shade50;
      chefBadgeText = Colors.orange.shade900;
      chefBadgeIcon = Icons.person_rounded;
    } else {
      chefAssignmentText = 'Unassigned';
      chefBadgeBg = Colors.grey.shade100;
      chefBadgeText = Colors.grey.shade600;
      chefBadgeIcon = Icons.remove_circle_outline_rounded;
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? primaryColor.withOpacity(0.5)
              : Colors.grey.shade200,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      color: isSelected ? primaryColor.withOpacity(0.02) : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedCategoryIds.remove(catId);
            } else {
              _selectedCategoryIds.add(catId);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Checkbox indicator
              Checkbox(
                value: isSelected,
                activeColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedCategoryIds.add(catId);
                    } else {
                      _selectedCategoryIds.remove(catId);
                    }
                  });
                },
              ),
              const SizedBox(width: 8),
              // Category details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      catName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isSelected ? primaryColor : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Chef handling badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: chefBadgeBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(chefBadgeIcon, size: 12, color: chefBadgeText),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              chefAssignmentText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: chefBadgeText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No categories match "$_searchQuery"'
                  : 'No categories available.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(Color primaryColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange.shade700),
            const SizedBox(height: 16),
            Text(
              'Cannot Load Categories',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(Color primaryColor) {
    final count = _selectedCategoryIds.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, -3),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: _isSaving ? null : _saveAssignments,
            child: _isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    'Save Assignments ($count Selected)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
