import 'package:flutter/material.dart';
import 'api_service.dart';

class ManagerEmployeeListScreen extends StatefulWidget {
  const ManagerEmployeeListScreen({super.key});

  @override
  State<ManagerEmployeeListScreen> createState() => _ManagerEmployeeListScreenState();
}

class _ManagerEmployeeListScreenState extends State<ManagerEmployeeListScreen> {
  List<dynamic> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';

  final List<String> _roles = [
    'waiter',
    'chef',
    'driver',
    'cashier',
    'manager',
    'supervisor',
    'delivery',
    'kitchen',
    'store_keeper',
    'account',
    'watcher',
  ];

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);
    try {
      final employees = await ApiService.instance.fetchEmployees();
      if (mounted) {
        setState(() {
          _employees = employees;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading employees: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateRole(String id, String newRole) async {
    try {
      await ApiService.instance.updateEmployeeRole(id, newRole);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role updated successfully!')),
        );
        _loadEmployees(); // Reload list to reflect changes
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating role: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _employees.where((e) {
      final name = e['name']?.toString().toLowerCase() ?? '';
      final eid = e['employeeId']?.toString().toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || eid.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee List', style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by Name or ID...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
        ),
      ),
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : filtered.isEmpty
              ? const Center(child: Text('No employees found.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final emp = filtered[index];
                    final String id = emp['id']?.toString() ?? emp['_id']?.toString() ?? '';
                    final String name = emp['name']?.toString() ?? 'Unknown';
                    final String empId = emp['employeeId']?.toString() ?? 'N/A';
                    final String role = emp['team']?.toString() ?? '';

                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blue[100],
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID: $empId',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            // Role Dropdown
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _roles.contains(role) ? role : null,
                                  hint: const Text('Role', style: TextStyle(fontSize: 13)),
                                  style: TextStyle(color: Colors.blue[900], fontSize: 14, fontWeight: FontWeight.bold),
                                  icon: Icon(Icons.arrow_drop_down, color: Colors.blue[900]),
                                  items: _roles.map((r) {
                                    return DropdownMenuItem<String>(
                                      value: r,
                                      child: Text(
                                        r.toUpperCase(),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newRole) {
                                    if (newRole != null && newRole != role) {
                                      _updateRole(id, newRole);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
