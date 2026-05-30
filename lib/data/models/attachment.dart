class Attachment {
  final String id;
  final String? ownerId;
  final String kind;
  final bool isLinked;
  final String? messageId;
  final String? userId;
  final String? serverId;
  final String filepath;
  final String originalName;
  final String? contentType;
  final int sizeBytes;
  final String url;
  final DateTime createdAt;
  final DateTime? linkedAt;

  Attachment({
    required this.id,
    this.ownerId,
    required this.kind,
    required this.isLinked,
    this.messageId,
    this.userId,
    this.serverId,
    required this.filepath,
    required this.originalName,
    this.contentType,
    required this.sizeBytes,
    required this.url,
    required this.createdAt,
    this.linkedAt,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String?,
      kind: json['kind'] as String,
      isLinked: json['is_linked'] as bool,
      messageId: json['message_id'] as String?,
      userId: json['user_id'] as String?,
      serverId: json['server_id'] as String?,
      filepath: json['filepath'] as String,
      originalName: json['original_name'] as String,
      contentType: json['content_type'] as String?,
      sizeBytes: json['size_bytes'] as int,
      url: json['url'] as String,
      createdAt: DateTime.parse(json['created_at']),
      linkedAt: json['linked_at'] != null ? DateTime.parse(json['linked_at']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner_id': ownerId,
        'kind': kind,
        'is_linked': isLinked,
        'message_id': messageId,
        'user_id': userId,
        'server_id': serverId,
        'filepath': filepath,
        'original_name': originalName,
        'content_type': contentType,
        'size_bytes': sizeBytes,
        'url': url,
        'created_at': createdAt.toIso8601String(),
        'linked_at': linkedAt?.toIso8601String(),
      };
}
