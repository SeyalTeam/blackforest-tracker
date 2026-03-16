import 'package:flutter/material.dart';

import 'common_scaffold.dart';
import 'kitchen_footer.dart';

class KitchenChatsScreen extends StatelessWidget {
  final VoidCallback onKotTap;
  final VoidCallback onReviewTap;

  const KitchenChatsScreen({
    super.key,
    required this.onKotTap,
    required this.onReviewTap,
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
      bottomNavigationBar: KitchenFooter(
        selectedTab: KitchenFooterTab.chats,
        onSelected: (tab) {
          switch (tab) {
            case KitchenFooterTab.kot:
              onKotTap();
              break;
            case KitchenFooterTab.review:
              onReviewTap();
              break;
            case KitchenFooterTab.chats:
              break;
          }
        },
      ),
    );
  }
}
