import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login.dart';
import 'attendance_manager.dart';
import 'tracker_contact_book_page.dart';
import 'api_service.dart';
import 'app_grid_settings.dart';

class CommonScaffold extends StatefulWidget {
  final Widget body;
  final String title;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? persistentFooter;

  const CommonScaffold({
    super.key,
    required this.body,
    required this.title,
    this.actions,
    this.bottomNavigationBar,
    this.persistentFooter,
  });

  @override
  State<CommonScaffold> createState() => _CommonScaffoldState();
}

class _CommonScaffoldState extends State<CommonScaffold> {
  static const _storage = FlutterSecureStorage();
  String _userName = '';
  String _userRole = '';
  String _userId = '';
  String? _profilePhotoUrl;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    await AppGridSettings.init();
    try {
      final values = await Future.wait([
        _storage.read(key: 'userName'),
        _storage.read(key: 'userRole'),
        _storage.read(key: 'employeeId'),
        _storage.read(key: 'userId'),
        _storage.read(key: 'userProfilePhoto'),
      ]);

      String name = values[0] ?? '';
      String role = values[1] ?? '';
      String empId = values[2] ?? '';
      String uId = values[3] ?? '';
      String photo = values[4] ?? '';

      if (name.isEmpty || role.isEmpty || photo.isEmpty || empId.isEmpty) {
        final profile = await ApiService.instance.fetchUserProfile();
        if (profile.isNotEmpty) {
          name = (profile['name'] ?? profile['username'] ?? name).toString();
          role = (profile['role'] ?? role).toString();
          uId = (profile['id'] ?? profile['_id'] ?? uId).toString();

          final emp = profile['employee'];
          if (emp is Map) {
            empId = (emp['employeeId'] ?? emp['id'] ?? empId).toString();
            final p = emp['photo'];
            if (p is Map) {
              photo = p['thumbnailURL']?.toString() ??
                  p['thumbnailUrl']?.toString() ??
                  p['url']?.toString() ??
                  photo;
            } else if (p is String) {
              photo = p;
            }
          }
          if (photo.isNotEmpty && !photo.startsWith('http')) {
            photo = 'https://blackforest-api.vseyal.com$photo';
          }
          if (photo.isNotEmpty) {
            await _storage.write(key: 'userProfilePhoto', value: photo);
          }
          if (name.isNotEmpty) {
            await _storage.write(key: 'userName', value: name);
          }
          if (role.isNotEmpty) {
            await _storage.write(key: 'userRole', value: role);
          }
          if (empId.isNotEmpty) {
            await _storage.write(key: 'employeeId', value: empId);
          }
        }
      }

      if (mounted) {
        setState(() {
          _userName = name;
          _userRole = role;
          _userId = empId.isNotEmpty ? empId : uId;
          _profilePhotoUrl = photo.isNotEmpty ? photo : null;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data for drawer: $e');
    }
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: Colors.greenAccent),
            tooltip: 'Live Contacts & Call History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TrackerContactBookPage(),
                ),
              );
            },
          ),
          ...?widget.actions,
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFFF8FAFC),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. User Profile Area (Premium Gradient Header)
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + 20,
                  20,
                  22,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1E293B), // Slate 800
                      Color(0xFF0F172A), // Slate 900
                    ],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F0F172A),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 28,
                            backgroundColor: const Color(0xFF334155),
                            backgroundImage: _profilePhotoUrl != null &&
                                    _profilePhotoUrl!.isNotEmpty
                                ? NetworkImage(_profilePhotoUrl!)
                                : null,
                            child: _profilePhotoUrl == null ||
                                    _profilePhotoUrl!.isEmpty
                                ? Text(
                                    _getInitials(_userName),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _userName.isNotEmpty ? _userName : 'Staff Member',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Text(
                                  _userRole.isNotEmpty
                                      ? _userRole.toUpperCase()
                                      : 'STAFF',
                                  style: const TextStyle(
                                    color: Color(0xFFFBBF24),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_userId.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              size: 14,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ID: $_userId',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. Preferences Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'PREFERENCES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade500,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 3. Grid Toggle Switch Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ValueListenableBuilder<int>(
                  valueListenable: AppGridSettings.columnCount,
                  builder: (context, colCount, _) {
                    final is3Col = colCount == 3;
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Toggle Switch Row
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 2,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.grid_view_rounded,
                                color: Color(0xFF4F46E5),
                                size: 22,
                              ),
                            ),
                            title: const Text(
                              'Grid Layout',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            subtitle: Text(
                              is3Col
                                  ? '3 Columns active'
                                  : '2 Columns active (Default)',
                              style: TextStyle(
                                fontSize: 12,
                                color: is3Col
                                    ? const Color(0xFF4F46E5)
                                    : const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: Switch.adaptive(
                              value: is3Col,
                              activeThumbColor: const Color(0xFF4F46E5),
                              activeTrackColor: const Color(0xFFA5B4FC),
                              onChanged: (bool val) {
                                AppGridSettings.setColumnCount(val ? 3 : 2);
                              },
                            ),
                          ),

                          // Segmented Sliding Pill Bar
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        AppGridSettings.setColumnCount(2);
                                      },
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: !is3Col
                                              ? Colors.white
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          boxShadow: !is3Col
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.08),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        alignment: Alignment.center,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.view_column_rounded,
                                              size: 16,
                                              color: !is3Col
                                                  ? const Color(0xFF1E293B)
                                                  : const Color(0xFF64748B),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '2 Grid (Default)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: !is3Col
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: !is3Col
                                                    ? const Color(0xFF1E293B)
                                                    : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        AppGridSettings.setColumnCount(3);
                                      },
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: is3Col
                                              ? const Color(0xFF4F46E5)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          boxShadow: is3Col
                                              ? [
                                                  BoxShadow(
                                                    color:
                                                        const Color(0xFF4F46E5)
                                                            .withValues(
                                                      alpha: 0.28,
                                                    ),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        alignment: Alignment.center,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.grid_view_rounded,
                                              size: 16,
                                              color: is3Col
                                                  ? Colors.white
                                                  : const Color(0xFF64748B),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '3 Grid',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: is3Col
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: is3Col
                                                    ? Colors.white
                                                    : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
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
                  },
                ),
              ),

              const Spacer(),

              // 4. Logout Option (Card Style)
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFEE2E2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFDC2626),
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Logout',
                    style: TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFF87171),
                    size: 20,
                  ),
                  onTap: () async {
                    AttendanceManager.instance.stopForegroundWatcher();
                    const storage = FlutterSecureStorage();
                    await storage.deleteAll();

                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const LoginPage(),
                        ),
                        (route) => false,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: widget.body,
      bottomNavigationBar: widget.persistentFooter == null
          ? widget.bottomNavigationBar
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.bottomNavigationBar != null)
                  widget.bottomNavigationBar!,
                widget.persistentFooter!,
              ],
            ),
    );
  }
}
