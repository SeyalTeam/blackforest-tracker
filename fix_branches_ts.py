import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Branches.ts', 'r') as f:
    code = f.read()

# 1. Add isClosingEntryEnabled field
old_stock_order_workflow = """
    {
      name: 'stockOrderWorkflow',
"""

new_stock_order_workflow = """
    {
      name: 'isClosingEntryEnabled',
      label: 'Enable Closing Entry Form',
      type: 'checkbox',
      defaultValue: false,
      admin: {
        description: 'When enabled by a manager, allows the branch cashier to submit their closing entry. Automatically resets to false after submission.',
        position: 'sidebar',
      },
    },
    {
      name: 'stockOrderWorkflow',
"""

code = code.replace(old_stock_order_workflow.strip(), new_stock_order_workflow.strip())

# 2. Add manager update access
old_access = """
    update: ({ req, id: _id }): boolean | import('payload').Where => {
      if (!req.user) return false
      if (req.user.role === 'superadmin') return true
      if (req.user.role === 'branch') {
"""

new_access = """
    update: ({ req, id: _id }): boolean | import('payload').Where => {
      if (!req.user) return false
      if (req.user.role === 'superadmin') return true
      if (req.user.role === 'manager') {
        const userCompanies = req.user.companies || [];
        const userCompanyIds = userCompanies.map((c: any) => typeof c === 'string' ? c : (c.id || ''));
        if (userCompanyIds.length > 0) {
          return { company: { in: userCompanyIds } };
        }
        return false;
      }
      if (req.user.role === 'branch') {
"""

code = code.replace(old_access.strip(), new_access.strip())

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Branches.ts', 'w') as f:
    f.write(code)

