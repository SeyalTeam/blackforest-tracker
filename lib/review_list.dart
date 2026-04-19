import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'common_scaffold.dart';
import 'api_service.dart';
import 'kitchen_chats_screen.dart';
import 'kitchen_footer.dart';
import 'stock_footer.dart';
import 'smooth_navigation.dart';

class ReviewListScreen extends StatefulWidget {
  final bool showKitchenFooter;
  final VoidCallback? onKotTap;
  final VoidCallback? onStockTap;
  final int stockBadgeCount;
  final int liveBadgeCount;
  final int reviewBadgeCount;
  final String footerMode; // 'KITCHEN' or 'STOCK'

  const ReviewListScreen({
    super.key,
    this.showKitchenFooter = false,
    this.onKotTap,
    this.onStockTap,
    this.stockBadgeCount = 0,
    this.liveBadgeCount = 0,
    this.reviewBadgeCount = 0,
    this.footerMode = 'KITCHEN',
  });

  @override
  State<ReviewListScreen> createState() => _ReviewListScreenState();
}

class _ReviewListScreenState extends State<ReviewListScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _reviews = []; // Flattened list of review items

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    try {
      if (mounted) setState(() => _isLoading = true);
      // Fetch all (recent 100) reviews without date filter
      final docs = await ApiService.instance.fetchReviews();

      // Flatten the structure: Review -> Items -> Item
      final List<Map<String, dynamic>> flattened = [];

      for (var review in docs) {
        final items = (review['items'] as List?) ?? [];
        final da =
            DateTime.tryParse(review['createdAt'] ?? '') ?? DateTime.now();
        final customerName = review['customerName'] ?? 'Customer';
        final reviewId = review['id'] ?? review['_id'];

        for (var item in items) {
          // Clone item to avoid mutation issues and add parent info
          final flatItem = Map<String, dynamic>.from(item as Map);
          flatItem['parentReviewId'] = reviewId;
          flatItem['customerName'] = customerName;
          flatItem['createdAt'] = da; // Using review creation time for sorting
          flattened.add(flatItem);
        }
      }

      // Sort by latest first
      flattened.sort(
        (a, b) =>
            (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime),
      );

      if (mounted) {
        setState(() {
          _reviews = flattened;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading reviews: $e')));
      }
    }
  }

  Future<void> _showReplyDialog(Map<String, dynamic> item) async {
    final TextEditingController controller = TextEditingController(
      text: item['chefReply'] ?? '',
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Reply to Customer',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Enter your reply...',
              hintStyle: TextStyle(color: Colors.grey),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white54),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final reply = controller.text.trim();
                if (reply.isNotEmpty) {
                  Navigator.pop(context);
                  await _submitReply(item, reply);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text(
                'Send Reply',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitReply(Map<String, dynamic> item, String reply) async {
    try {
      // Optimistic Update UI
      setState(() {
        item['chefReply'] = reply;
        item['status'] = 'replied'; // Optimistically update status
      });

      final reviewId = item['parentReviewId'];
      final itemId = item['id'] ?? item['_id']; // Item ID within the array

      await ApiService.instance.replyToReview(reviewId, itemId, reply);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply sent successfully!')),
        );
        // Refresh to get official state/timestamps
        _fetchReviews();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send reply: $e')));
      }
      _fetchReviews(); // Revert on error
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: CommonScaffold(
        title: 'Customer Reviews',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchReviews),
        ],
        bottomNavigationBar: widget.showKitchenFooter
            ? (widget.footerMode == 'STOCK'
                ? StockFooter(
                    selectedTab: StockFooterTab.review,
                    onSelected: _handleStockFooterSelection,
                    stockBadgeCount: widget.stockBadgeCount,
                    liveBadgeCount: widget.liveBadgeCount,
                    reviewBadgeCount: widget.reviewBadgeCount,
                  )
                : KitchenFooter(
                    selectedTab: KitchenFooterTab.review,
                    onSelected: _handleKitchenFooterSelection,
                    stockBadgeCount: widget.stockBadgeCount,
                    reviewBadgeCount: widget.reviewBadgeCount,
                  ))
            : null,
        body: Column(
          children: [
            Container(
              color: Colors.black, // Dark background for tabs
              child: const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.amber,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: 'WAITING'),
                  Tab(text: 'REPLIED'),
                  Tab(text: 'APPROVED'),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _buildReviewList(status: 'waiting'),
                        _buildReviewList(status: 'replied'),
                        _buildReviewList(status: 'approved'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleStockFooterSelection(StockFooterTab tab) {
    switch (tab) {
      case StockFooterTab.live:
        if (widget.onKotTap != null) {
          widget.onKotTap!();
        } else {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        break;
      case StockFooterTab.stock:
        if (widget.onStockTap != null) {
          widget.onStockTap!();
        } else {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        break;
      case StockFooterTab.review:
        break;
      case StockFooterTab.chats:
        Navigator.pushReplacement(
          context,
          smoothPageRoute(
            KitchenChatsScreen(
              onKotTap:
                  widget.onKotTap ??
                  () {
                    Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst);
                  },
              onStockTap:
                  widget.onStockTap ??
                  () {
                    Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst);
                  },
              onReviewTap: () {},
              stockBadgeCount: widget.stockBadgeCount,
              liveBadgeCount: widget.liveBadgeCount,
              reviewBadgeCount: widget.reviewBadgeCount,
              footerMode: 'STOCK',
            ),
          ),
        );
        break;
    }
  }

  void _handleKitchenFooterSelection(KitchenFooterTab tab) {
    switch (tab) {
      case KitchenFooterTab.kot:
        if (widget.onKotTap != null) {
          widget.onKotTap!();
        } else {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        break;
      case KitchenFooterTab.stock:
        if (widget.onStockTap != null) {
          widget.onStockTap!();
        } else {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        break;
      case KitchenFooterTab.review:
        break;
      case KitchenFooterTab.chats:
        Navigator.pushReplacement(
          context,
          smoothPageRoute(
            KitchenChatsScreen(
              onKotTap: widget.onKotTap ??
                  () => Navigator.of(context).popUntil((r) => r.isFirst),
              onStockTap: widget.onStockTap ??
                  () => Navigator.of(context).popUntil((r) => r.isFirst),
              onReviewTap: () {},
              stockBadgeCount: widget.stockBadgeCount,
              liveBadgeCount: widget.liveBadgeCount,
              reviewBadgeCount: widget.reviewBadgeCount,
              footerMode: 'KITCHEN',
            ),
          ),
        );
        break;
    }
  }

  Widget _buildReviewList({required String status}) {
    // Filter reviews based on status
    final filtered = _reviews.where((item) {
      final itemStatus = item['status'] ?? 'waiting';
      final hasReply = (item['chefReply'] as String?)?.isNotEmpty ?? false;

      if (status == 'waiting') {
        // Show if status is waiting AND no reply (just in case status isn't updated)
        return itemStatus == 'waiting' && !hasReply;
      } else if (status == 'replied') {
        return itemStatus == 'replied' ||
            hasReply; // Fallback if status not set but reply exists
      } else if (status == 'approved') {
        return itemStatus == 'approved';
      }
      return false;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 48, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              'No $status reviews',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        return _buildReviewCard(filtered[index]);
      },
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> item) {
    final rating = (item['rating'] as num?)?.toInt() ?? 0;
    final feedback = item['feedback'] ?? '';
    final chefReply = item['chefReply'];
    final productName =
        (item['product'] is Map ? item['product']['name'] : 'Product') ??
        'Unknown Product';
    final customerName = item['customerName'] ?? 'Guest'; // Default to Guest
    final dateRaw = item['createdAt'];
    final date = dateRaw is DateTime
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(dateRaw)
        : '';

    // Generate initials
    String initials = 'G';
    if (customerName.isNotEmpty) {
      initials = customerName
          .trim()
          .split(' ')
          .take(2)
          .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
          .join();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // Premium dark card
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.indigoAccent,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        rating.toString(),
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white10),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.restaurant_menu,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        productName,
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  feedback,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          // Footer / Reply Section
          if (chefReply != null && (chefReply as String).isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: Colors.blue[400],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Replied by Chef',
                        style: TextStyle(
                          color: Colors.blue[400],
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showReplyDialog(item),
                        child: const Text(
                          'Edit',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    chefReply,
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showReplyDialog(item),
                  icon: const Icon(Icons.reply, size: 18, color: Colors.white),
                  label: const Text(
                    'Reply Now',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
