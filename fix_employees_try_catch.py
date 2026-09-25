import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Employees.ts', 'r') as f:
    code = f.read()

old_loop = """
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
"""

new_loop = """
            for (const user of usersRes.docs) {
              try {
                await req.payload.update({
                  collection: 'users',
                  id: user.id,
                  data: {
                    role: doc.team,
                  },
                  overrideAccess: true,
                })
              } catch (e) {
                console.error(`Failed to sync role to user ${user.id}:`, e)
              }
            }
"""

code = code.replace(old_loop.strip(), new_loop.strip())

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Employees.ts', 'w') as f:
    f.write(code)

