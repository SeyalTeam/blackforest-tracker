import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Users.ts', 'r') as f:
    code = f.read()

# Fix the company check in Users.ts to use resolvedCompany
old_company_check = """
          if ((nextData.role === 'company' || nextData.role === 'chef') && !nextData.company) {
            throw new Error(`Company is required for ${nextData.role} role users`)
          }
"""

new_company_check = """
          const resolvedCompany =
            nextData.company ??
            (operation === 'update'
              ? (originalDoc as { company?: unknown } | undefined)?.company
              : undefined)
              
          if ((resolvedRole === 'company' || resolvedRole === 'chef') && !resolvedCompany) {
            throw new Error(`Company is required for ${resolvedRole} role users`)
          }
"""

code = code.replace(old_company_check.strip(), new_company_check.strip())

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Users.ts', 'w') as f:
    f.write(code)

