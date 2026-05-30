class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final String type;
  final String? mediaUrl;
  final String status;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? deletedBy;
  final DateTime? pinnedAt;
  final String? pinnedBy;
  final List<dynamic>? attachments;
  final List<dynamic>? reactions;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.type,
    this.mediaUrl,
    required this.status,
    required this.createdAt,
    this.editedAt,
    this.deletedAt,
    this.deletedBy,
    this.pinnedAt,
    this.pinnedBy,
    this.attachments,
    this.reactions,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json["id"],
      roomId: json["room_id"],
      senderId: json["sender_id"],
      content: json["content"],
      type: json["type"],
      mediaUrl: json["media_url"],
      status: json["status"] ?? "sent",
      createdAt: DateTime.parse(json["created_at"]),
      editedAt: json["edited_at"] != null ? DateTime.parse(json["edited_at"]) : null,
      deletedAt: json["deleted_at"] != null ? DateTime.parse(json["deleted_at"]) : null,
      deletedBy: json["deleted_by"],
      pinnedAt: json["pinned_at"] != null ? DateTime.parse(json["pinned_at"]) : null,
      pinnedBy: json["pinned_by"],
      attachments: json["attachments"],
      reactions: json["reactions"],
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "room_id": roomId,
        "sender_id": senderId,
        "content": content,
        "type": type,
        "media_url": mediaUrl,
        "status": status,
        "created_at": createdAt.toIso8601String(),
        "edited_at": editedAt?.toIso8601String(),
        "deleted_at": deletedAt?.toIso8601String(),
        "deleted_by": deletedBy,
        "pinned_at": pinnedAt?.toIso8601String(),
        "pinned_by": pinnedBy,
        "attachments": attachments,
        "reactions": reactions,
      };
}
