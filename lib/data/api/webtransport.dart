import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gritos_client/data/api/json_event_transport.dart';
import 'package:gritos_client/data/api/rest.dart';

class WebTransportClient extends JsonEventTransport {
  static const _channel = MethodChannel('gritos_client/webtransport');

  final ApiClient apiClient;
  void Function(dynamic message)? _onMessage;
  void Function()? _onDone;
  void Function(Object error)? _onError;
  bool _isConnected = false;

  WebTransportClient({required this.apiClient}) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  String get logPrefix => "WT";

  @override
  Future<void> connect() async {
    final token = await apiClient.getWebTransportToken();
    final apiUri = Uri.parse(apiClient.baseUrl);
    final wtUri = Uri(
      scheme: "https",
      host: apiUri.host,
      port: 7092,
      path: "/webtransport/global/register/$token",
    );

    try {
      await _channel.invokeMethod<void>("connect", {
        "url": wtUri.toString(),
        "origin": apiUri.origin,
      });
      _isConnected = true;
      debugPrint("WT: Connected to $wtUri");
    } catch (e) {
      debugPrint("WT: Connection failed: $e");
      _isConnected = false;
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
      debugPrint("WT: Cannot send message, transport is not connected");
      return;
    }
    debugPrint("WT Sending command: $message");
    unawaited(
      _channel.invokeMethod<void>("send", {"message": message}).catchError((
        error,
      ) {
        debugPrint("WT send failed: $error");
      }),
    );
  }

  @override
  void close() {
    _isConnected = false;
    unawaited(
      _channel.invokeMethod<void>("disconnect").catchError((error) {
        debugPrint("WT disconnect failed: $error");
      }),
    );
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case "onMessage":
        _onMessage?.call(call.arguments);
        break;
      case "onClosed":
        _isConnected = false;
        debugPrint("WT: Connection closed");
        _onDone?.call();
        break;
      case "onError":
        final error = call.arguments ?? "Unknown WebTransport error";
        debugPrint("WT error: $error");
        _isConnected = false;
        _onError?.call(error);
        break;
    }
  }
}
