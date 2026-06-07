class Room {
  final String id;
  final String serverId;
  final String name;
  final String type; // "chat", "rtc"
  final DateTime createdAt;

  Room({
    required this.id,
    required this.serverId,
    required this.name,
    required this.type,
    required this.createdAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json["id"] as String,
      serverId: json["server_id"] as String? ?? '',
      name: json["name"] as String? ?? 'Room',
      type: json["type"] as String? ?? 'chat',
      createdAt: DateTime.parse(
        json["created_at"] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'server_id': serverId,
    'name': name,
    'type': type,
    'created_at': createdAt.toIso8601String(),
  };
}
