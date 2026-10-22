import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_service.dart';
import 'camera_page.dart';
import 'daily_tasks_page.dart';

class DutyStartPage extends StatefulWidget {
  final String? attendanceId;
  final String? branchName;
  final String? employeePhotoUrl;
  final File? initialSelfie;
  final bool hasActiveSession;
  final bool isAlreadyStarted;
  final DateTime? dutyStartTime;
  final Future<void> Function(File photo)? onPunchInRequired;
  final Future<void> Function()? onStartDuty;

  const DutyStartPage({
    super.key,
    this.attendanceId,
    this.branchName,
    this.employeePhotoUrl,
    this.initialSelfie,
    this.hasActiveSession = false,
    this.isAlreadyStarted = false,
    this.dutyStartTime,
    this.onPunchInRequired,
    this.onStartDuty,
  });

  @override
  State<DutyStartPage> createState() => _DutyStartPageState();
}

class _DutyStartPageState extends State<DutyStartPage> {
  File? _selfieFile;
  bool _isStarting = false;
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selfieFile = widget.initialSelfie;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
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
      debugPrint('Error capturing selfie: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  Future<void> _handleStartDuty() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);

    try {
      // 1. If punch-in is required and selfie taken
      if (widget.onPunchInRequired != null && !widget.hasActiveSession && _selfieFile != null) {
        await widget.onPunchInRequired!(_selfieFile!);
      }

      // 2. Call onStartDuty if provided, otherwise direct ApiService call
      if (widget.onStartDuty != null) {
        await widget.onStartDuty!();
      } else {
        final res = await ApiService.instance.startWork(attendanceId: widget.attendanceId);
        if (res['success'] != true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message']?.toString() ?? 'Could not start duty'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DailyTasksPage(attendanceId: widget.attendanceId),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting duty: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting duty: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
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
            'Tap to Take Selfie',
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

  @override
  Widget build(BuildContext context) {
    final displayTime = widget.isAlreadyStarted && widget.dutyStartTime != null
        ? widget.dutyStartTime!
        : _currentTime;
    final timeStr = DateFormat('hh:mm a').format(displayTime);
    final dateStr = DateFormat('dd MMMM yyyy').format(displayTime);
    final branchStr = widget.branchName ?? 'Branch';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1648),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isAlreadyStarted ? 'IN DUTY' : 'DUTY START',
          style: const TextStyle(
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
          // Green Banner section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            color: const Color(0xFF43A047),
            child: Column(
              children: [
                Text(
                  widget.isAlreadyStarted ? 'Duty In Progress' : 'Ready to Start Duty',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '🙌',
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
                  Text(
                    widget.isAlreadyStarted ? 'Duty Selfie' : 'Take a Selfie',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Selfie Photo Card
                  GestureDetector(
                    onTap: widget.isAlreadyStarted ? null : _takeSelfie,
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
                            else if (widget.employeePhotoUrl != null &&
                                widget.employeePhotoUrl!.isNotEmpty)
                              Image.network(
                                widget.employeePhotoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildPlaceholder(),
                              )
                            else
                              _buildPlaceholder(),
                            if (!widget.isAlreadyStarted)
                              Positioned(
                                bottom: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF43A047),
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
                  const SizedBox(height: 22),

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
                  const SizedBox(height: 12),

                  // Branch Location
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Color(0xFF2563EB),
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        branchStr,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _isStarting
                          ? null
                          : (widget.isAlreadyStarted
                              ? () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DailyTasksPage(
                                        attendanceId: widget.attendanceId,
                                      ),
                                    ),
                                  );
                                }
                              : _handleStartDuty),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF43A047),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isStarting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              widget.isAlreadyStarted ? 'VIEW TASKS' : 'START DUTY',
                              style: const TextStyle(
                                fontSize: 16,
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
