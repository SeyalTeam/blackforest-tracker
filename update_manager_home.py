import re

with open('lib/manager_home.dart', 'r') as f:
    code = f.read()

import_statement = "import 'manager_product_time_report.dart';"
new_import_statement = import_statement + "\nimport 'manager_employee_list.dart';"
code = code.replace(import_statement, new_import_statement)

old_grid_item = """
              _buildGridItem(
                context,
                title: 'Product Time Report',
                icon: Icons.timer,
                color: Colors.indigo,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManagerProductTimeReportScreen(
                        managerCompanyIds: managerCompanyIds,
                      ),
                    ),
                  );
                },
              ),
"""

new_grid_item = old_grid_item + """
              _buildGridItem(
                context,
                title: 'Manage Employees',
                icon: Icons.people,
                color: Colors.blueGrey,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManagerEmployeeListScreen(),
                    ),
                  );
                },
              ),
"""

code = code.replace(old_grid_item.strip(), new_grid_item.strip())

with open('lib/manager_home.dart', 'w') as f:
    f.write(code)

