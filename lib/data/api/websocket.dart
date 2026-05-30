import 'package:flutter/foundation.dart';
import 'package:gritos_client/data/api/rest.dart';
import 'package:gritos_client/data/api/json_event_transport.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WsClient extends JsonEventTransport {
  WebSocketChannel? _channel;
  final ApiClient apiClient;

  WsClient({required this.apiClient});

  @override
  String get logPrefix => "WS";

  @override
  Future<void> connect() async {
    final uri = Uri.parse(apiClient.baseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final baseUrl = "$wsScheme://${uri.host}/ws/global/register";

    final cookieJar = apiClient.cookieJar;
    final cookies = await cookieJar.loadForRequest(
      Uri.parse(apiClient.baseUrl),
    );
    final cookieHeader = cookies.map((c) => "${c.name}=${c.value}").join("; ");

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(baseUrl),
        headers: {"Cookie": cookieHeader},
      );
      debugPrint("WS: Connected to $baseUrl");
    } catch (e) {
      debugPrint("WS: Connection failed: $e");
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
      onMessage,
      onDone: () {
        debugPrint("WS: Connection closed by server");
        onDone?.call();
      },
      onError: (e) {
        debugPrint("WS error: $e");
        onError?.call(e);
      },
      cancelOnError: false,
    );
  }

  @override
  void sendJsonMessage(String message) {
    debugPrint("WS Sending command: $message");
    _send(message);
  }

  void _send(String msg) {
    if (_channel != null && _channel?.sink != null) {
      _channel!.sink.add(msg);
    } else {
      debugPrint("WS: Cannot send message, channel is null");
    }
  }

  @override
  void close() {
    _channel?.sink.close();
    _channel = null;
  }
}
