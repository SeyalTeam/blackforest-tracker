import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/ClosingEntries.ts', 'r') as f:
    code = f.read()

old_hooks = """
  hooks: {
    beforeChange: [
"""

new_hooks = """
  hooks: {
    afterChange: [
      async ({ operation, doc, req }) => {
        // Reset branch isClosingEntryEnabled when a new entry is submitted
        if (operation === 'create' && doc.branch) {
          try {
            const branchId = typeof doc.branch === 'object' && doc.branch !== null ? (doc.branch.id || doc.branch._id) : doc.branch;
            if (branchId) {
              await req.payload.update({
                collection: 'branches',
                id: branchId,
                data: {
                  isClosingEntryEnabled: false,
                },
                overrideAccess: true,
              });
            }
          } catch (e) {
            console.error('Failed to reset branch isClosingEntryEnabled on closing entry creation:', e);
          }
        }
      },
    ],
    beforeChange: [
"""

code = code.replace(old_hooks.strip(), new_hooks.strip())

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/ClosingEntries.ts', 'w') as f:
    f.write(code)

