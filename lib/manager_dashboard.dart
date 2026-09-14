import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class ManagerDashboard extends StatefulWidget {
  final List<String> managerCompanyIds;
  const ManagerDashboard({super.key, required this.managerCompanyIds});

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  bool _isLoading = true;
  String _errorMessage = '';
  
  Map<String, dynamic>? _billingReport;
  List<dynamic> _branches = [];
  List<dynamic> _companies = [];

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
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load dashboard: $e';
        _isLoading = false;
      });
    }
  }

  Map<String, Map<String, dynamic>> _aggregateByCompany() {
    // Group branch stats by company
    final stats = _billingReport?['stats'] as List<dynamic>? ?? [];
    
    // Create branchName -> companyId map
    final branchToCompany = <String, String>{};
    for (var b in _branches) {
      final name = b['name']?.toString() ?? '';
      final c = b['company'];
      final cId = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
      branchToCompany[name] = cId;
    }

    // Create companyId -> companyName map
    final companyNames = <String, String>{};
    for (var c in _companies) {
      final id = (c['id'] ?? c['_id'])?.toString() ?? '';
      companyNames[id] = c['name']?.toString() ?? 'Unknown Company';
    }

    // Aggregate
    final Map<String, Map<String, dynamic>> aggregated = {};

    for (var stat in stats) {
      final branchName = stat['branchName']?.toString() ?? '';
      final cId = branchToCompany[branchName] ?? 'unknown';
      
      // If the manager has specific companies, filter to only those (though backend should already do this)
      if (widget.managerCompanyIds.isNotEmpty && cId != 'unknown' && !widget.managerCompanyIds.contains(cId)) {
        continue;
      }

      final cName = cId == 'unknown' ? 'Other Branches' : (companyNames[cId] ?? 'Unknown Company');

      if (!aggregated.containsKey(cName)) {
        aggregated[cName] = {
          'totalAmount': 0.0,
          'totalBills': 0,
          'cash': 0.0,
          'upi': 0.0,
          'card': 0.0,
        };
      }

      aggregated[cName]!['totalAmount'] += (stat['totalAmount'] ?? 0).toDouble();
      aggregated[cName]!['totalBills'] += (stat['totalBills'] ?? 0) as int;
      aggregated[cName]!['cash'] += (stat['cash'] ?? 0).toDouble();
      aggregated[cName]!['upi'] += (stat['upi'] ?? 0).toDouble();
      aggregated[cName]!['card'] += (stat['card'] ?? 0).toDouble();
    }

    return aggregated;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
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
    }

    final aggregated = _aggregateByCompany();
    final totals = _billingReport?['totals'] ?? {};

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOverallTotals(totals),
            const SizedBox(height: 24),
            const Text(
              'Company Reports',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (aggregated.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('No billing data for today.', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: aggregated.length,
                itemBuilder: (context, index) {
                  final cName = aggregated.keys.elementAt(index);
                  final data = aggregated[cName]!;
                  return _buildCompanyCard(cName, data);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallTotals(Map<String, dynamic> totals) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[700]!, Colors.blue[900]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Overall Today',
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            currencyFormat.format((totals['totalAmount'] ?? 0).toDouble()),
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStat('BILLS', (totals['totalBills'] ?? 0).toString()),
              _buildMiniStat('CASH', currencyFormat.format((totals['cash'] ?? 0).toDouble())),
              _buildMiniStat('ONLINE', currencyFormat.format(((totals['upi'] ?? 0) + (totals['card'] ?? 0)).toDouble())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildCompanyCard(String companyName, Map<String, dynamic> data) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            companyName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            'Total Sales',
            style: TextStyle(color: Colors.grey[600], fontSize: 11),
          ),
          Text(
            currencyFormat.format(data['totalAmount']),
            style: const TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bills', style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                  Text('${data['totalBills']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Online', style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                  Text(currencyFormat.format(data['upi'] + data['card']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
