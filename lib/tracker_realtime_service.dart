import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrackerRealtimeService {
  static final TrackerRealtimeService _instance = TrackerRealtimeService._internal();
  static TrackerRealtimeService get instance => _instance;

  TrackerRealtimeService._internal();

  io.WebSocket? _wsSocket;
  StreamSubscription<dynamic>? _wsSocketSubscription;
  bool _wsConnecting = false;
  int _wsConnectionGeneration = 0;
  Timer? _wsReconnectTimer;

  String _wsToken = '';
  String _wsBranchId = '';
  String _currentUserId = '';

  final _callSignalController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onCallSignal => _callSignalController.stream;

  bool get isConnected => _wsSocket != null && _wsSocket!.readyState == io.WebSocket.open;

  Future<void> _loadSession() async {
    try {
      const storage = FlutterSecureStorage();
      _wsToken = (await storage.read(key: 'token') ?? '').trim();
      _wsBranchId = (await storage.read(key: 'userBranchId') ?? '').trim();
      _currentUserId = (await storage.read(key: 'userId') ?? '').trim();
    } catch (_) {}

    if (_wsToken.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _wsToken = (prefs.getString('token') ?? prefs.getString('auth_token') ?? '').trim();
        if (_wsBranchId.isEmpty) {
          _wsBranchId = (prefs.getString('branchId') ?? prefs.getString('branch') ?? '').trim();
        }
        if (_currentUserId.isEmpty) {
          _currentUserId = (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
        }
      } catch (_) {}
    }
  }

  Future<void> connect() async {
    if (_wsConnecting) return;
    if (_wsSocket != null && _wsSocket!.readyState == io.WebSocket.open) return;

    _wsReconnectTimer?.cancel();
    await _loadSession();
    if (_wsToken.isEmpty) {
      debugPrint('TrackerRealtimeService: no token found, scheduling reconnect in 4s');
      _scheduleReconnect();
      return;
    }

    _wsConnecting = true;
    try {
      final candidateHosts = <String>[
        'admin.theblackforestcakes.com',
        'blackforest.vseyal.com',
      ];

      io.WebSocket? connectedSocket;
      for (final host in candidateHosts) {
        try {
          final wsUri = Uri(scheme: 'wss', host: host, path: '/ws/v1');
          debugPrint('TrackerRealtimeService: connecting to $wsUri');
          final s = await io.WebSocket.connect(
            wsUri.toString(),
            headers: <String, dynamic>{'Authorization': 'Bearer $_wsToken'},
          ).timeout(const Duration(seconds: 6));
          connectedSocket = s;
          debugPrint('TrackerRealtimeService: connected successfully to $host');
          break;
        } catch (e) {
          debugPrint('TrackerRealtimeService: failed connecting to $host: $e');
        }
      }

      if (connectedSocket == null) {
        throw Exception('All candidate WebSocket hosts failed');
      }

      final generation = ++_wsConnectionGeneration;
      final socket = connectedSocket;

      if (generation != _wsConnectionGeneration) {
        await socket.close();
        return;
      }

      await _closeSocket();
      _wsSocket = socket;

      _wsSocketSubscription = socket.listen(
        (frame) => _handleFrame(frame, generation),
        onError: (_) => _handleClosed(generation, socket),
        onDone: () => _handleClosed(generation, socket),
        cancelOnError: false,
      );

      _sendSubscribe();
    } catch (err) {
      debugPrint('TrackerRealtimeService: connection error: $err');
      _scheduleReconnect();
    } finally {
      _wsConnecting = false;
    }
  }

  void _sendSubscribe() {
    if (_wsSocket == null || _wsSocket!.readyState != io.WebSocket.open) return;
    try {
      if (_wsBranchId.isNotEmpty) {
        _wsSocket!.add(jsonEncode({
          'action': 'subscribe',
          'branchId': _wsBranchId,
          'topic': 'kot.item-status',
        }));
      }
    } catch (_) {}
  }

  void _handleFrame(dynamic frame, int generation) {
    if (generation != _wsConnectionGeneration) return;
    try {
      final raw = frame is String ? frame : utf8.decode(frame as List<int>);
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final eventType = decoded['eventType']?.toString();

      if (eventType == 'ping') {
        try {
          _wsSocket?.add(jsonEncode({'action': 'pong'}));
        } catch (_) {}
        return;
      }

      if (eventType == 'call_signal' ||
          eventType == 'call_signal_ack' ||
          eventType == 'call_signal_nack' ||
          decoded['action'] == 'call_signal') {
        _callSignalController.add(decoded);
      }
    } catch (e) {
      debugPrint('TrackerRealtimeService: error parsing frame: $e');
    }
  }

  void _handleClosed(int generation, io.WebSocket socket) {
    if (generation != _wsConnectionGeneration) return;
    debugPrint('TrackerRealtimeService: socket closed');
    _closeSocket();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 4), () {
      connect();
    });
  }

  Future<void> _closeSocket() async {
    _wsSocketSubscription?.cancel();
    _wsSocketSubscription = null;
    try {
      await _wsSocket?.close();
    } catch (_) {}
    _wsSocket = null;
  }

  void sendJsonMessage(Map<String, dynamic> data) {
    if (_wsSocket == null || _wsSocket!.readyState != io.WebSocket.open) {
      debugPrint('TrackerRealtimeService: cannot send message - socket not open');
      connect();
      return;
    }
    try {
      _wsSocket!.add(jsonEncode(data));
    } catch (e) {
      debugPrint('TrackerRealtimeService: error sending message: $e');
    }
  }

  void dispose() {
    _wsReconnectTimer?.cancel();
    _closeSocket();
    _callSignalController.close();
  }
}
