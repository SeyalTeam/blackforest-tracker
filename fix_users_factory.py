import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Users.ts', 'r') as f:
    code = f.read()

old_factory_check = """
          if (
            nextData.role === 'factory' &&
            (!nextData.factory_companies || nextData.factory_companies.length === 0)
          ) {
            throw new Error('At least one company is required for factory role users')
          }
"""

new_factory_check = """
          const resolvedFactoryCompanies =
            nextData.factory_companies ??
            (operation === 'update'
              ? (originalDoc as { factory_companies?: unknown[] } | undefined)?.factory_companies
              : undefined)
              
          if (
            resolvedRole === 'factory' &&
            (!Array.isArray(resolvedFactoryCompanies) || resolvedFactoryCompanies.length === 0)
          ) {
            throw new Error('At least one company is required for factory role users')
          }
"""

code = code.replace(old_factory_check.strip(), new_factory_check.strip())

old_storekeeper_check = """
          if (
            nextData.role === 'store_keeper' &&
            (!nextData.storekeeper_companies || nextData.storekeeper_companies.length === 0)
          ) {
            throw new Error('At least one company is required for store keeper role users')
          }
"""

new_storekeeper_check = """
          const resolvedStorekeeperCompanies =
            nextData.storekeeper_companies ??
            (operation === 'update'
              ? (originalDoc as { storekeeper_companies?: unknown[] } | undefined)?.storekeeper_companies
              : undefined)
              
          if (
            resolvedRole === 'store_keeper' &&
            (!Array.isArray(resolvedStorekeeperCompanies) || resolvedStorekeeperCompanies.length === 0)
          ) {
            throw new Error('At least one company is required for store keeper role users')
          }
"""

code = code.replace(old_storekeeper_check.strip(), new_storekeeper_check.strip())

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Users.ts', 'w') as f:
    f.write(code)

