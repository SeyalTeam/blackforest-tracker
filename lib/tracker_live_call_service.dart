import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'tracker_call_history_service.dart';
import 'tracker_live_call_screen.dart';
import 'tracker_realtime_service.dart';

enum TrackerCallState {
  idle,
  connecting,
  ringing,
  connected,
  ended,
  declined,
  busy,
  offline,
  error,
}

class TrackerLiveCallService extends ChangeNotifier {
  static final TrackerLiveCallService instance = TrackerLiveCallService._internal();
  TrackerLiveCallService._internal();

  GlobalKey<NavigatorState>? _navigatorKey;
  StreamSubscription? _signalSub;
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  Timer? _autoCleanupTimer;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  TrackerCallState _callState = TrackerCallState.idle;
  TrackerCallState get callState => _callState;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _currentCallId;
  String? get currentCallId => _currentCallId;

  String? _callerUserId;
  String? get callerUserId => _callerUserId;

  String _callerName = 'Staff';
  String get callerName => _callerName;

  String _callerRole = 'Staff';
  String get callerRole => _callerRole;

  dynamic _pendingOfferSdp;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  bool _isOutgoing = false;
  bool get isOutgoing => _isOutgoing;

  Timer? _durationTimer;
  int _durationSeconds = 0;
  int get durationSeconds => _durationSeconds;

  String get formattedDuration {
    final minutes = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _signalSub?.cancel();
    _signalSub = TrackerRealtimeService.instance.onCallSignal.listen(
      _handleCallSignal,
      onError: (err) {
        debugPrint('TrackerLiveCallService: signal stream error: $err');
      },
    );
  }

  Future<void> _handleCallSignal(Map<String, dynamic> message) async {
    String myUserId = '';
    try {
      const storage = FlutterSecureStorage();
      myUserId = (await storage.read(key: 'userId') ?? '').trim();
    } catch (_) {}
    if (myUserId.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      myUserId = (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
    }

    final signalType = message['signalType']?.toString();
    final callId = message['callId']?.toString();
    final senderId = message['senderId']?.toString();
    final senderName = message['senderName']?.toString() ?? message['callerName']?.toString() ?? 'Staff';
    final senderRole = message['senderRole']?.toString() ?? message['callerRole']?.toString() ?? 'Staff';

    // Discard signals not intended for us
    final targetUserId = (message['targetUserId'] ?? message['recipientUserId'])?.toString().trim();
    if (targetUserId != null && targetUserId.isNotEmpty && myUserId.isNotEmpty && targetUserId != myUserId) {
      return;
    }

    if (signalType == 'offer') {
      if (_callState != TrackerCallState.idle) {
        if (senderId != null) {
          TrackerRealtimeService.instance.sendJsonMessage({
            'action': 'call_signal',
            'callId': callId,
            'signalType': 'busy',
            'targetUserId': senderId,
          });
        }
        return;
      }

      _autoCleanupTimer?.cancel();
      _isOutgoing = false;
      _currentCallId = callId;
      _callerUserId = senderId;
      _callerName = senderName;
      _callerRole = senderRole;
      _pendingOfferSdp = message['sdp'];
      _callState = TrackerCallState.ringing;
      _errorMessage = null;
      _durationSeconds = 0;
      _isMuted = false;
      _isSpeakerOn = false;
      notifyListeners();

      if (senderId != null) {
        TrackerRealtimeService.instance.sendJsonMessage({
          'action': 'call_signal',
          'callId': callId,
          'signalType': 'ringing',
          'targetUserId': senderId,
        });
      }

      await _startRingtone();

      try {
        await NotificationService().showNotification(
          id: 9992,
          title: 'Incoming Call from $senderName',
          body: '$senderRole is calling you live. Tap to answer.',
          payload: 'call_incoming',
        );
      } catch (_) {}

      unawaited(TrackerCallHistoryService.recordVoiceCall(
        callId: callId ?? 'call_${DateTime.now().millisecondsSinceEpoch}',
        callerName: senderName,
        callerRole: senderRole,
        callerUserId: senderId,
        status: 'missed',
      ));

      _showIncomingCallScreen();
    } else if (signalType == 'ringing') {
      if (_currentCallId == callId && _callState == TrackerCallState.connecting) {
        _callState = TrackerCallState.ringing;
        notifyListeners();
      }
    } else if (signalType == 'answer') {
      if (_currentCallId == callId) {
        await _handleRemoteAnswer(message['sdp']);
      }
    } else if (signalType == 'ice_candidate') {
      if (_currentCallId == callId) {
        await _handleRemoteIceCandidate(message['candidate']);
      }
    } else if (signalType == 'reject') {
      if (_currentCallId == callId || _callState != TrackerCallState.idle) {
        await _stopRingtone();
        _callState = TrackerCallState.declined;
        _errorMessage = 'Call declined by $_callerName';
        notifyListeners();
        if (_currentCallId != null) {
          unawaited(TrackerCallHistoryService.updateVoiceCallStatus(
            callId: _currentCallId!,
            status: 'declined',
          ));
        }
        _scheduleAutoCleanup();
      }
    } else if (signalType == 'busy') {
      if (_currentCallId == callId || _callState != TrackerCallState.idle) {
        await _stopRingtone();
        _callState = TrackerCallState.busy;
        _errorMessage = '$_callerName line is busy';
        notifyListeners();
        if (_currentCallId != null) {
          unawaited(TrackerCallHistoryService.updateVoiceCallStatus(
            callId: _currentCallId!,
            status: 'missed',
          ));
        }
        _scheduleAutoCleanup();
      }
    } else if (signalType == 'user_offline') {
      if (_isOutgoing &&
          (_currentCallId == callId ||
              _callState == TrackerCallState.connecting ||
              _callState == TrackerCallState.ringing)) {
        await _stopRingtone();
        _callState = TrackerCallState.offline;
        _errorMessage = '$_callerName is currently offline';
        notifyListeners();
        if (_currentCallId != null) {
          unawaited(TrackerCallHistoryService.updateVoiceCallStatus(
            callId: _currentCallId!,
            status: 'missed',
          ));
        }
        _scheduleAutoCleanup();
      }
    } else if (signalType == 'end') {
      if (_currentCallId == callId || _callState != TrackerCallState.idle) {
        await _stopRingtone();
        final wasConnected = _durationSeconds > 0;
        _callState = TrackerCallState.ended;
        _errorMessage = 'Call ended';
        notifyListeners();
        if (_currentCallId != null) {
          unawaited(TrackerCallHistoryService.updateVoiceCallStatus(
            callId: _currentCallId!,
            status: wasConnected ? 'accepted' : 'missed',
            durationSeconds: _durationSeconds,
          ));
        }
        _scheduleAutoCleanup();
      }
    }
  }

  Future<void> _startRingtone() async {
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(AssetSource('sounds/table.mp3'));
    } catch (_) {
      try {
        await _ringtonePlayer.play(AssetSource('sounds/alert.wav'));
      } catch (_) {}
    }
  }

  Future<void> _stopRingtone() async {
    try {
      await _ringtonePlayer.stop();
    } catch (_) {}
  }

  void _showIncomingCallScreen() {
    final navContext = _navigatorKey?.currentContext;
    if (navContext == null) return;

    Navigator.of(navContext).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => TrackerLiveCallScreen(callerName: _callerName),
      ),
    );
  }

  void showIncomingCallScreen() => _showIncomingCallScreen();

  Future<void> acceptCall() async {
    await _stopRingtone();
    _callState = TrackerCallState.connecting;
    notifyListeners();

    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        await declineCall();
        return;
      }

      await Helper.setSpeakerphoneOn(false);

      _peerConnection = await createPeerConnection(_iceConfig);

      final constraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      for (final track in _localStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && _callerUserId != null) {
          TrackerRealtimeService.instance.sendJsonMessage({
            'action': 'call_signal',
            'callId': _currentCallId,
            'signalType': 'ice_candidate',
            'targetUserId': _callerUserId,
            'candidate': candidate.toMap(),
          });
        }
      };

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _applyAudioRouting();
          notifyListeners();
        }
      };

      _peerConnection!.onConnectionState = (state) {
        debugPrint('TrackerLiveCallService: connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _onConnected();
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          if (_callState == TrackerCallState.connected) {
            endCall();
          }
        }
      };

      if (_pendingOfferSdp != null) {
        final sdpMap = _pendingOfferSdp is Map
            ? Map<String, dynamic>.from(_pendingOfferSdp)
            : jsonDecode(_pendingOfferSdp.toString());
        final description = RTCSessionDescription(
          sdpMap['sdp']?.toString() ?? '',
          sdpMap['type']?.toString() ?? 'offer',
        );
        await _peerConnection!.setRemoteDescription(description);
      }

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(answer);

      String myName = 'Staff';
      String myRole = 'staff';
      try {
        const storage = FlutterSecureStorage();
        myName = (await storage.read(key: 'userName') ?? '').trim();
        myRole = (await storage.read(key: 'userRole') ?? 'staff').trim();
      } catch (_) {}

      TrackerRealtimeService.instance.sendJsonMessage({
        'action': 'call_signal',
        'callId': _currentCallId,
        'signalType': 'answer',
        'targetUserId': _callerUserId,
        'sdp': answer.toMap(),
        'callerName': myName.isNotEmpty ? myName : 'Staff',
        'callerRole': myRole.isNotEmpty ? myRole : 'staff',
      });

      _onConnected();
    } catch (e) {
      debugPrint('TrackerLiveCallService: error accepting call: $e');
      await declineCall();
    }
  }

  Future<void> _handleRemoteIceCandidate(dynamic candidateData) async {
    if (_peerConnection == null || candidateData == null) return;
    try {
      final cMap = candidateData is Map
          ? Map<String, dynamic>.from(candidateData)
          : jsonDecode(candidateData.toString());
      final candidate = RTCIceCandidate(
        cMap['candidate']?.toString(),
        cMap['sdpMid']?.toString(),
        cMap['sdpMLineIndex'] as int?,
      );
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      debugPrint('TrackerLiveCallService: error adding ice candidate: $e');
    }
  }

  Future<void> _handleRemoteAnswer(dynamic sdpData) async {
    if (_peerConnection == null || sdpData == null) return;
    try {
      final sdpMap = sdpData is Map ? Map<String, dynamic>.from(sdpData) : jsonDecode(sdpData.toString());
      final description = RTCSessionDescription(
        sdpMap['sdp']?.toString() ?? '',
        sdpMap['type']?.toString() ?? 'answer',
      );
      await _peerConnection!.setRemoteDescription(description);
      _onConnected();
    } catch (e) {
      debugPrint('TrackerLiveCallService: error setting remote answer: $e');
    }
  }

  Future<void> startCallToUser({
    required String targetUserId,
    required String targetName,
    String targetRole = 'Staff',
  }) async {
    if (_callState != TrackerCallState.idle) return;

    String myUserId = '';
    String myName = 'Staff';
    String myRole = 'staff';
    try {
      const storage = FlutterSecureStorage();
      myUserId = (await storage.read(key: 'userId') ?? '').trim();
      myName = (await storage.read(key: 'userName') ?? '').trim();
      myRole = (await storage.read(key: 'userRole') ?? 'staff').trim();
    } catch (_) {}

    if (targetUserId.isEmpty || targetUserId == myUserId) {
      throw Exception('Target contact is unavailable.');
    }

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      debugPrint('TrackerLiveCallService: microphone permission denied');
      return;
    }

    _autoCleanupTimer?.cancel();
    _isOutgoing = true;
    _currentCallId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    _callerUserId = targetUserId;
    _callerName = targetName;
    _callerRole = targetRole;
    _callState = TrackerCallState.connecting;
    _errorMessage = null;
    _durationSeconds = 0;
    _isMuted = false;
    _isSpeakerOn = false;
    notifyListeners();

    _showIncomingCallScreen();

    unawaited(TrackerCallHistoryService.recordVoiceCall(
      callId: _currentCallId!,
      callerName: targetName,
      callerRole: targetRole,
      callerUserId: targetUserId,
      status: 'missed',
      direction: 'outgoing',
    ));

    try {
      await Helper.setSpeakerphoneOn(false);

      _peerConnection = await createPeerConnection(_iceConfig);

      final constraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      for (final track in _localStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          TrackerRealtimeService.instance.sendJsonMessage({
            'action': 'call_signal',
            'callId': _currentCallId,
            'signalType': 'ice_candidate',
            'targetUserId': targetUserId,
            'candidate': candidate.toMap(),
          });
        }
      };

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _applyAudioRouting();
          notifyListeners();
        }
      };

      _peerConnection!.onConnectionState = (state) {
        debugPrint('TrackerLiveCallService: connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _onConnected();
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          if (_callState == TrackerCallState.connected) {
            endCall();
          }
        }
      };

      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(offer);

      TrackerRealtimeService.instance.sendJsonMessage({
        'action': 'call_signal',
        'callId': _currentCallId,
        'signalType': 'offer',
        'targetUserId': targetUserId,
        'sdp': offer.toMap(),
        'callerName': myName.isNotEmpty ? myName : 'Staff',
        'callerRole': myRole.isNotEmpty ? myRole : 'staff',
      });
    } catch (e) {
      debugPrint('TrackerLiveCallService: error starting call to user: $e');
      _callState = TrackerCallState.error;
      _errorMessage = 'Call failed to connect';
      notifyListeners();
      _scheduleAutoCleanup();
    }
  }

  void _onConnected() {
    if (_callState == TrackerCallState.connected) return;
    _callState = TrackerCallState.connected;
    _errorMessage = null;
    _isSpeakerOn = false;
    _durationSeconds = 0;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds++;
      notifyListeners();
    });

    if (_currentCallId != null) {
      unawaited(TrackerCallHistoryService.updateVoiceCallStatus(
        callId: _currentCallId!,
        status: 'accepted',
      ));
    }

    _applyAudioRouting();
    notifyListeners();
  }

  Future<void> declineCall() async {
    await _stopRingtone();

    if (_callerUserId != null && _currentCallId != null) {
      TrackerRealtimeService.instance.sendJsonMessage({
        'action': 'call_signal',
        'callId': _currentCallId,
        'signalType': 'reject',
        'targetUserId': _callerUserId,
      });
    }

    if (_currentCallId != null) {
      unawaited(TrackerCallHistoryService.updateVoiceCallStatus(
        callId: _currentCallId!,
        status: 'declined',
      ));
    }

    _callState = TrackerCallState.declined;
    _errorMessage = 'Call declined';
    notifyListeners();
    _cleanupWebRTC();
    _scheduleAutoCleanup();
  }

  Future<void> endCall() async {
    await _stopRingtone();
    _durationTimer?.cancel();

    if (_callerUserId != null && _currentCallId != null) {
      TrackerRealtimeService.instance.sendJsonMessage({
        'action': 'call_signal',
        'callId': _currentCallId,
        'signalType': 'end',
        'targetUserId': _callerUserId,
        'durationSeconds': _durationSeconds,
      });
    }

    final wasConnected = _durationSeconds > 0;
    if (_currentCallId != null) {
      unawaited(TrackerCallHistoryService.updateVoiceCallStatus(
        callId: _currentCallId!,
        status: wasConnected ? 'accepted' : 'missed',
        durationSeconds: _durationSeconds,
      ));
    }

    _callState = TrackerCallState.ended;
    _errorMessage = 'Call ended';
    notifyListeners();
    _cleanupWebRTC();
    _scheduleAutoCleanup();
  }

  Future<void> toggleMute() async {
    if (_localStream == null) return;
    _isMuted = !_isMuted;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
    notifyListeners();
  }

  void _applyAudioRouting() {
    Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  void _cleanupWebRTC() {
    _durationTimer?.cancel();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;

    _remoteStream?.getTracks().forEach((t) => t.stop());
    _remoteStream?.dispose();
    _remoteStream = null;

    _peerConnection?.close();
    _peerConnection?.dispose();
    _peerConnection = null;
    _pendingOfferSdp = null;
  }

  void _scheduleAutoCleanup() {
    _autoCleanupTimer?.cancel();
    _autoCleanupTimer = Timer(const Duration(milliseconds: 2500), () {
      reset();
    });
  }

  void reset() {
    _autoCleanupTimer?.cancel();
    _cleanupWebRTC();
    _stopRingtone();
    _callState = TrackerCallState.idle;
    _errorMessage = null;
    _currentCallId = null;
    _callerUserId = null;
    _callerName = 'Staff';
    _callerRole = 'Staff';
    _isMuted = false;
    _isSpeakerOn = false;
    _isOutgoing = false;
    _durationSeconds = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _signalSub?.cancel();
    _ringtonePlayer.dispose();
    _cleanupWebRTC();
    super.dispose();
  }
}
