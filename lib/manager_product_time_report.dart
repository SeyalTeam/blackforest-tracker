import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';
import 'branch_product_time_details.dart';

class ManagerProductTimeReportScreen extends StatefulWidget {
  final List<String> managerCompanyIds;

  const ManagerProductTimeReportScreen({
    super.key,
    required this.managerCompanyIds,
  });

  @override
  State<ManagerProductTimeReportScreen> createState() => _ManagerProductTimeReportScreenState();
}

class _ManagerProductTimeReportScreenState extends State<ManagerProductTimeReportScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  Map<String, List<Map<String, dynamic>>> _groupedReports = {};
  String _errorMessage = '';
  
  List<dynamic> _branches = [];
  List<dynamic> _companies = [];
  String? _selectedCompanyId;

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _groupedReports = {};
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final api = ApiService.instance;

      // Fetch branches and companies
      _branches = await api.fetchBranches(forceRefresh: true);
      _companies = await api.fetchCompanies();

      final Map<String, List<Map<String, dynamic>>> grouped = {};

      // Manager's allocated branches? Wait, managerCompanyIds are actually companies in some places, or branch IDs?
      // In the app, managerCompanyIds are actually COMPANY IDs. So we need to fetch branches for those companies!
      final relevantBranches = _branches.where((b) {
        final cId = b['company']?['id']?.toString() ?? b['company']?.toString();
        return widget.managerCompanyIds.contains(cId);
      }).toList();

      // Fetch for each relevant branch in parallel
      final futures = relevantBranches.map((branchInfo) async {
        final branchId = branchInfo['id']?.toString() ?? branchInfo['_id']?.toString();
        if (branchId == null || branchId.isEmpty) return;

        try {
          final res = await api.fetchProductTimeReport(
            startDate: dateStr,
            endDate: dateStr,
            branchId: branchId,
          );
          
          final details = res['details'] as List<dynamic>? ?? [];
          if (details.isNotEmpty) {
            final companyId = branchInfo['company']?['id']?.toString() ?? branchInfo['company']?.toString() ?? 'unknown';
            final branchName = branchInfo['name']?.toString() ?? 'Unknown Branch';

            double totalAmount = 0;
            int totalItems = 0;
            for (var item in details) {
               totalAmount += ((item['amount'] ?? 0) as num).toDouble();
               totalItems += ((item['quantity'] ?? 1) as num).toInt();
            }

            final stat = {
              'branchId': branchId,
              'branchName': branchName,
              'totalAmount': totalAmount,
              'totalItems': totalItems,
              'count': details.length,
              'items': details,
            };

            if (!grouped.containsKey(companyId)) {
              grouped[companyId] = [];
            }
            grouped[companyId]!.add(stat);
          }
        } catch (e) {
          debugPrint('Error fetching product time for $branchId: $e');
        }
      });

      await Future.wait(futures);

      // Filter out empty branches
      final filteredGrouped = <String, List<Map<String, dynamic>>>{};
      for (var entry in grouped.entries) {
        final validBranches = entry.value.where((stat) => (stat['count'] as int? ?? 0) > 0).toList();
        if (validBranches.isNotEmpty) {
          filteredGrouped[entry.key] = validBranches;
        }
      }

      setState(() {
        _groupedReports = filteredGrouped;
        _isLoading = false;
        
        if (_selectedCompanyId == null && filteredGrouped.isNotEmpty) {
          _selectedCompanyId = filteredGrouped.keys.first;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load report data: $e';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchReports();
    }
  }

  String _getCompanyName(String companyId) {
    try {
      final comp = _companies.firstWhere((c) => c['id'] == companyId || c['_id'] == companyId);
      return comp['name']?.toString() ?? 'Unknown Company';
    } catch (e) {
      return 'Unknown Company';
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

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
              onPressed: _fetchReports,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (_groupedReports.isEmpty) {
      bodyContent = const Center(child: Text('No product time data found.'));
    } else {
      final branches = _selectedCompanyId != null ? (_groupedReports[_selectedCompanyId!] ?? []) : [];
      branches.sort((a, b) => (b['totalAmount'] as double).compareTo(a['totalAmount'] as double));

      bodyContent = RefreshIndicator(
        onRefresh: _fetchReports,
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
                  children: _groupedReports.keys.map((companyId) {
                    final isSelected = _selectedCompanyId == companyId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_getCompanyName(companyId)),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedCompanyId = companyId);
                          }
                        },
                        selectedColor: Colors.indigo.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.indigo[700] : Colors.grey[700],
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(height: 1),
            // Branch List
            Expanded(
              child: branches.isEmpty
                  ? const Center(child: Text('No product time data for this company'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: branches.length,
                      itemBuilder: (context, index) {
                        return _buildBranchCard(branches[index], format);
                      },
                    ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Product Time Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              DateFormat('dd MMM yyyy').format(_selectedDate),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Colors.indigo),
            onPressed: _pickDate,
            tooltip: 'Select Date',
          ),
        ],
      ),
      body: bodyContent,
    );
  }

  Widget _buildBranchCard(Map<String, dynamic> stat, NumberFormat format) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BranchProductTimeDetailsScreen(
              branchName: stat['branchName']?.toString() ?? 'Unknown Branch',
              items: stat['items'] as List<dynamic>? ?? [],
            ),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      stat['branchName']?.toString() ?? 'Unknown Branch',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.timer, color: Colors.indigo),
                ],
              ),
              const Divider(height: 24),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ITEMS PREPARED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                      Text('${stat['totalItems'] ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('TOTAL AMOUNT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                      Text(format.format(stat['totalAmount'] ?? 0), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.indigo[800])),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
