import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Branches.ts', 'r') as f:
    code = f.read()

old_manager_check = """
      if (req.user.role === 'manager') {
        const userCompanies = req.user.companies || [];
        const userCompanyIds = userCompanies.map((c: any) => typeof c === 'string' ? c : (c.id || ''));
        if (userCompanyIds.length > 0) {
          return { company: { in: userCompanyIds } };
        }
        return false;
      }
"""

new_manager_check = """
      if (req.user.role === 'manager') {
        const userCompanies = req.user.manager_companies || [];
        const userCompanyIds = userCompanies.map((c: any) => typeof c === 'string' ? c : (c.id || ''));
        if (userCompanyIds.length > 0) {
          return { company: { in: userCompanyIds } };
        }
        return false;
      }
"""

code = code.replace(old_manager_check.strip(), new_manager_check.strip())

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Branches.ts', 'w') as f:
    f.write(code)

