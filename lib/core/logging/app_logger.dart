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

  static const _reset = '\x1B[0m';
  static const _cyan = '\x1B[36m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _red = '\x1B[31m';

  void debug(String message, {Object? data}) {
    _write(LogLevel.debug, message, data: data);
  }

  void debugLong(String message, {Object? data}) {
    _write(LogLevel.debug, message, data: data, truncateData: false);
  }

  void info(String message, {Object? data}) {
    _write(LogLevel.info, message, data: data);
  }

  void infoLong(String message, {Object? data}) {
    _write(LogLevel.info, message, data: data, truncateData: false);
  }

  void warn(String message, {Object? data}) {
    _write(LogLevel.warn, message, data: data);
  }

  void warnLong(String message, {Object? data}) {
    _write(LogLevel.warn, message, data: data, truncateData: false);
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
    bool truncateData = true,
  }) {
    final now = DateTime.now().toIso8601String();
    final buffer = StringBuffer('[$now] ${level.label} $scope | $message');
    if (data != null) {
      buffer.write(
        ' | data=${truncateData ? _formatData(data) : _formatDataFull(data)}',
      );
    }
    if (error != null) {
      buffer.write(' | error=$error');
    }
    _printChunks(level, buffer.toString());
    if (stackTrace != null && level == LogLevel.error) {
      _printChunks(level, stackTrace.toString());
    }
  }

  static String _colorize(LogLevel level, String line) {
    if (kReleaseMode) return line;
    final color = switch (level) {
      LogLevel.debug => _cyan,
      LogLevel.info => _green,
      LogLevel.warn => _yellow,
      LogLevel.error => _red,
    };
    return '$color$line$_reset';
  }

  static String summarizeEventPayload(Object? payload) {
    try {
      final decoded = payload is String ? jsonDecode(payload) : payload;
      if (decoded is! Map) return _truncate(decoded.toString());

      final type = decoded['type'];
      final data = decoded['data'];
      if (data is Map) {
        if (type == 'error') {
          return '{type=$type, code=${data['code']}, message=${_truncate(data['message'].toString(), maxLength: 160)}}';
        }
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

  static String _formatDataFull(Object data) {
    if (data is Map || data is Iterable) {
      return jsonEncode(data);
    }
    return data.toString();
  }

  static void _printChunks(LogLevel level, String line) {
    const maxChunkLength = 700;
    if (line.length <= maxChunkLength) {
      debugPrint(_colorize(level, line));
      return;
    }

    final total = (line.length / maxChunkLength).ceil();
    for (var index = 0; index < total; index += 1) {
      final start = index * maxChunkLength;
      final end = start + maxChunkLength;
      final chunk = line.substring(
        start,
        end > line.length ? line.length : end,
      );
      debugPrint(_colorize(level, '[chunk ${index + 1}/$total] $chunk'));
    }
  }

  static String _truncate(String value, {int maxLength = 700}) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}...<${value.length - maxLength} more chars>';
  }
}
