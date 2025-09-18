import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gritos_client/data/api/rest.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';


class WsClient {
  late WebSocketChannel channel;
  final ApiClient apiClient;

  WsClient({required this.apiClient});

  Future<void> connect() async {
    final baseUrl = "wss://vimh.evilempty.space/ws/global/register";
    final cookieJar = apiClient.cookieJar;
    final cookies = await cookieJar.loadForRequest(Uri.parse(baseUrl));
    final cookieHeader = cookies.map((c) => "${c.name}=${c.value}").join("; ");

    channel = IOWebSocketChannel.connect(
      Uri.parse(baseUrl),
      headers: {
        "Cookie": cookieHeader,
      },
    );
  }

  void listen(void Function(dynamic) onMessage) {
    channel.stream.listen(onMessage, onError: (e) {
      debugPrint("WS error: $e");
    });
  }

  void send(String msg) {
    channel.sink.add(msg);
  }

  void sendMessage(String type, Map<String, dynamic> data) {
    final message = jsonEncode({
      "type": type,
      "data": data,
    });
    debugPrint("Sending WS message: $message");
    send(message);
  }

  void close() {
    channel.sink.close();
  }
}
