import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Branches.ts', 'r') as f:
    code = f.read()

code = code.replace("update: ({ req }) => req.user?.role === 'superadmin',", "update: ({ req }) => req.user?.role === 'superadmin' || req.user?.role === 'admin',")

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Branches.ts', 'w') as f:
    f.write(code)

