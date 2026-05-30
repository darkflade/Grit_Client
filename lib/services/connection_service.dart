import 'dart:async';
import '../data/api/rest.dart';
import '../data/api/event_transport.dart';
import '../data/api/websocket.dart';

class ConnectionService {
  final ApiClient apiClient;
  late final EventTransport eventTransport;

  final _messageController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get messageStream => _messageController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  ConnectionService(this.apiClient) {
    eventTransport = WsClient(apiClient: apiClient);
  }

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

  void dispose() {
    _messageController.close();
    disconnect();
  }
}
