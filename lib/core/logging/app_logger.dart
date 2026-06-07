import 'dart:convert';

import 'package:flutter/foundation.dart';

enum LogLevel {
  debug('DBG'),
  info('INF'),
  warn('WRN'),
  error('ERR');

  const LogLevel(this.label);

  final String label;
}

class AppLogger {
  const AppLogger(this.scope);

  final String scope;

  void debug(String message, {Object? data}) {
    _write(LogLevel.debug, message, data: data);
  }

  void info(String message, {Object? data}) {
    _write(LogLevel.info, message, data: data);
  }

  void warn(String message, {Object? data}) {
    _write(LogLevel.warn, message, data: data);
  }

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Object? data,
  }) {
    _write(
      LogLevel.error,
      message,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );
  }

  AppLogger child(String childScope) => AppLogger('$scope.$childScope');

  void _write(
    LogLevel level,
    String message, {
    Object? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final now = DateTime.now().toIso8601String();
    final buffer = StringBuffer('[$now] ${level.label} $scope | $message');
    if (data != null) {
      buffer.write(' | data=${_formatData(data)}');
    }
    if (error != null) {
      buffer.write(' | error=$error');
    }
    debugPrint(buffer.toString());
    if (stackTrace != null && level == LogLevel.error) {
      debugPrint(stackTrace.toString());
    }
  }

  static String summarizeEventPayload(Object? payload) {
    try {
      final decoded = payload is String ? jsonDecode(payload) : payload;
      if (decoded is! Map) return _truncate(decoded.toString());

      final type = decoded['type'];
      final data = decoded['data'];
      if (data is Map) {
        final roomId = data['room_id'];
        final nestedData = data['data'];
        if (nestedData is Map && nestedData['sdp'] is String) {
          return '{type=$type, room=$roomId, sdpType=${nestedData['type']}, sdpLength=${nestedData['sdp'].length}}';
        }
        if (nestedData is Map && nestedData['candidate'] is String) {
          return '{type=$type, room=$roomId, candidateLength=${nestedData['candidate'].length}, mid=${nestedData['sdpMid']}, mLine=${nestedData['sdpMLineIndex']}}';
        }
        if (nestedData == null && type == 'sfu_ice_candidate') {
          return '{type=$type, room=$roomId, candidate=end}';
        }
        return '{type=$type, keys=${data.keys.join(',')}}';
      }
      return '{type=$type, data=${_truncate(data.toString())}}';
    } catch (_) {
      return _truncate(payload.toString());
    }
  }

  static bool shouldLogRealtimePayload(Object? payload) {
    try {
      final decoded = payload is String ? jsonDecode(payload) : payload;
      if (decoded is! Map) return true;
      return !{
        'sfu_active_speakers',
        'sfu_ice_candidate',
        'typing_indicator',
      }.contains(decoded['type']);
    } catch (_) {
      return true;
    }
  }

  static String _formatData(Object data) {
    if (data is Map || data is Iterable) {
      return _truncate(jsonEncode(data));
    }
    return _truncate(data.toString());
  }

  static String _truncate(String value, {int maxLength = 700}) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}...<${value.length - maxLength} more chars>';
  }
}
