import re

with open('lib/manager_attendance_report.dart', 'r') as f:
    code = f.read()

# Replace class names
code = code.replace('BranchClosingReportScreen', 'BranchAttendanceReportScreen')
code = code.replace('_BranchClosingReportScreenState', '_BranchAttendanceReportScreenState')
code = code.replace('ManagerClosingReportScreen', 'ManagerAttendanceReportScreen')
code = code.replace('_ManagerClosingReportScreenState', '_ManagerAttendanceReportScreenState')

# Replace API call
code = code.replace('fetchClosingEntryReport', 'fetchAttendanceReport')
code = code.replace('_closingReport', '_attendanceReport')

# Replace titles and text
code = code.replace("'Closing Entry Report'", "'Attendance Report'")

# Replace import branch_closing_entries.dart
code = code.replace("import 'branch_closing_entries.dart';", "")

# In the grouping logic _groupStatsByCompany, it uses _closingReport?['stats']
# Attendance uses _attendanceReport?['branchStats']
code = code.replace("_attendanceReport?['stats']", "_attendanceReport?['branchStats']")

# Replace the default branch stats
default_stats = """
        grouped[cId]!.add({
          'branchName': bName,
          'presentCount': 0,
          'activeCount': 0,
          'totalHours': 0.0,
        });
"""
# Find and replace the default branch dict
code = re.sub(r"grouped\[cId\]!\.add\(\{\s*'branchName': bName,[^\}]+\}\);", default_stats.strip(), code, flags=re.MULTILINE)


# For sorting, sort by presentCount instead of net
code = re.sub(r"final amountA = \(a\['net'\].*?\)\.toDouble\(\);", "final amountA = (a['presentCount'] ?? 0).toDouble();", code)
code = re.sub(r"final amountB = \(b\['net'\].*?\)\.toDouble\(\);", "final amountB = (b['presentCount'] ?? 0).toDouble();", code)


# Rewrite the _buildBranchCard completely for attendance
new_branch_card = """
  Widget _buildBranchCard(Map<String, dynamic> stat, NumberFormat format) {
    return InkWell(
      onTap: null, // TODO: Show branch attendance entries
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
                  const Icon(Icons.people, color: Colors.blue),
                ],
              ),
              const Divider(height: 24),
              
              // Metrics Grid
              Row(
                children: [
                  Expanded(child: _buildMetric('PRESENT', '${stat['presentCount'] ?? 0}')),
                  Expanded(child: _buildMetric('ACTIVE NOW', '${stat['activeCount'] ?? 0}')),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL HOURS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                    Text(
                      '${(stat['totalHours'] ?? 0).toStringAsFixed(1)} h',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.blue[900],
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
"""

# Replace the _buildBranchCard function
code = re.sub(r"Widget _buildBranchCard\(Map<String, dynamic> stat, NumberFormat format\) \{.*?  \}\n", new_branch_card, code, flags=re.DOTALL)

with open('lib/manager_attendance_report.dart', 'w') as f:
    f.write(code)
