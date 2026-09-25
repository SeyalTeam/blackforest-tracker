import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/ClosingEntries.ts', 'r') as f:
    code = f.read()

code = code.replace("data: {", "data: {")
code = code.replace("isClosingEntryEnabled: false,", "isClosingEntryEnabled: false,")
# Actually, I can just cast the data object to any
code = code.replace("data: {", "data: {")
code = code.replace("data: {\n                  isClosingEntryEnabled: false,\n                },", "data: {\n                  isClosingEntryEnabled: false,\n                } as any,")

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/ClosingEntries.ts', 'w') as f:
    f.write(code)

