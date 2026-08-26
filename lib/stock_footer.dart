import 'package:flutter/material.dart';
import 'chat_page.dart';

enum StockFooterTab { home, live, stock, review, chat }

class StockFooter extends StatelessWidget {
  final StockFooterTab selectedTab;
  final ValueChanged<StockFooterTab> onSelected;
  final int stockBadgeCount;
  final int liveBadgeCount;
  final int reviewBadgeCount;
  final int chatBadgeCount;
  final bool isChef;
  final bool isDriver;

  const StockFooter({
    super.key,
    required this.selectedTab,
    required this.onSelected,
    this.stockBadgeCount = 0,
    this.liveBadgeCount = 0,
    this.reviewBadgeCount = 0,
    this.chatBadgeCount = 0,
    this.isChef = false,
    this.isDriver = false,
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
              child: _StockFooterItem(
                icon: Icons.home_rounded,
                label: 'HOME',
                isSelected: selectedTab == StockFooterTab.home,
                onTap: () => onSelected(StockFooterTab.home),
              ),
            ),
            if (!isChef)
              Expanded(
                child: _StockFooterItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'LIVE',
                  isSelected: selectedTab == StockFooterTab.live,
                  onTap: () => onSelected(StockFooterTab.live),
                  badgeCount: liveBadgeCount,
                ),
              ),
            if (!isChef)
              Expanded(
                child: _StockFooterItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'STOCK',
                  isSelected: selectedTab == StockFooterTab.stock,
                  onTap: () => onSelected(StockFooterTab.stock),
                  badgeCount: stockBadgeCount,
                ),
              ),
            if (!isDriver)
              Expanded(
                child: _StockFooterItem(
                  icon: Icons.reviews_outlined,
                  label: 'REVIEW',
                  isSelected: selectedTab == StockFooterTab.review,
                  onTap: () => onSelected(StockFooterTab.review),
                  badgeCount: reviewBadgeCount,
                ),
              ),
            ValueListenableBuilder<int>(
              valueListenable: ChatPage.unreadChatNotifier,
              builder: (context, unreadCount, _) {
                final count = selectedTab == StockFooterTab.chat
                    ? 0
                    : (chatBadgeCount > 0 ? chatBadgeCount : unreadCount);
                return Expanded(
                  child: _StockFooterItem(
                    icon: Icons.forum_rounded,
                    label: 'CHAT',
                    isSelected: selectedTab == StockFooterTab.chat,
                    onTap: () => onSelected(StockFooterTab.chat),
                    badgeCount: count,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StockFooterItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;
  final int badgeCount;

  const _StockFooterItem({
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
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
