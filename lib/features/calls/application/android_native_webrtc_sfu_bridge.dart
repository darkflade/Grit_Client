import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';

class AndroidNativeWebRtcSfuBridge {
  AndroidNativeWebRtcSfuBridge({
    required this.roomId,
    required this.logger,
    required this.onLocalDescription,
    required this.onIceCandidate,
    required this.onConnectionState,
    required this.onIceConnectionState,
    required this.onIceGatheringState,
    required this.onSignalingState,
    required this.onRemoteTrack,
    required this.onIceRestartNeeded,
  }) {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  static const MethodChannel _channel = MethodChannel(
    'gritos_client/native_webrtc_sfu',
  );

  final String roomId;
  final AppLogger logger;
  final void Function(String type, String sdp) onLocalDescription;
  final void Function(Map<String, dynamic>? candidate) onIceCandidate;
  final void Function(String state) onConnectionState;
  final void Function(String state) onIceConnectionState;
  final void Function(String state) onIceGatheringState;
  final void Function(String state) onSignalingState;
  final void Function(Map<String, dynamic> track) onRemoteTrack;
  final void Function(String reason) onIceRestartNeeded;

  Future<void> create({
    required Map<String, dynamic> configuration,
    required bool useCommunicationAudio,
  }) {
    return _channel.invokeMethod<void>('create', {
      'roomId': roomId,
      'configuration': configuration,
      'useCommunicationAudio': useCommunicationAudio,
    });
  }

  Future<void> startOffer(String reason) {
    return _channel.invokeMethod<void>('startOffer', {'reason': reason});
  }

  Future<void> handleRemoteDescription({
    required String type,
    required String sdp,
  }) {
    return _channel.invokeMethod<void>('handleRemoteDescription', {
      'type': type,
      'sdp': sdp,
    });
  }

  Future<void> addIceCandidate(Map<String, dynamic>? candidate) {
    return _channel.invokeMethod<void>('addIceCandidate', {
      'candidate': candidate,
    });
  }

  Future<void> setMuted(String kind, bool muted) {
    return _channel.invokeMethod<void>('setMuted', {
      'kind': kind,
      'muted': muted,
    });
  }

  Future<void> switchToRelay({
    required Map<String, dynamic> configuration,
    required String reason,
  }) {
    return _channel.invokeMethod<void>('switchToRelay', {
      'configuration': configuration,
      'reason': reason,
    });
  }

  Future<Map<String, String>> getDebugSnapshot() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'getDebugSnapshot',
    );
    if (raw == null) return const {};
    return raw.map((key, value) => MapEntry(key, value?.toString() ?? '-'));
  }

  Future<void> close() async {
    await _channel.invokeMethod<void>('close');
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleNativeEvent(MethodCall call) async {
    final data = _asMap(call.arguments);
    switch (call.method) {
      case 'onLocalDescription':
        final type = data['type'];
        final sdp = data['sdp'];
        if (type is String && sdp is String) {
          onLocalDescription(type, sdp);
        }
        break;
      case 'onIceCandidate':
        onIceCandidate(call.arguments == null ? null : data);
        break;
      case 'onConnectionState':
        final state = data['state'];
        if (state is String) onConnectionState(state);
        break;
      case 'onIceConnectionState':
        final state = data['state'];
        if (state is String) onIceConnectionState(state);
        break;
      case 'onIceGatheringState':
        final state = data['state'];
        if (state is String) onIceGatheringState(state);
        break;
      case 'onSignalingState':
        final state = data['state'];
        if (state is String) onSignalingState(state);
        break;
      case 'onTrack':
        onRemoteTrack(data);
        break;
      case 'onIceRestartNeeded':
        onIceRestartNeeded(data['reason']?.toString() ?? 'native-ice-restart');
        break;
      case 'onLog':
        _logNative(data);
        break;
      case 'onRenegotiationNeeded':
        logger.debug('native renegotiation needed');
        break;
      default:
        logger.debug(
          'unknown native WebRTC event',
          data: {'method': call.method, 'arguments': call.arguments},
        );
    }
  }

  void _logNative(Map<String, dynamic> data) {
    final message = data['message']?.toString() ?? 'native WebRTC log';
    final level = data['level']?.toString();
    switch (level) {
      case 'warn':
        logger.warn(message, data: data);
        break;
      case 'debug':
        logger.debug(message, data: data);
        break;
      case 'error':
        logger.error(message, data: data);
        break;
      default:
        logger.info(message, data: data);
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }
}
