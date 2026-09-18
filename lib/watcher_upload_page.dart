import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

class WatcherUploadPage extends StatefulWidget {
  final List<Map<String, dynamic>> branches;

  const WatcherUploadPage({super.key, required this.branches});

  @override
  State<WatcherUploadPage> createState() => _WatcherUploadPageState();
}

class _WatcherUploadPageState extends State<WatcherUploadPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _messageCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  File? _pickedImage;
  String? _selectedBranchId;
  String _selectedStatus = 'pending';
  bool _isSubmitting = false;

  // ── Status options ────────────────────────────────────────────────────────

  static const _statusOptions = [
    {'value': 'pending', 'label': 'Pending'},
    {'value': 'urgent', 'label': 'Urgent'},
    {'value': 'mng_replied', 'label': 'Mng Replied'},
    {'value': 'st_replied', 'label': 'ST Replied'},
  ];

  static Color _colorForStatus(String val) {
    switch (val) {
      case 'pending':    return const Color(0xFFF59E0B);
      case 'urgent':     return const Color(0xFFEF4444);
      case 'mng_replied': return const Color(0xFF3B82F6);
      case 'st_replied': return const Color(0xFF10B981);
      default:           return Colors.grey;
    }
  }

  // ── Image picker ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (file != null && mounted) {
        setState(() => _pickedImage = File(file.path));
      }
    } catch (e) {
      _showSnack('Could not access ${source == ImageSource.camera ? "camera" : "gallery"}: $e');
    }
  }

  void _showImageSourceDialog() {
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
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickedImage == null) {
      _showSnack('Please select a screenshot first');
      return;
    }
    if (_selectedBranchId == null) {
      _showSnack('Please select a branch');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ApiService.instance.createCctvReport(
        screenshotFile: _pickedImage!,
        branchId: _selectedBranchId!,
        message: _messageCtrl.text.trim(),
        status: _selectedStatus,
      );
      if (mounted) {
        Navigator.pop(context, true); // return true = refresh list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showSnack('Failed to submit: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('New CCTV Report'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Screenshot picker ────────────────────────────────────────
              _sectionLabel('Screenshot *'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showImageSourceDialog,
                child: Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _pickedImage != null
                          ? Colors.black
                          : Colors.grey.shade300,
                      width: _pickedImage != null ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _pickedImage != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(_pickedImage!, fit: BoxFit.cover),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: () => setState(() => _pickedImage = null),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to take/choose screenshot',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Branch dropdown ──────────────────────────────────────────
              _sectionLabel('Branch *'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedBranchId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                    hintText: 'Select a branch',
                  ),
                  items: widget.branches
                      .map((b) {
                        final id = (b['id'] ?? b['_id'])?.toString() ?? '';
                        final name = b['name']?.toString() ?? id;
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text(name),
                        );
                      })
                      .toList(),
                  onChanged: (v) => setState(() => _selectedBranchId = v),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Please select a branch' : null,
                ),
              ),

              const SizedBox(height: 24),

              // ── Message ──────────────────────────────────────────────────
              _sectionLabel('Issue Description *'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _messageCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Describe the issue observed on the CCTV...',
                  filled: true,
                  fillColor: Colors.white,
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
                    borderSide: const BorderSide(color: Colors.black),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Please describe the issue' : null,
              ),

              const SizedBox(height: 36),

              // ── Submit button ────────────────────────────────────────────

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Submit Report',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
        letterSpacing: 0.3,
      ),
    );
  }
}
