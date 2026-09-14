import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class ManagerBillingReportScreen extends StatefulWidget {
  final List<String> managerCompanyIds;
  const ManagerBillingReportScreen({super.key, required this.managerCompanyIds});

  @override
  State<ManagerBillingReportScreen> createState() => _ManagerBillingReportScreenState();
}

class _ManagerBillingReportScreenState extends State<ManagerBillingReportScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  
  Map<String, dynamic>? _billingReport;
  List<dynamic> _branches = [];
  List<dynamic> _companies = [];

  String? _selectedCompanyId;

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

      final today = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(today);

      final results = await Future.wait([
        ApiService.instance.fetchBranchBillingReport(startDate: dateStr, endDate: dateStr),
        ApiService.instance.fetchBranches(),
        ApiService.instance.fetchCompanies(),
      ]);

      setState(() {
        _billingReport = results[0] as Map<String, dynamic>;
        _branches = results[1] as List<dynamic>;
        _companies = results[2] as List<dynamic>;
        _isLoading = false;
        
        // Auto-select first company if available
        final grouped = _groupStatsByCompany();
        if (grouped.isNotEmpty && _selectedCompanyId == null) {
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
    final stats = _billingReport?['stats'] as List<dynamic>? ?? [];
    
    // Create branchName -> companyId map
    final branchToCompany = <String, String>{};
    for (var b in _branches) {
      final name = b['name']?.toString() ?? '';
      final c = b['company'];
      final cId = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
      branchToCompany[name] = cId;
    }

    // Grouping
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var stat in stats) {
      final branchName = stat['branchName']?.toString() ?? '';
      final cId = branchToCompany[branchName] ?? 'unknown';
      
      if (widget.managerCompanyIds.isNotEmpty && cId != 'unknown' && !widget.managerCompanyIds.contains(cId)) {
        continue;
      }

      if (!grouped.containsKey(cId)) {
        grouped[cId] = [];
      }
      grouped[cId]!.add(stat as Map<String, dynamic>);
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

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Billing Report'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: bodyContent,
    );
  }

  Widget _buildBranchCard(Map<String, dynamic> stat, NumberFormat format) {
    return Card(
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
                Expanded(child: _buildMetric('TOTAL BILLS', '${stat['totalBills'] ?? 0}')),
                Expanded(child: _buildMetric('CASH TOTAL', format.format(stat['cash'] ?? 0))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildMetric('UPI PAYMENTS', format.format(stat['upi'] ?? 0))),
                Expanded(child: _buildMetric('CARD REVENUE', format.format(stat['card'] ?? 0))),
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
                    'TOTAL AMOUNT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  Text(
                    format.format(stat['totalAmount'] ?? 0),
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
    );
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
