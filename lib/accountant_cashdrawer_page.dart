import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'accountant_printer_settings_page.dart';

class AccountantCashDrawerPage extends StatefulWidget {
  const AccountantCashDrawerPage({super.key});

  @override
  State<AccountantCashDrawerPage> createState() => _AccountantCashDrawerPageState();
}

class _AccountantCashDrawerPageState extends State<AccountantCashDrawerPage> {
  bool _isLoading = true;
  bool _isAuthorized = false;

  String _connectionType = 'wifi'; // 'wifi' or 'bluetooth'
  String _printerIp = '192.168.1.100';
  String? _btPrinterName;
  String? _btPrinterMac;

  @override
  void initState() {
    super.initState();
    _loadPrinterSettings();
    _checkAuthorization();
  }

  Future<void> _loadPrinterSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final type = prefs.getString('printer_connection_type') ?? 'wifi';
    final savedIp = prefs.getString('printerIp') ??
        prefs.getString('printer_ip') ??
        prefs.getString('accountant_printer_ip') ??
        '192.168.1.100';
    final btName = prefs.getString('bt_printer_name');
    final btMac = prefs.getString('bt_printer_mac');

    if (mounted) {
      setState(() {
        _connectionType = type;
        _printerIp = savedIp;
        _btPrinterName = btName;
        _btPrinterMac = btMac;
      });
    }
  }

  Future<void> _openPrinterSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AccountantPrinterSettingsPage(),
      ),
    );
    _loadPrinterSettings();
  }

  Future<void> _checkAuthorization() async {
    setState(() => _isLoading = true);
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      final baseUrl = ApiService.baseUrl;

      final headers = {
        'Content-Type': 'application/json',
        'x-app-secret': 'bf_tracker_4b5c6d7e8f9a0b1c',
        'x-app-key': 'bf_tracker_4b5c6d7e8f9a0b1c',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      var response = await http.get(
        Uri.parse('$baseUrl/branches/toggle-cashdrawer-access?branchId=accountant'),
        headers: headers,
      );

      if (response.statusCode == 404 || response.statusCode != 200) {
        response = await http.get(
          Uri.parse('$baseUrl/globals/payment-settings'),
          headers: headers,
        );
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _isAuthorized = data['isCashDrawerEnabled'] == true ||
              data['isAccountantCashDrawerEnabled'] == true;
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
    final drawerBytes = [27, 112, 0, 25, 250];

    try {
      if (_connectionType == 'bluetooth') {
        if (_btPrinterMac == null || _btPrinterMac!.isEmpty) {
          throw Exception('No Bluetooth printer configured. Tap printer settings below.');
        }

        final isConnected = await PrintBluetoothThermal.connectionStatus;
        if (!isConnected) {
          await PrintBluetoothThermal.connect(macPrinterAddress: _btPrinterMac!);
        }

        final success = await PrintBluetoothThermal.writeBytes(drawerBytes);
        if (!success) {
          throw Exception('Failed to send open signal to Bluetooth printer.');
        }
      } else {
        // Wi-Fi Socket connection
        final ip = _printerIp.trim();
        if (ip.isEmpty) {
          throw Exception('Printer IP is not configured. Tap printer settings below.');
        }

        final socket = await Socket.connect(
          ip,
          9100,
          timeout: const Duration(seconds: 4),
        );
        socket.add(drawerBytes);
        await socket.flush();
        await socket.close();
      }

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
            content: Text('Error opening cash drawer: $e'),
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

  String get _displayPrinterText {
    if (_connectionType == 'bluetooth') {
      return (_btPrinterName != null && _btPrinterName!.isNotEmpty)
          ? 'Bluetooth: $_btPrinterName'
          : 'Bluetooth Printer (Not paired)';
    } else {
      return 'Wi-Fi: $_printerIp:9100';
    }
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
            icon: Icon(
              _connectionType == 'bluetooth'
                  ? Icons.bluetooth_rounded
                  : Icons.wifi_rounded,
              color: const Color(0xFF0F766E),
            ),
            tooltip: 'Printer Settings (Bluetooth / Wi-Fi)',
            onPressed: _openPrinterSettings,
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
                        InkWell(
                          onTap: _openPrinterSettings,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _connectionType == 'bluetooth'
                                      ? Icons.bluetooth_rounded
                                      : Icons.wifi_rounded,
                                  size: 16,
                                  color: const Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$_displayPrinterText (Change)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
