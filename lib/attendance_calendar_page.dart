import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

class AttendanceCalendarPage extends StatefulWidget {
  const AttendanceCalendarPage({super.key});

  @override
  State<AttendanceCalendarPage> createState() => _AttendanceCalendarPageState();
}

class _AttendanceCalendarPageState extends State<AttendanceCalendarPage> {
  DateTime _currentMonth = DateTime.now();
  Map<String, Map<String, dynamic>> _attendanceMap = {};
  bool _isLoading = true;

  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _fetchMonthlyAttendance();
  }

  Future<void> _fetchMonthlyAttendance() async {
    setState(() => _isLoading = true);
    try {
      final startOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
      final endOfMonth = DateTime(
        _currentMonth.year,
        _currentMonth.month + 1,
        0,
        23, 59, 59
      );

      final startStr = startOfMonth.toUtc().toIso8601String();
      final endStr = endOfMonth.toUtc().toIso8601String();

      // We need the current user ID to filter (or query directly)
      final userStr = await _storage.read(key: 'user');
      String? userId;
      if (userStr != null) {
        final userData = json.decode(userStr);
        userId = userData['id']?.toString();
      }

      final token = await _storage.read(key: 'token');

      // Query the attendance collection directly
      final url = Uri.parse(
        '${ApiService.baseUrl}/attendance?where[user][equals]=$userId&where[date][greater_than_equal]=$startStr&where[date][less_than_equal]=$endStr&limit=100',
      );

      final res = await http.get(
        url,
        headers: {if (token != null) 'Authorization': 'JWT $token'},
      );

      final newMap = <String, Map<String, dynamic>>{};
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final docs = data['docs'] as List?;
        if (docs != null) {
          for (final doc in docs) {
            final ds = doc['dateString'] as String?;
            if (ds != null) {
              newMap[ds] = doc as Map<String, dynamic>;
            }
          }
        }
      } else {
        debugPrint('Failed to load attendance: ${res.statusCode}');
      }

      if (mounted) {
        setState(() {
          _attendanceMap = newMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching monthly attendance: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
    _fetchMonthlyAttendance();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
    _fetchMonthlyAttendance();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Calendar',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: const Icon(
                    Icons.calendar_month,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.list, color: Colors.grey, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildMonthSelector(),
                  const SizedBox(height: 16),
                  _buildCalendarGrid(),
                  const SizedBox(height: 24),
                  _buildLegend(),
                  const SizedBox(height: 24),
                  _buildPendingRegularization(),
                ],
              ),
            ),
    );
  }

  Widget _buildMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: _previousMonth,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_left, color: Colors.blue),
          ),
        ),
        Text(
          DateFormat('MMMM yyyy').format(_currentMonth),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        GestureDetector(
          onTap: _nextMonth,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_right, color: Colors.blue),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final firstDayWeekday = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      1,
    ).weekday; // 1=Mon, 7=Sun
    final startingOffset = firstDayWeekday % 7; // Map so Sun=0, Mon=1, etc.

    final totalCells = ((daysInMonth + startingOffset) / 7).ceil() * 7;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Weekday headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          // Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalCells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              if (index < startingOffset ||
                  index >= startingOffset + daysInMonth) {
                return const SizedBox.shrink();
              }
              final day = index - startingOffset + 1;
              final date = DateTime(
                _currentMonth.year,
                _currentMonth.month,
                day,
              );
              return _buildDayCell(date);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final isToday = dateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());

    final attendance = _attendanceMap[dateStr];

    // Status Logic
    bool isPresent = attendance != null;
    bool isHalfDay = attendance?['dayType'] == 'half_day';
    bool isAbsent = !isPresent && date.isBefore(DateTime.now());
    bool isSunday = date.weekday == 7;

    // Colors based on image
    Color bgColor = const Color(0xFFF0F2F5); // default future or empty
    Color textColor = Colors.grey[600]!;
    Border? border;

    if (isToday) {
      border = Border.all(color: Colors.blue, width: 2);
    }

    if (isPresent) {
      if (isHalfDay) {
        bgColor = const Color(0xFFFFF3E0); // light orange
        textColor = Colors.orange[900]!;
      } else {
        bgColor = const Color(0xFFE8F5E9); // light green
        textColor = Colors.green[800]!;
      }
    } else if (isSunday && date.isBefore(DateTime.now())) {
      bgColor = Colors.grey[200]!;
      textColor = Colors.grey[700]!;
    } else if (isAbsent) {
      bgColor = const Color(0xFFFFEBEE); // light red
      textColor = Colors.red[800]!;
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: border,
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          if (isHalfDay)
            Positioned(
              bottom: 4,
              left: 0,
              right: 0,
              child: Center(
                child: Icon(
                  Icons.access_time_filled,
                  color: Colors.orange,
                  size: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        _buildLegendItem('Today', Colors.blue, isOutline: true),
        _buildLegendItem('Present', Colors.green),
        _buildLegendItem('Absent', Colors.red),
        _buildLegendItem('On leave', Colors.purple),
        _buildLegendItem('Half Day', Colors.orange),
        _buildLegendItem('Week Off', Colors.blueGrey),
        _buildLegendItem('Holiday', Colors.teal),
        _buildLegendItem('Late', Colors.orange, icon: Icons.access_time_filled),
        _buildLegendItem(
          'Punch Error',
          Colors.orange,
          icon: Icons.warning_rounded,
        ),
      ],
    );
  }

  Widget _buildLegendItem(
    String label,
    Color color, {
    bool isOutline = false,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, color: color, size: 14)
          else if (isOutline)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
            )
          else
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[800],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRegularization() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: Colors.black87),
            SizedBox(width: 8),
            Text(
              'Pending Regularization',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Empty state for now
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: const Center(
            child: Text(
              'No pending items',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}
