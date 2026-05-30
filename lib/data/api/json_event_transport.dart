import 'dart:convert';

import 'event_transport.dart';

abstract class JsonEventTransport implements EventTransport {
  String get logPrefix;

  void sendJsonMessage(String message);

  @override
  void sendCommand(String type, Map<String, dynamic> data, {String? nonce}) {
    final payload = <String, dynamic>{"type": type, "data": data};
    if (nonce != null) {
      payload["nonce"] = nonce;
    }
    sendJsonMessage(jsonEncode(payload));
  }

  @override
  void subscribeServer(String serverId) {
    sendCommand("subscribe_server", {"server_id": serverId});
  }

  @override
  void unsubscribeServer(String serverId) {
    sendCommand("unsubscribe_server", {"server_id": serverId});
  }

  @override
  void joinRoom(String serverId, String roomId) {
    sendCommand("join_room", {"server_id": serverId, "room_id": roomId});
  }

  @override
  void leaveRoom(String roomId) {
    sendCommand("leave_room", {"room_id": roomId});
  }

  @override
  void chat(
    String serverId,
    String roomId,
    String content, {
    String? nonce,
    List<String>? attachmentIds,
  }) {
    final data = <String, dynamic>{
      "server_id": serverId,
      "room_id": roomId,
      "content": content,
    };
    if (attachmentIds != null) {
      data["attachment_ids"] = attachmentIds;
    }
    sendCommand("chat", data, nonce: nonce);
  }

  @override
  void directMessage(
    String roomId,
    String content, {
    String? nonce,
    List<String>? attachmentIds,
  }) {
    final data = <String, dynamic>{"room_id": roomId, "content": content};
    if (attachmentIds != null) {
      data["attachment_ids"] = attachmentIds;
    }
    sendCommand("direct_message", data, nonce: nonce);
  }

  @override
  void sendTypingIndicator(
    String roomId,
    bool isTyping, {
    required String scope,
  }) {
    sendCommand("typing_indicator", {
      "room_id": roomId,
      "is_typing": isTyping,
      "scope": scope,
    });
  }

  @override
  void pinMessage(String roomId, String messageId, {bool isDirect = false}) {
    sendCommand(isDirect ? "direct_message_pin" : "pin_message", {
      "room_id": roomId,
      "message_id": messageId,
    });
  }

  @override
  void markMessageRead(
    String roomId,
    String messageId, {
    bool isDirect = false,
  }) {
    sendCommand(isDirect ? "direct_message_read" : "mark_message_read", {
      "room_id": roomId,
      "message_id": messageId,
    });
  }
}
