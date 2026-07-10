import 'package:flutter/material.dart';

class ModuleSwitcherFooter extends StatelessWidget {
  final String activeModule;
  final ValueChanged<String> onModuleChanged;

  const ModuleSwitcherFooter({
    super.key,
    required this.activeModule,
    required this.onModuleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          top: BorderSide(color: Colors.grey[300]!, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SwitcherItem(
              label: 'Kitchen',
              icon: Icons.restaurant_menu_rounded,
              isActive: activeModule == 'KITCHEN',
              onTap: () => onModuleChanged('KITCHEN'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SwitcherItem(
              label: 'Stock',
              icon: Icons.inventory_2_rounded,
              isActive: activeModule == 'STOCK',
              onTap: () => onModuleChanged('STOCK'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitcherItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _SwitcherItem({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: Colors.blue.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive ? Colors.white : Colors.black,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
