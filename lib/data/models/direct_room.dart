import 'user.dart';

class DirectRoom {
  final String id;
  final String? name;
  final bool isGroup;
  final DateTime createdAt;
  final List<User> members;

  List<String> get userIds => members.map((m) => m.id).toList();

  DirectRoom({
    required this.id,
    this.name,
    required this.isGroup,
    required this.createdAt,
    required this.members,
  });

  factory DirectRoom.fromJson(Map<String, dynamic> json) {
    return DirectRoom(
      id: json['id'] as String,
      name: json['name'] as String?,
      isGroup: json['is_group'] as bool,
      createdAt: DateTime.parse(json['created_at']),
      members: json['members'] != null
          ? (json['members'] as List)
                .map((e) => User.fromJson(e as Map<String, dynamic>))
                .toList()
          : [],
    );
  }

  String getDisplayName(String currentUserId) {
    if (name != null && name!.isNotEmpty) return name!;
    if (!isGroup) {
      final otherMember = members
          .where((m) => m.id != currentUserId)
          .firstOrNull;
      return otherMember?.nickname ?? 'Unknown User';
    }
    final otherNicknames = members
        .where((m) => m.id != currentUserId)
        .map((m) => m.nickname)
        .join(', ');
    return otherNicknames.isNotEmpty ? otherNicknames : 'Group Chat';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'is_group': isGroup,
    'created_at': createdAt.toIso8601String(),
    'members': members.map((e) => e.toJson()).toList(),
  };
}
