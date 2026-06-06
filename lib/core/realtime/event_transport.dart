abstract class EventTransport {
  Future<void> connect();
  void disconnect();
  void listen(
    void Function(dynamic message) onMessage, {
    void Function()? onDone,
    void Function(Object error)? onError,
  });
  void sendCommand(String type, Map<String, dynamic> data, {String? nonce});
  void close();

  // Transport info
  String get transportType;
  String get connectionState;

  // High level command methods
  void subscribeServer(String serverId);
  void unsubscribeServer(String serverId);
  void joinRoom(String serverId, String roomId);
  void leaveRoom(String roomId);
  void chat(
    String serverId,
    String roomId,
    String content, {
    String? nonce,
    List<String>? attachmentIds,
  });
  void directMessage(
    String roomId,
    String content, {
    String? nonce,
    List<String>? attachmentIds,
  });
  void directCallStart(String roomId);
  void directCallEnd(String roomId, String callId);
  void directCallDecline(String roomId, String callId);

  // Snapshot requests
  void getServerParticipants(String serverId);
  void getServerRooms(String serverId);
  void getRoomMessages(String roomId, {int limit = 25, String? cursor});
  void getDirectMessages(String roomId, {int limit = 25, String? cursor});

  // New commands
  void sendTypingIndicator(
    String roomId,
    bool isTyping, {
    required String scope,
  });
  void pinMessage(String roomId, String messageId, {bool isDirect = false});
  void unpinMessage(String roomId, String messageId, {bool isDirect = false});
  void markMessageRead(
    String roomId,
    String messageId, {
    bool isDirect = false,
  });

  // SFU Signaling
  void sfuJoin(String roomId);
  void sfuLeave(String roomId, String sessionId);
  void sfuSendOffer(String roomId, String sdp, String type);
  void sfuSendAnswer(String roomId, String sdp, String type);
  void sfuSendIceCandidate(String roomId, Map<String, dynamic>? candidate);
  void sfuSendIceRestart(String roomId);
  void sfuSendMediaState(String roomId, Map<String, dynamic> state);
}
