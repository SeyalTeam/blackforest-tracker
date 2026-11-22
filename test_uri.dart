import 'package:intl/intl.dart';

void main() {
  final _currentMonth = DateTime(2026, 9);
  final startOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
  final endOfMonth = DateTime(
    _currentMonth.year,
    _currentMonth.month + 1,
    0,
    23, 59, 59
  );

  final startStr = startOfMonth.toUtc().toIso8601String();
  final endStr = endOfMonth.toUtc().toIso8601String();
  final userId = "6a51c3edec08231d01c3a3d1";

  final urlString = 'https://blackforest.vseyal.com/api/attendance?where[user][equals]=$userId&where[date][greater_than_equal]=$startStr&where[date][less_than_equal]=$endStr&limit=100';
  
  try {
    final url = Uri.parse(urlString);
    print("URL Parsed: " + url.toString());
  } catch (e) {
    print("Parse Error: " + e.toString());
  }
}
