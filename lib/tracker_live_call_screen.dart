import 'dart:async';
import 'package:flutter/material.dart';
import 'tracker_live_call_service.dart';

class TrackerLiveCallScreen extends StatefulWidget {
  final String callerName;

  const TrackerLiveCallScreen({
    super.key,
    required this.callerName,
  });

  @override
  State<TrackerLiveCallScreen> createState() => _TrackerLiveCallScreenState();
}

class _TrackerLiveCallScreenState extends State<TrackerLiveCallScreen>
    with SingleTickerProviderStateMixin {
  late final TrackerLiveCallService _callService;
  late final AnimationController _pulseController;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _callService = TrackerLiveCallService.instance;
    _callService.addListener(_handleCallStateChanged);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    final state = _callService.callState;
    if (state == TrackerCallState.ended ||
        state == TrackerCallState.declined ||
        state == TrackerCallState.busy ||
        state == TrackerCallState.offline ||
        state == TrackerCallState.error) {
      _autoCloseTimer = Timer(const Duration(milliseconds: 2800), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _pulseController.dispose();
    _callService.removeListener(_handleCallStateChanged);
    super.dispose();
  }

  void _handleCallStateChanged() {
    if (!mounted) return;
    setState(() {});

    final state = _callService.callState;
    if (state == TrackerCallState.ended ||
        state == TrackerCallState.declined ||
        state == TrackerCallState.busy ||
        state == TrackerCallState.offline ||
        state == TrackerCallState.error) {
      _autoCloseTimer?.cancel();
      _autoCloseTimer = Timer(const Duration(milliseconds: 2800), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  String _getStatusText() {
    final displayName = _callService.callerName.isNotEmpty
        ? _callService.callerName
        : (widget.callerName.isNotEmpty ? widget.callerName : 'Staff');

    if (!_callService.isOutgoing && _callService.callState == TrackerCallState.ringing) {
      return 'Incoming Call from $displayName...';
    }
    switch (_callService.callState) {
      case TrackerCallState.idle:
      case TrackerCallState.connecting:
        return _callService.isOutgoing ? 'Calling $displayName...' : 'Connecting...';
      case TrackerCallState.ringing:
        return _callService.isOutgoing ? 'Ringing...' : 'Incoming Audio Call...';
      case TrackerCallState.connected:
        return _callService.formattedDuration;
      case TrackerCallState.ended:
        return _callService.errorMessage ?? 'Call ended';
      case TrackerCallState.declined:
        return _callService.errorMessage ?? 'Call declined by $displayName';
      case TrackerCallState.busy:
        return _callService.errorMessage ?? '$displayName line is busy';
      case TrackerCallState.offline:
        return _callService.errorMessage ?? '$displayName is currently offline';
      case TrackerCallState.error:
        return _callService.errorMessage ?? 'Call failed';
    }
  }

  Color _getStatusColor() {
    switch (_callService.callState) {
      case TrackerCallState.connected:
        return const Color(0xFF25D366);
      case TrackerCallState.ended:
      case TrackerCallState.declined:
      case TrackerCallState.busy:
      case TrackerCallState.offline:
      case TrackerCallState.error:
        return const Color(0xFFF87171);
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _callService.callState;
    final isConnected = state == TrackerCallState.connected;
    final isRinging = state == TrackerCallState.ringing;
    final showAnswerDecline = isRinging && !_callService.isOutgoing;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (showAnswerDecline) {
          await _callService.declineCall();
          if (nav.canPop()) {
            nav.pop();
          }
        } else if (isConnected) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF182229),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'End Live Call?',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                'Do you want to hang up this live call?',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Stay', style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('End Call', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          );
          if (shouldExit == true) {
            await _callService.endCall();
            if (nav.canPop()) {
              nav.pop();
            }
          }
        } else {
          await _callService.endCall();
          if (nav.canPop()) {
            nav.pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF111B21),
        body: SafeArea(
          child: Column(
            children: [
              // Header bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                      onPressed: () async {
                        if (showAnswerDecline) {
                          await _callService.declineCall();
                        } else if (isConnected) {
                          await _callService.endCall();
                        } else {
                          await _callService.endCall();
                        }
                        if (!context.mounted) return;
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                    Row(
                      children: [
                        Icon(
                          isConnected ? Icons.lock_outline_rounded : Icons.shield_outlined,
                          size: 15,
                          color: isConnected ? const Color(0xFF25D366) : Colors.white38,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isConnected ? 'End-to-End Encrypted' : 'Secured Audio',
                          style: TextStyle(
                            fontSize: 12,
                            color: isConnected ? const Color(0xFF25D366) : Colors.white38,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              const Spacer(),

              // Center Avatar with Pulsing Rings
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale = isRinging || state == TrackerCallState.connecting
                          ? 1.0 + (_pulseController.value * 0.18)
                          : 1.0;
                      final opacity = isRinging || state == TrackerCallState.connecting
                          ? (1.0 - _pulseController.value).clamp(0.0, 1.0)
                          : 0.0;
                      return Container(
                        width: 148 * scale,
                        height: 148 * scale,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0F766E).withValues(alpha: opacity * 0.28),
                        ),
                      );
                    },
                  ),
                  Container(
                    width: 114,
                    height: 114,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isConnected
                            ? [const Color(0xFF16A34A), const Color(0xFF0F766E)]
                            : [const Color(0xFF0F766E), const Color(0xFF0284C7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isConnected
                              ? const Color(0xFF16A34A).withValues(alpha: 0.35)
                              : Colors.black45,
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _callService.callerName.isNotEmpty
                            ? _callService.callerName[0].toUpperCase()
                            : (widget.callerName.isNotEmpty ? widget.callerName[0].toUpperCase() : '?'),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Caller Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _callService.callerName.isNotEmpty
                      ? _callService.callerName
                      : (widget.callerName.isNotEmpty ? widget.callerName : 'Staff'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _callService.callerRole.isNotEmpty
                    ? _callService.callerRole.toUpperCase()
                    : 'STAFF LIVE CALL',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF25D366),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              // Call Status / Duration
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _getStatusText(),
                  key: ValueKey(_getStatusText()),
                  style: TextStyle(
                    fontSize: isConnected ? 20 : 16,
                    fontWeight: isConnected ? FontWeight.w600 : FontWeight.normal,
                    color: _getStatusColor(),
                    letterSpacing: 0.4,
                  ),
                ),
              ),

              const Spacer(),

              // Live audio streaming indicator badge when connected
              if (isConnected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF25D366),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Live Audio Streaming',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Call Controls Row
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF182229),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white10),
                ),
                child: showAnswerDecline
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Decline Call Button
                          GestureDetector(
                            onTap: () async {
                              final nav = Navigator.of(context);
                              await _callService.declineCall();
                              if (nav.canPop()) {
                                nav.pop();
                              }
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEA4335),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x60EA4335),
                                        blurRadius: 16,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
                                ),
                                const SizedBox(height: 8),
                                const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          ),

                          // Answer Call Button
                          GestureDetector(
                            onTap: () async {
                              await _callService.acceptCall();
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF25D366),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x6025D366),
                                        blurRadius: 16,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.call_rounded, color: Colors.white, size: 30),
                                ),
                                const SizedBox(height: 8),
                                const Text('Answer', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Speaker Toggle
                          GestureDetector(
                            onTap: isConnected ? _callService.toggleSpeaker : null,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _callService.isSpeakerOn
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                              child: Icon(
                                _callService.isSpeakerOn
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_down_rounded,
                                color: _callService.isSpeakerOn ? const Color(0xFF25D366) : Colors.white70,
                                size: 24,
                              ),
                            ),
                          ),

                          // Mute Toggle
                          GestureDetector(
                            onTap: isConnected ? _callService.toggleMute : null,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _callService.isMuted
                                    ? Colors.redAccent.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                              child: Icon(
                                _callService.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                color: _callService.isMuted ? Colors.redAccent : Colors.white70,
                                size: 24,
                              ),
                            ),
                          ),

                          // End Call Button
                          GestureDetector(
                            onTap: () async {
                              final nav = Navigator.of(context);
                              await _callService.endCall();
                              if (nav.canPop()) {
                                nav.pop();
                              }
                            },
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEA4335),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x60EA4335),
                                    blurRadius: 16,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
