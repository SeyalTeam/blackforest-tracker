import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Branches.ts', 'r') as f:
    code = f.read()

code = code.replace("if (req.user.role === 'superadmin') return true", "if (req.user.role === 'superadmin' || req.user.role === 'admin') return true")
# Also add admin to create
code = code.replace("create: ({ req }) => req.user?.role === 'superadmin',", "create: ({ req }) => req.user?.role === 'superadmin' || req.user?.role === 'admin',")
# And read
code = code.replace("read: ({ req }) => req.user?.role === 'superadmin',", "read: ({ req }) => req.user?.role === 'superadmin' || req.user?.role === 'admin',")

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Branches.ts', 'w') as f:
    f.write(code)

