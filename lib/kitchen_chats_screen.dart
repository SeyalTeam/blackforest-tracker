import 'package:flutter/material.dart';

import 'common_scaffold.dart';
import 'kitchen_footer.dart';
import 'stock_footer.dart';

class KitchenChatsScreen extends StatelessWidget {
  final VoidCallback onKotTap;
  final VoidCallback onStockTap;
  final VoidCallback onReviewTap;
  final int stockBadgeCount;
  final int liveBadgeCount;
  final int reviewBadgeCount;
  final String footerMode; // 'KITCHEN' or 'STOCK'

  const KitchenChatsScreen({
    super.key,
    required this.onKotTap,
    required this.onStockTap,
    required this.onReviewTap,
    this.stockBadgeCount = 0,
    this.liveBadgeCount = 0,
    this.reviewBadgeCount = 0,
    this.footerMode = 'KITCHEN',
  });

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Chats',
      body: const Center(
        child: Text(
          'Chats coming soon',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomNavigationBar: footerMode == 'STOCK'
          ? StockFooter(
              selectedTab: StockFooterTab.chats,
              onSelected: (tab) {
                switch (tab) {
                  case StockFooterTab.live:
                    onKotTap();
                    break;
                  case StockFooterTab.stock:
                    onStockTap();
                    break;
                  case StockFooterTab.review:
                    onReviewTap();
                    break;
                  case StockFooterTab.chats:
                    break;
                }
              },
              stockBadgeCount: stockBadgeCount,
              liveBadgeCount: liveBadgeCount,
              reviewBadgeCount: reviewBadgeCount,
            )
          : KitchenFooter(
              selectedTab: KitchenFooterTab.chats,
              onSelected: (tab) {
                switch (tab) {
                  case KitchenFooterTab.kot:
                    onKotTap();
                    break;
                  case KitchenFooterTab.stock:
                    onStockTap();
                    break;
                  case KitchenFooterTab.review:
                    onReviewTap();
                    break;
                  case KitchenFooterTab.chats:
                    break;
                }
              },
              stockBadgeCount: stockBadgeCount,
              reviewBadgeCount: reviewBadgeCount,
            ),
    );
  }
}




