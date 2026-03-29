import 'package:flutter/material.dart';

enum KitchenFooterTab { kot, stock, review, chats }

class KitchenFooter extends StatelessWidget {
  final KitchenFooterTab selectedTab;
  final ValueChanged<KitchenFooterTab> onSelected;

  const KitchenFooter({
    super.key,
    required this.selectedTab,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _KitchenFooterItem(
                icon: Icons.receipt_long_rounded,
                label: 'KOT',
                isSelected: selectedTab == KitchenFooterTab.kot,
                onTap: () => onSelected(KitchenFooterTab.kot),
              ),
            ),
            Expanded(
              child: _KitchenFooterItem(
                icon: Icons.inventory_2_outlined,
                label: 'Stock',
                isSelected: selectedTab == KitchenFooterTab.stock,
                onTap: () => onSelected(KitchenFooterTab.stock),
              ),
            ),
            Expanded(
              child: _KitchenFooterItem(
                icon: Icons.reviews_outlined,
                label: 'Review',
                isSelected: selectedTab == KitchenFooterTab.review,
                onTap: () => onSelected(KitchenFooterTab.review),
              ),
            ),
            Expanded(
              child: _KitchenFooterItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Chats',
                isSelected: selectedTab == KitchenFooterTab.chats,
                onTap: () => onSelected(KitchenFooterTab.chats),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KitchenFooterItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;

  const _KitchenFooterItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = Colors.black;
    final inactiveColor = Colors.grey[600]!;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
