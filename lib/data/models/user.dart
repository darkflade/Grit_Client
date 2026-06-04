class User {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? bio;
  final String? customStatus;
  final String status;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;
  final DateTime createdAt;

  User({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.bio,
    this.customStatus,
    required this.status,
    this.lastSeenAt,
    this.updatedAt,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      nickname:
          json['nickname'] as String? ??
          (json['username'] as String? ?? 'Unknown'),
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      customStatus: json['custom_status'] as String?,
      status: json['status'] as String? ?? 'offline',
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'avatar_url': avatarUrl,
    'bio': bio,
    'custom_status': customStatus,
    'status': status,
    'last_seen_at': lastSeenAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };
}
