import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_service.dart';
import 'watcher_report_detail.dart';

class ManagerCctvReportsScreen extends StatefulWidget {
  final List<String> managerCompanyIds;

  const ManagerCctvReportsScreen({
    super.key,
    required this.managerCompanyIds,
  });

  @override
  State<ManagerCctvReportsScreen> createState() => _ManagerCctvReportsScreenState();
}

class _ManagerCctvReportsScreenState extends State<ManagerCctvReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  String _selectedStatusFilter = 'all'; // all, pending, mng_replied, st_replied
  String _searchQuery = '';
  final Set<String> _allowedBranchIds = {};

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    try {
      // If managerCompanyIds is provided, fetch branches to filter
      if (widget.managerCompanyIds.isNotEmpty) {
        final branches = await ApiService.instance.fetchBranches();
        _allowedBranchIds.clear();
        for (var b in branches) {
          final c = b['company'];
          final cId = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
          final bId = (b['id'] ?? b['_id'])?.toString() ?? '';
          if (widget.managerCompanyIds.contains(cId) && bId.isNotEmpty) {
            _allowedBranchIds.add(bId);
          }
        }
      }

      final reports = await ApiService.instance.fetchCctvReports(limit: 100);

      // Filter by manager's branches if company IDs specified
      final filtered = widget.managerCompanyIds.isEmpty
          ? reports
          : reports.where((r) {
              final b = r['branch'];
              final bId = (b is Map ? (b['id'] ?? b['_id']) : b)?.toString() ?? '';
              return _allowedBranchIds.contains(bId);
            }).toList();

      if (mounted) {
        setState(() {
          _reports = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading reports: $e')),
        );
      }
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

  Color _colorForStatus(String? status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'mng_replied':
        return const Color(0xFF3B82F6);
      case 'st_replied':
        return const Color(0xFF10B981);
      default:
        return Colors.grey;
    }
  }

  String _labelForStatus(String? status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'mng_replied':
        return 'Mng Replied';
      case 'st_replied':
        return 'ST Replied';
      default:
        return status ?? '—';
    }
  }

  String _formatDate(dynamic rawDate) {
    if (rawDate == null) return '';
    final dt = DateTime.tryParse(rawDate.toString())?.toLocal();
    if (dt == null) return rawDate.toString();
    return DateFormat('dd MMM, hh:mm a').format(dt);
  }

  List<Map<String, dynamic>> get _displayedReports {
    return _reports.where((r) {
      final status = r['status']?.toString() ?? 'pending';
      if (_selectedStatusFilter != 'all' && status != _selectedStatusFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final branch = r['branch'];
        final bName = (branch is Map ? branch['name'] : '')?.toString().toLowerCase() ?? '';
        final message = (r['message'] ?? '').toString().toLowerCase();
        final mngMsg = (r['managerMessage'] ?? '').toString().toLowerCase();
        if (!bName.contains(query) && !message.contains(query) && !mngMsg.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  int _countForStatus(String status) {
    if (status == 'all') return _reports.length;
    return _reports.where((r) => (r['status'] ?? 'pending') == status).length;
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _displayedReports;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('CCTV Reports'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReports,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search & Filter header ─────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Search field
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search by branch, issue...',
                    hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Status Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'All'),
                      const SizedBox(width: 8),
                      _buildFilterChip('pending', 'Pending'),
                      const SizedBox(width: 8),
                      _buildFilterChip('mng_replied', 'Mng Replied'),
                      const SizedBox(width: 8),
                      _buildFilterChip('st_replied', 'ST Replied'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Reports List ───────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayed.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _loadReports,
                        child: ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.videocam_off_rounded, size: 56, color: Colors.grey[300]),
                                  const SizedBox(height: 12),
                                  Text(
                                    _searchQuery.isNotEmpty || _selectedStatusFilter != 'all'
                                        ? 'No matching CCTV reports'
                                        : 'No CCTV reports yet',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadReports,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: displayed.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final report = displayed[index];
                            return _buildReportCard(report);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String statusKey, String label) {
    final isSelected = _selectedStatusFilter == statusKey;
    final count = _countForStatus(statusKey);
    final color = statusKey == 'all' ? Colors.black : _colorForStatus(statusKey);

    return InkWell(
      onTap: () => setState(() => _selectedStatusFilter = statusKey),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.25) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final status = report['status']?.toString() ?? 'pending';
    final branch = report['branch'];
    final branchName = (branch is Map ? branch['name'] : '')?.toString() ?? '—';
    final message = report['message']?.toString() ?? '';
    final mngReply = report['managerMessage']?.toString() ?? '';
    final imgUrl = _resolveImageUrl(report['screenshot']);
    final dateStr = _formatDate(report['createdAt']);
    final statusColor = _colorForStatus(status);

    return InkWell(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WatcherReportDetail(
              report: report,
              isManager: true,
            ),
          ),
        );
        if (result == true) {
          _loadReports();
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Branch & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.storefront_rounded, size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          branchName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    _labelForStatus(status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Content: Thumbnail + Issue Description
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: imgUrl.isNotEmpty
                      ? Image.network(
                          imgUrl,
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildThumbPlaceholder(),
                        )
                      : _buildThumbPlaceholder(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Manager reply status snippet
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: mngReply.isNotEmpty ? Colors.blue.shade50 : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    mngReply.isNotEmpty ? Icons.reply_rounded : Icons.pending_actions_rounded,
                    size: 15,
                    color: mngReply.isNotEmpty ? Colors.blue.shade700 : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      mngReply.isNotEmpty ? 'Reply: $mngReply' : 'Waiting for manager action (Tap to reply)',
                      style: TextStyle(
                        fontSize: 12,
                        color: mngReply.isNotEmpty ? Colors.blue.shade800 : Colors.amber.shade900,
                        fontWeight: mngReply.isNotEmpty ? FontWeight.w500 : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbPlaceholder() {
    return Container(
      width: 68,
      height: 68,
      color: Colors.grey.shade200,
      child: Icon(Icons.videocam_off_rounded, size: 28, color: Colors.grey.shade400),
    );
  }
}
