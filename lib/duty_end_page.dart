import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';

import 'api_service.dart';
import 'camera_page.dart';
import 'daily_tasks_page.dart';

class DutyEndPage extends StatefulWidget {
  final String? attendanceId;
  final String? branchName;
  final String? employeePhotoUrl;
  final String? dutyCompletePhotoUrl;
  final List<Map<String, dynamic>>? completedTasks;
  final Future<void> Function()? onDutyEnded;

  const DutyEndPage({
    super.key,
    this.attendanceId,
    this.branchName,
    this.employeePhotoUrl,
    this.dutyCompletePhotoUrl,
    this.completedTasks,
    this.onDutyEnded,
  });

  @override
  State<DutyEndPage> createState() => _DutyEndPageState();
}

class _DutyEndPageState extends State<DutyEndPage> {
  File? _selfieFile;
  bool _isEnding = false;
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();
  List<Map<String, dynamic>> _completedTasksList = [];
  List<Map<String, dynamic>> _pendingTasksList = [];
  int _totalTaskCount = 0;
  bool _loadingTasks = true;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });

    _loadTasks();
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  bool _isTaskDone(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase().trim();
    if (status == 'yes' || status == 'completed' || status == 'no_complaint') return true;
    if (status == null && task['completed'] == true) return true;
    return false;
  }

  Future<void> _loadTasks() async {
    setState(() => _loadingTasks = true);
    try {
      final res = await ApiService.instance.fetchMyDailyTasks();
      if (res['success'] == true && res['tasks'] is List) {
        final allTasks = List<Map<String, dynamic>>.from(
          (res['tasks'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        final completed = <Map<String, dynamic>>[];
        final pending = <Map<String, dynamic>>[];
        for (final t in allTasks) {
          if (_isTaskDone(t)) {
            completed.add(t);
          } else {
            pending.add(t);
          }
        }
        if (mounted) {
          setState(() {
            _completedTasksList = completed;
            _pendingTasksList = pending;
            _totalTaskCount = allTasks.length;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading daily tasks in DutyEndPage: $e');
    } finally {
      if (mounted) setState(() => _loadingTasks = false);
    }
  }

  bool get _canEndDuty {
    if (_loadingTasks) return false;
    // If there are pending tasks, do NOT allow ending duty
    if (_pendingTasksList.isNotEmpty) return false;
    return true;
  }

  Future<void> _takeSelfie() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      final XFile? file = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraPage(cameras: cameras, isFaceCapture: true),
        ),
      );
      if (file != null && mounted) {
        setState(() {
          _selfieFile = File(file.path);
        });
      }
    } catch (e) {
      debugPrint('Error capturing duty end selfie: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  Future<String?> _uploadSelfie(File file) async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token == null) return null;

      final filename = 'duty_end_selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final urlStr = '${ApiService.baseUrl}/media?prefix=attendance';

      final request = http.MultipartRequest('POST', Uri.parse(urlStr));
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['alt'] = 'Duty End Selfie';
      request.fields['prefix'] = 'attendance';

      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: filename,
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final doc = data['doc'] ?? data;
        return doc['id']?.toString();
      }
    } catch (e) {
      debugPrint('Error uploading duty end selfie: $e');
    }
    return null;
  }

  Future<void> _handleEndDuty() async {
    if (_isEnding) return;

    if (!_canEndDuty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot end duty: You have ${_pendingTasksList.length} incomplete task(s)! Please complete them first. ⚠️',
          ),
          backgroundColor: const Color(0xFFEA580C),
          action: SnackBarAction(
            label: 'VIEW TASKS',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DailyTasksPage(attendanceId: widget.attendanceId),
                ),
              ).then((_) => _loadTasks());
            },
          ),
        ),
      );
      return;
    }

    if (_selfieFile == null && (widget.dutyCompletePhotoUrl == null || widget.dutyCompletePhotoUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take an End Duty selfie first! 📸'),
          backgroundColor: Color(0xFFFB8C00),
        ),
      );
      await _takeSelfie();
      if (_selfieFile == null) return;
    }

    setState(() => _isEnding = true);

    try {
      String? dutyPhotoId;

      // 1. Upload selfie captured on this screen
      if (_selfieFile != null) {
        dutyPhotoId = await _uploadSelfie(_selfieFile!);
      }

      // 2. Call completeWork API
      final res = await ApiService.instance.completeWork(
        attendanceId: widget.attendanceId,
        dutyCompletePhoto: dutyPhotoId,
      );

      if (res['success'] == true) {
        if (widget.onDutyEnded != null) {
          await widget.onDutyEnded!();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Duty ended successfully! Great work today! 🎉')),
                ],
              ),
              backgroundColor: Color(0xFFFB8C00),
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message']?.toString() ?? 'Could not end duty'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error ending duty: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ending duty: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isEnding = false);
    }
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFFF1F5F9),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.camera_alt_rounded,
            size: 48,
            color: Color(0xFF94A3B8),
          ),
          SizedBox(height: 8),
          Text(
            'Take a Selfie',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: Colors.white,
              size: 13,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('hh:mm a').format(_currentTime);
    final dateStr = DateFormat('dd MMMM yyyy').format(_currentTime);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1648),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'DUTY END',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Orange Banner section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            color: const Color(0xFFFB8C00),
            child: const Column(
              children: [
                Text(
                  'End Duty',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '👍',
                  style: TextStyle(fontSize: 42),
                ),
              ],
            ),
          ),

          // White Main Area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Take a Selfie',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Selfie Photo Card
                  GestureDetector(
                    onTap: _takeSelfie,
                    child: Container(
                      width: 215,
                      height: 245,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_selfieFile != null)
                              Image.file(_selfieFile!, fit: BoxFit.cover)
                            else if (widget.dutyCompletePhotoUrl != null &&
                                widget.dutyCompletePhotoUrl!.isNotEmpty)
                              Image.network(
                                widget.dutyCompletePhotoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildPlaceholder(),
                              )
                            else if (widget.employeePhotoUrl != null &&
                                widget.employeePhotoUrl!.isNotEmpty)
                              Image.network(
                                widget.employeePhotoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildPlaceholder(),
                              )
                            else
                              _buildPlaceholder(),
                            Positioned(
                              bottom: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFB8C00),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Time
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Date
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Section Title for Completed Tasks
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _totalTaskCount > 0
                          ? 'Completed Tasks (${_completedTasksList.length}/$_totalTaskCount)'
                          : 'Completed Tasks',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF334155),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Real Completed Tasks ONLY
                  if (_loadingTasks)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFFFB8C00), strokeWidth: 2),
                      ),
                    )
                  else if (_completedTasksList.isEmpty && _totalTaskCount > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text(
                        'No tasks completed yet',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF94A3B8),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (_completedTasksList.isEmpty && _totalTaskCount == 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: const Text(
                        'No specific daily tasks assigned for today',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF166534),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        children: _completedTasksList.map((t) {
                          final title = (t['title'] ?? t['name'] ?? t['taskName'] ?? 'Task').toString();
                          return _buildCheckItem(title);
                        }).toList(),
                      ),
                    ),

                  // Warning block if tasks are pending
                  if (!_loadingTasks && _pendingTasksList.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDBA74), width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFEA580C), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '${_pendingTasksList.length} Task${_pendingTasksList.length > 1 ? 's' : ''} Still Pending',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFC2410C),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'You must complete all daily tasks before you are allowed to end duty.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF7C2D12),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DailyTasksPage(
                                      attendanceId: widget.attendanceId,
                                    ),
                                  ),
                                ).then((_) => _loadTasks());
                              },
                              icon: const Icon(Icons.task_alt, size: 16, color: Color(0xFFEA580C)),
                              label: const Text(
                                'Complete Pending Tasks Now',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFEA580C),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFEA580C), width: 1.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Action Button (Disabled if pending tasks exist)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _isEnding ? null : _handleEndDuty,
                      style: FilledButton.styleFrom(
                        backgroundColor: _canEndDuty
                            ? const Color(0xFFFB8C00)
                            : const Color(0xFFCBD5E1),
                        foregroundColor: _canEndDuty
                            ? Colors.white
                            : const Color(0xFF64748B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isEnding
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              _canEndDuty
                                  ? 'END DUTY'
                                  : 'COMPLETE ALL TASKS TO END DUTY',
                              style: TextStyle(
                                fontSize: _canEndDuty ? 16 : 13.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
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
}
