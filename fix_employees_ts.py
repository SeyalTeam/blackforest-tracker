import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Employees.ts', 'r') as f:
    code = f.read()

# Fix update access
old_update = "return user.role === 'company' || user.role === 'branch'"
new_update = "return user.role === 'company' || user.role === 'branch' || user.role === 'manager'"
code = code.replace(old_update, new_update)

# Add afterChange hook
old_hooks = """
  hooks: {
    beforeChange: [
      async ({ operation, data, req: _req }) => {
        if (operation === 'create' || operation === 'update') {
          if (data.name === 'Kitchen') {
            data.team = 'kitchen'
          }
        }
        return data
      },
    ],
  },
"""

new_hooks = """
  hooks: {
    beforeChange: [
      async ({ operation, data, req: _req }) => {
        if (operation === 'create' || operation === 'update') {
          if (data.name === 'Kitchen') {
            data.team = 'kitchen'
          }
        }
        return data
      },
    ],
    afterChange: [
      async ({ doc, previousDoc, req }) => {
        // If team (role) has changed, update the associated User record
        if (doc.team !== previousDoc?.team) {
          const usersRes = await req.payload.find({
            collection: 'users',
            where: {
              employee: {
                equals: doc.id,
              },
            },
            depth: 0,
            overrideAccess: true,
          })

          if (usersRes.docs && usersRes.docs.length > 0) {
            for (const user of usersRes.docs) {
              await req.payload.update({
                collection: 'users',
                id: user.id,
                data: {
                  role: doc.team,
                },
                overrideAccess: true,
              })
            }
          }
        }
      },
    ],
  },
"""

code = code.replace(old_hooks.strip(), new_hooks.strip())

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Employees.ts', 'w') as f:
    f.write(code)

