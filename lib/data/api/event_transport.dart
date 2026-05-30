abstract class EventTransport {
  Future<void> connect();
  void disconnect();
  void listen(void Function(dynamic message) onMessage);
  void sendCommand(String type, Map<String, dynamic> data, {String? nonce});
  void close();
  
  // High level command methods
  void subscribeServer(String serverId);
  void unsubscribeServer(String serverId);
  void joinRoom(String serverId, String roomId);
  void leaveRoom(String roomId);
  void chat(String serverId, String roomId, String content, {String? nonce, List<String>? attachmentIds});
  void directMessage(String roomId, String content, {String? nonce, List<String>? attachmentIds});
  
  // New commands
  void sendTypingIndicator(String roomId, bool isTyping, {required String scope});
  void pinMessage(String roomId, String messageId, {bool isDirect = false});
  void markMessageRead(String roomId, String messageId, {bool isDirect = false});
}
