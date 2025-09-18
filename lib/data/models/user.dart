class User {
  final String id;
  final String username;
  // Add other fields like email, avatarUrl, etc., if your API returns them and they are needed.

  User({
    required this.id,
    required this.username,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      // Ensure your API provides 'username'. If it can be null, handle accordingly:
      // username: json['username'] as String? ?? 'DefaultUsername',
      username: json['username'] as String? ?? (json['id'] as String? ?? 'Unknown User'), // Fallback to id or a default
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
      };
}
