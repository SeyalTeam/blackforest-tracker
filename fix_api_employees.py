import re

with open('lib/api_service.dart', 'r') as f:
    code = f.read()

new_methods = """
  Future<List<dynamic>> fetchEmployees() async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/employees?limit=2000&where[status][equals]=active';
      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['docs'] ?? [];
      } else {
        throw Exception('Failed to load employees: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching employees: $e');
      rethrow;
    }
  }

  Future<void> updateEmployeeRole(String id, String role) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/employees/$id';
      final res = await http.patch(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'team': role}),
      );

      if (res.statusCode != 200) {
        throw Exception('Failed to update employee role: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error updating employee role: $e');
      rethrow;
    }
  }

  Future<void> submitManagerClosingReply
"""

code = code.replace("  Future<void> submitManagerClosingReply", new_methods.strip() + " ")

with open('lib/api_service.dart', 'w') as f:
    f.write(code)

