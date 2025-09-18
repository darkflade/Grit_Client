// This model assumes the API returns the full user object for the sender
import 'package:gritos_client/data/models/user.dart';

class FriendRequest {
  final String id;
  final User fromUser;
  final String status;
  final DateTime createdAt;

  FriendRequest({
    required this.id,
    required this.fromUser,
    required this.status,
    required this.createdAt,
  });


  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json["id"],
      // Assumes the backend sends a nested 'from_user' object
      fromUser: User.fromJson(json["from_user"]),
      status: json["status"],
      createdAt: DateTime.parse(json["created_at"]),
    );
  }
}