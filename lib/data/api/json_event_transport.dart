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
  void directCallStart(String roomId) {
    sendCommand("direct_call_start", {"room_id": roomId});
  }

  @override
  void directCallEnd(String roomId, String callId) {
    sendCommand("direct_call_end", {"room_id": roomId, "call_id": callId});
  }

  @override
  void directCallDecline(String roomId, String callId) {
    sendCommand("direct_call_decline", {"room_id": roomId, "call_id": callId});
  }

  @override
  void getRoomMessages(String roomId, {int limit = 25, String? cursor}) {
    final data = <String, dynamic>{"room_id": roomId, "limit": limit};
    if (cursor != null) data["cursor"] = cursor;
    sendCommand("get_room_messages", data);
  }

  @override
  void getDirectMessages(String roomId, {int limit = 25, String? cursor}) {
    final data = <String, dynamic>{"room_id": roomId, "limit": limit};
    if (cursor != null) data["cursor"] = cursor;
    sendCommand("get_direct_messages", data);
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

  @override
  void sfuJoin(String roomId) {
    sendCommand("sfu_join", {"room_id": roomId});
  }

  @override
  void sfuLeave(String roomId, String sessionId) {
    sendCommand("sfu_leave", {"room_id": roomId, "session_id": sessionId});
  }

  @override
  void sfuSendOffer(String roomId, String sdp, String type) {
    sendCommand("sfu_offer", {
      "room_id": roomId,
      "data": {"sdp": sdp, "type": type}
    });
  }

  @override
  void sfuSendAnswer(String roomId, String sdp, String type) {
    sendCommand("sfu_answer", {
      "room_id": roomId,
      "data": {"sdp": sdp, "type": type}
    });
  }

  @override
  void sfuSendIceCandidate(String roomId, Map<String, dynamic>? candidate) {
    sendCommand("sfu_ice_candidate", {
      "room_id": roomId,
      "data": candidate,
    });
  }

  @override
  void sfuSendIceRestart(String roomId) {
    sendCommand("sfu_ice_restart", {"room_id": roomId});
  }

  @override
  void sfuSendMediaState(String roomId, Map<String, dynamic> state) {
    sendCommand("sfu_media_state", {
      "room_id": roomId,
      ...state,
    });
  }
}
