import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/api/event_transport.dart';

class ConnectionService {
  EventTransport eventTransport;

  final _messageController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get messageStream => _messageController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _manualDisconnect = false;
  bool _isConnecting = false;
  bool _reconnectScheduled = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  final Set<String> _subscribedServerIds = {};
  final Map<String, String> _joinedRooms = {};

  ConnectionService(this.eventTransport);

  Future<void> setTransport(EventTransport transport) async {
    final shouldReconnect = _isConnected || _isConnecting;
    final oldTransport = eventTransport;
    _cancelReconnect();
    _manualDisconnect = true;
    oldTransport.disconnect();
    eventTransport = transport;
    _isConnected = false;
    _isConnecting = false;
    _manualDisconnect = false;

    if (shouldReconnect) {
      await connect();
    } else {
      oldTransport.close();
    }
  }

  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;
    _manualDisconnect = false;
    _isConnecting = true;
    try {
      await eventTransport.connect();
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempt = 0;
      eventTransport.listen(
        (message) {
          _messageController.add(message);
        },
        onDone: _handleTransportDone,
        onError: _handleTransportError,
      );
      _restoreSubscriptions();
    } catch (e) {
      debugPrint("ConnectionService: Failed to connect: $e");
      _isConnected = false;
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _cancelReconnect();
    eventTransport.disconnect();
    _isConnected = false;
    _isConnecting = false;
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
    _subscribedServerIds.add(serverId);
    eventTransport.subscribeServer(serverId);
  }

  void unsubscribeServer(String serverId) {
    _subscribedServerIds.remove(serverId);
    eventTransport.unsubscribeServer(serverId);
  }

  void joinRoom(String serverId, String roomId) {
    _joinedRooms[roomId] = serverId;
    eventTransport.joinRoom(serverId, roomId);
  }

  void leaveRoom(String roomId) {
    _joinedRooms.remove(roomId);
    eventTransport.leaveRoom(roomId);
  }

  void chat(
    String serverId,
    String roomId,
    String content, {
    String? nonce,
    List<String>? attachmentIds,
  }) {
    eventTransport.chat(
      serverId,
      roomId,
      content,
      nonce: nonce,
      attachmentIds: attachmentIds,
    );
  }

  void directMessage(
    String roomId,
    String content, {
    String? nonce,
    List<String>? attachmentIds,
  }) {
    eventTransport.directMessage(
      roomId,
      content,
      nonce: nonce,
      attachmentIds: attachmentIds,
    );
  }

  void sendTypingIndicator(
    String roomId,
    bool isTyping, {
    required String scope,
  }) {
    eventTransport.sendTypingIndicator(roomId, isTyping, scope: scope);
  }

  void pinMessage(String roomId, String messageId, {bool isDirect = false}) {
    eventTransport.pinMessage(roomId, messageId, isDirect: isDirect);
  }

  void markMessageRead(
    String roomId,
    String messageId, {
    bool isDirect = false,
  }) {
    eventTransport.markMessageRead(roomId, messageId, isDirect: isDirect);
  }

  void _handleTransportDone() {
    debugPrint("ConnectionService: Transport closed.");
    _isConnected = false;
    if (!_manualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _handleTransportError(Object error) {
    debugPrint("ConnectionService: Transport error: $error");
    _isConnected = false;
    if (!_manualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect ||
        _messageController.isClosed ||
        _reconnectScheduled) {
      return;
    }
    _reconnectScheduled = true;
    final seconds = _reconnectDelaySeconds();
    debugPrint("ConnectionService: Reconnecting in ${seconds}s.");
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectScheduled = false;
      _reconnectAttempt++;
      unawaited(connect());
    });
  }

  int _reconnectDelaySeconds() {
    const delays = [1, 2, 5, 10, 20, 30];
    final index = _reconnectAttempt.clamp(0, delays.length - 1);
    return delays[index];
  }

  void _cancelReconnect() {
    _reconnectScheduled = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
  }

  void _restoreSubscriptions() {
    for (final serverId in _subscribedServerIds) {
      eventTransport.subscribeServer(serverId);
    }
    for (final entry in _joinedRooms.entries) {
      eventTransport.joinRoom(entry.value, entry.key);
    }
  }

  void dispose() {
    _manualDisconnect = true;
    _cancelReconnect();
    _messageController.close();
    disconnect();
  }
}
