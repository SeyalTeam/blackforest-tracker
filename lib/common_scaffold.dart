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
        backgroundColor: const Color(0xFF141414),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. User Profile Area (Photo, Name, Role, ID)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF1F1F1F),
                  border: Border(
                    bottom: BorderSide(color: Colors.white10),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white12,
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
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.amber.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  _userRole.isNotEmpty
                                      ? _userRole.toUpperCase()
                                      : 'STAFF',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_userId.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              size: 15,
                              color: Colors.white60,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ID: $_userId',
                              style: const TextStyle(
                                color: Colors.white70,
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

              const SizedBox(height: 16),

              // 2. Grid Menu Option (2 or 3 Grid Switch)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ValueListenableBuilder<int>(
                  valueListenable: AppGridSettings.columnCount,
                  builder: (context, colCount, _) {
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1F1F),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.grid_view_rounded,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Grid Layout',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$colCount Columns',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Switch between 2 or 3 grid columns for both KOT and Stock Orders.',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    AppGridSettings.setColumnCount(2);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colCount == 2
                                          ? Colors.amber
                                          : const Color(0xFF2B2B2B),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.view_column_rounded,
                                          size: 17,
                                          color: colCount == 2
                                              ? Colors.black
                                              : Colors.white70,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '2 Grid (Default)',
                                          style: TextStyle(
                                            color: colCount == 2
                                                ? Colors.black
                                                : Colors.white70,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    AppGridSettings.setColumnCount(3);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colCount == 3
                                          ? Colors.amber
                                          : const Color(0xFF2B2B2B),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.grid_on_rounded,
                                          size: 17,
                                          color: colCount == 3
                                              ? Colors.black
                                              : Colors.white70,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '3 Grid',
                                          style: TextStyle(
                                            color: colCount == 3
                                                ? Colors.black
                                                : Colors.white70,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const Spacer(),

              const Divider(color: Colors.white12, height: 1),

              // 3. Logout Option
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
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
