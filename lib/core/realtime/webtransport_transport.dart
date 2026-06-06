import 'dart:async';
import 'package:flutter/services.dart';
import 'package:gritos_client/core/logging/app_logger.dart';
import 'package:gritos_client/core/realtime/json_event_transport.dart';
import 'package:gritos_client/data/api/rest.dart';

class WebTransportClient extends JsonEventTransport {
  static const _channel = MethodChannel('gritos_client/webtransport');
  static const _log = AppLogger('WT');

  final ApiClient apiClient;
  void Function(dynamic message)? _onMessage;
  void Function()? _onDone;
  void Function(Object error)? _onError;
  bool _isConnected = false;
  String _connectionState = "Disconnected";
  static const _connectTimeout = Duration(seconds: 10);

  WebTransportClient({required this.apiClient}) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  String get logPrefix => "WT";

  @override
  String get transportType => "WebTransport";

  @override
  String get connectionState => _connectionState;

  @override
  Future<void> connect() async {
    _connectionState = "Connecting...";
    try {
      final token = await apiClient.getWebTransportToken().timeout(
        _connectTimeout,
      );
      final apiUri = Uri.parse(apiClient.baseUrl);
      final wtUri = Uri(
        scheme: "https",
        host: apiUri.host,
        port: 7092,
        path: "/webtransport/global/register/$token",
      );

      await _channel
          .invokeMethod<void>("connect", {
            "url": wtUri.toString(),
            "origin": apiUri.origin,
          })
          .timeout(_connectTimeout);
      _isConnected = true;
      _connectionState = "Connected";
      _log.info(
        'connected',
        data: {'host': wtUri.host, 'port': wtUri.port, 'origin': apiUri.origin},
      );
    } catch (e) {
      unawaited(
        _channel.invokeMethod<void>("disconnect").catchError((error) {
          _log.error('cleanup after connection failure failed', error: error);
        }),
      );
      _log.error('connection failed', error: e);
      _isConnected = false;
      _connectionState = "Error";
      rethrow;
    }
  }

  @override
  void disconnect() {
    close();
  }

  @override
  void listen(
    void Function(dynamic message) onMessage, {
    void Function()? onDone,
    void Function(Object error)? onError,
  }) {
    _onMessage = onMessage;
    _onDone = onDone;
    _onError = onError;
  }

  @override
  void sendJsonMessage(String message) {
    if (!_isConnected) {
      _log.warn('cannot send message, transport is not connected');
      return;
    }
    unawaited(
      _channel.invokeMethod<void>("send", {"message": message}).catchError((
        error,
      ) {
        _log.error('send failed', error: error);
      }),
    );
  }

  @override
  void close() {
    _isConnected = false;
    _connectionState = "Disconnected";
    unawaited(
      _channel.invokeMethod<void>("disconnect").catchError((error) {
        _log.error('disconnect failed', error: error);
      }),
    );
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case "onMessage":
        _log.debug(
          '<= message',
          data: AppLogger.summarizeEventPayload(call.arguments),
        );
        _onMessage?.call(call.arguments);
        break;
      case "onClosed":
        _isConnected = false;
        _connectionState = "Disconnected";
        _log.warn('connection closed');
        _onDone?.call();
        break;
      case "onError":
        final error = call.arguments ?? "Unknown WebTransport error";
        _log.error('native error', error: error);
        _isConnected = false;
        _connectionState = "Error";
        _onError?.call(error);
        break;
      case "onLog":
        _log.debug('native log', data: call.arguments);
        break;
    }
  }
}
