import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'api_service.dart';
import 'category_list.dart';
import 'stockorder_report.dart';

class DepartmentListPage extends StatefulWidget {
  const DepartmentListPage({super.key});

  @override
  State<DepartmentListPage> createState() => _DepartmentListPageState();
}

class _DepartmentListPageState extends State<DepartmentListPage> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<dynamic> _departments = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final data = await _api.fetchDepartments();
      if (mounted) {
        setState(() {
          _departments = [
            {'id': 'ALL', 'name': 'All Stock'},
            ...data
          ];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Departments',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 16.0,
                      mainAxisSpacing: 16.0,
                    ),
                    itemCount: _departments.length,
                    itemBuilder: (context, index) {
                      final dept = _departments[index];
                      return Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: InkWell(
                          onTap: () {
                            if (dept['id'] == 'ALL') {
                               Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const StockOrderReportPage()),
                               );
                            } else {
                               Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CategoryListPage(
                                      departmentId: dept['id'],
                                      pageTitle: dept['name'],
                                    ),
                                  ),
                               );
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                dept['name'] ?? 'Unknown',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
