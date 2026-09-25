import re

with open('lib/api_service.dart', 'r') as f:
    code = f.read()

new_methods = """
  Future<void> updateBranchClosingAccess(String branchId, bool isEnabled) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/branches/$branchId';
      final res = await http.patch(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'isClosingEntryEnabled': isEnabled}),
      );

      if (res.statusCode != 200) {
        throw Exception('Failed to update branch access: ${res.statusCode}');
      }
      
      // Clear branch cache so UI updates next time it fetches branches
      _cachedBranches = null;
    } catch (e) {
      debugPrint('Error updating branch access: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> fetchEmployees() async {
"""

code = code.replace("  Future<List<dynamic>> fetchEmployees() async {", new_methods.strip() + "\n\n  Future<List<dynamic>> fetchEmployees() async {")

with open('lib/api_service.dart', 'w') as f:
    f.write(code)

