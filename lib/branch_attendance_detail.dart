import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BranchAttendanceDetailScreen extends StatelessWidget {
  final String branchName;
  final List<dynamic> items;

  const BranchAttendanceDetailScreen({
    super.key,
    required this.branchName,
    required this.items,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'active': return Colors.green;
      case 'on_break': return Colors.orange;
      default: return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active': return 'Active';
      case 'on_break': return 'On Break';
      default: return 'Closed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...items]..sort((a, b) {
        const order = {'active': 0, 'on_break': 1, 'closed': 2};
        return (order[a['status']] ?? 2).compareTo(order[b['status']] ?? 2);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text('$branchName - Attendance', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: sorted.isEmpty
          ? const Center(child: Text('No attendance records found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = sorted[index];
                final status = item['status']?.toString() ?? 'closed';
                final statusColor = _statusColor(status);
                final statusLabel = _statusLabel(status);

                final name = item['employeeName']?.toString() ?? item['userName']?.toString() ?? 'Unknown';
                final role = (item['employeeTeam'] ?? item['userRole'] ?? '').toString().toUpperCase();
                final phone = item['employeePhone']?.toString() ?? '';
                final empId = item['employeeId']?.toString() ?? '';

                final firstIn = item['firstPunchIn'] != null
                    ? DateFormat('hh:mm a').format(DateTime.parse(item['firstPunchIn']).toLocal())
                    : '--';
                final workFormatted = item['totalWorkFormatted']?.toString() ?? '0m';
                final breakFormatted = item['totalBreakFormatted']?.toString() ?? '0m';
                final sessions = item['sessionCount'] ?? 0;
                final breaks = item['breakCount'] ?? 0;

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withValues(alpha: 0.15),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                if (role.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(role, style: TextStyle(fontSize: 10, color: Colors.blue[700])),
                                  ),
                                if (empId.isNotEmpty)
                                  Text('#$empId', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Punch-In / Punch-Out buttons
                          Row(
                            children: [
                              _punchButton(
                                label: 'IN',
                                time: firstIn,
                                color: Colors.green,
                                icon: Icons.login,
                              ),
                              const SizedBox(width: 8),
                              Builder(
                                builder: (context) {
                                  // Get last punch-out from activities
                                  final activities = item['activities'] as List<dynamic>? ?? [];
                                  final sessions = activities.where((a) => a['type'] == 'session').toList();
                                  String lastOut = '--';
                                  bool isActive = status == 'active' || status == 'on_break';
                                  for (final s in sessions) {
                                    if (s['punchOut'] != null) {
                                      final t = DateFormat('hh:mm a').format(DateTime.parse(s['punchOut']).toLocal());
                                      lastOut = t;
                                    }
                                  }
                                  if (isActive) lastOut = 'Active';
                                  return _punchButton(
                                    label: 'OUT',
                                    time: lastOut,
                                    color: isActive ? Colors.orange : Colors.red[400]!,
                                    icon: Icons.logout,
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _stat('First In', firstIn, Icons.login, Colors.green),
                            _stat('Work Time', workFormatted, Icons.access_time, Colors.blue),
                            _stat('Break Time', breakFormatted, Icons.coffee, Colors.orange),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _stat('Sessions', '$sessions', Icons.repeat, Colors.purple),
                            _stat('Breaks', '$breaks', Icons.pause_circle_outline, Colors.deepOrange),
                            if (phone.isNotEmpty)
                              _stat('Phone', phone, Icons.phone, Colors.teal)
                            else
                              const Expanded(child: SizedBox()),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Timeline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                        ),
                        const SizedBox(height: 8),
                        ..._buildTimeline(item['activities'] as List<dynamic>? ?? []),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _punchButton({
    required String label,
    required String time,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            time,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTimeline(List<dynamic> activities) {
    if (activities.isEmpty) {
      return [const Text('No activity records.', style: TextStyle(color: Colors.grey, fontSize: 12))];
    }

    final sorted = [...activities];
    sorted.sort((a, b) {
      final ta = a['punchIn'] != null ? DateTime.tryParse(a['punchIn'])?.millisecondsSinceEpoch ?? 0 : 0;
      final tb = b['punchIn'] != null ? DateTime.tryParse(b['punchIn'])?.millisecondsSinceEpoch ?? 0 : 0;
      return ta.compareTo(tb);
    });

    return sorted.map((act) {
      final type = act['type']?.toString() ?? 'session';
      final isBreak = type == 'break';
      final color = isBreak ? Colors.orange : Colors.green;
      final icon = isBreak ? Icons.coffee : Icons.work;

      final punchIn = act['punchIn'] != null
          ? DateFormat('hh:mm a').format(DateTime.parse(act['punchIn']).toLocal())
          : '--';
      final punchOut = act['punchOut'] != null
          ? DateFormat('hh:mm a').format(DateTime.parse(act['punchOut']).toLocal())
          : (act['status'] == 'active' ? 'Active' : '--');
      final duration = act['durationFormatted']?.toString() ?? '';

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Text(
                    isBreak ? 'Break' : 'Session',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                  ),
                  const SizedBox(width: 8),
                  Text('$punchIn → $punchOut', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            if (duration.isNotEmpty)
              Text(duration, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
      );
    }).toList();
  }
}
