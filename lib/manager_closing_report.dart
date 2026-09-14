import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';
import 'branch_closing_entries.dart';

class ManagerClosingReportScreen extends StatefulWidget {
  final List<String> managerCompanyIds;
  const ManagerClosingReportScreen({super.key, required this.managerCompanyIds});

  @override
  State<ManagerClosingReportScreen> createState() => _ManagerClosingReportScreenState();
}

class _ManagerClosingReportScreenState extends State<ManagerClosingReportScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  
  Map<String, dynamic>? _closingReport;
  List<dynamic> _branches = [];
  List<dynamic> _companies = [];

  String? _selectedCompanyId;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final results = await Future.wait([
        ApiService.instance.fetchClosingEntryReport(startDate: dateStr, endDate: dateStr),
        ApiService.instance.fetchBranches(forceRefresh: true),
        ApiService.instance.fetchCompanies(),
      ]);

      setState(() {
        _closingReport = results[0] as Map<String, dynamic>;
        _branches = results[1] as List<dynamic>;
        _companies = results[2] as List<dynamic>;
        _isLoading = false;
        
        // Auto-select first company if available
        final grouped = _groupStatsByCompany();
        if (grouped.isNotEmpty && (_selectedCompanyId == null || !grouped.containsKey(_selectedCompanyId))) {
          _selectedCompanyId = grouped.keys.first;
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load report: $e';
        _isLoading = false;
      });
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupStatsByCompany() {
    final stats = _closingReport?['stats'] as List<dynamic>? ?? [];
    
    // Grouping
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    // First, initialize all active branches that belong to the manager's companies
    for (var b in _branches) {
      final bName = b['name']?.toString() ?? '';
      final c = b['company'];
      final cId = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
      final status = b['status']?.toString().toLowerCase();
      
      // Only include active branches (or null/empty for backwards compatibility)
      final isActive = status == null || status.isEmpty || status == 'active';
      
      if (isActive && cId.isNotEmpty && (widget.managerCompanyIds.isEmpty || widget.managerCompanyIds.contains(cId))) {
        if (!grouped.containsKey(cId)) {
          grouped[cId] = [];
        }
        
        // Add a 0-value template for this branch
        grouped[cId]!.add({
          'branchName': bName,
          'totalEntries': 0,
          'cash': 0.0,
          'upi': 0.0,
          'expenses': 0.0,
          'net': 0.0,
          'totalSales': 0.0,
        });
      }
    }

    // Now overlay the actual stats from the report
    for (var stat in stats) {
      final branchName = stat['branchName']?.toString() ?? '';
      
      // Find which company this branch belongs to
      String foundCompanyId = '';
      bool isActive = true;
      for (var b in _branches) {
        if ((b['name']?.toString() ?? '') == branchName) {
          final c = b['company'];
          foundCompanyId = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
          final status = b['status']?.toString().toLowerCase();
          isActive = status == null || status.isEmpty || status == 'active';
          break;
        }
      }
      
      if (!isActive) continue;
      
      final cId = foundCompanyId.isNotEmpty ? foundCompanyId : 'unknown';
      
      if (widget.managerCompanyIds.isNotEmpty && cId != 'unknown' && !widget.managerCompanyIds.contains(cId)) {
        continue;
      }

      if (!grouped.containsKey(cId)) {
        grouped[cId] = [];
      }

      // Find the template we added earlier and replace it, or add if it wasn't there
      final existingIndex = grouped[cId]!.indexWhere((s) => s['branchName'] == branchName);
      if (existingIndex >= 0) {
        grouped[cId]![existingIndex] = stat as Map<String, dynamic>;
      } else {
        grouped[cId]!.add(stat as Map<String, dynamic>);
      }
    }

    return grouped;
  }

  String _getCompanyName(String companyId) {
    if (companyId == 'unknown') return 'Other Branches';
    for (var c in _companies) {
      final id = (c['id'] ?? c['_id'])?.toString() ?? '';
      if (id == companyId) {
        return c['name']?.toString() ?? 'Unknown Company';
      }
    }
    return 'Unknown Company';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    if (_isLoading) {
      bodyContent = const Center(child: CircularProgressIndicator());
    } else if (_errorMessage.isNotEmpty) {
      bodyContent = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else {
      final groupedStats = _groupStatsByCompany();

      if (groupedStats.isEmpty) {
        bodyContent = const Center(
          child: Text('No billing data available.', style: TextStyle(color: Colors.grey)),
        );
      } else {
        // Ensure selected company is valid
        if (_selectedCompanyId == null || !groupedStats.containsKey(_selectedCompanyId)) {
          _selectedCompanyId = groupedStats.keys.first;
        }

        final selectedStats = groupedStats[_selectedCompanyId]!;
        
        // Sort from top sales to zero
        selectedStats.sort((a, b) {
          final amountA = (a['net'] ?? a['totalSales'] ?? 0).toDouble();
          final amountB = (b['net'] ?? b['totalSales'] ?? 0).toDouble();
          return amountB.compareTo(amountA);
        });

        final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

        bodyContent = RefreshIndicator(
          onRefresh: _fetchData,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Company Tabs
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: groupedStats.keys.map((cId) {
                      final isSelected = cId == _selectedCompanyId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(_getCompanyName(cId)),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedCompanyId = cId;
                              });
                            }
                          },
                          selectedColor: Colors.blue[600],
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          backgroundColor: Colors.grey[200],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              
              // Branch List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: selectedStats.length,
                  itemBuilder: (context, index) {
                    final stat = selectedStats[index];
                    return _buildBranchCard(stat, currencyFormat);
                  },
                ),
              ),
            ],
          ),
        );
      }
    }

    final dateDisplay = DateFormat('dd MMM yyyy').format(_selectedDate);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Closing Entry Report', style: TextStyle(fontSize: 16)),
            Text(
              dateDisplay,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Colors.blue),
            onPressed: _pickDate,
            tooltip: 'Select Date',
          ),
        ],
      ),
      body: bodyContent,
    );
  }

  Widget _buildBranchCard(Map<String, dynamic> stat, NumberFormat format) {
    // Determine the branch ID for navigation
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BranchClosingEntriesScreen(stat: stat),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Branch Name Header
            Row(
              children: [
                Icon(Icons.storefront, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stat['branchName']?.toString().toUpperCase() ?? 'UNKNOWN BRANCH',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // Metrics Grid
            Row(
              children: [
                Expanded(child: _buildMetric('TOTAL ENTRIES', '${stat['totalEntries'] ?? 0}')),
                Expanded(child: _buildMetric('CASH', format.format(stat['cash'] ?? 0))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildMetric('UPI', format.format(stat['upi'] ?? 0))),
                Expanded(child: _buildMetric('EXPENSES', format.format(stat['expenses'] ?? 0))),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'NET AMOUNT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  Text(
                    format.format(stat['net'] ?? stat['totalSales'] ?? 0),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.green[900],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey[500],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
