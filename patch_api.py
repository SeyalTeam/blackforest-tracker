with open('lib/api_service.dart', 'r') as f:
    code = f.read()

new_method = """
  Future<List<dynamic>> fetchManagerClosingReplies({
    required String branchId,
    required String dateStr,
  }) async {
    try {
      final token = await _getToken();
      // Date format is yyyy-MM-dd. We can search exactly this date if we stored it as 'dayOnly' in Payload.
      // Payload stores dayOnly dates as strings like "2026-09-18T00:00:00.000Z".
      // We can use a like or contains, or just fetch all for the branch and filter locally, but it's better to filter by branch and date.
      // Actually, since there won't be many replies for a branch, we can just fetch by branch and sort by date descending, or limit by date prefix.
      final url = '$_baseUrl/api/manager-closing-replies?where[branch][equals]=$branchId&limit=50';
      
      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        import 'dart:convert';
        final data = json.decode(res.body);
        final docs = data['docs'] as List<dynamic>? ?? [];
        // Filter locally by date just to be safe
        return docs.where((doc) {
          final docDate = doc['date']?.toString() ?? '';
          return docDate.startsWith(dateStr);
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching replies: $e');
      return [];
    }
  }

  Future<void> submitManagerClosingReply
"""

code = code.replace("  Future<void> submitManagerClosingReply", new_method.strip())

with open('lib/api_service.dart', 'w') as f:
    f.write(code)
