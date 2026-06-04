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
      id: json["id"],
      serverId: json["server_id"],
      name: json["name"],
      type: json["type"],
      createdAt: DateTime.parse(json["created_at"]),
    );
  }
}
