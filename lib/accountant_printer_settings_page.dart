import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountantPrinterSettingsPage extends StatefulWidget {
  const AccountantPrinterSettingsPage({super.key});

  @override
  State<AccountantPrinterSettingsPage> createState() =>
      _AccountantPrinterSettingsPageState();
}

class _AccountantPrinterSettingsPageState
    extends State<AccountantPrinterSettingsPage> {
  // Connection type: 'wifi' or 'bluetooth'
  String _connectionType = 'wifi';

  // Wi-Fi state
  bool _isCheckingWifi = true;
  String? _deviceIp;
  String? _printerIp;
  bool _isWifiConnected = false;

  // Bluetooth state
  bool _isBluetoothOn = false;
  bool _isScanningBt = false;
  bool _isConnectingBt = false;
  bool _isBtConnected = false;
  String? _savedBtMac;
  String? _savedBtName;
  List<BluetoothInfo> _btDevices = [];
  String _btMessage = '';

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedType = prefs.getString('printer_connection_type') ?? 'wifi';

    setState(() {
      _connectionType = savedType;
      _savedBtMac = prefs.getString('bt_printer_mac');
      _savedBtName = prefs.getString('bt_printer_name');
    });

    await Future.wait([
      _loadWifiSettings(),
      _initBluetooth(),
    ]);
  }

  // ================= Wi-Fi Methods =================
  Future<void> _loadWifiSettings() async {
    setState(() => _isCheckingWifi = true);
    final prefs = await SharedPreferences.getInstance();

    String? deviceIp;
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.isNotEmpty) {
            deviceIp = addr.address;
            break;
          }
        }
        if (deviceIp != null) break;
      }
    } catch (_) {}

    final savedPrinterIp = (prefs.getString('printerIp') ??
            prefs.getString('printer_ip') ??
            prefs.getString('accountant_printer_ip') ??
            '192.168.1.100')
        .trim();

    bool isConnected = false;
    if (savedPrinterIp.isNotEmpty) {
      try {
        final socket = await Socket.connect(
          savedPrinterIp,
          9100,
          timeout: const Duration(seconds: 2),
        );
        await socket.close();
        isConnected = true;
      } catch (_) {
        isConnected = false;
      }
    }

    if (!mounted) return;
    setState(() {
      _deviceIp = deviceIp;
      _printerIp = savedPrinterIp;
      _isWifiConnected = isConnected;
      _isCheckingWifi = false;
    });
  }

  Future<void> _updateWifiPrinterIp(String ip) async {
    final cleanIp = ip.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printerIp', cleanIp);
    await prefs.setString('printer_ip', cleanIp);
    await prefs.setString('accountant_printer_ip', cleanIp);
    setState(() => _printerIp = cleanIp);
    _checkWifiConnection(cleanIp);
  }

  Future<void> _checkWifiConnection(String ip) async {
    if (ip.isEmpty) return;
    try {
      final socket = await Socket.connect(
        ip,
        9100,
        timeout: const Duration(seconds: 2),
      );
      await socket.close();
      if (mounted) setState(() => _isWifiConnected = true);
    } catch (_) {
      if (mounted) setState(() => _isWifiConnected = false);
    }
  }

  // ================= Bluetooth Methods =================
  Future<void> _initBluetooth() async {
    try {
      final status = await Permission.bluetoothConnect.status;
      if (!status.isGranted) {
        await [
          Permission.bluetooth,
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
        ].request();
      }

      final isEnabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!mounted) return;
      setState(() => _isBluetoothOn = isEnabled);

      if (isEnabled) {
        await _scanBluetoothDevices();
        final isConnected = await PrintBluetoothThermal.connectionStatus;
        if (mounted) setState(() => _isBtConnected = isConnected);
      }
    } catch (e) {
      debugPrint('Error init bluetooth: $e');
    }
  }

  Future<void> _scanBluetoothDevices() async {
    if (!mounted) return;
    setState(() {
      _isScanningBt = true;
      _btMessage = 'Scanning paired Bluetooth devices...';
    });

    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths.timeout(
        const Duration(seconds: 5),
        onTimeout: () => [],
      );

      if (!mounted) return;
      setState(() {
        _btDevices = devices;
        _isScanningBt = false;
        _btMessage = devices.isEmpty
            ? 'No paired devices found. Please pair printer in phone Bluetooth settings first.'
            : 'Select your thermal printer:';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanningBt = false;
        _btMessage = 'Scan error: $e';
      });
    }
  }

  Future<void> _connectBluetoothDevice(BluetoothInfo device) async {
    if (_isConnectingBt) return;
    setState(() {
      _isConnectingBt = true;
      _btMessage = 'Connecting to ${device.name}...';
    });

    try {
      await PrintBluetoothThermal.disconnect;
      await Future.delayed(const Duration(milliseconds: 500));

      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: device.macAdress,
      );

      if (!mounted) return;
      if (connected) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bt_printer_mac', device.macAdress);
        await prefs.setString('bt_printer_name', device.name);
        await prefs.setString('printer_connection_type', 'bluetooth');

        setState(() {
          _isBtConnected = true;
          _savedBtMac = device.macAdress;
          _savedBtName = device.name;
          _connectionType = 'bluetooth';
          _btMessage = 'Connected to ${device.name}';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device.name}'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      } else {
        setState(() {
          _isBtConnected = false;
          _btMessage = 'Failed to connect. Make sure printer is ON and paired.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection failed. Turn printer ON and retry.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _btMessage = 'Error connecting: $e');
    } finally {
      if (mounted) setState(() => _isConnectingBt = false);
    }
  }

  // ================= Test Ping (Prints Test Slip) =================
  Future<void> _handleTestPing() async {
    // Generate ESC/POS bytes for "Test Ping" text print (NOT opening drawer)
    final List<int> bytes = [];
    // Reset/Initialize printer: ESC @
    bytes.addAll([27, 64]);
    // Align center: ESC a 1
    bytes.addAll([27, 97, 1]);
    // Bold on: ESC E 1
    bytes.addAll([27, 69, 1]);
    bytes.addAll(utf8.encode("\n--- TEST PING ---\n"));
    bytes.addAll(utf8.encode("PRINTER WORKING\n"));
    // Bold off: ESC E 0
    bytes.addAll([27, 69, 0]);
    bytes.addAll(utf8.encode("--------------------------------\n\n\n\n"));
    // Paper feed: ESC d 3
    bytes.addAll([27, 100, 3]);

    if (_connectionType == 'bluetooth') {
      try {
        final isConnected = await PrintBluetoothThermal.connectionStatus;
        if (!isConnected && _savedBtMac != null) {
          await PrintBluetoothThermal.connect(macPrinterAddress: _savedBtMac!);
        }

        final success = await PrintBluetoothThermal.writeBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success
                  ? 'Test Ping sent via Bluetooth! (Printer Working)'
                  : 'Failed to write to Bluetooth printer.'),
              backgroundColor: success ? const Color(0xFF16A34A) : Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bluetooth Print Error: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } else {
      // Wi-Fi / IP test ping
      final ip = _printerIp?.trim() ?? '';
      if (ip.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a Printer IP address.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      try {
        final socket = await Socket.connect(
          ip,
          9100,
          timeout: const Duration(seconds: 4),
        );
        socket.add(bytes);
        await socket.flush();
        await socket.close();

        if (mounted) {
          setState(() => _isWifiConnected = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Test Ping printed successfully! (Printer Working)'),
              backgroundColor: Color(0xFF16A34A),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isWifiConnected = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to print to $ip:9100 ($e)'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  void _showEditIpDialog() {
    final controller = TextEditingController(text: _printerIp ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: Color(0xFF16A34A)),
            SizedBox(width: 8),
            Text('Edit Printer IP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the local IP address of your receipt printer (Port 9100):',
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
                prefixIcon: const Icon(Icons.print_rounded),
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
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final newIp = controller.text.trim();
              if (newIp.isNotEmpty) {
                _updateWifiPrinterIp(newIp);
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
    const primaryColor = Color(0xFF16A34A);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Printer Settings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadAllSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Selector: Bluetooth or Wi-Fi (Mirroring Branch App)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      setState(() => _connectionType = 'wifi');
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('printer_connection_type', 'wifi');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _connectionType == 'wifi' ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _connectionType == 'wifi'
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.wifi_rounded,
                            size: 20,
                            color: _connectionType == 'wifi' ? primaryColor : Colors.grey[700],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Wi-Fi Printer',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _connectionType == 'wifi' ? Colors.black87 : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      setState(() => _connectionType = 'bluetooth');
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('printer_connection_type', 'bluetooth');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _connectionType == 'bluetooth' ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _connectionType == 'bluetooth'
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_rounded,
                            size: 20,
                            color: _connectionType == 'bluetooth' ? const Color(0xFF2563EB) : Colors.grey[700],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Bluetooth Printer',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _connectionType == 'bluetooth' ? Colors.black87 : Colors.grey[700],
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
          const SizedBox(height: 20),

          // 2. Active Mode Details
          if (_connectionType == 'wifi') ...[
            // Wi-Fi Connection Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isWifiConnected
                              ? primaryColor.withOpacity(0.12)
                              : Colors.red.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isWifiConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                          color: _isWifiConnected ? primaryColor : Colors.red,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isWifiConnected ? 'Wi-Fi Connected' : 'Wi-Fi Disconnected',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isWifiConnected
                                  ? 'Thermal printer reachable at port 9100'
                                  : 'Unable to connect to printer IP',
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.phone_android_rounded, 'Device IP', _deviceIp ?? 'Disconnected'),
                  const Divider(height: 28),
                  InkWell(
                    onTap: _showEditIpDialog,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.print_rounded, size: 20, color: Colors.black87),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Printer IP',
                                style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                _printerIp ?? 'Not Set (Tap to edit)',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          color: primaryColor,
                          onPressed: _showEditIpDialog,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Bluetooth Connection Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isBtConnected
                              ? const Color(0xFF2563EB).withOpacity(0.12)
                              : Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.bluetooth_connected_rounded,
                          color: _isBtConnected ? const Color(0xFF2563EB) : Colors.grey,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isBtConnected ? 'Bluetooth Connected' : 'Bluetooth Printer',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _savedBtName != null && _savedBtName!.isNotEmpty
                                  ? _savedBtName!
                                  : (_isBluetoothOn ? 'Select device to connect' : 'Bluetooth is turned OFF'),
                              style: TextStyle(
                                fontSize: 13,
                                color: _isBtConnected ? const Color(0xFF2563EB) : Colors.grey[600],
                                fontWeight: _isBtConnected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: _isScanningBt
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded),
                        onPressed: _scanBluetoothDevices,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    _btMessage.isNotEmpty ? _btMessage : 'Paired Devices:',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (_btDevices.isEmpty && !_isScanningBt)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'No paired devices. Pair your Bluetooth printer in phone settings first.',
                          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._btDevices.map((device) {
                      final isCurrent = _savedBtMac == device.macAdress;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.print_rounded,
                          color: isCurrent ? const Color(0xFF2563EB) : Colors.grey[600],
                        ),
                        title: Text(
                          device.name.isNotEmpty ? device.name : 'Unknown Printer',
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent ? const Color(0xFF2563EB) : Colors.black87,
                          ),
                        ),
                        subtitle: Text(device.macAdress, style: const TextStyle(fontSize: 11)),
                        trailing: isCurrent && _isBtConnected
                            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20)
                            : OutlinedButton(
                                onPressed: _isConnectingBt ? null : () => _connectBluetoothDevice(device),
                                child: const Text('Connect', style: TextStyle(fontSize: 12)),
                              ),
                      );
                    }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // 3. Test Ping Button Only (Prints Test Ping / Printer Working text on slip)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
            ),
            onPressed: _handleTestPing,
            icon: const Icon(Icons.receipt_long_rounded, size: 22),
            label: const Text(
              'Test Ping',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Prints "Test Ping - Printer Working" on receipt paper. Cash Drawer will not open.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ],
        ),
      ],
    );
  }
}
