import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'api_service.dart';

class ChefCleaningAuditDialog extends StatefulWidget {
  final Map<String, dynamic> task;
  final String? chefType;
  final String? branchId;
  final VoidCallback? onCompleted;

  const ChefCleaningAuditDialog({
    super.key,
    required this.task,
    this.chefType,
    this.branchId,
    this.onCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> task,
    String? chefType,
    String? branchId,
    VoidCallback? onCompleted,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ChefCleaningAuditDialog(
        task: task,
        chefType: chefType,
        branchId: branchId,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<ChefCleaningAuditDialog> createState() => _ChefCleaningAuditDialogState();
}

class _ChefCleaningAuditDialogState extends State<ChefCleaningAuditDialog> {
  final ImagePicker _picker = ImagePicker();
  final List<File> _capturedImages = [];
  final TextEditingController _notesController = TextEditingController();
  AudioPlayer? _alertPlayer;
  bool _isSubmitting = false;
  String _uploadStatus = '';

  String get _taskTitle => widget.task['title']?.toString() ?? 'Kitchen Cleaning';
  String get _taskId => widget.task['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _playAlarmSound();
  }

  Future<void> _playAlarmSound() async {
    try {
      _alertPlayer = AudioPlayer();
      await _alertPlayer?.setReleaseMode(ReleaseMode.loop);
      await _alertPlayer?.play(AssetSource('sounds/cleaning_alarm.wav'));
    } catch (e) {
      debugPrint('Error playing cleaning alarm siren sound: $e');
      try {
        await _alertPlayer?.play(AssetSource('sounds/alert.wav'));
      } catch (_) {}
    }
  }

  Future<void> _takePhoto() async {
    try {
      _alertPlayer?.stop();
      final XFile? file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file != null) {
        setState(() {
          _capturedImages.add(File(file.path));
        });
      }
    } catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('கேமரா பிழை / Camera error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _submitAudit() async {
    _alertPlayer?.stop();
    if (_capturedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('குறைந்தது 1 புகைப்படம் எடுக்க வேண்டும்! / Please capture at least 1 photo!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _uploadStatus = 'புகைப்படங்கள் பதிவேற்றப்படுகின்றன... (Uploading photos...)';
    });

    try {
      final res = await ApiService.instance.submitTaskPhotoAudit(
        taskId: _taskId,
        imageFiles: _capturedImages,
        notes: _notesController.text.trim(),
        chefType: widget.chefType ?? widget.task['chefType']?.toString() ?? 'kitchen',
        branchId: widget.branchId,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _uploadStatus = 'புகைப்படம் $current / $total பதிவேற்றப்படுகிறது...';
            });
          }
        },
      );

      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ கிளீனிங் ஆய்வு வெற்றிகரமாக அனுப்பப்பட்டது! / Cleaning audit submitted!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.of(context).pop();
          widget.onCompleted?.call();
        }
      } else {
        throw Exception(res['message'] ?? 'சமர்ப்பிக்க முடியவில்லை');
      }
    } catch (e) {
      debugPrint('Error submitting audit: $e');
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _uploadStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('பிழை / Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _alertPlayer?.stop();
    _alertPlayer?.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent dismissing by back button
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 550, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE11D48), Color(0xFFBE123C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cleaning_services_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '🚨 Mandatory Kitchen Cleaning Audit',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Instructions Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECDD3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFFE11D48), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'கிச்சனை சுத்தமாக வைத்து புகைப்படங்கள் எடுக்கவும் (அடுப்பு, மேஜை, தரை, சிங்க்). ஒன்றுக்கு மேற்பட்ட புகைப்படங்களை இணைக்கலாம்.',
                                style: TextStyle(
                                  color: Colors.grey.shade900,
                                  fontSize: 12.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Photos Section Header
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'புகைப்படங்கள் (${_capturedImages.length})',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _isSubmitting ? null : _takePhoto,
                            icon: const Icon(Icons.camera_alt, size: 16),
                            label: const Text('+ புகைப்படம்'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFE11D48),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Photos Grid or Empty Prompt
                      if (_capturedImages.isEmpty)
                        InkWell(
                          onTap: _isSubmitting ? null : _takePhoto,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 135,
                            width: double.infinity,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_a_photo_rounded, size: 40, color: Color(0xFFE11D48)),
                                const SizedBox(height: 8),
                                const Text(
                                  'புகைப்படம் எடுக்க இங்கே கிளிக் செய்யவும்',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Click here to capture cleaning proof photos',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (int i = 0; i < _capturedImages.length; i++)
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      _capturedImages[i],
                                      width: 95,
                                      height: 95,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: GestureDetector(
                                      onTap: _isSubmitting
                                          ? null
                                          : () {
                                              setState(() {
                                                _capturedImages.removeAt(i);
                                              });
                                            },
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.black87,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, color: Colors.white, size: 14),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 2,
                                    left: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '#${i + 1}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            // Small "+ Add" box in grid
                            InkWell(
                              onTap: _isSubmitting ? null : _takePhoto,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 95,
                                height: 95,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add, size: 28, color: Colors.grey),
                                    Text('Add', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 16),

                      // Optional Remarks Field
                      const Text(
                        'சுருக்கமான குறிப்பு (Optional Remarks):',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _notesController,
                        enabled: !_isSubmitting,
                        decoration: InputDecoration(
                          hintText: 'எ.கா: அடுப்பு & கவுண்டர் சுத்தம் செய்யப்பட்டது',
                          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        maxLines: 2,
                        style: const TextStyle(fontSize: 13),
                      ),

                      if (_uploadStatus.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _uploadStatus,
                                style: const TextStyle(fontSize: 12, color: Color(0xFFE11D48), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Action Buttons Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting || _capturedImages.isEmpty ? null : _submitAudit,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_outline, size: 20),
                        label: Text(
                          _isSubmitting
                              ? 'சமர்ப்பிக்கப்படுகிறது...'
                              : 'ஆய்வை சமர்ப்பி (${_capturedImages.length} Photos)',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE11D48),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
