import 'package:flutter/material.dart';
import 'api_service.dart';

class ManagerClosingControlScreen extends StatefulWidget {
  final List<String> managerCompanyIds;

  const ManagerClosingControlScreen({
    super.key,
    required this.managerCompanyIds,
  });

  @override
  State<ManagerClosingControlScreen> createState() => _ManagerClosingControlScreenState();
}

class _ManagerClosingControlScreenState extends State<ManagerClosingControlScreen> {
  List<dynamic> _branches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    try {
      final allBranches = await ApiService.instance.fetchBranches();
      if (mounted) {
        setState(() {
          _branches = allBranches.where((b) {
            final comp = b['company'];
            final compId = comp is Map ? (comp['id'] ?? comp['_id']) : comp;
            return widget.managerCompanyIds.contains(compId?.toString());
          }).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading branches: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleClosingAccess(String branchId, bool newValue) async {
    try {
      // Optimistic UI update
      setState(() {
        final idx = _branches.indexWhere((b) => (b['id'] ?? b['_id']).toString() == branchId);
        if (idx != -1) {
          _branches[idx]['isClosingEntryEnabled'] = newValue;
        }
      });

      await ApiService.instance.updateBranchClosingAccess(branchId, newValue);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Closing entry access updated')),
        );
      }
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          final idx = _branches.indexWhere((b) => (b['id'] ?? b['_id']).toString() == branchId);
          if (idx != -1) {
            _branches[idx]['isClosingEntryEnabled'] = !newValue;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating access: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Closing Entry Control', style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _branches.isEmpty
              ? const Center(child: Text('No branches found.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _branches.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final branch = _branches[index];
                    final String id = branch['id']?.toString() ?? branch['_id']?.toString() ?? '';
                    final String name = branch['name']?.toString() ?? 'Unknown Branch';
                    final bool isEnabled = branch['isClosingEntryEnabled'] == true;

                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            Switch(
                              value: isEnabled,
                              onChanged: (val) => _toggleClosingAccess(id, val),
                              activeColor: Colors.teal,
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
