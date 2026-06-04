import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/logging/app_logger.dart';

class IceRestartController {
  IceRestartController({
    required this.roomId,
    required this.logger,
    this.disconnectedGracePeriod = const Duration(seconds: 8),
    this.restartCooldown = const Duration(seconds: 15),
  });

  final String roomId;
  final AppLogger logger;
  final Duration disconnectedGracePeriod;
  final Duration restartCooldown;

  Timer? _disconnectedTimer;
  DateTime? _lastRestartAt;
  RTCIceConnectionState? _lastState;

  void handleState(
    RTCIceConnectionState state, {
    required void Function(String reason) requestRestart,
  }) {
    _lastState = state;

    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
      case RTCIceConnectionState.RTCIceConnectionStateNew:
      case RTCIceConnectionState.RTCIceConnectionStateChecking:
        _cancelDisconnectedTimer();
        return;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        _scheduleGracefulRestart(requestRestart);
        return;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _cancelDisconnectedTimer();
        _restartIfAllowed('ice-failed', requestRestart);
        return;
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
      case RTCIceConnectionState.RTCIceConnectionStateCount:
        _cancelDisconnectedTimer();
        return;
    }
  }

  void dispose() {
    _cancelDisconnectedTimer();
  }

  void _scheduleGracefulRestart(void Function(String reason) requestRestart) {
    if (_disconnectedTimer != null) return;
    logger.warn(
      'ICE disconnected; waiting before restart',
      data: {
        'room_id': roomId,
        'grace_ms': disconnectedGracePeriod.inMilliseconds,
      },
    );
    _disconnectedTimer = Timer(disconnectedGracePeriod, () {
      _disconnectedTimer = null;
      final state = _lastState;
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _restartIfAllowed('ice-disconnected-timeout', requestRestart);
      }
    });
  }

  void _restartIfAllowed(
    String reason,
    void Function(String reason) requestRestart,
  ) {
    final now = DateTime.now();
    final lastRestartAt = _lastRestartAt;
    if (lastRestartAt != null &&
        now.difference(lastRestartAt) < restartCooldown) {
      logger.warn(
        'ICE restart skipped by cooldown',
        data: {
          'room_id': roomId,
          'reason': reason,
          'cooldown_ms': restartCooldown.inMilliseconds,
        },
      );
      return;
    }

    _lastRestartAt = now;
    requestRestart(reason);
  }

  void _cancelDisconnectedTimer() {
    _disconnectedTimer?.cancel();
    _disconnectedTimer = null;
  }
}
