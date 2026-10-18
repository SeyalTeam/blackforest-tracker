import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login.dart';
import 'home.dart';
import 'notification_service.dart';
import 'background_service.dart';
import 'tracker_live_call_service.dart';
import 'tracker_realtime_service.dart';
import 'tracker_contact_book_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  await initializeService();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription? _notificationSubscription;
  bool? _isLoggedIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TrackerLiveCallService.instance.init(_navigatorKey);
    TrackerRealtimeService.instance.connect();

    _notificationSubscription = NotificationService().onNotificationClick.listen((payload) {
      if (payload != null && payload.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationClick(payload);
        });
      }
    });

    _checkInitialNotification();
    _checkLoginStatus();
  }

  Future<void> _checkInitialNotification() async {
    try {
      final details = await NotificationService()
          .flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        final payload = details?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleNotificationClick(payload);
          });
        }
      }
    } catch (e) {
      debugPrint('main: error checking initial notification: $e');
    }
  }

  void _handleNotificationClick(String payload) {
    final trimmedPayload = payload.trim();
    if (trimmedPayload.isEmpty) return;

    final context = _navigatorKey.currentContext;
    if (context != null) {
      if (trimmedPayload == 'call_incoming' || trimmedPayload.startsWith('call_')) {
        if (TrackerLiveCallService.instance.callState != TrackerCallState.idle) {
          TrackerLiveCallService.instance.showIncomingCallScreen();
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const TrackerContactBookPage(
                initialTab: TrackerContactBookTab.allCalls,
              ),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      TrackerRealtimeService.instance.connect();
    }
  }

  Future<void> _checkLoginStatus() async {
    const storage = FlutterSecureStorage();
    String? isLoggedIn = await storage.read(key: 'isLoggedIn');

    if (mounted) {
      setState(() {
        _isLoggedIn = isLoggedIn == 'true';
      });
      if (_isLoggedIn == true) {
        TrackerRealtimeService.instance.connect();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoggedIn == null) {
      return MaterialApp(
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Tracker App',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: _isLoggedIn! ? const HomeScreen() : const LoginPage(),
    );
  }
}
