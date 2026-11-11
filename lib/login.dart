import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io';
import 'app_http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'home.dart';
import 'geofence_util.dart';
import 'tracker_realtime_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _privateIp;
  bool _isIpAuthorized = true; // Default to true until check completes
  List<String> _dynamicAllowedRanges = [];

  static const List<String> _allowedIpRanges = [
    '157.51.21.130-157.51.21.250',
    '157.51.32.24-157.51.32.78',
  ];

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    _fetchDynamicRanges();
    _fetchIp();
    _prewarmLocationAndSettings();
  }

  Future<void> _prewarmLocationAndSettings() async {
    try {
      // Request location permission upfront as soon as the login screen appears
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      // Preload branch settings in memory in background
      GeofenceUtil.preloadSettings();
    } catch (e) {
      debugPrint('Prewarm location/settings error: $e');
    }
  }

  Future<void> _fetchDynamicRanges() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/branches?limit=1000&depth=0'),
        headers: {
          'Accept': 'application/json',
          'x-app-key': 'bf_tracker_4b5c6d7e8f9a0b1c',
          'x-app-secret': 'bf_tracker_4b5c6d7e8f9a0b1c',
        },
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] as List?;
        if (docs != null) {
          final ranges = docs
              .map((d) => d['ipAddress']?.toString().trim() ?? '')
              .where((ip) => ip.isNotEmpty)
              .toList();
          if (mounted) {
            setState(() {
              _dynamicAllowedRanges = ranges;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch dynamic ranges: $e');
    }
  }

  int _ipToLong(String ip) {
    try {
      List<int> parts = ip.split('.').map(int.parse).toList();
      return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
    } catch (e) {
      return 0;
    }
  }

  bool _checkIpInRange(String ip, String range) {
    if (!range.contains('-')) return ip == range.trim();

    List<String> parts = range.split('-').map((e) => e.trim()).toList();
    if (parts.length != 2) return false;

    int ipLong = _ipToLong(ip);
    int startLong = _ipToLong(parts[0]);
    int endLong = _ipToLong(parts[1]);

    if (ipLong == 0 || startLong == 0 || endLong == 0) return false;

    return ipLong >= startLong && ipLong <= endLong;
  }

  bool _isPrivateIpAuthorized(String? private) {
    final allRanges = [..._allowedIpRanges, ..._dynamicAllowedRanges];
    for (final range in allRanges) {
      if (private != null && _checkIpInRange(private, range)) return true;
    }
    return false;
  }

  Future<void> _fetchIp() async {
    String? private;

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      ).timeout(const Duration(seconds: 3));

      if (interfaces.isNotEmpty) {
        // Find the best local IP (prioritize common LAN ranges)
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            final ip = addr.address;
            // Prioritize standard private ranges
            if (ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                ip.startsWith('172.16.') ||
                ip.startsWith('192.0.')) {
              private = ip;
              break;
            }
            // Fallback to any non-loopback IPv4
            private ??= ip;
          }
          if (private != null) break;
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch Private IP: $e');
    }

    if (mounted) {
      setState(() {
        _privateIp = private;
        _isIpAuthorized = _isPrivateIpAuthorized(private);
      });
    }
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;

    // Check GPS service immediately before spinning loader / long network calls
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.location_off, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Location services are disabled. Please turn ON GPS.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission is required to verify branch attendance.'),
              backgroundColor: Colors.red[800],
            ),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location permission is permanently denied. Please enable in App Settings.'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch Private IP if available (with timeout)
      if (_privateIp == null) {
        await _fetchIp();
      }

      // Quick GPS capture - permission is verified, grab fast fix or last known position
      Position? loginPosition;
      try {
        loginPosition = await Geolocator.getLastKnownPosition();
        if (loginPosition == null) {
          loginPosition = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(const Duration(seconds: 3));
        }
      } catch (_) {}

      final rawInput = _branchController.text.trim();
      final emailToUse = rawInput.contains('@') ? rawInput : '$rawInput@bf.com';

      var res = await http.post(
        Uri.parse('${ApiService.baseUrl}/users/login'),
        headers: {
          'Content-Type': 'application/json',
          'x-private-ip': _privateIp ?? '',
          'x-app-secret': 'bf_tracker_4b5c6d7e8f9a0b1c',
          'x-app-key': 'bf_tracker_4b5c6d7e8f9a0b1c',
        },
        body: jsonEncode({
          'email': emailToUse,
          'password': _passwordController.text,
          'privateIp': _privateIp,
        }),
      ).timeout(const Duration(seconds: 40));

      // Fallback: If @bf.com failed and input had no @, try sending rawInput directly as identifier
      if (res.statusCode != 200 && !rawInput.contains('@')) {
        try {
          final fallbackRes = await http.post(
            Uri.parse('${ApiService.baseUrl}/users/login'),
            headers: {
              'Content-Type': 'application/json',
              'x-private-ip': _privateIp ?? '',
              'x-app-secret': 'bf_tracker_4b5c6d7e8f9a0b1c',
              'x-app-key': 'bf_tracker_4b5c6d7e8f9a0b1c',
            },
            body: jsonEncode({
              'email': rawInput,
              'password': _passwordController.text,
              'privateIp': _privateIp,
            }),
          ).timeout(const Duration(seconds: 40));
          if (fallbackRes.statusCode == 200) {
            res = fallbackRes;
          }
        } catch (_) {}
      }

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final token = (data['token'] ?? '').toString();
        final user = data['user'] ?? {};

        const storage = FlutterSecureStorage();
        final prefs = await SharedPreferences.getInstance();

        // Immediately persist token so that all subsequent requests are authenticated
        if (token.isNotEmpty) {
          await storage.write(key: 'token', value: token);
          await prefs.setString('token', token);
          await prefs.setString('auth_token', token);
        }

        // FETCH FULL PROFILE to ensure nested fields like user.kitchen are populated
        Map<String, dynamic> fullUser = user;
        try {
          final profile = await ApiService.instance.fetchUserProfile(token: token);
          if (profile.isNotEmpty) fullUser = profile;
        } catch (e) {
          debugPrint('DEBUG: Failed to fetch full profile: $e');
        }

        final userRole = fullUser['role']?.toString().toLowerCase() ?? '';
        final userName = fullUser['name']?.toString() ?? '';
        final userId = (fullUser['id'] ?? fullUser['_id'])?.toString() ?? '';

        debugPrint(
          'DEBUG: Login attempt. Role: $userRole, Name: $userName, ID: $userId',
        );

        // Block factory, admin, and superadmin roles from logging into Tracker App
        if (userRole == 'factory' || userRole == 'admin' || userRole == 'superadmin') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Access Denied: $userRole role is not permitted to access Tracker App.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // Watcher does not require branch geofence circle to login
        final isExemptFromGeofence = userRole == 'watcher';

        if (!isExemptFromGeofence) {
          if (!mounted) return;
          final geoResult = await GeofenceUtil.checkLocationAndGeofence(
            existingPosition: loginPosition,
          );
          if (!geoResult.isInside) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.location_off, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          geoResult.errorMessage ?? 'Not inside branch geofence. Login blocked.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.red[800],
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            return; // Block login if not inside branch circle
          }
        }

        final bool hasKitchenFlag = fullUser['isKitchen'] is bool;
        final bool hasStockFlag = fullUser['isStock'] is bool;

        final bool isKitchen = hasKitchenFlag
            ? (fullUser['isKitchen'] as bool)
            : (userRole == 'kitchen' || userRole == 'chef');
        final bool isStock = hasStockFlag
            ? (fullUser['isStock'] as bool)
            : (['supervisor', 'manager', 'driver'].contains(userRole) || (userRole == 'chef' && !hasKitchenFlag));

        await storage.write(key: 'isLoggedIn', value: 'true');
        await prefs.setString('isLoggedIn', 'true');
        await storage.write(key: 'token', value: token);
        await prefs.setString('token', token);
        await prefs.setString('auth_token', token);
        await storage.write(key: 'userId', value: userId);
        await prefs.setString('userId', userId);
        await storage.write(key: 'userRole', value: userRole);
        await prefs.setString('userRole', userRole);
        await storage.write(key: 'userName', value: userName);
        await prefs.setString('userName', userName);
        await storage.write(key: 'userIsKitchen', value: isKitchen.toString());
        await prefs.setString('userIsKitchen', isKitchen.toString());
        await storage.write(key: 'userIsStock', value: isStock.toString());
        await prefs.setString('userIsStock', isStock.toString());

          // Extract manager_companies (for manager role)
          if (userRole == 'manager') {
            final rawCompanies = fullUser['manager_companies'];
            final companyIds = <String>[];
            if (rawCompanies is List) {
              for (final c in rawCompanies) {
                final id = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
                if (id.isNotEmpty) companyIds.add(id);
              }
            }
            await storage.write(key: 'managerCompanyIds', value: companyIds.join(','));
            debugPrint('DEBUG: Manager company IDs stored: $companyIds');
          }

          // Extract Branch ID and Name for ALL roles (crucial for notifications filtering)
          final branchObj = fullUser['branch'];
          final kitchenBranches = fullUser['kitchenBranches'] as List?;
          var bId = (branchObj is Map ? (branchObj['id'] ?? branchObj['_id']) : branchObj)?.toString() ?? '';
          var bName = (branchObj is Map ? branchObj['name'] : null)?.toString() ?? '';
          
          if (bId.isEmpty && kitchenBranches != null && kitchenBranches.isNotEmpty) {
            final firstBranch = kitchenBranches.first;
            bId = (firstBranch is Map ? (firstBranch['id'] ?? firstBranch['_id']) : firstBranch)?.toString() ?? '';
            if (bName.isEmpty && firstBranch is Map && firstBranch['name'] != null) {
              bName = firstBranch['name'].toString();
            }
          }
          if (bId.isEmpty && fullUser['employee'] is Map) {
            final emp = fullUser['employee'];
            bId = (emp['branch'] is Map ? (emp['branch']['id'] ?? emp['branch']['_id']) : emp['branch'])?.toString() ?? '';
            if (bName.isEmpty && emp['branch'] is Map && emp['branch']['name'] != null) {
              bName = emp['branch']['name'].toString();
            }
          }

          if (bName.isEmpty) {
            bName = prefs.getString('branchName') ?? prefs.getString('lastGpsBranchName') ?? '';
          }

          await storage.write(key: 'userBranchId', value: bId);
          await storage.write(key: 'userBranchName', value: bName);
          await prefs.setString('userIsKitchen', isKitchen.toString());
          await prefs.setString('userIsStock', isStock.toString());
          if (bId.isNotEmpty) {
            await prefs.setString('branchId', bId);
            await prefs.setString('branch', bId);
          }
          if (bName.isNotEmpty) {
            await prefs.setString('branchName', bName);
          }

          if (fullUser['employee'] != null) {
            final emp = fullUser['employee'];
            final empDocId = (emp is Map ? (emp['id'] ?? emp['_id']) : emp)?.toString() ?? '';
            if (empDocId.isNotEmpty) {
              await storage.write(key: 'employeeDocId', value: empDocId);
              await prefs.setString('employee_id', empDocId);
              if (emp is Map && emp['name'] != null) {
                await prefs.setString('employee_name', emp['name'].toString());
              }
            }
          }
          

          if (isKitchen || userRole == 'chef') {
            final kitchenObj = fullUser['kitchen'];

            // Extract Kitchen ID and Categories
            String kitchenId = '';
            String kitchenName = '';
            List<String> categories = [];

            if (kitchenObj is List && kitchenObj.isNotEmpty) {
              final firstK = kitchenObj.first;
              if (firstK is Map) {
                kitchenId =
                    (firstK['id'] ?? firstK['_id'])?.toString() ?? '';
                if (firstK['name'] != null) {
                  kitchenName = firstK['name'].toString();
                }
              } else if (firstK is String) {
                kitchenId = firstK;
              }
            } else if (kitchenObj is Map) {
              kitchenId =
                  (kitchenObj['id'] ?? kitchenObj['_id'])?.toString() ?? '';
              if (kitchenObj['name'] != null) {
                kitchenName = kitchenObj['name'].toString();
              }
            } else if (kitchenObj is String) {
              kitchenId = kitchenObj;
            }

            // Fallback: Check employee collection if still needed for legacy
            if (kitchenId.isEmpty && fullUser['employee'] is Map) {
              final emp = fullUser['employee'];
              final empK = emp['kitchen'];
              if (empK is Map) {
                kitchenId = (empK['id'] ?? empK['_id'])?.toString() ?? '';
                if (kitchenName.isEmpty && empK['name'] != null) {
                  kitchenName = empK['name'].toString();
                }
              } else if (empK is String) {
                kitchenId = empK;
              }
            }

            final userCats = fullUser['categories'] as List?;
            final List<String> categoryNames = [];
            if (userCats != null && userCats.isNotEmpty) {
              for (var c in userCats) {
                final cId = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
                final cName = (c is Map ? (c['name'] ?? c['title']) : null)?.toString() ?? '';
                if (cId.isNotEmpty && !categories.contains(cId)) {
                  categories.add(cId);
                }
                if (cName.isNotEmpty && !categoryNames.contains(cName)) {
                  categoryNames.add(cName);
                }
              }
            }

            if (kitchenName.isEmpty && kitchenId.isNotEmpty) {
              try {
                final kitchenDetails = await ApiService.instance.fetchKitchenDetails(kitchenId);
                if (kitchenDetails['name'] != null) {
                  kitchenName = kitchenDetails['name'].toString();
                }
              } catch (_) {}
            }

            debugPrint(
              'DEBUG: Extracted kitchenId: "$kitchenId", KitchenName: "$kitchenName", BranchId: "$bId", Categories: ${categories.length}',
            );

            await storage.write(key: 'userKitchenId', value: kitchenId);
            if (kitchenName.isNotEmpty) {
              await storage.write(key: 'userKitchenName', value: kitchenName);
            }
            await storage.write(
              key: 'userKitchenCategoryIds',
              value: categories.join(','),
            );
            await storage.write(
              key: 'userKitchenCategoryNames',
              value: categoryNames.join(','),
            );
          }

          if (isStock || userRole == 'chef' || userRole == 'supervisor') {
            // Extract Stock Order Categories
            final userStockCats = fullUser['stockCategories'] as List?;
            final List<String> stockCategoryIds = [];
            final List<String> stockCategoryNames = [];
            if (userStockCats != null && userStockCats.isNotEmpty) {
              for (var c in userStockCats) {
                final cId = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
                final cName = (c is Map ? (c['name'] ?? c['title']) : null)?.toString() ?? '';
                if (cId.isNotEmpty && !stockCategoryIds.contains(cId)) {
                  stockCategoryIds.add(cId);
                }
                if (cName.isNotEmpty && !stockCategoryNames.contains(cName)) {
                  stockCategoryNames.add(cName);
                }
              }
            }

            await storage.write(
              key: 'userStockCategoryIds',
              value: stockCategoryIds.join(','),
            );
            await storage.write(
              key: 'userStockCategoryNames',
              value: stockCategoryNames.join(','),
            );
          }

          if (!mounted) return;
          TrackerRealtimeService.instance.connect();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          // Login Failed - Improved error handling
          debugPrint('DEBUG: Login failed status ${res.statusCode}: ${res.body}');
          String errorMessage =
              'Login Failed: ${res.statusCode}. Check credentials.';
          try {
            final errorData = jsonDecode(res.body);
            if (errorData is Map) {
              if (errorData['errors'] != null &&
                  errorData['errors'] is List &&
                  (errorData['errors'] as List).isNotEmpty) {
                final firstErr = errorData['errors'][0];
                if (firstErr is Map && firstErr['message'] != null) {
                  errorMessage = firstErr['message'].toString();
                } else if (firstErr is String) {
                  errorMessage = firstErr;
                }
              } else if (errorData['message'] != null) {
                errorMessage = errorData['message'].toString();
              } else if (errorData['error'] != null) {
                errorMessage = errorData['error'].toString();
              }
            }
          } catch (e) {
            debugPrint('Error parsing login failure response: $e');
          }

          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(errorMessage)));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
  }

  @override
  void dispose() {
    _branchController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Blackforest Tracker',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 48),
                TextFormField(
                  controller: _branchController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Login', style: TextStyle(fontSize: 18)),
                  ),
                ),
                if (_privateIp != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildIpRow(
                          Icons.lan,
                          'Private IP',
                          _privateIp!,
                          isAuthorized: _isIpAuthorized,
                        ),
                      ],
                    ),
                  ),
                  if (!_isIpAuthorized)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Unauthorized Network',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIpRow(
    IconData icon,
    String label,
    String value, {
    bool? isAuthorized,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: (isAuthorized != null && isAuthorized)
                      ? Colors.green[700]
                      : (isAuthorized != null && !isAuthorized)
                      ? Colors.red[700]
                      : Colors.grey[800],
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (isAuthorized != null)
          Icon(
            isAuthorized ? Icons.check_circle : Icons.error,
            size: 16,
            color: isAuthorized ? Colors.green : Colors.red,
          ),
      ],
    );
  }
}
