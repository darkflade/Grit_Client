import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gritos_client/data/api/rest.dart';
import 'package:gritos_client/data/api/event_transport.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WsClient implements EventTransport {
  WebSocketChannel? _channel;
  final ApiClient apiClient;

  WsClient({required this.apiClient});

  @override
  Future<void> connect() async {
    // Using the host from ApiClient to ensure consistency
    final uri = Uri.parse(apiClient.baseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final baseUrl = "$wsScheme://${uri.host}/ws/global/register";
    
    final cookieJar = apiClient.cookieJar;
    final cookies = await cookieJar.loadForRequest(Uri.parse(apiClient.baseUrl));
    final cookieHeader = cookies.map((c) => "${c.name}=${c.value}").join("; ");

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(baseUrl),
        headers: {
          "Cookie": cookieHeader,
        },
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
  void listen(void Function(dynamic message) onMessage) {
    _channel?.stream.listen(
      onMessage,
      onDone: () {
        debugPrint("WS: Connection closed by server");
      },
      onError: (e) {
        debugPrint("WS error: $e");
      },
      cancelOnError: false,
    );
  }

  @override
  void sendCommand(String type, Map<String, dynamic> data, {String? nonce}) {
    final payload = {
      "type": type,
      "data": data,
    };
    if (nonce != null) {
      payload["nonce"] = nonce;
    }
    final message = jsonEncode(payload);
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

  // Helper methods for common commands (can be moved to a higher level or kept here as convenience)
  void subscribeServer(String serverId) {
    sendCommand("subscribe_server", {"server_id": serverId});
  }

  void unsubscribeServer(String serverId) {
    sendCommand("unsubscribe_server", {"server_id": serverId});
  }

  void joinRoom(String serverId, String roomId) {
    sendCommand("join_room", {"server_id": serverId, "room_id": roomId});
  }

  void leaveRoom(String roomId) {
    sendCommand("leave_room", {"room_id": roomId});
  }

  void chat(String serverId, String roomId, String content, {String? nonce}) {
    sendCommand("chat", {
      "server_id": serverId,
      "room_id": roomId,
      "content": content,
    }, nonce: nonce);
  }

  @override
  void close() {
    _channel?.sink.close();
    _channel = null;
  }
}
