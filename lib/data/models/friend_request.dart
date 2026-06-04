import 'package:gritos_client/data/models/user.dart';

class FriendRequest {
  final String initiatorId;
  final String friendId;
  final User initiator;
  final User friend;
  final String status; // Kept for app state management
  final DateTime createdAt;
  final DateTime updatedAt;

  FriendRequest({
    required this.initiatorId,
    required this.friendId,
    required this.initiator,
    required this.friend,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      initiatorId: json["initiator_id"],
      friendId: json["friend_id"],
      initiator: User.fromJson(json["initiator"]),
      friend: User.fromJson(json["friend"]),
      status: json["status"] ?? "pending",
      createdAt: DateTime.parse(json["created_at"]),
      updatedAt: DateTime.parse(json["updated_at"] ?? json["created_at"]),
    );
  }

  Map<String, dynamic> toJson() => {
    "initiator_id": initiatorId,
    "friend_id": friendId,
    "initiator": initiator.toJson(),
    "friend": friend.toJson(),
    "status": status,
    "created_at": createdAt.toIso8601String(),
    "updated_at": updatedAt.toIso8601String(),
  };
}
