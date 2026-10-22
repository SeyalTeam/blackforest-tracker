import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img_lib;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'camera_page.dart';
import 'login.dart';
import 'geofence_util.dart';
import 'notification_service.dart';
import 'attendance_manager.dart';
import 'attendance_calendar_page.dart';
import 'daily_tasks_page.dart';
import 'rank_card_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _storage = const FlutterSecureStorage();
  bool _profileLoading = false;
  String? _employeeName;
  String? _employeeRole;
  List<String> _managerCompanyNames = [];
  String? _kitchenName;
  String? _employeeId;
  String? _employeePhotoUrl;
  String? _branchName;
  String? _employeePhone;
  bool _isLoggingOut = false;
  bool _isProcessingPunch = false;
  String? _attendanceDocId;
  bool _hasActiveSession = false;
  bool _activeSessionHasPhoto = true;
  String? _lastPunchOutType;
  File? _capturedPunchInPhoto;
  List<dynamic> _rawActivities = [];
  String _workStatus = 'not_started'; // 'not_started' | 'in_progress' | 'completed'
  DateTime? _workStartTime;
  DateTime? _workCompletedTime;
  bool _isStartingWork = false;

  Timer? _timer;
  Timer? _geofenceTimer; // polls GPS every 60s while session is active
  bool _autoPunchOutFired = false; // prevents double-fire on same geofence exit
  bool _autoPunchInFired = false;
  StreamSubscription<String?>? _notificationSubscription;
  StreamSubscription<Map<String, dynamic>>? _attendanceManagerSub;
  Duration _workDuration = Duration.zero;
  Duration _breakDuration = Duration.zero;
  List<Map<String, dynamic>> _activities = [];
  String? _dayType; // 'full_day' | 'half_day' | null
  String? _loginBranchName;
  bool _isFetchingInitialAttendance = true;
  bool _loadingTasks = false;
  List<Map<String, dynamic>> _dailyTasks = [];
  final Set<String> _togglingTaskIds = {};
  Map<String, dynamic>? _reportCardData;

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
    _fetchReportCard();
    _notificationSubscription = NotificationService().onNotificationClick
        .listen((payload) {
          if (payload == 'auto_punch_in') {
            if (_hasActiveSession && !_activeSessionHasPhoto) {
              _attachSelfieToActiveSession();
            } else {
              _autoCaptureAndPunchIn();
            }
          }
        });
    _attendanceManagerSub = AttendanceManager.instance.onAttendanceUpdate
        .listen((event) {
          debugPrint('ProfilePage: received attendance update: $event');
          if (mounted) {
            _fetchAttendance();
          }
        });
    AttendanceManager.instance.checkNow();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _geofenceTimer?.cancel();
    _notificationSubscription?.cancel();
    _attendanceManagerSub?.cancel();
    super.dispose();
  }

  Future<void> _loadEmployeeData() async {
    try {
      final cachedName = await _storage.read(key: 'userName');
      final cachedRole = await _storage.read(key: 'userRole');
      final cachedKitchenName = await _storage.read(key: 'userKitchenName');
      final cachedBranchName = await _storage.read(key: 'userBranchName');
      final cachedEmpId = await _storage.read(key: 'employeeId');
      final cachedCompaniesStr = await _storage.read(key: 'managerCompanyNames');
      final cachedHasPhotoStr = await _storage.read(key: 'activeSessionHasPhoto');
      final cachedPunchIn = await _storage.read(key: 'activePunchIn');
      final cachedPastSecsStr = await _storage.read(key: 'pastWorkSeconds');
      final cachedBreakSecsStr = await _storage.read(key: 'totalBreakSeconds');

      Duration initialWorkDuration = Duration.zero;
      Duration initialBreakDuration = Duration.zero;
      bool hasCachedActive = false;

      if (cachedBreakSecsStr != null && cachedBreakSecsStr.isNotEmpty) {
        final breakSecs = int.tryParse(cachedBreakSecsStr) ?? 0;
        if (breakSecs > 0) {
          initialBreakDuration = Duration(seconds: breakSecs);
        }
      }

      if (cachedPunchIn != null && cachedPunchIn.isNotEmpty) {
        final activeStart = DateTime.tryParse(cachedPunchIn);
        final now = DateTime.now();
        if (activeStart != null &&
            activeStart.year == now.year &&
            activeStart.month == now.month &&
            activeStart.day == now.day) {
          hasCachedActive = true;
          final pastSecs = int.tryParse(cachedPastSecsStr ?? '0') ?? 0;
          final pastWork = Duration(seconds: pastSecs);
          initialWorkDuration = pastWork + now.difference(activeStart);

          _timer?.cancel();
          _timer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted) return;
            setState(() {
              _workDuration =
                  pastWork + DateTime.now().difference(activeStart);
            });
          });
        }
      }

      if (mounted) {
        setState(() {
          _employeeName = cachedName;
          _employeeRole = cachedRole;
          if (cachedKitchenName != null && cachedKitchenName.isNotEmpty) {
            _kitchenName = cachedKitchenName;
          }
          if (cachedBranchName != null && cachedBranchName.isNotEmpty) {
            _branchName = cachedBranchName;
          }
          if (cachedEmpId != null && cachedEmpId.isNotEmpty) {
            _employeeId = cachedEmpId;
          }
          if (cachedCompaniesStr != null && cachedCompaniesStr.isNotEmpty) {
            _managerCompanyNames = cachedCompaniesStr.split('||');
          }
          if (cachedHasPhotoStr != null) {
            _activeSessionHasPhoto = cachedHasPhotoStr == 'true';
          }
          if (initialBreakDuration > Duration.zero) {
            _breakDuration = initialBreakDuration;
          }
          if (hasCachedActive) {
            _workDuration = initialWorkDuration;
            _hasActiveSession = true;
          }
          // Render cached profile info immediately for zero-lag UI
          _profileLoading = false;
        });
      }

      // Fetch fresh network updates in parallel
      await Future.wait([
        _fetchEmployeeProfile(),
        _fetchAttendance(),
        _fetchDailyTasks(),
        _fetchReportCard(),
      ]);
    } catch (e) {
      debugPrint('Error loading employee data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _profileLoading = false;
        });
      }
    }
  }

  String _resolveApiAssetUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    if (value.startsWith('data:image/')) return value;

    final sanitized = value.replaceAll(' ', '%20');
    final normalizedInput = sanitized.startsWith('//')
        ? 'https:$sanitized'
        : sanitized;

    if (normalizedInput.startsWith('http://') ||
        normalizedInput.startsWith('https://')) {
      return normalizedInput;
    }

    final relative = normalizedInput.startsWith('/')
        ? normalizedInput
        : '/$normalizedInput';

    return 'https://blackforest-api.vseyal.com$relative';
  }

  Future<void> _fetchEmployeeProfile() async {
    try {
      final profile = await ApiService.instance.fetchUserProfile();
      if (profile.isNotEmpty) {
        final user = profile['user'] ?? profile;
        final employee = user['employee'] ?? {};
        final branch = user['branch'] ?? {};

        final name = user['name']?.toString() ?? employee['name']?.toString();
        final role = user['role']?.toString();
        final code = employee['employeeId']?.toString();
        final phone = employee['phoneNumber']?.toString();
        final bName = branch['name']?.toString();

        final photo = employee['photo'];
        String? photoUrl;
        if (photo is Map) {
          photoUrl =
              photo['thumbnailURL']?.toString() ??
              photo['thumbnailUrl']?.toString() ??
              photo['url']?.toString();
        } else if (photo is String) {
          photoUrl = photo;
        }

        String? resolvedUrl;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          resolvedUrl = _resolveApiAssetUrl(photoUrl);
        }

        List<String> companyNames = [];
        if (role == 'manager') {
          final rawCompanies = user['manager_companies'];
          if (rawCompanies is List) {
            for (final c in rawCompanies) {
              if (c is Map && c['name'] != null) {
                companyNames.add(c['name'].toString());
              }
            }
          }
        }

        String? kName;
        String? kId;

        // 1. Check user['kitchen']
        final userKitchen = user['kitchen'];
        if (userKitchen is List && userKitchen.isNotEmpty) {
          final firstK = userKitchen.first;
          if (firstK is Map) {
            kName = firstK['name']?.toString();
            kId = (firstK['id'] ?? firstK['_id'])?.toString();
          } else if (firstK is String && firstK.isNotEmpty) {
            kId = firstK;
          }
        } else if (userKitchen is Map) {
          kName = userKitchen['name']?.toString();
          kId = (userKitchen['id'] ?? userKitchen['_id'])?.toString();
        } else if (userKitchen is String && userKitchen.isNotEmpty) {
          kId = userKitchen;
        }

        // 2. Fallback: Check employee['kitchen']
        if (employee is Map) {
          final empKitchen = employee['kitchen'];
          if (empKitchen is Map) {
            kName ??= empKitchen['name']?.toString();
            kId ??= (empKitchen['id'] ?? empKitchen['_id'])?.toString();
          } else if (empKitchen is String && empKitchen.isNotEmpty) {
            kId ??= empKitchen;
          }
        }

        // 3. Fallback: Check user['kitchens'] list if any
        final userKitchens = user['kitchens'];
        if (userKitchens is List && userKitchens.isNotEmpty) {
          final firstK = userKitchens.first;
          if (firstK is Map) {
            kName ??= firstK['name']?.toString();
            kId ??= (firstK['id'] ?? firstK['_id'])?.toString();
          } else if (firstK is String && firstK.isNotEmpty) {
            kId ??= firstK;
          }
        }

        // 4. Fetch kitchen details if we have kId but not kName
        if ((kName == null || kName.isEmpty) && kId != null && kId.isNotEmpty) {
          try {
            final kDetails = await ApiService.instance.fetchKitchenDetails(kId);
            kName = kDetails['name']?.toString();
          } catch (e) {
            debugPrint('DEBUG: Error fetching kitchen details in profile: $e');
          }
        }

        // 5. Fallback: check storage for userKitchenId
        if (kName == null || kName.isEmpty) {
          final storedKId = await _storage.read(key: 'userKitchenId');
          if (storedKId != null && storedKId.isNotEmpty) {
            try {
              final kDetails = await ApiService.instance.fetchKitchenDetails(storedKId);
              kName = kDetails['name']?.toString();
            } catch (e) {
              debugPrint('DEBUG: Error fetching stored kitchen details in profile: $e');
            }
          }
        }

        // 6. Fallback: check kitchens matching user's branch
        if (kName == null || kName.isEmpty) {
          final bId = (branch is Map ? (branch['id'] ?? branch['_id']) : branch)?.toString();
          if (bId != null && bId.isNotEmpty) {
            try {
              final allKitchens = await ApiService.instance.fetchKitchens();
              for (final k in allKitchens) {
                final targetBId = (k['branch'] is Map ? (k['branch']['id'] ?? k['branch']['_id']) : k['branch'])?.toString();
                if (targetBId == bId) {
                  kName = k['name']?.toString();
                  if (kName != null && kName.isNotEmpty) break;
                }
              }
            } catch (_) {}
          }
        }

        if (kName != null && kName.isNotEmpty) {
          await _storage.write(key: 'userKitchenName', value: kName);
        }
        if (bName != null && bName.isNotEmpty) {
          await _storage.write(key: 'userBranchName', value: bName);
        }
        if (code != null && code.isNotEmpty) {
          await _storage.write(key: 'employeeId', value: code);
        }
        if (companyNames.isNotEmpty) {
          await _storage.write(
            key: 'managerCompanyNames',
            value: companyNames.join('||'),
          );
        }

        if (mounted) {
          setState(() {
            if (name != null) _employeeName = name;
            if (role != null) _employeeRole = role;
            if (code != null) _employeeId = code;
            if (phone != null) _employeePhone = phone;
            if (bName != null) _branchName = bName;
            if (kName != null && kName.isNotEmpty) _kitchenName = kName;
            if (resolvedUrl != null) _employeePhotoUrl = resolvedUrl;
            if (companyNames.isNotEmpty) _managerCompanyNames = companyNames;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching employee profile: $e');
    }
  }

  Future<void> _fetchReportCard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final empDocId = (await _storage.read(key: 'employeeDocId')) ??
          (await _storage.read(key: 'employeeId')) ??
          prefs.getString('employee_id') ??
          _employeeId ??
          '';
      final role = _employeeRole ?? (await _storage.read(key: 'userRole')) ?? prefs.getString('role') ?? '';
      final branchId = (await _storage.read(key: 'userBranchId')) ?? prefs.getString('branchId') ?? '';
      final branchName = _loginBranchName ?? _branchName ?? (await _storage.read(key: 'userBranchName')) ?? '';
      final now = DateTime.now();
      final monthStr = DateFormat('yyyy-MM').format(now);

      final res = await ApiService.instance.fetchReportCardData(
        employeeId: empDocId.isNotEmpty ? empDocId : null,
        month: monthStr,
        role: role.isNotEmpty ? role : null,
        period: 'month',
        branchId: branchId.isNotEmpty ? branchId : null,
        branchName: branchName.isNotEmpty ? branchName : null,
      );

      if (mounted && res.isNotEmpty && res['error'] == null) {
        final rules = (res['rules'] as List<dynamic>?) ?? [];
        if (rules.isNotEmpty) {
          final computedMax = rules.fold<num>(0, (sum, r) => sum + ((r is Map ? r['maxMarks'] : 100) as num? ?? 100));
          final computedScore = rules.fold<num>(0, (sum, r) => sum + ((r is Map ? r['score'] : 0) as num? ?? 0));
          res['totalMaxMarks'] = computedMax;
          res['totalScore'] = computedScore;
          if (computedMax > 0) {
            res['overallScore'] = (computedScore / computedMax * 100).round();
          }
        }
        setState(() {
          _reportCardData = res;
        });
      }
    } catch (e) {
      debugPrint('Error fetching report card data in profile page: $e');
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getRoleAndBranchSubtitle() {
    if (_employeeRole == 'manager' && _managerCompanyNames.isNotEmpty) {
      final branch = _loginBranchName ?? _branchName ?? '';
      return branch.isNotEmpty
          ? '${_managerCompanyNames.join(' • ')} • $branch'
          : _managerCompanyNames.join(' • ');
    }
    final roleStr = _employeeRole != null && _employeeRole!.isNotEmpty
        ? _employeeRole![0].toUpperCase() + _employeeRole!.substring(1)
        : 'Staff';
    final branch = _loginBranchName ?? _branchName ?? '';
    if (branch.isNotEmpty) {
      return '$roleStr • $branch';
    }
    return roleStr;
  }

  Future<void> _fetchAttendance() async {
    final token = await _storage.read(key: 'token');
    final userId = await _storage.read(key: 'userId');

    if (token == null || userId == null) return;

    final now = DateTime.now();
    final localMidnight = DateTime(now.year, now.month, now.day);
    final queryDate = localMidnight
        .subtract(const Duration(days: 1))
        .toUtc()
        .toIso8601String();

    try {
      final url =
          '${ApiService.baseUrl}/attendance?where[user][equals]=$userId&where[date][greater_than_equal]=$queryDate&sort=-date&limit=10';
      final response = await http.get(
        Uri.parse(url),
        headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
      );

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final docs =
          (data is Map<String, dynamic> ? data['docs'] : null) as List?;
      if (docs == null) return;

      final allActivities = <Map<String, dynamic>>[];
      var totalWork = Duration.zero;
      var totalBreak = Duration.zero;
      var activeSessionFound = false;
      var activePhotoFound = true;
      String? latestPunchOutType;
      DateTime? latestPunchOutTime;

      if (docs.isNotEmpty && docs.first is Map<String, dynamic>) {
        final firstDoc = docs.first as Map<String, dynamic>;
        final docDateStr = firstDoc['dateString']?.toString() ?? '';
        final queryDateStr = localMidnight.toIso8601String().split('T')[0];

        if (docDateStr == queryDateStr ||
            (firstDoc['date']?.toString().startsWith(queryDateStr) == true)) {
          _attendanceDocId = firstDoc['id']?.toString();
          _rawActivities = (firstDoc['activities'] as List?) ?? [];
          _dayType = firstDoc['dayType']?.toString();
          _workStatus = firstDoc['workStatus']?.toString() ?? 'not_started';
          _workStartTime = firstDoc['workStartTime'] != null
              ? DateTime.tryParse(firstDoc['workStartTime'].toString())
              : null;
          _workCompletedTime = firstDoc['workCompletedTime'] != null
              ? DateTime.tryParse(firstDoc['workCompletedTime'].toString())
              : null;
          
          final loginBranchData = firstDoc['loginBranch'];
          if (loginBranchData is Map<String, dynamic>) {
            _loginBranchName = loginBranchData['name']?.toString();
            final newBranchId = loginBranchData['id']?.toString() ?? loginBranchData['_id']?.toString();
            if (newBranchId != null && _loginBranchName != null) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('branchId', newBranchId);
              await prefs.setString('userBranchName', _loginBranchName!);
              await _storage.write(key: 'userBranchName', value: _loginBranchName!);
              if (mounted) {
                setState(() {
                  _branchName = _loginBranchName;
                });
              }
            }
          } else {
            _loginBranchName = null;
          }
        } else {
          _attendanceDocId = null;
          _rawActivities = [];
          _dayType = null;
          _loginBranchName = null;
          _workStatus = 'not_started';
          _workStartTime = null;
          _workCompletedTime = null;
        }
      } else {
        _attendanceDocId = null;
        _rawActivities = [];
        _loginBranchName = null;
      }

      for (final dynamic doc in docs) {
        final activities =
            (doc is Map<String, dynamic> ? doc['activities'] : null) as List?;
        if (activities == null) continue;

        for (final dynamic rawActivity in activities) {
          if (rawActivity is! Map<String, dynamic>) continue;
          final type = rawActivity['type'];
          final punchInStr = rawActivity['punchIn']?.toString();
          final punchOutStr = rawActivity['punchOut']?.toString();
          final status = rawActivity['status']?.toString();
          final durationSeconds = _toInt(rawActivity['durationSeconds']);
          final breakDurationSeconds = _toInt(
            rawActivity['breakDurationSeconds'],
          );

          if (punchInStr == null || punchInStr.isEmpty) continue;

          final punchIn = DateTime.tryParse(punchInStr)?.toLocal();
          final punchOut = punchOutStr != null
              ? DateTime.tryParse(punchOutStr)?.toLocal()
              : null;

          if (punchIn == null) continue;

          final inTimeStr = DateFormat('hh:mm a').format(punchIn);
          final outTimeStr = punchOut != null
              ? DateFormat('hh:mm a').format(punchOut)
              : 'Active';

          if (type == 'session') {
            // ── Stale active session guard (FIRST — before any accumulation) ──
            // If active but punchIn was before today's midnight, the employee
            // forgot to punch out. Auto-close it on the server and skip it
            // entirely so it never inflates today's work timer.
            if (status == 'active' && punchIn.isBefore(localMidnight)) {
              final endOfDay = DateTime(
                punchIn.year,
                punchIn.month,
                punchIn.day,
                23,
                59,
                59,
              );
              final durationSecs = endOfDay.difference(punchIn).inSeconds;

              final ownerDoc = docs.firstWhere((d) {
                final acts = (d is Map ? d['activities'] : null) as List?;
                return acts?.any(
                      (a) =>
                          a is Map &&
                          a['punchIn']?.toString() == punchInStr &&
                          a['status'] == 'active',
                    ) ??
                    false;
              }, orElse: () => null);

              if (ownerDoc != null) {
                final ownerDocId = ownerDoc['id']?.toString();
                final ownerActivities = List<dynamic>.from(
                  (ownerDoc['activities'] as List?) ?? [],
                );
                for (final a in ownerActivities) {
                  if (a is Map &&
                      a['punchIn']?.toString() == punchInStr &&
                      a['status'] == 'active') {
                    a['punchOut'] = endOfDay.toUtc().toIso8601String();
                    a['status'] = 'closed';
                    a['durationSeconds'] = durationSecs > 0 ? durationSecs : 0;
                    a['punchOutType'] = 'auto';
                    break;
                  }
                }
                final storedToken = token;
                if (ownerDocId != null &&
                    storedToken != null &&
                    storedToken.isNotEmpty) {
                  http
                      .patch(
                        Uri.parse(
                          '${ApiService.baseUrl}/attendance/$ownerDocId',
                        ),
                        headers: {
                          'Authorization': 'Bearer $storedToken',
                          'Content-Type': 'application/json',
                        },
                        body: jsonEncode({'activities': ownerActivities}),
                      )
                      .then((_) {
                        if (mounted) _fetchAttendance();
                      })
                      .catchError((e) {
                        debugPrint('Stale session auto-close error: $e');
                      });
                }
              }
              // Skip entirely — don't add to totalWork, don't show in UI
              continue;
            }

            // ── Only count today's sessions toward the work timer ─────────
            if (punchOut != null) {
              if (latestPunchOutTime == null ||
                  punchOut.isAfter(latestPunchOutTime)) {
                latestPunchOutTime = punchOut;
                latestPunchOutType = rawActivity['punchOutType']?.toString();
              }
            }

            final isToday =
                punchIn.isAfter(localMidnight) ||
                (punchOut != null && punchOut.isAfter(localMidnight));

            final duration = punchOut != null
                ? Duration(
                    seconds: durationSeconds > 0
                        ? durationSeconds
                        : punchOut.difference(punchIn).inSeconds,
                  )
                : DateTime.now().difference(punchIn);

            if (isToday) {
              totalWork += duration;
            }

            // Add break card before this session if breakDurationSeconds is stored
            if (breakDurationSeconds > 0 && punchIn.isAfter(localMidnight)) {
              final breakDur = Duration(seconds: breakDurationSeconds);
              totalBreak += breakDur;
              allActivities.add({
                'type': 'break',
                'title': breakDur.inHours > 0
                    ? '${breakDur.inHours}h ${breakDur.inMinutes % 60}m Break'
                    : breakDur.inMinutes > 0
                    ? '${breakDur.inMinutes} Min Break'
                    : '${breakDur.inSeconds} Sec Break',
                'color': const Color(0xFFFFE0B2),
                'textColor': Colors.orange[900],
                'startTime': punchIn.subtract(
                  Duration(seconds: breakDurationSeconds),
                ),
              });
            }

            if (isToday) {
              allActivities.add({
                'type': 'session',
                'inTime': inTimeStr,
                'outTime': outTimeStr,
                'color': Colors.white,
                'startTime': punchIn,
                'isActive': status == 'active',
              });
            }

            if (status == 'active') {
              // Normal active session for today — start the live ticker
              activeSessionFound = true;
              final capturedImg = rawActivity['capturedImage'];
              activePhotoFound =
                  capturedImg != null &&
                  capturedImg.toString().trim().isNotEmpty;
              final activeStart = punchIn;
              final pastWork =
                  totalWork - DateTime.now().difference(activeStart);
              _timer?.cancel();
              _timer = Timer.periodic(const Duration(seconds: 1), (_) {
                if (!mounted) return;
                setState(() {
                  _workDuration =
                      pastWork + DateTime.now().difference(activeStart);
                });
              });
              // Cache active session start & past work for instant initial render
              _storage.write(key: 'activePunchIn', value: activeStart.toIso8601String());
              _storage.write(key: 'pastWorkSeconds', value: pastWork.inSeconds.toString());
              _storage.write(key: 'activeSessionHasPhoto', value: activePhotoFound.toString());
            }
          } else if (type == 'break') {
            final duration = punchOut != null
                ? Duration(
                    seconds: durationSeconds > 0
                        ? durationSeconds
                        : punchOut.difference(punchIn).inSeconds,
                  )
                : Duration.zero;

            totalBreak += duration;

            if (punchIn.isAfter(localMidnight)) {
              allActivities.add({
                'type': 'break',
                'title': duration.inMinutes > 0
                    ? '${duration.inMinutes} Min Break'
                    : '${duration.inSeconds} Sec Break',
                'color': const Color(0xFFFFE0B2),
                'textColor': Colors.orange[900],
                'startTime': punchIn,
              });
            }
          }
        }
      }

      if (!activeSessionFound) {
        _timer?.cancel();
        _storage.delete(key: 'activePunchIn');
        _storage.delete(key: 'pastWorkSeconds');
      }

      if (!mounted) return;
      setState(() {
        allActivities.sort(
          (a, b) => (b['startTime'] as DateTime).compareTo(
            a['startTime'] as DateTime,
          ),
        );
        _activities = allActivities;
        _workDuration = totalWork;
        _breakDuration = totalBreak;
        _storage.write(
          key: 'totalBreakSeconds',
          value: totalBreak.inSeconds.toString(),
        );
        _hasActiveSession = activeSessionFound;
        _activeSessionHasPhoto = activePhotoFound;
        _lastPunchOutType = latestPunchOutType;
        // dayType is only meaningful after midnight for a COMPLETED past day.
        // Never show half/full day badge for today's ongoing session.
        final todayStr = DateFormat('yyyy-MM-dd').format(localMidnight);
        final docDateStr2 = docs.isNotEmpty && docs.first is Map
            ? (docs.first as Map)['dateString']?.toString() ?? ''
            : '';
        final isToday = docDateStr2 == todayStr;
        if (!isToday && allActivities.isNotEmpty) {
          // Past date: all sessions closed = full day, any open session = half day
          _dayType = activeSessionFound ? 'half_day' : 'full_day';
        } else {
          _dayType = null; // Today: no judgement yet
        }
      });

      // Start or stop the geofence watcher based on session state
      if (activeSessionFound) {
        _autoPunchOutFired =
            false; // reset so a fresh punch-out can trigger auto punch-out
      } else {
        _autoPunchInFired =
            false; // reset so auto punch-in is enabled whenever not in a session
        _autoPunchOutFired = false;
      }
      _startGeofenceWatcher();
      
      if (mounted) {
        setState(() {
          _isFetchingInitialAttendance = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching attendance: $e');
      if (mounted) {
        setState(() {
          _isFetchingInitialAttendance = false;
        });
      }
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _formatTwoDigits(int n) => n.toString().padLeft(2, '0');

  static Future<List<int>?> _compressImageIsolate(List<int> bytes) async {
    try {
      final image = img_lib.decodeImage(Uint8List.fromList(bytes));
      if (image == null) return null;

      img_lib.Image resized = image;
      if (image.width > 1280 || image.height > 1280) {
        if (image.width > image.height) {
          resized = img_lib.copyResize(image, width: 1280);
        } else {
          resized = img_lib.copyResize(image, height: 1280);
        }
      }
      return img_lib.encodeJpg(resized, quality: 70);
    } catch (_) {
      return null;
    }
  }

  Future<File> _prepareImageForUpload(File originalFile) async {
    try {
      if (!await originalFile.exists()) return originalFile;
      final length = await originalFile.length();
      if (length < 1500 * 1024) return originalFile;

      final bytes = await originalFile.readAsBytes();
      final compressedBytes = await compute(_compressImageIsolate, bytes);

      if (compressedBytes == null) return originalFile;

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/opt_selfie_$timestamp.jpg');
      await tempFile.writeAsBytes(compressedBytes);
      return tempFile;
    } catch (_) {
      return originalFile;
    }
  }

  Future<String?> _uploadMedia(File file) async {
    final uploadFile = await _prepareImageForUpload(file);
    if (!await uploadFile.exists()) return null;

    final token = await _storage.read(key: 'token');
    if (token == null) return null;

    final filename = 'selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final urlStr = '${ApiService.baseUrl}/media?prefix=attendance';

    try {
      final request = http.MultipartRequest('POST', Uri.parse(urlStr));
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['alt'] = 'Attendance Selfie';
      request.fields['prefix'] = 'attendance';

      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        uploadFile.path,
        filename: filename,
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);

      final response = await request.send();
      final body = await response.stream.bytesToString();
      debugPrint(
        'DEBUG: Selfie upload response status: ${response.statusCode}, body: $body',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(body);
        final doc = data['doc'] ?? data;
        return doc['id']?.toString();
      } else {
        debugPrint(
          'DEBUG: Selfie upload failed. Status: ${response.statusCode}, Body: $body',
        );
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    }
    return null;
  }

  Future<void> _capturePhoto() async {
    if (_hasActiveSession || _isProcessingPunch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are already punched in.')),
      );
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No camera found')));
      return;
    }

    final XFile? capturedFile = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras, isFaceCapture: true),
      ),
    );

    if (capturedFile != null) {
      setState(() {
        _capturedPunchInPhoto = File(capturedFile.path);
      });
      await _submitPunchIn(isAuto: true);
    }
  }

  Future<void> _submitPunchIn({bool isAuto = false}) async {
    if (_capturedPunchInPhoto == null ||
        _hasActiveSession ||
        _isProcessingPunch)
      return;

    setState(() {
      _isProcessingPunch = true;
    });

    final role = (_employeeRole ?? await _storage.read(key: 'userRole'))?.toLowerCase();
    final isWatcher = role == 'watcher';

    // GPS Geofence Check (bypassed for watcher working from home).
    // We use checkLocationAndGeofence() directly so we can reuse the
    // already-fetched Position in _punchIn — avoiding a second GPS call
    // that would race against the selfie upload timeout.
    Position? geofencePosition;
    String? geofenceBranchId;
    if (!isWatcher) {
      if (!mounted) return;
      final geo = await GeofenceUtil.checkLocationAndGeofence();
      if (!geo.isInside && mounted) {
        // Show the same error message that isInsideAnyBranch would show
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(geo.errorMessage ?? 'Not inside branch geofence area.')),
        );
        setState(() => _isProcessingPunch = false);
        return; // Block punch in if not inside branch circle
      }
      geofencePosition = geo.position;
      geofenceBranchId = geo.branchId;
    }

    // If we didn't get a position from the geofence check (watcher role or
    // position was null), try to get one now before the upload starts.
    if (geofencePosition == null) {
      try {
        geofencePosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('_submitPunchIn pre-upload location error: $e');
      }
    }

    try {
      final mediaId = await _uploadMedia(_capturedPunchInPhoto!);
      if (mediaId != null) {
        await _punchIn(mediaId, isAuto: isAuto, position: geofencePosition, branchId: geofenceBranchId);
        if (mounted) {
          setState(() {
            _capturedPunchInPhoto = null;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload selfie.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Submit Punch In Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPunch = false;
        });
      }
    }
  }

  Future<void> _punchIn(String mediaId, {bool isAuto = false, Position? position, String? branchId}) async {
    final token = await _storage.read(key: 'token');
    final userId = await _storage.read(key: 'userId');
    if (token == null || userId == null) return;

    if (position == null) {
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('PunchIn location error: $e');
      }
    }

    final now = DateTime.now();
    final newActivity = {
      'type': 'session',
      'punchIn': now.toUtc().toIso8601String(),
      'status': 'active',
      'capturedImage': mediaId,
      'punchInType': isAuto ? 'auto' : 'manual',
      if (position != null) 'latitude': position.latitude,
      if (position != null) 'longitude': position.longitude,
    };

    try {
      if (_attendanceDocId != null) {
        final updatedActivities = List.from(_rawActivities)..add(newActivity);
        final url = '${ApiService.baseUrl}/attendance/$_attendanceDocId';
        final response = await http.patch(
          Uri.parse(url),
          headers: token.isNotEmpty
              ? {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                }
              : {},
          body: jsonEncode({'activities': updatedActivities}),
        );
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully punched in!')),
          );
          await _fetchEmployeeProfile();
          await _fetchAttendance();
          await _fetchDailyTasks();
          _lastPunchOutType = null;
          await _storage.delete(key: 'lastPunchOutType');
        }
      } else {
        final localMidnight = DateTime(now.year, now.month, now.day);
        final dateString = DateFormat('yyyy-MM-dd').format(localMidnight);

        final url = '${ApiService.baseUrl}/attendance';
        final response = await http.post(
          Uri.parse(url),
          headers: token.isNotEmpty
              ? {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                }
              : {},
          body: jsonEncode({
            'user': userId,
            'date': localMidnight.toUtc().toIso8601String(),
            'dateString': dateString,
            'activities': [newActivity],
            if (branchId != null) 'loginBranch': branchId,
          }),
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully punched in!')),
          );
          await _fetchEmployeeProfile();
          await _fetchAttendance();
          await _fetchDailyTasks();
          _lastPunchOutType = null;
          await _storage.delete(key: 'lastPunchOutType');
        }
      }
    } catch (e) {
      debugPrint('Punch In Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPunch = false;
        });
      }
    }
  }

  // ── Geofence watcher ────────────────────────────────────────────────────────

  void _startGeofenceWatcher() async {
    _geofenceTimer?.cancel();
    _geofenceTimer = null;

    final role = (_employeeRole ?? await _storage.read(key: 'userRole'))?.toLowerCase();
    if (role == 'watcher') {
      debugPrint('Geofence watcher skipped for watcher role');
      return;
    }

    // Check IMMEDIATELY on start / refresh
    _checkGeofence();

    _geofenceTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _checkGeofence();
    });
  }

  Future<void> _checkGeofence() async {
    if (!mounted || _isProcessingPunch) return;
    await AttendanceManager.instance.checkNow();
  }

  Future<void> _autoPunchInWithoutSelfie() async {
    if (_hasActiveSession || _isProcessingPunch) return;

    setState(() {
      _isProcessingPunch = true;
    });

    final token = await _storage.read(key: 'token');
    final userId = await _storage.read(key: 'userId');
    if (token == null || userId == null) {
      setState(() => _isProcessingPunch = false);
      return;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('AutoPunchIn location error: $e');
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    final now = DateTime.now();
    final newActivity = {
      'type': 'session',
      'punchIn': now.toUtc().toIso8601String(),
      'status': 'active',
      'capturedImage': null,
      'punchInType': 'auto',
      if (position != null) 'latitude': position.latitude,
      if (position != null) 'longitude': position.longitude,
    };

    try {
      if (_attendanceDocId != null) {
        final updatedActivities = List.from(_rawActivities)..add(newActivity);
        final url = '${ApiService.baseUrl}/attendance/$_attendanceDocId';
        final response = await http.patch(
          Uri.parse(url),
          headers: token.isNotEmpty
              ? {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                }
              : {},
          body: jsonEncode({'activities': updatedActivities}),
        );
        debugPrint(
          'AutoPunchIn PATCH response: ${response.statusCode} -> ${response.body}',
        );
        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auto punched in! Please add your selfie photo.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.blue[800],
                duration: const Duration(seconds: 5),
              ),
            );
          }
          await _fetchEmployeeProfile();
          await _fetchAttendance();
          _lastPunchOutType = null;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Auto punch-in rejected by server (${response.statusCode}): ${response.body}',
                ),
                backgroundColor: Colors.red[800],
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      } else {
        final localMidnight = DateTime(now.year, now.month, now.day);
        final dateString = DateFormat('yyyy-MM-dd').format(localMidnight);

        final url = '${ApiService.baseUrl}/attendance';
        final response = await http.post(
          Uri.parse(url),
          headers: token.isNotEmpty
              ? {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                }
              : {},
          body: jsonEncode({
            'user': userId,
            'date': localMidnight.toUtc().toIso8601String(),
            'dateString': dateString,
            'activities': [newActivity],
          }),
        );
        debugPrint(
          'AutoPunchIn POST response: ${response.statusCode} -> ${response.body}',
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auto punched in! Please add your selfie photo.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.blue[800],
                duration: const Duration(seconds: 5),
              ),
            );
          }
          await _fetchEmployeeProfile();
          await _fetchAttendance();
          _lastPunchOutType = null;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Auto punch-in rejected by server (${response.statusCode}): ${response.body}',
                ),
                backgroundColor: Colors.red[800],
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Auto punch in error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPunch = false;
        });
      }
    }
  }

  Future<void> _attachSelfieToActiveSession() async {
    if (_isProcessingPunch) return;

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No camera found')));
      return;
    }

    final XFile? capturedFile = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras, isFaceCapture: true),
      ),
    );

    if (capturedFile == null) return;

    final photoFile = File(capturedFile.path);
    setState(() {
      _capturedPunchInPhoto = photoFile;
      _isProcessingPunch = true;
    });

    try {
      final mediaId = await _uploadMedia(photoFile);
      if (mediaId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload selfie photo.')),
          );
        }
        return;
      }

      final token = await _storage.read(key: 'token');
      if (token == null || _attendanceDocId == null) return;

      final updatedActivities = List.from(_rawActivities);
      for (var i = updatedActivities.length - 1; i >= 0; i--) {
        final activity = updatedActivities[i];
        if (activity is Map &&
            activity['type'] == 'session' &&
            activity['status'] == 'active') {
          activity['capturedImage'] = mediaId;
          break;
        }
      }

      final url = '${ApiService.baseUrl}/attendance/$_attendanceDocId';
      final response = await http.patch(
        Uri.parse(url),
        headers: token.isNotEmpty
            ? {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              }
            : {},
        body: jsonEncode({'activities': updatedActivities}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Selfie attached successfully! You can now punch out when done.',
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
        await _fetchAttendance();
        AttendanceManager.instance.checkNow();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to update attendance: ${response.statusCode}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error attaching selfie: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessingPunch = false);
      }
    }
  }

  Future<void> _autoCaptureAndPunchIn() async {
    if (_hasActiveSession || _isProcessingPunch) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.location_on, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Inside branch! Please take a selfie to complete punch-in.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 4),
        ),
      );
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      _autoPunchInFired = false;
      return;
    }

    if (!mounted) return;
    final XFile? capturedFile = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras, isFaceCapture: true),
      ),
    );

    if (capturedFile != null) {
      setState(() {
        _capturedPunchInPhoto = File(capturedFile.path);
      });
      await _submitPunchIn(isAuto: true);
    } else {
      // User cancelled camera without taking photo: allow re-trigger
      _autoPunchInFired = false;
    }
  }

  void _stopGeofenceWatcher() {
    _geofenceTimer?.cancel();
    _geofenceTimer = null;
  }

  /// Identical to _punchOut() but stamps punchOutType:'auto' and shows a
  /// different banner explaining the reason.
  Future<void> _autoPunchOut() async {
    if (!_hasActiveSession || _attendanceDocId == null || _isProcessingPunch)
      return;

    setState(() => _isProcessingPunch = true);

    final token = await _storage.read(key: 'token');
    if (token == null) {
      setState(() => _isProcessingPunch = false);
      return;
    }

    try {
      final updatedActivities = List.from(_rawActivities);

      for (var i = updatedActivities.length - 1; i >= 0; i--) {
        final activity = updatedActivities[i];
        if (activity['type'] == 'session' && activity['status'] == 'active') {
          final punchInTime = DateTime.parse(activity['punchIn']);
          final punchOutTime = DateTime.now();
          final durationSecs = punchOutTime.difference(punchInTime).inSeconds;

          activity['punchOut'] = punchOutTime.toUtc().toIso8601String();
          activity['status'] = 'closed';
          activity['durationSeconds'] = durationSecs;
          activity['punchOutType'] =
              'auto'; // ← marks this as geofence-triggered
          break;
        }
      }

      final url = '${ApiService.baseUrl}/attendance/$_attendanceDocId';
      final response = await http.patch(
        Uri.parse(url),
        headers: token.isNotEmpty
            ? {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              }
            : {},
        body: jsonEncode({'activities': updatedActivities}),
      );

      if (response.statusCode == 200) {
        _lastPunchOutType = 'auto';
        _autoPunchInFired = false;
        _stopGeofenceWatcher();
        await _fetchEmployeeProfile();
        await _fetchAttendance();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.location_off, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Auto punched out — you left the branch area.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange[800],
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Auto Punch Out Error: $e');
      _autoPunchOutFired = false; // allow retry on next tick if network failed
    } finally {
      if (mounted) setState(() => _isProcessingPunch = false);
    }
  }

  // ── Manual Punch Out ────────────────────────────────────────────────────────

  Future<void> _punchOut() async {
    if (!_hasActiveSession || _attendanceDocId == null || _isProcessingPunch)
      return;

    if (!_activeSessionHasPhoto) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Photo Required'),
            ],
          ),
          content: const Text(
            'You cannot punch out yet! Please add your selfie photo to complete today\'s attendance first.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _attachSelfieToActiveSession();
              },
              icon: const Icon(Icons.camera_alt, size: 18),
              label: const Text('Add Photo Now'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _isProcessingPunch = true;
    });

    final token = await _storage.read(key: 'token');
    if (token == null) return;

    try {
      final updatedActivities = List.from(_rawActivities);

      for (var i = updatedActivities.length - 1; i >= 0; i--) {
        final activity = updatedActivities[i];
        if (activity['type'] == 'session' && activity['status'] == 'active') {
          final punchInTime = DateTime.parse(activity['punchIn']);
          final punchOutTime = DateTime.now();
          final durationSecs = punchOutTime.difference(punchInTime).inSeconds;

          activity['punchOut'] = punchOutTime.toUtc().toIso8601String();
          activity['status'] = 'closed';
          activity['durationSeconds'] = durationSecs;
          activity['punchOutType'] = 'manual'; // ← employee tapped the button
          break;
        }
      }

      final url = '${ApiService.baseUrl}/attendance/$_attendanceDocId';
      final response = await http.patch(
        Uri.parse(url),
        headers: token.isNotEmpty
            ? {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              }
            : {},
        body: jsonEncode({'activities': updatedActivities}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully punched out!')),
        );
        await _fetchEmployeeProfile();
        await _fetchAttendance();
        _autoPunchInFired = false;
        _lastPunchOutType = 'manual';
        await _storage.write(key: 'lastPunchOutType', value: 'manual');
      }
    } catch (e) {
      debugPrint('Punch Out Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPunch = false;
        });
      }
    }
  }

  Future<void> _confirmLogout() async {
    if (_isLoggingOut || !mounted) return;
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Do you want to logout from this device?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    setState(() {
      _isLoggingOut = true;
    });

    try {
      AttendanceManager.instance.stopForegroundWatcher();
      await _storage.deleteAll();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Logout Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logout failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF5B36AC),
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 46,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () async {
              await _fetchEmployeeProfile();
              await _fetchAttendance();
              await _fetchDailyTasks();
              await _fetchReportCard();
              _autoPunchInFired = false;
              await _checkGeofence();
            },
          ),
        ],
      ),
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _profileLoading
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: const Center(
            child: CircularProgressIndicator(color: Color(0xFF5B36AC)),
          ),
          secondChild: RefreshIndicator(
            onRefresh: () async {
              await _fetchEmployeeProfile();
              await _fetchAttendance();
              await _fetchDailyTasks();
              await _fetchReportCard();
              _autoPunchInFired = false;
              await _checkGeofence();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  // 1. Purple Header with Profile Photo, Greeting, Name, Role/Branch
                  _buildPurpleTopHeader(),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                    child: Column(
                      children: [
                        // 1. Live Performance Score Card with Gauge & Mini Stats
                        _buildLivePerformanceCard(),
                        const SizedBox(height: 14),

                        // 2. 3x2 Square Grid
                        _buildSquareGrid(),
                        const SizedBox(height: 14),

                        if (_workStatus != 'not_started') ...[
                          _buildWorkStatusSection(),
                          const SizedBox(height: 16),
                        ],

                        // 5. Punch Out, Auto/Manual Status, Selfie Alert, Logout
                        _buildPunchAndLogoutSection(),

                        // 6. Routine Tasks (if any)
                        _buildRoutineTasksSection(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPurpleTopHeader() {
    final hours = _formatTwoDigits(_workDuration.inHours);
    final minutes = _formatTwoDigits(_workDuration.inMinutes % 60);
    final seconds = _formatTwoDigits(_workDuration.inSeconds % 60);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF5B36AC),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Profile photo with camera badge preserving exact camera / selfie punch-in logic
          GestureDetector(
            onTap: _hasActiveSession
                ? (!_activeSessionHasPhoto
                      ? _attachSelfieToActiveSession
                      : null)
                : _capturePhoto,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _hasActiveSession
                          ? (_activeSessionHasPhoto
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444))
                          : Colors.white.withValues(alpha: 0.85),
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _capturedPunchInPhoto != null
                        ? Image.file(_capturedPunchInPhoto!, fit: BoxFit.cover)
                        : (_employeePhotoUrl != null && _employeePhotoUrl!.isNotEmpty
                            ? Image.network(
                                _employeePhotoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.white24,
                                  child: const Icon(Icons.person, color: Colors.white, size: 26),
                                ),
                              )
                            : Container(
                                color: Colors.white24,
                                child: const Icon(Icons.person, color: Colors.white, size: 26),
                              )),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      color: _hasActiveSession && !_activeSessionHasPhoto
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF2563EB),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: Icon(
                      _hasActiveSession && !_activeSessionHasPhoto
                          ? Icons.add_a_photo
                          : Icons.camera_alt,
                      color: Colors.white,
                      size: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getGreeting(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _employeeName ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  _getRoleAndBranchSubtitle(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Live Working Hours Running Time Badge on the right side
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1.0,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _hasActiveSession
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFF94A3B8),
                        shape: BoxShape.circle,
                        boxShadow: _hasActiveSession
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF4ADE80).withValues(alpha: 0.6),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$hours:$minutes:$seconds',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _dayType == 'full_day'
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : (_dayType == 'half_day'
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.12)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _dayType == 'full_day'
                        ? 'Full Day'
                        : (_dayType == 'half_day'
                            ? 'Half Day'
                            : (_hasActiveSession ? 'Running' : 'Working Hrs')),
                    style: TextStyle(
                      color: _dayType == 'full_day'
                          ? const Color(0xFF86EFAC)
                          : (_dayType == 'half_day'
                              ? const Color(0xFFFDBA74)
                              : Colors.white.withValues(alpha: 0.75)),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePerformanceCard() {
    final overallScore = (_reportCardData?['overallScore'] ?? 0) as num;
    final rules = _reportCardData?['rules'] as List<dynamic>? ?? [];
    final totalMax = _reportCardData?['totalMaxMarks'] != null
        ? (_reportCardData!['totalMaxMarks'] as num)
        : (rules.isNotEmpty
            ? rules.fold<num>(0, (sum, r) => sum + ((r is Map ? r['maxMarks'] : 100) as num? ?? 100))
            : 1000);
    final totalScore = _reportCardData?['totalScore'] != null
        ? (_reportCardData!['totalScore'] as num)
        : (rules.isNotEmpty
            ? rules.fold<num>(0, (sum, r) => sum + ((r is Map ? r['score'] : 0) as num? ?? 0))
            : ((overallScore / 100) * totalMax).round());

    final double percentage = totalMax > 0 ? (totalScore / totalMax) : 0.0;
    final double progress = percentage.clamp(0.0, 1.0);
    final scoreStr = totalScore % 1 == 0 ? totalScore.toInt().toString() : totalScore.toStringAsFixed(1);
    final totalMaxStr = totalMax % 1 == 0 ? totalMax.toInt().toString() : totalMax.toStringAsFixed(0);

    String statusTag;
    Color statusColor;
    if (percentage >= 0.85) {
      statusTag = 'EXCELLENT';
      statusColor = const Color(0xFF10B981);
    } else if (percentage >= 0.70) {
      statusTag = 'TARGET MET';
      statusColor = const Color(0xFF10B981);
    } else if (percentage >= 0.50) {
      statusTag = 'GOOD';
      statusColor = const Color(0xFF10B981);
    } else if (percentage >= 0.35) {
      statusTag = 'AVERAGE';
      statusColor = const Color(0xFFF59E0B);
    } else {
      statusTag = 'NEEDS FOCUS';
      statusColor = const Color(0xFFEF4444);
    }

    final todayChange = _reportCardData?['todayChange']?.toString() ??
        '+${(totalScore * 0.05).round() > 0 ? (totalScore * 0.05).round() : 10}';
    final weekChange = _reportCardData?['weekChange']?.toString() ??
        '+${(totalScore * 0.15).round() > 0 ? (totalScore * 0.15).round() : 34}';
    final monthChange = _reportCardData?['monthChange']?.toString() ??
        '+${(totalScore * 0.25).round() > 0 ? (totalScore * 0.25).round() : 63}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const RankCardPage(),
              ),
            ).then((_) => _fetchReportCard());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 20),
                    const Text(
                      'LIVE PERFORMANCE SCORE',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                        letterSpacing: 0.6,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                SizedBox(
                  width: 170,
                  height: 115,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(170, 115),
                        painter: _PerformanceSpeedometerGauge(
                          progress: progress,
                        ),
                      ),
                      Positioned(
                        top: 25,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              scoreStr,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1E293B),
                                height: 1.0,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '/$totalMaxStr',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                statusTag,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: statusColor,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildMiniStatBox(
                          label: "Today's Change",
                          value: todayChange.startsWith('+') ? todayChange : '+$todayChange',
                          color: const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildMiniStatBox(
                          label: 'This Week',
                          value: weekChange.startsWith('+') ? weekChange : '+$weekChange',
                          color: const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildMiniStatBox(
                          label: 'This Month',
                          value: monthChange.startsWith('+') ? monthChange : '+$monthChange',
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStatBox({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSquareGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSquareGridItem(
                icon: _workStatus == 'completed'
                    ? Icons.check_circle_rounded
                    : (_workStatus == 'in_progress'
                        ? Icons.hourglass_top_rounded
                        : Icons.play_arrow_rounded),
                iconBgColor: _workStatus == 'completed'
                    ? const Color(0xFF2E7D32)
                    : (_workStatus == 'in_progress'
                        ? const Color(0xFF1E88E5)
                        : const Color(0xFF00C853)),
                label: _workStatus == 'completed'
                    ? 'Duty Done'
                    : (_workStatus == 'in_progress' ? 'In Duty' : 'Duty Start'),
                onTap: () {
                  if (_workStatus == 'not_started') {
                    _handleStartWork();
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DailyTasksPage(attendanceId: _attendanceDocId),
                      ),
                    ).then((_) {
                      _fetchAttendance();
                      _fetchDailyTasks();
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSquareGridItem(
                icon: Icons.speed_rounded,
                iconBgColor: const Color(0xFF7C3AED),
                label: 'My Score',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RankCardPage(),
                    ),
                  ).then((_) => _fetchReportCard());
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSquareGridItem(
                icon: Icons.assignment_turned_in_rounded,
                iconBgColor: const Color(0xFFEA580C),
                label: 'My Tasks',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DailyTasksPage(attendanceId: _attendanceDocId),
                    ),
                  ).then((_) {
                    _fetchAttendance();
                    _fetchDailyTasks();
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSquareGridItem(
                icon: Icons.coffee_rounded,
                iconBgColor: const Color(0xFFD97706),
                label: 'Break / Lunch',
                onTap: () => _showActivitiesBottomSheet(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSquareGridItem(
                icon: Icons.calendar_month_rounded,
                iconBgColor: const Color(0xFFE11D48),
                label: 'Attendance',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AttendanceCalendarPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSquareGridItem(
                icon: Icons.account_circle_outlined,
                iconBgColor: const Color(0xFF0284C7),
                label: 'My Profile',
                onTap: _showProfileDetailsModal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSquareGridItem({
    required IconData icon,
    required Color iconBgColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPunchAndLogoutSection() {
    return Column(
      children: [
        // Total Break box (if any)
        if (_breakDuration > Duration.zero) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE0B2),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.orange[800],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.coffee, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 14),
                Text(
                  'Total Break  ',
                  style: TextStyle(
                    color: Colors.orange[900],
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_formatTwoDigits(_breakDuration.inHours)}h : ${_formatTwoDigits(_breakDuration.inMinutes % 60)}m',
                  style: TextStyle(
                    color: Colors.orange[900],
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],

        // 1. Auto/Manual Geofence Status Container (shown when not punched in)
        if (!_hasActiveSession) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF90CAF9)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1976D2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _lastPunchOutType == 'auto'
                            ? 'Auto Punch-In Ready (Auto Punched Out)'
                            : 'Punched Out (Manual)',
                        style: const TextStyle(
                          color: Color(0xFF0D47A1),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _lastPunchOutType == 'auto'
                            ? 'Will auto punch-in when you enter branch'
                            : 'Manual punch out active. Use camera to punch in.',
                        style: const TextStyle(
                          color: Color(0xFF1565C0),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isProcessingPunch ? null : () => _checkGeofence(),
                  child: _isProcessingPunch
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Check Now',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ],

        // 2. Selfie warning alert (if active session lacks photo)
        if (_hasActiveSession && !_activeSessionHasPhoto) ...[
          GestureDetector(
            onTap: _attachSelfieToActiveSession,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.redAccent, width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selfie Required for Punch-In',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tap here to add selfie. Punch-out is blocked until added.',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.camera_alt, color: Colors.red, size: 20),
                ],
              ),
            ),
          ),
        ],

        // 3. Manual Punch-In button (if photo was captured)
        if (!_hasActiveSession && _capturedPunchInPhoto != null) ...[
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isProcessingPunch ? null : () => _submitPunchIn(isAuto: false),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C853),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _isProcessingPunch
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.login, size: 20),
              label: Text(
                _isProcessingPunch ? 'Punching in...' : 'Punch In',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 4. Punch Out Button (when in active session)
        if (_hasActiveSession) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange[800],
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: (_isLoggingOut || _isProcessingPunch) ? null : _punchOut,
              icon: _isProcessingPunch
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.punch_clock, size: 20),
              label: Text(
                _isProcessingPunch ? 'Processing...' : 'Punch Out',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 5. Logout Button (always positioned at the end after square grid)
        SizedBox(
          width: double.infinity,
          child: _hasActiveSession
              ? OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD32F2F),
                    side: const BorderSide(color: Color(0xFFEF5350), width: 1.5),
                    backgroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: (_isLoggingOut || _isProcessingPunch) ? null : _confirmLogout,
                  icon: _isLoggingOut
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD32F2F)),
                          ),
                        )
                      : const Icon(Icons.logout_rounded, size: 20),
                  label: Text(
                    _isLoggingOut ? 'Logging out...' : 'Logout',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: (_isLoggingOut || _isProcessingPunch) ? null : _confirmLogout,
                  icon: _isLoggingOut
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.logout_rounded, size: 20),
                  label: Text(
                    _isLoggingOut ? 'Logging out...' : 'Logout',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
        ),
      ],
    );
  }

  void _showProfileDetailsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF5B36AC).withValues(alpha: 0.1),
                backgroundImage: _capturedPunchInPhoto != null
                    ? FileImage(_capturedPunchInPhoto!) as ImageProvider
                    : (_employeePhotoUrl != null && _employeePhotoUrl!.isNotEmpty
                        ? NetworkImage(_employeePhotoUrl!)
                        : null),
                child: _capturedPunchInPhoto == null && (_employeePhotoUrl == null || _employeePhotoUrl!.isEmpty)
                    ? const Icon(Icons.person, size: 40, color: Color(0xFF5B36AC))
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                _employeeName ?? 'Staff Member',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B36AC).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  (_employeeRole ?? 'Staff').toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF5B36AC),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildProfileInfoTile(Icons.badge_outlined, 'Employee ID', _employeeId ?? '-'),
              _buildProfileInfoTile(Icons.store_outlined, 'Branch', _loginBranchName ?? _branchName ?? '-'),
              if (_managerCompanyNames.isNotEmpty)
                _buildProfileInfoTile(Icons.business_outlined, 'Companies', _managerCompanyNames.join(' • ')),
              if (_kitchenName != null && _kitchenName!.isNotEmpty)
                _buildProfileInfoTile(Icons.restaurant_outlined, 'Kitchen', _kitchenName!),
              if (_employeePhone != null && _employeePhone!.isNotEmpty)
                _buildProfileInfoTile(Icons.phone_outlined, 'Phone', _employeePhone!),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5B36AC),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileInfoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF64748B)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B), fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  void _showActivitiesBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Color(0xFFF8F9FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Your Activity',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  children: [
                    if (_activities.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'No activity for today',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      ),
                    ..._activities.map((activity) {
                      if (activity['type'] == 'break') {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: activity['color'] as Color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              activity['title']?.toString() ?? '',
                              style: TextStyle(
                                color:
                                    (activity['textColor'] as Color?) ??
                                    Colors.orange[900],
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        );
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(12),
                                      bottomLeft: Radius.circular(12),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.login,
                                            size: 18,
                                            color: Colors.green,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Punch In',
                                            style: TextStyle(
                                              color: Colors.green[800],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        activity['inTime']?.toString() ?? '-',
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 1, color: Colors.grey[300]),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: activity['isActive'] == true
                                        ? Colors.white
                                        : Colors.red.withValues(alpha: 0.08),
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.logout,
                                            size: 18,
                                            color: activity['isActive'] == true
                                                ? Colors.grey
                                                : Colors.red,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Punch Out',
                                            style: TextStyle(
                                              color:
                                                  activity['isActive'] == true
                                                  ? Colors.grey[600]
                                                  : Colors.red[800],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        activity['outTime']?.toString() ?? '-',
                                        style: TextStyle(
                                          color: activity['isActive'] == true
                                              ? Colors.green[700]
                                              : Colors.red[700],
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Future<void> _fetchDailyTasks() async {
    try {
      if (mounted) setState(() => _loadingTasks = true);
      final res = await ApiService.instance.fetchMyDailyTasks();
      if (res['success'] == true && res['tasks'] is List) {
        if (mounted) {
          setState(() {
            _dailyTasks = List<Map<String, dynamic>>.from(
              (res['tasks'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
            if (res['workStatus'] != null) {
              _workStatus = res['workStatus'].toString();
            }
            if (res['workStartTime'] != null) {
              _workStartTime = DateTime.tryParse(res['workStartTime'].toString());
            }
            if (res['workCompletedTime'] != null) {
              _workCompletedTime = DateTime.tryParse(res['workCompletedTime'].toString());
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading daily tasks: $e');
    } finally {
      if (mounted) setState(() => _loadingTasks = false);
    }
  }

  Future<void> _handleStartWork() async {
    if (_isStartingWork) return;
    setState(() => _isStartingWork = true);

    try {
      if (_attendanceDocId == null) {
        await _fetchAttendance();
      }
      final res = await ApiService.instance.startWork(attendanceId: _attendanceDocId);
      if (res['success'] == true) {
        final now = DateTime.now();
        setState(() {
          _workStatus = 'in_progress';
          _workStartTime = now;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.play_circle_fill, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Work officially started! 🚀 Good luck!')),
                ],
              ),
              backgroundColor: Color(0xFF00C853),
              duration: Duration(seconds: 3),
            ),
          );

          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => DailyTasksPage(attendanceId: _attendanceDocId)),
          ).then((_) {
            _fetchAttendance();
            _fetchDailyTasks();
          });
        }
      } else {
        throw Exception(res['message'] ?? 'Failed to start work');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start work: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingWork = false);
    }
  }

  Widget _buildWorkStatusSection() {
    final hasPunchedIn = _hasActiveSession || _attendanceDocId != null;

    if (!hasPunchedIn && _workStatus == 'not_started') {
      return const SizedBox.shrink();
    }

    if (_workStatus == 'not_started') {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
            ),
            onPressed: _isStartingWork ? null : _handleStartWork,
            icon: _isStartingWork
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.rocket_launch_rounded, size: 20),
            label: Text(
              _isStartingWork ? 'Starting Work...' : 'Start My Work 🚀',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    if (_workStatus == 'in_progress') {
      final startTimeStr = _workStartTime != null
          ? DateFormat('hh:mm a').format(_workStartTime!)
          : 'Just now';
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E88E5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Work In Progress ⏱️',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Started at $startTimeStr',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DailyTasksPage(attendanceId: _attendanceDocId),
                    ),
                  ).then((_) {
                    _fetchAttendance();
                    _fetchDailyTasks();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E88E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.assignment, size: 16),
                label: const Text(
                  'Tasks',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_workStatus == 'completed') {
      final startStr = _workStartTime != null
          ? DateFormat('hh:mm a').format(_workStartTime!)
          : null;
      final completedStr = _workCompletedTime != null
          ? DateFormat('hh:mm a').format(_workCompletedTime!)
          : null;
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFF2E7D32),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Work Completed Today 🎉',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (startStr != null && completedStr != null)
                          ? '$startStr - $completedStr'
                          : 'All daily tasks completed!',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  bool _isRoutineTask(Map<String, dynamic> task) {
    final labels = task['labels'];
    if (labels is List) {
      for (final l in labels) {
        if (l is Map) {
          final text = (l['text'] ?? l['name'] ?? l['label'])?.toString().toLowerCase().trim();
          if (text == 'routine') return true;
        } else if (l is String) {
          if (l.toLowerCase().trim() == 'routine') return true;
        }
      }
    }
    final singleLabel = task['label']?.toString().toLowerCase().trim();
    if (singleLabel == 'routine') return true;
    return false;
  }

  bool _isTaskYes(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase().trim();
    if (status == 'yes') return true;
    if (status == null && task['completed'] == true) return true;
    return false;
  }

  bool _isTaskNo(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase().trim();
    return status == 'no';
  }

  bool _isTaskNoComplaint(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase().trim();
    return status == 'no_complaint';
  }

  bool _isTaskAnswered(Map<String, dynamic> task) {
    return _isTaskYes(task) || _isTaskNo(task) || _isTaskNoComplaint(task);
  }

  String _getYesButtonText(Map<String, dynamic> task) {
    final customYes = task['yesText']?.toString().trim();
    if (customYes != null && customYes.isNotEmpty) {
      return customYes.contains('✓') ? customYes : '$customYes ✓';
    }
    final title = task['title']?.toString() ?? '';
    final desc = task['description']?.toString() ?? '';
    final lower = '$title $desc'.toLowerCase();
    if (lower.contains('தயாரா') || lower.contains('ready')) {
      return "Yes, I'm Ready ✓";
    }
    return 'Yes ✓';
  }

  Widget _buildTaskIconWidget(Map<String, dynamic> task) {
    final title = task['title']?.toString() ?? '';
    final desc = task['description']?.toString() ?? '';
    final iconField = task['icon']?.toString().trim() ?? '';

    String emoji = '';
    if (iconField.isNotEmpty) {
      switch (iconField) {
        case 'smile':
          final lowerCase = '$title $desc'.toLowerCase();
          if (lowerCase.contains('தயாரா') || lowerCase.contains('ready') || lowerCase.contains('smile') || lowerCase.contains('மனநிலை')) {
            emoji = '😊';
          }
          break;
        case 'brain':
          emoji = '🧠';
          break;
        case 'cleaning':
          emoji = '🧹';
          break;
        case 'settings':
          emoji = '⚙️';
          break;
        case 'complaint':
          emoji = '💬';
          break;
        case 'team':
          emoji = '👥';
          break;
        case 'checklist':
          emoji = '📋';
          break;
        case 'hygiene':
          emoji = '🧼';
          break;
        case 'cash':
          emoji = '💰';
          break;
        case 'inventory':
          emoji = '📦';
          break;
        case 'time':
          emoji = '⏰';
          break;
        case 'uniform':
          emoji = '⭐';
          break;
        case 'food':
          emoji = '🍲';
          break;
        case 'cake':
          emoji = '🎂';
          break;
        default:
          emoji = iconField;
      }
    }

    if (emoji.isEmpty) {
      final lower = '$title $desc'.toLowerCase();
      if (lower.contains('தயாரா') || lower.contains('ready') || lower.contains('work') || lower.contains('வேலைக்கு')) {
        emoji = '😊';
      } else if (lower.contains('மனநிலை') || lower.contains('mind') || lower.contains('mental') || lower.contains('brain')) {
        emoji = '🧠';
      } else if (lower.contains('complaint') || lower.contains('புகார்') || lower.contains('customer') || lower.contains('வாடிக்கையாளர்')) {
        emoji = '💬';
      } else if (lower.contains('clean') || lower.contains('neat') || lower.contains('sweep') || lower.contains('தூய்மை') || lower.contains('சுத்தம்')) {
        emoji = '🧹';
      } else if (lower.contains('equipment') || lower.contains('machine') || lower.contains('கருவி') || lower.contains('maintain')) {
        emoji = '⚙️';
      } else if (lower.contains('team') || lower.contains('support') || lower.contains('குழு') || lower.contains('உதவி')) {
        emoji = '👥';
      } else if (lower.contains('stock') || lower.contains('inventory') || lower.contains('பொருட்கள்')) {
        emoji = '📦';
      } else if (lower.contains('cash') || lower.contains('bill') || lower.contains('money') || lower.contains('பணம்')) {
        emoji = '💰';
      } else if (lower.contains('kitchen') || lower.contains('food') || lower.contains('cake') || lower.contains('சமையல்')) {
        emoji = '🍲';
      } else {
        emoji = '📋';
      }
    }

    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      child: Text(
        emoji,
        style: const TextStyle(fontSize: 32),
      ),
    );
  }

  Future<void> _handleTaskAction(Map<String, dynamic> task, String targetStatus) async {
    final taskId = task['id']?.toString() ?? '';
    final currentStatus = task['status']?.toString();
    if (currentStatus == targetStatus) return;

    if (_togglingTaskIds.contains(taskId)) return;

    final index = _dailyTasks.indexWhere((t) => t['id']?.toString() == taskId);
    if (index == -1) return;

    final bool targetCompleted = targetStatus == 'yes' || targetStatus == 'no_complaint';

    // Optimistic UI update
    setState(() {
      _togglingTaskIds.add(taskId);
      _dailyTasks[index]['status'] = targetStatus;
      _dailyTasks[index]['completed'] = targetCompleted;
      _dailyTasks[index]['completedAt'] = DateTime.now().toIso8601String();
    });

    try {
      final res = await ApiService.instance.toggleDailyTask(
        taskId: taskId,
        status: targetStatus,
        completed: targetCompleted,
      );
      if (res['success'] != true) {
        // Revert on failure
        if (mounted) {
          setState(() {
            _dailyTasks[index]['status'] = currentStatus;
            _dailyTasks[index]['completed'] = currentStatus == 'yes';
          });
        }
      }
    } catch (e) {
      debugPrint('Error updating task: $e');
      if (mounted) {
        setState(() {
          _dailyTasks[index]['status'] = currentStatus;
          _dailyTasks[index]['completed'] = currentStatus == 'yes';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _togglingTaskIds.remove(taskId);
        });
      }
    }
  }

  Widget _buildRoutineTasksSection() {
    final routineTasks = _dailyTasks.where((t) => _isRoutineTask(t)).toList();
    if (routineTasks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Routine',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${routineTasks.where((t) => _isTaskAnswered(t)).length}/${routineTasks.length}',
                  style: const TextStyle(
                    color: Color(0xFF2E7D32),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: routineTasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = routineTasks[index];
              final taskId = task['id']?.toString() ?? '';
              final isYes = _isTaskYes(task);
              final isNo = _isTaskNo(task);
              final isNoComplaint = _isTaskNoComplaint(task);
              final isAnswered = _isTaskAnswered(task);
              final isToggling = _togglingTaskIds.contains(taskId);
              final title = task['title']?.toString() ?? 'Task';
              final desc = task['description']?.toString() ?? '';
              final hasComplaintOption = title.toLowerCase().contains('complaint') ||
                  title.contains('புகார்') ||
                  desc.toLowerCase().contains('complaint') ||
                  desc.contains('புகார்');
              final yesButtonText = _getYesButtonText(task);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: isYes
                      ? const Color(0xFFF0FDF4)
                      : (isNo
                          ? const Color(0xFFFEF2F2)
                          : (isNoComplaint ? const Color(0xFFF0F9FF) : Colors.white)),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: isYes
                        ? const Color(0xFF86EFAC)
                        : (isNo
                            ? const Color(0xFFFECACA)
                            : (isNoComplaint ? const Color(0xFFBAE6FD) : Colors.grey[200]!)),
                    width: isAnswered ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTaskIconWidget(task),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isYes
                                  ? const Color(0xFF15803D)
                                  : (isNo ? const Color(0xFF991B1B) : const Color(0xFF1E293B)),
                              height: 1.25,
                            ),
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              desc,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                                height: 1.25,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: isToggling ? null : () => _handleTaskAction(task, 'yes'),
                                    borderRadius: BorderRadius.circular(8),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: isNo
                                            ? const Color(0xFFDCFCE7)
                                            : const Color(0xFF00C853),
                                        borderRadius: BorderRadius.circular(8),
                                        border: isNo
                                            ? Border.all(color: const Color(0xFF86EFAC), width: 1)
                                            : null,
                                        boxShadow: !isNo
                                            ? [
                                                BoxShadow(
                                                  color: const Color(0xFF00C853).withValues(alpha: 0.25),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                )
                                              ]
                                            : null,
                                      ),
                                      alignment: Alignment.center,
                                      child: isToggling && isYes
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : Text(
                                              yesButtonText,
                                              maxLines: 1,
                                              softWrap: false,
                                              style: TextStyle(
                                                color: isNo ? const Color(0xFF15803D) : Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: isToggling ? null : () => _handleTaskAction(task, 'no'),
                                    borderRadius: BorderRadius.circular(8),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: isNo ? const Color(0xFFDC2626) : const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: isNo ? null : Border.all(color: const Color(0xFFFECACA), width: 1),
                                        boxShadow: isNo
                                            ? [
                                                BoxShadow(
                                                  color: const Color(0xFFDC2626).withValues(alpha: 0.25),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                )
                                              ]
                                            : null,
                                      ),
                                      alignment: Alignment.center,
                                      child: isToggling && isNo
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : Text(
                                              'No',
                                              maxLines: 1,
                                              softWrap: false,
                                              style: TextStyle(
                                                color: isNo ? Colors.white : const Color(0xFFDC2626),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                if (hasComplaintOption) ...[
                                  const SizedBox(width: 8),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: isToggling ? null : () => _handleTaskAction(task, 'no_complaint'),
                                      borderRadius: BorderRadius.circular(8),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: isNoComplaint ? const Color(0xFF0284C7) : const Color(0xFFE0F2FE),
                                          borderRadius: BorderRadius.circular(8),
                                          border: isNoComplaint ? null : Border.all(color: const Color(0xFFBAE6FD), width: 0.8),
                                        ),
                                        child: Text(
                                          'No Complaint',
                                          maxLines: 1,
                                          softWrap: false,
                                          style: TextStyle(
                                            color: isNoComplaint ? Colors.white : const Color(0xFF0284C7),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}


class _PerformanceSpeedometerGauge extends CustomPainter {
  final double progress; // 0.0 to 1.0

  _PerformanceSpeedometerGauge({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.66);
    final radius = size.width * 0.36;
    const strokeWidth = 10.0;

    // Start angle: 140 degrees (in radians)
    // End angle: 400 degrees (sweeps 260 degrees = 4.5378 radians)
    const startAngle = 140 * math.pi / 180;
    const totalSweep = 260 * math.pi / 180;

    // 1. Background track
    final trackPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final arcRect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      arcRect,
      startAngle,
      totalSweep,
      false,
      trackPaint,
    );

    // 2. Active progress arc with amber-to-green gradient
    final clampedProgress = progress.clamp(0.0, 1.0);
    if (clampedProgress > 0) {
      final activeSweep = totalSweep * clampedProgress;

      final gradient = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + totalSweep,
        colors: const [
          Color(0xFFF59E0B), // Amber 500
          Color(0xFF10B981), // Emerald 500
        ],
      );

      final activePaint = Paint()
        ..shader = gradient.createShader(arcRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        arcRect,
        startAngle,
        activeSweep,
        false,
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PerformanceSpeedometerGauge oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

