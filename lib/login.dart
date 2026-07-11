import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import 'home.dart';

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
    await _fetchDynamicRanges();
    await _fetchIp();
  }

  Future<void> _fetchDynamicRanges() async {
    try {
      final res = await http.get(
        Uri.parse('https://blackforest.vseyal.com/api/branches?limit=1000'),
      );
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
      );

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
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      // Ensure Private IP is fetched before proceeding
      if (_privateIp == null) {
        await _fetchIp();
        if (_privateIp == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Working on network identification... Please try again in 2 seconds.',
                ),
              ),
            );
            setState(() => _isLoading = false);
            return;
          }
        }
      }

      try {
        // Attempt Real Login
        // Assuming 'email' is the identifier. The UI says 'Branch', but payload default is email.
        // We try sending the input as email.

        final res = await http.post(
          Uri.parse('https://blackforest.vseyal.com/api/users/login'),
          headers: {
            'Content-Type': 'application/json',
            'x-private-ip': _privateIp ?? '',
          },
          body: jsonEncode({
            'email': _branchController.text.trim().contains('@')
                ? _branchController.text.trim()
                : '${_branchController.text.trim()}@bf.com',
            'password': _passwordController.text,
            'privateIp':
                _privateIp, // Send private IP for server-side validation
          }),
        );

        if (!mounted) {
          setState(() => _isLoading = false);
          return;
        }

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final token = data['token'];
          final user = data['user'] ?? {};

          setState(() => _isLoading = false);

          // FETCH FULL PROFILE to ensure nested fields like user.kitchen are populated
          Map<String, dynamic> fullUser = user;
          try {
            final profile = await ApiService.instance.fetchUserProfile();
            if (profile.isNotEmpty) fullUser = profile;
          } catch (e) {
            debugPrint('DEBUG: Failed to fetch full profile: $e');
          }

          final userRole = fullUser['role']?.toString().toLowerCase() ?? '';
          final userName = fullUser['name']?.toString() ?? '';
          final userId = (fullUser['id'] ?? fullUser['_id'])?.toString() ?? '';

          debugPrint(
            'DEBUG: Login success. Role: $userRole, Name: $userName, ID: $userId',
          );

          final isKitchen =
              fullUser['isKitchen'] == true || userRole == 'kitchen';
          final isStock =
              fullUser['isStock'] == true ||
              userRole == 'chef' ||
              userRole == 'supervisor' ||
              userRole == 'driver' ||
              userRole == 'factory';

          const storage = FlutterSecureStorage();
          await storage.write(key: 'isLoggedIn', value: 'true');
          await storage.write(key: 'token', value: token);
          await storage.write(key: 'userId', value: userId);
          await storage.write(key: 'userRole', value: userRole);
          await storage.write(key: 'userName', value: userName);
          await storage.write(key: 'userIsKitchen', value: isKitchen.toString());
          await storage.write(key: 'userIsStock', value: isStock.toString());

          if (isKitchen) {
            final branchObj = fullUser['branch'];
            final kitchenObj = fullUser['kitchen'];
            final kitchenBranches = fullUser['kitchenBranches'] as List?;

            // Extract Kitchen ID and Categories
            String kitchenId = '';
            List<String> categories = [];

            if (kitchenObj is Map) {
              kitchenId =
                  (kitchenObj['id'] ?? kitchenObj['_id'])?.toString() ?? '';
              if (kitchenObj['categories'] is List) {
                for (var c in kitchenObj['categories']) {
                  final cId =
                      (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
                  if (cId.isNotEmpty) categories.add(cId);
                }
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
              } else if (empK is String) {
                kitchenId = empK;
              }
            }

            // Branch ID extraction
            var bId =
                (branchObj is Map ? branchObj['id'] : branchObj)?.toString() ??
                '';

            // Check kitchenBranches if primary branch is missing
            if (bId.isEmpty &&
                kitchenBranches != null &&
                kitchenBranches.isNotEmpty) {
              final firstBranch = kitchenBranches.first;
              bId =
                  (firstBranch is Map ? firstBranch['id'] : firstBranch)
                      ?.toString() ??
                  '';
            }

            // Fallback for branch in employee
            if (bId.isEmpty && fullUser['employee'] is Map) {
              final emp = fullUser['employee'];
              bId =
                  (emp['branch'] is Map ? emp['branch']['id'] : emp['branch'])
                      ?.toString() ??
                  '';
            }

            debugPrint(
              'DEBUG: Extracted kitchenId: "$kitchenId", BranchId: "$bId", Categories: ${categories.length}',
            );

            await storage.write(key: 'userKitchenId', value: kitchenId);
            await storage.write(key: 'userBranchId', value: bId);
            await storage.write(
              key: 'userKitchenCategoryIds',
              value: categories.join(','),
            );
          }

          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          // Login Failed - Improved error handling
          String errorMessage =
              'Login Failed: ${res.statusCode}. Check credentials.';
          try {
            final errorData = jsonDecode(res.body);
            if (errorData['errors'] != null &&
                errorData['errors'] is List &&
                errorData['errors'].isNotEmpty) {
              errorMessage = errorData['errors'][0]['message'] ?? errorMessage;
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
