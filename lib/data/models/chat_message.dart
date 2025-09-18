class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final String type; // Could be "text", "image", etc.
  final String? mediaUrl;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.type,
    this.mediaUrl,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json["id"],
      roomId: json["room_id"],
      senderId: json["sender_id"],
      content: json["content"],
      type: json["type"],
      mediaUrl: json["media_url"],
      createdAt: DateTime.parse(json["created_at"]),
    );
  }
}