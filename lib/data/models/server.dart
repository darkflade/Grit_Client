class Server {
  final String id;
  final String ownerId;
  final String name;
  final String? iconUrl;
  final DateTime createdAt;

  Server({
    required this.id,
    required this.ownerId,
    required this.name,
    this.iconUrl,
    required this.createdAt,
  });

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      id: json["id"] as String,
      ownerId: json["owner_id"] as String? ?? '',
      name: json["name"] as String? ?? 'Server',
      iconUrl: json["icon_url"] as String?,
      createdAt: DateTime.parse(
        json["created_at"] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'name': name,
    'icon_url': iconUrl,
    'created_at': createdAt.toIso8601String(),
  };
}
