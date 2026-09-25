import re

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Users.ts', 'r') as f:
    code = f.read()

old_employee_check = """
          if (
            typeof nextData.role === 'string' &&
            ['waiter', 'cashier', 'supervisor', 'delivery', 'driver', 'chef', 'store_keeper'].includes(
              nextData.role,
            ) &&
            !nextData.employee
          ) {
            throw new Error(
              'Employee is required for waiter, cashier, supervisor, delivery, driver, chef, or store keeper role users',
            )
          }
"""

new_employee_check = """
          const resolvedEmployee =
            nextData.employee ??
            (operation === 'update'
              ? (originalDoc as { employee?: unknown } | undefined)?.employee
              : undefined)
              
          if (
            typeof resolvedRole === 'string' &&
            ['waiter', 'cashier', 'supervisor', 'delivery', 'driver', 'chef', 'store_keeper'].includes(
              resolvedRole,
            ) &&
            !resolvedEmployee
          ) {
            throw new Error(
              'Employee is required for waiter, cashier, supervisor, delivery, driver, chef, or store keeper role users',
            )
          }
"""

code = code.replace(old_employee_check.strip(), new_employee_check.strip())

with open('/Users/castromurugan/Documents/Blackforest/blackforest-payload/src/collections/Users.ts', 'w') as f:
    f.write(code)

