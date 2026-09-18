import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_service.dart';
import 'chat_page.dart';
import 'profile_page.dart';
import 'smooth_navigation.dart';
import 'watcher_report_detail.dart';
import 'watcher_upload_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Watcher Footer
// ─────────────────────────────────────────────────────────────────────────────

enum WatcherFooterTab { home, chat }

class _WatcherFooter extends StatelessWidget {
  final WatcherFooterTab selectedTab;
  final ValueChanged<WatcherFooterTab> onSelected;
  final int chatBadgeCount;

  const _WatcherFooter({
    required this.selectedTab,
    required this.onSelected,
    this.chatBadgeCount = 0,
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
              child: _FooterItem(
                icon: Icons.home_rounded,
                label: 'HOME',
                isSelected: selectedTab == WatcherFooterTab.home,
                onTap: () => onSelected(WatcherFooterTab.home),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: ChatPage.unreadChatNotifier,
                builder: (_, unread, __) {
                  final count = unread > 0 ? unread : chatBadgeCount;
                  return _FooterItem(
                    icon: Icons.forum_rounded,
                    label: 'CHAT',
                    isSelected: selectedTab == WatcherFooterTab.chat,
                    onTap: () => onSelected(WatcherFooterTab.chat),
                    badgeCount: count,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;
  final int badgeCount;

  const _FooterItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isSelected,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final active = Colors.black;
    final inactive = Colors.grey[600]!;

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
                Icon(icon, color: isSelected ? active : inactive, size: 24),
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
                color: isSelected ? active : inactive,
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

// ─────────────────────────────────────────────────────────────────────────────
//  Watcher Home Screen
// ─────────────────────────────────────────────────────────────────────────────

class WatcherHome extends StatefulWidget {
  final String profilePhotoUrl;

  const WatcherHome({super.key, this.profilePhotoUrl = ''});

  @override
  State<WatcherHome> createState() => _WatcherHomeState();
}

class _WatcherHomeState extends State<WatcherHome> {
  WatcherFooterTab _tab = WatcherFooterTab.home;
  bool _isLoading = true;
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _branches = [];
  int _chatUnread = 0;
  Timer? _pollTimer;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadAll();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _fetchReports(showLoader: false);
      _fetchChatUnread();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([
      _fetchReports(),
      _fetchBranches(),
      _fetchChatUnread(),
    ]);
  }

  Future<void> _fetchReports({bool showLoader = true}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);
    try {
      final reports = await ApiService.instance.fetchCctvReports();
      if (mounted) {
        setState(() {
          _reports = reports;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('WatcherHome: fetchReports error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchBranches() async {
    try {
      final raw = await ApiService.instance.fetchBranches();
      if (mounted) {
        setState(() {
          _branches = raw.cast<Map<String, dynamic>>();
          _branches.sort((a, b) =>
              (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
        });
      }
    } catch (e) {
      debugPrint('WatcherHome: fetchBranches error: $e');
    }
  }

  Future<void> _fetchChatUnread() async {
    try {
      final count = await ChatPage.checkUnreadChatCount();
      if (mounted) setState(() => _chatUnread = count);
    } catch (_) {}
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _handleFooter(WatcherFooterTab tab) {
    if (tab == WatcherFooterTab.chat) {
      _openChat();
      return;
    }
    setState(() => _tab = tab);
  }

  void _openChat() {
    Navigator.push(
      context,
      smoothPageRoute(
        ChatPage(
          footerMode: 'STOCK',
          chatBadgeCount: _chatUnread,
        ),
      ),
    ).then((_) => _fetchChatUnread());
  }

  void _openUpload() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WatcherUploadPage(branches: _branches),
      ),
    );
    if (result == true) _fetchReports();
  }

  void _openDetail(Map<String, dynamic> report) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WatcherReportDetail(report: report),
      ),
    ).then((_) => _fetchReports(showLoader: false));
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Color _colorForStatus(String? status) {
    switch (status) {
      case 'pending':     return const Color(0xFFF59E0B);
      case 'mng_replied': return const Color(0xFF3B82F6);
      case 'st_replied':  return const Color(0xFF10B981);
      default:            return Colors.grey;
    }
  }

  static String _labelForStatus(String? status) {
    switch (status) {
      case 'pending':     return 'Pending';
      case 'mng_replied': return 'Mng Replied';
      case 'st_replied':  return 'ST Replied';
      default:            return status ?? '—';
    }
  }

  String _resolveImageUrl(dynamic screenshot) {
    if (screenshot == null) return '';
    String raw = '';
    if (screenshot is Map) {
      raw = screenshot['thumbnailURL']?.toString() ??
          screenshot['thumbnailUrl']?.toString() ??
          screenshot['url']?.toString() ??
          '';
    } else if (screenshot is String) {
      raw = screenshot;
    }
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    return '${ApiService.baseUrl.replaceFirst('/api', '')}$raw';
  }

  String _branchName(dynamic branch) {
    if (branch is Map) return branch['name']?.toString() ?? '—';
    return branch?.toString() ?? '—';
  }

  String _formattedDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    return DateFormat('dd MMM, hh:mm a').format(dt);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('CCTV Watch'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          GestureDetector(
            onTap: _openProfile,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white24,
                backgroundImage:
                    widget.profilePhotoUrl.isNotEmpty
                        ? NetworkImage(widget.profilePhotoUrl)
                        : null,
                child: widget.profilePhotoUrl.isEmpty
                    ? const Icon(Icons.person, size: 20, color: Colors.white)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetchReports(),
              child: _reports.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _reports.length,
                      itemBuilder: (_, i) => _buildReportCard(_reports[i]),
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openUpload,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        tooltip: 'New CCTV Report',
        child: const Icon(Icons.add_a_photo_rounded),
      ),
      bottomNavigationBar: _WatcherFooter(
        selectedTab: _tab,
        onSelected: _handleFooter,
        chatBadgeCount: _chatUnread,
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Center(
          child: Column(
            children: [
              Icon(Icons.videocam_off_rounded, size: 72, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                'No reports yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap + to submit a new CCTV report',
                style: TextStyle(fontSize: 14, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final status = report['status']?.toString() ?? 'pending';
    final imgUrl = _resolveImageUrl(report['screenshot']);
    final branch = _branchName(report['branch']);
    final message = report['message']?.toString() ?? '';
    final date = _formattedDate(report['createdAt']?.toString());
    final color = _colorForStatus(status);

    return GestureDetector(
      onTap: () => _openDetail(report),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail ────────────────────────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: SizedBox(
                width: 100,
                height: 100,
                child: imgUrl.isNotEmpty
                    ? Image.network(
                        imgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumbPlaceholder(),
                      )
                    : _thumbPlaceholder(),
              ),
            ),

            // ── Content ──────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Branch + status
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            branch,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _labelForStatus(status),
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Message excerpt
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Date
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      color: Colors.grey[100],
      child: Icon(Icons.videocam_rounded, color: Colors.grey[400], size: 32),
    );
  }
}
