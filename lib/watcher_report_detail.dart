import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_service.dart';

class WatcherReportDetail extends StatefulWidget {
  final Map<String, dynamic> report;
  final bool isManager;

  const WatcherReportDetail({
    super.key,
    required this.report,
    this.isManager = false,
  });

  @override
  State<WatcherReportDetail> createState() => _WatcherReportDetailState();
}

class _WatcherReportDetailState extends State<WatcherReportDetail> {
  late Map<String, dynamic> _report;
  final TextEditingController _replyController = TextEditingController();
  bool _isSubmittingReply = false;
  bool _hasModified = false;

  final ImagePicker _picker = ImagePicker();
  File? _managerProofPhoto;

  bool get _isClosed {
    final status = _report['status']?.toString();
    return status == 'closed' ||
        status == 'mng_replied' ||
        (_report['managerMessage']?.toString() ?? '').isNotEmpty ||
        _resolveImageUrl(_getManagerProofScreenshot()).isNotEmpty;
  }

  // ── Status helpers ────────────────────────────────────────────────────────

  static Color _colorForStatus(String? status) {
    switch (status) {
      case 'pending':     return const Color(0xFFF59E0B);
      case 'closed':
      case 'mng_replied': return const Color(0xFF10B981);
      default:            return Colors.grey;
    }
  }

  static String _labelForStatus(String? status) {
    switch (status) {
      case 'pending':     return 'Pending';
      case 'closed':
      case 'mng_replied': return 'Closed';
      default:            return status ?? 'Unknown';
    }
  }

  String _resolveImageUrl(dynamic screenshot) {
    if (screenshot == null) return '';
    String raw = '';
    if (screenshot is Map) {
      raw = screenshot['url']?.toString() ??
          screenshot['thumbnailURL']?.toString() ??
          screenshot['thumbnailUrl']?.toString() ??
          '';
      if (raw.isEmpty && screenshot['filename'] != null) {
        final filename = screenshot['filename'].toString();
        final prefix = screenshot['prefix']?.toString() ?? '';
        raw = prefix.isNotEmpty ? '/media/file/$prefix/$filename' : '/media/file/$filename';
      }
    } else if (screenshot is String) {
      if (!screenshot.contains('/') && !screenshot.contains('.')) {
        return '';
      }
      raw = screenshot;
    }
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    return '${ApiService.baseUrl.replaceFirst('/api', '')}$raw';
  }

  dynamic _getManagerProofScreenshot() {
    return _report['proofPhoto'] ?? _report['managerScreenshot'];
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
    final existingReply = _report['managerMessage']?.toString() ?? '';
    if (widget.isManager && existingReply.isNotEmpty) {
      _replyController.text = existingReply;
    }
    _fetchFreshReport();
  }

  Future<void> _fetchFreshReport() async {
    final id = (_report['id'] ?? _report['_id'])?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      final fresh = await ApiService.instance.fetchCctvReportById(id);
      if (fresh != null && mounted) {
        setState(() {
          _report = Map<String, dynamic>.from(fresh);
          final existingReply = _report['managerMessage']?.toString() ?? '';
          if (widget.isManager && existingReply.isNotEmpty && _replyController.text.isEmpty) {
            _replyController.text = existingReply;
          }
        });
        _ensureMediaPopulated();
      } else {
        _ensureMediaPopulated();
      }
    } catch (_) {
      _ensureMediaPopulated();
    }
  }

  Future<void> _ensureMediaPopulated() async {
    bool changed = false;
    final keys = ['screenshot', 'proofPhoto', 'managerScreenshot', 'watcherReplyScreenshot'];
    for (final key in keys) {
      final val = _report[key];
      if (val is String && val.length == 24 && !val.contains('/') && !val.contains('.')) {
        try {
          final media = await ApiService.instance.fetchMediaById(val);
          _report[key] = media;
          changed = true;
        } catch (_) {}
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _sendManagerReply() async {
    final text = _replyController.text.trim();
    final existingProof = _resolveImageUrl(_getManagerProofScreenshot());
    if (text.isEmpty && _managerProofPhoto == null && existingProof.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reply message or upload a proof photo')),
      );
      return;
    }

    setState(() => _isSubmittingReply = true);
    try {
      final id = (_report['id'] ?? _report['_id'])?.toString() ?? '';
      final updated = await ApiService.instance.replyToCctvReport(
        id: id,
        managerMessage: text,
        proofPhoto: _managerProofPhoto,
      );
      if (mounted) {
        setState(() {
          _report = Map<String, dynamic>.from(updated);
          _hasModified = true;
          _managerProofPhoto = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply submitted and issue closed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send reply: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingReply = false);
    }
  }

  Future<void> _pickProofPhoto(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (file != null && mounted) {
        setState(() {
          _managerProofPhoto = File(file.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not access image source: $e')));
      }
    }
  }

  void _showProofSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take Proof Photo (Camera)'),
              onTap: () { Navigator.pop(context); _pickProofPhoto(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose Proof from Gallery'),
              onTap: () { Navigator.pop(context); _pickProofPhoto(ImageSource.gallery); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _viewFullScreenImage(String imgUrl) {
    if (imgUrl.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(imgUrl, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imgUrl = _resolveImageUrl(_report['screenshot']);
    final currentStatus = _report['status']?.toString() ?? 'pending';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Return hasModified if user pops back
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: Text(widget.isManager ? 'CCTV Report & Reply' : 'Report Detail'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _hasModified),
          ),
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
                GestureDetector(
                  onTap: () => _viewFullScreenImage(imgUrl),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          imgUrl,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imagePlaceholder(),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.all(10),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('Zoom', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                _imagePlaceholder(),

              const SizedBox(height: 24),

              // ── Info cards ───────────────────────────────────────────────
              _infoRow(Icons.store_rounded, 'Branch', _branchName()),
              const SizedBox(height: 12),
              _infoRow(Icons.access_time_rounded, 'Reported At', _formattedDate()),
              if (_report['createdBy'] != null) ...[
                const SizedBox(height: 12),
                _infoRow(
                  Icons.person_pin_rounded,
                  'Watcher',
                  _extractUserName(_report['createdBy']),
                ),
              ],

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

              const SizedBox(height: 24),

              // ── Manager Reply (Visible when Manager has replied / closed) ────
              if (_isClosed) ...[
                _replySection(
                  label: widget.isManager ? 'Your Submitted Reply' : 'Manager Reply',
                  message: _report['managerMessage']?.toString() ?? '',
                  userName: _extractUserName(_report['manager']),
                  color: Colors.green,
                  imageUrl: _resolveImageUrl(_getManagerProofScreenshot()),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Issue Closed: The manager has reviewed this mistake and uploaded proof.',
                          style: TextStyle(
                            color: Color(0xFF065F46),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ] else if (!widget.isManager) ...[
                // Watcher waiting for manager
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded, color: Colors.amber.shade800, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Pending Manager Reply: Awaiting branch manager to review this mistake and upload proof photo.',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // ── Manager Reply Composer (When isManager is true and not closed) ─────────────
              if (widget.isManager && !_isClosed) ...[
                Container(
                  padding: const EdgeInsets.all(16),
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
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.reply_rounded, color: Colors.blue.shade700, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                (_report['managerMessage']?.toString() ?? '').isNotEmpty
                                    ? 'Your Reply (Manager)'
                                    : 'Reply to Watcher',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ],
                          ),
                          if ((_report['managerMessage']?.toString() ?? '').isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Replied',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Proof Photo for Manager ────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.add_a_photo_rounded, size: 16, color: Colors.blue.shade800),
                              const SizedBox(width: 6),
                              Text(
                                'Proof Photo',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ],
                          ),
                          if (_resolveImageUrl(_getManagerProofScreenshot()).isNotEmpty && _managerProofPhoto == null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Text(
                                'Proof Uploaded',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Existing Proof Photo (if uploaded previously and no new photo selected yet)
                      Builder(builder: (context) {
                        final existingProof = _resolveImageUrl(_getManagerProofScreenshot());
                        if (_managerProofPhoto == null && existingProof.isNotEmpty) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Current Proof:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _showProofSourceDialog(),
                                      icon: const Icon(Icons.refresh_rounded, size: 14),
                                      label: const Text('Change Photo', style: TextStyle(fontSize: 12)),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => _viewFullScreenImage(existingProof),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Stack(
                                      alignment: Alignment.bottomRight,
                                      children: [
                                        Image.network(
                                          existingProof,
                                          width: double.infinity,
                                          height: 160,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => _imagePlaceholder(),
                                        ),
                                        Container(
                                          margin: const EdgeInsets.all(8),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.zoom_in, color: Colors.white, size: 14),
                                              SizedBox(width: 4),
                                              Text('Tap to View', style: TextStyle(color: Colors.white, fontSize: 11)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Proof Photo Picker / Preview for Manager
                        return GestureDetector(
                          onTap: () => _showProofSourceDialog(),
                          child: Container(
                            width: double.infinity,
                            height: _managerProofPhoto != null ? 180 : 75,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _managerProofPhoto != null ? Colors.blue.shade500 : Colors.blue.shade300,
                                width: _managerProofPhoto != null ? 1.5 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _managerProofPhoto != null
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.file(_managerProofPhoto!, fit: BoxFit.cover),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: GestureDetector(
                                          onTap: () => setState(() => _managerProofPhoto = null),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.close, color: Colors.white, size: 18),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 8,
                                        left: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 14),
                                              SizedBox(width: 4),
                                              Text(
                                                'Proof photo attached',
                                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.camera_alt_rounded, color: Colors.blue.shade700, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Take / Upload Proof Photo',
                                            style: TextStyle(
                                              color: Colors.blue.shade900,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            'Tap to capture photo or pick from gallery',
                                            style: TextStyle(
                                              color: Colors.blue.shade600,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      }),

                      const SizedBox(height: 16),
                      Text(
                        'Reply Message',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _replyController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Enter your action or instructions for this issue...',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmittingReply ? null : _sendManagerReply,
                          icon: _isSubmittingReply
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline_rounded, size: 18),
                          label: Text(
                            _isSubmittingReply ? 'Submitting...' : 'Submit Reply & Close',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              const SizedBox(height: 8),
            ],
          ),
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

  String _extractUserName(dynamic userObj) {
    if (userObj == null) return 'Unknown';
    if (userObj is Map) {
      return userObj['name']?.toString() ?? 'Unknown';
    }
    return 'Unknown';
  }

  Widget _replySection({
    required String label,
    required String message,
    required String userName,
    required MaterialColor color,
    String? imageUrl,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: color.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (userName != 'Unknown')
              Text(
                'by $userName',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => _viewFullScreenImage(imageUrl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageUrl,
                      width: double.infinity,
                      height: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (message.isNotEmpty)
                Text(
                  message,
                  style: TextStyle(fontSize: 15, height: 1.5, color: color.shade900),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
