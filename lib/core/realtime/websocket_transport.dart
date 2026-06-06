import 'dart:async';

import 'package:gritos_client/data/api/rest.dart';
import 'package:gritos_client/core/logging/app_logger.dart';
import 'package:gritos_client/core/realtime/json_event_transport.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WsClient extends JsonEventTransport {
  static const _log = AppLogger('WS');

  WebSocketChannel? _channel;
  final ApiClient apiClient;
  String _connectionState = "Disconnected";
  static const _connectTimeout = Duration(seconds: 8);

  WsClient({required this.apiClient});

  @override
  String get logPrefix => "WS";

  @override
  String get transportType => "WebSocket";

  @override
  String get connectionState => _connectionState;

  @override
  Future<void> connect() async {
    _connectionState = "Connecting...";
    final uri = Uri.parse(apiClient.baseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final baseUrl = "$wsScheme://${uri.host}/ws/global/register";

    final cookieJar = apiClient.cookieJar;
    final cookies = await cookieJar.loadForRequest(
      Uri.parse(apiClient.baseUrl),
    );
    final cookieHeader = cookies.map((c) => "${c.name}=${c.value}").join("; ");

    try {
      final channel = IOWebSocketChannel.connect(
        Uri.parse(baseUrl),
        headers: {"Cookie": cookieHeader},
        pingInterval: const Duration(seconds: 20),
        connectTimeout: _connectTimeout,
      );
      await channel.ready.timeout(_connectTimeout);
      _channel = channel;
      _connectionState = "Connected";
      _log.info('connected', data: {'url': baseUrl});
    } catch (e) {
      _channel?.sink.close();
      _channel = null;
      _connectionState = "Error";
      _log.error('connection failed', error: e, data: {'url': baseUrl});
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
    _channel?.stream.listen(
      (message) {
        _log.debug(
          '<= message',
          data: AppLogger.summarizeEventPayload(message),
        );
        onMessage(message);
      },
      onDone: () {
        _connectionState = "Disconnected";
        _log.warn('connection closed by server');
        onDone?.call();
      },
      onError: (e) {
        _connectionState = "Error";
        _log.error('stream error', error: e);
        onError?.call(e);
      },
      cancelOnError: false,
    );
  }

  @override
  void sendJsonMessage(String message) {
    _send(message);
  }

  void _send(String msg) {
    if (_channel != null && _channel?.sink != null) {
      _channel!.sink.add(msg);
    } else {
      _log.warn('cannot send message, channel is null');
    }
  }

  @override
  void close() {
    _channel?.sink.close();
    _channel = null;
    _connectionState = "Disconnected";
  }
}
