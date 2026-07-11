import 'package:flutter/material.dart';

enum KitchenFooterTab { kot, stock, review, chats }

class KitchenFooter extends StatelessWidget {
  final KitchenFooterTab selectedTab;
  final ValueChanged<KitchenFooterTab> onSelected;
  final int stockBadgeCount;
  final int liveBadgeCount;
  final int reviewBadgeCount;

  const KitchenFooter({
    super.key,
    required this.selectedTab,
    required this.onSelected,
    this.stockBadgeCount = 0,
    this.liveBadgeCount = 0,
    this.reviewBadgeCount = 0,
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
                badgeCount: liveBadgeCount,
              ),
            ),
            Expanded(
              child: _KitchenFooterItem(
                icon: Icons.inventory_2_rounded,
                label: 'STOCK',
                isSelected: selectedTab == KitchenFooterTab.stock,
                onTap: () => onSelected(KitchenFooterTab.stock),
                badgeCount: stockBadgeCount,
              ),
            ),
            Expanded(
              child: _KitchenFooterItem(
                icon: Icons.reviews_outlined,
                label: 'Review',
                isSelected: selectedTab == KitchenFooterTab.review,
                onTap: () => onSelected(KitchenFooterTab.review),
                badgeCount: reviewBadgeCount,
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
  final int badgeCount;

  const _KitchenFooterItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isSelected,
    this.badgeCount = 0,
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected ? activeColor : inactiveColor,
                  size: 24,
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
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
