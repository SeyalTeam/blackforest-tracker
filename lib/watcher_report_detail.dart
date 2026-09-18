import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'api_service.dart';

class WatcherReportDetail extends StatefulWidget {
  final Map<String, dynamic> report;

  const WatcherReportDetail({super.key, required this.report});

  @override
  State<WatcherReportDetail> createState() => _WatcherReportDetailState();
}

class _WatcherReportDetailState extends State<WatcherReportDetail> {
  late Map<String, dynamic> _report;
  bool _isUpdating = false;

  // ── Status helpers ────────────────────────────────────────────────────────

  static const _statusOptions = [
    {'value': 'pending', 'label': 'Pending'},
    {'value': 'mng_replied', 'label': 'Mng Replied'},
    {'value': 'st_replied', 'label': 'ST Replied'},
  ];

  static Color _colorForStatus(String? status) {
    switch (status) {
      case 'pending':    return const Color(0xFFF59E0B);
      case 'mng_replied': return const Color(0xFF3B82F6);
      case 'st_replied': return const Color(0xFF10B981);
      default:           return Colors.grey;
    }
  }

  static String _labelForStatus(String? status) {
    for (final s in _statusOptions) {
      if (s['value'] == status) return s['label']!;
    }
    return status ?? 'Unknown';
  }

  // ── API ───────────────────────────────────────────────────────────────────

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final token = await ApiService.storage.read(key: 'token');
      final id = (_report['id'] ?? _report['_id'])?.toString() ?? '';
      if (id.isEmpty) return;

      final res = await http.patch(
        Uri.parse('${ApiService.baseUrl}/cctv-reports/$id'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'status': newStatus}),
      );

      if (res.statusCode == 200) {
        final updated = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _report = Map<String, dynamic>.from(updated['doc'] ?? updated);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Status updated to ${_labelForStatus(newStatus)}'),
              backgroundColor: Colors.green[700],
            ),
          );
        }
      } else {
        _showError('Failed to update status (${res.statusCode})');
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _resolveImageUrl(dynamic screenshot) {
    if (screenshot == null) return '';
    String raw = '';
    if (screenshot is Map) {
      raw = screenshot['url']?.toString() ??
          screenshot['thumbnailURL']?.toString() ??
          screenshot['thumbnailUrl']?.toString() ??
          '';
    } else if (screenshot is String) {
      raw = screenshot;
    }
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    return '${ApiService.baseUrl.replaceFirst('/api', '')}$raw';
  }

  String _branchName() {
    final b = _report['branch'];
    if (b is Map) return b['name']?.toString() ?? '—';
    return b?.toString() ?? '—';
  }

  String _formattedDate() {
    final raw = _report['createdAt']?.toString() ?? '';
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _report = Map<String, dynamic>.from(widget.report);
  }

  @override
  Widget build(BuildContext context) {
    final imgUrl = _resolveImageUrl(_report['screenshot']);
    final currentStatus = _report['status']?.toString() ?? 'pending';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Report Detail'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _colorForStatus(currentStatus).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _colorForStatus(currentStatus)),
              ),
              child: Text(
                _labelForStatus(currentStatus),
                style: TextStyle(
                  color: _colorForStatus(currentStatus),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Screenshot ───────────────────────────────────────────────
            if (imgUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  imgUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _imagePlaceholder(),
                ),
              )
            else
              _imagePlaceholder(),

            const SizedBox(height: 24),

            // ── Info cards ───────────────────────────────────────────────
            _infoRow(Icons.store_rounded, 'Branch', _branchName()),
            const SizedBox(height: 12),
            _infoRow(Icons.access_time_rounded, 'Reported At', _formattedDate()),

            const SizedBox(height: 20),

            // ── Issue message ────────────────────────────────────────────
            const Text(
              'Issue Description',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                _report['message']?.toString() ?? '—',
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),

            const SizedBox(height: 28),

            // ── Change status ────────────────────────────────────────────
            const Text(
              'Change Status',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (_isUpdating)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _statusOptions.map((s) {
                  final val = s['value']!;
                  final isActive = val == currentStatus;
                  final color = _colorForStatus(val);
                  return GestureDetector(
                    onTap: isActive ? null : () => _updateStatus(val),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isActive ? color : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: color,
                          width: isActive ? 0 : 1.5,
                        ),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : [],
                      ),
                      child: Text(
                        s['label']!,
                        style: TextStyle(
                          color: isActive ? Colors.white : color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(Icons.videocam_off_rounded, size: 60, color: Colors.grey[400]),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
