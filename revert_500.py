import re

with open('lib/api_service.dart', 'r') as f:
    code = f.read()

# Make it print the response body on failure
old_throw = "throw Exception('Failed to update employee role: ${res.statusCode} ${res.body}');"
new_throw = "throw Exception('Failed to update employee role: ${res.statusCode}');"
code = code.replace(old_throw, new_throw)

with open('lib/api_service.dart', 'w') as f:
    f.write(code)

