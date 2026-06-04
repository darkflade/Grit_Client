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
      id: json["id"],
      ownerId: json["owner_id"],
      name: json["name"],
      iconUrl: json["icon_url"],
      createdAt: DateTime.parse(json["created_at"]),
    );
  }
}
