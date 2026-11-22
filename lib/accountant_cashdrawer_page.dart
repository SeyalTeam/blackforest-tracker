import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AccountantCashDrawerPage extends StatefulWidget {
  const AccountantCashDrawerPage({super.key});

  @override
  State<AccountantCashDrawerPage> createState() => _AccountantCashDrawerPageState();
}

class _AccountantCashDrawerPageState extends State<AccountantCashDrawerPage> {
  bool _isLoading = true;
  bool _isAuthorized = false;
  String _printerIp = '192.168.1.100';

  @override
  void initState() {
    super.initState();
    _loadPrinterSettings();
    _checkAuthorization();
  }

  Future<void> _loadPrinterSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('accountant_printer_ip');
    if (savedIp != null && savedIp.isNotEmpty) {
      setState(() => _printerIp = savedIp);
    }
  }

  Future<void> _savePrinterIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accountant_printer_ip', ip.trim());
    setState(() => _printerIp = ip.trim());
  }

  Future<void> _checkAuthorization() async {
    setState(() => _isLoading = true);
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      final baseUrl = ApiService.baseUrl;

      final url = '$baseUrl/branches/toggle-cashdrawer-access?branchId=accountant';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _isAuthorized = data['isCashDrawerEnabled'] == true;
        });
      } else {
        setState(() {
          _isAuthorized = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking accountant drawer access: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to check authorization: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openCashDrawer() async {
    setState(() => _isLoading = true);
    try {
      final ip = _printerIp.trim();
      if (ip.isEmpty) {
        throw Exception('Printer IP is not configured. Tap the settings icon above.');
      }

      // Connect directly to the thermal printer on port 9100 via TCP socket
      final socket = await Socket.connect(
        ip,
        9100,
        timeout: const Duration(seconds: 4),
      );

      // ESC p 0 25 250 command to pop open the cash drawer
      socket.add([27, 112, 0, 25, 250]);
      await socket.flush();
      await socket.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cash drawer open command sent successfully!'),
            backgroundColor: Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error connecting to printer ($_printerIp:9100): $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showPrinterConfigDialog() {
    final controller = TextEditingController(text: _printerIp);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.print_rounded, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('Printer IP Setup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the local IP address of the receipt printer connected to the Cash Drawer (Port 9100):',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Printer IP Address',
                hintText: 'e.g. 192.168.1.100',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.router_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final newIp = controller.text.trim();
              if (newIp.isNotEmpty) {
                _savePrinterIp(newIp);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Cash Drawer',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configure Printer IP',
            onPressed: _showPrinterConfigDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Status',
            onPressed: _checkAuthorization,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0F766E)),
            )
          : !_isAuthorized
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.lock_rounded,
                            size: 64,
                            color: Colors.red.shade600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Access Denied',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Owner/Admin approval required to open the cash drawer. Please request the owner to enable access from the Admin App.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        OutlinedButton.icon(
                          onPressed: _checkAuthorization,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Check Status Again'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F766E),
                            side: const BorderSide(color: Color(0xFF0F766E)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF047857)),
                              SizedBox(width: 8),
                              Text(
                                'Access Granted by Owner',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF065F46),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),
                        Material(
                          elevation: 6,
                          shadowColor: const Color(0xFF059669).withOpacity(0.4),
                          borderRadius: BorderRadius.circular(24),
                          child: InkWell(
                            onTap: _openCashDrawer,
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              width: 260,
                              height: 180,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF059669), Color(0xFF047857)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_rounded,
                                    size: 56,
                                    color: Colors.white,
                                  ),
                                  SizedBox(height: 14),
                                  Text(
                                    'OPEN CASHDRAWER',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Printer: $_printerIp:9100',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
