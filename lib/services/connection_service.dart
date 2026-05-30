import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/api/event_transport.dart';

class ConnectionService {
  final EventTransport eventTransport;

  final _messageController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get messageStream => _messageController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  ConnectionService(this.eventTransport);

  Future<void> connect() async {
    if (_isConnected) return;
    try {
      await eventTransport.connect();
      _isConnected = true;
      eventTransport.listen((message) {
        _messageController.add(message);
      });
    } catch (e) {
      debugPrint("ConnectionService: Failed to connect: $e");
      _isConnected = false;
      rethrow;
    }
  }

  void disconnect() {
    eventTransport.disconnect();
    _isConnected = false;
  }

  void sendCommand(String type, Map<String, dynamic> data, {String? nonce}) {
    if (!_isConnected) {
      debugPrint("ConnectionService: Cannot send command, not connected.");
      return;
    }
    eventTransport.sendCommand(type, data, nonce: nonce);
  }

  // Common commands abstracted
  void subscribeServer(String serverId) {
    eventTransport.subscribeServer(serverId);
  }

  void unsubscribeServer(String serverId) {
    eventTransport.unsubscribeServer(serverId);
  }

  void joinRoom(String serverId, String roomId) {
    eventTransport.joinRoom(serverId, roomId);
  }

  void leaveRoom(String roomId) {
    eventTransport.leaveRoom(roomId);
  }

  void chat(String serverId, String roomId, String content, {String? nonce, List<String>? attachmentIds}) {
    eventTransport.chat(serverId, roomId, content, nonce: nonce, attachmentIds: attachmentIds);
  }

  void directMessage(String roomId, String content, {String? nonce, List<String>? attachmentIds}) {
    eventTransport.directMessage(roomId, content, nonce: nonce, attachmentIds: attachmentIds);
  }

  void sendTypingIndicator(String roomId, bool isTyping, {required String scope}) {
    eventTransport.sendTypingIndicator(roomId, isTyping, scope: scope);
  }

  void pinMessage(String roomId, String messageId, {bool isDirect = false}) {
    eventTransport.pinMessage(roomId, messageId, isDirect: isDirect);
  }

  void markMessageRead(String roomId, String messageId, {bool isDirect = false}) {
    eventTransport.markMessageRead(roomId, messageId, isDirect: isDirect);
  }

  void dispose() {
    _messageController.close();
    disconnect();
  }
}
