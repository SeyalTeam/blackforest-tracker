import re

with open('lib/branch_product_time_details.dart', 'r') as f:
    code = f.read()

# Replace the parsing logic for orderedAt
old_time_logic = """
                final time = item['orderedAt'] != null 
                    ? DateFormat('hh:mm a').format(DateTime.parse(item['orderedAt']).toLocal())
                    : '';
"""

new_time_logic = """
                String time = '';
                if (item['orderedAt'] != null && item['orderedAt'].toString().isNotEmpty) {
                  final str = item['orderedAt'].toString();
                  final parsed = DateTime.tryParse(str);
                  if (parsed != null) {
                    time = DateFormat('hh:mm a').format(parsed.toLocal());
                  } else {
                    try {
                      final timeDate = DateFormat('HH:mm:ss').parse(str);
                      time = DateFormat('hh:mm a').format(timeDate);
                    } catch (_) {
                      time = str;
                    }
                  }
                }
"""

code = code.replace(old_time_logic.strip(), new_time_logic.strip())

with open('lib/branch_product_time_details.dart', 'w') as f:
    f.write(code)

