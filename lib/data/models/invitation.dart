import 'user.dart';

class Invitation {
  final String id;
  final String serverId;
  final String token;
  final String role;
  final String? email;
  final String? invitedUserId;
  final String? inviterId;
  final User? invitedUser;
  final User? inviter;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  Invitation({
    required this.id,
    required this.serverId,
    required this.token,
    required this.role,
    this.email,
    this.invitedUserId,
    this.inviterId,
    this.invitedUser,
    this.inviter,
    this.expiresAt,
    this.createdAt,
  });

  factory Invitation.fromJson(Map<String, dynamic> json) {
    return Invitation(
      id: json['id'] as String? ?? '',
      serverId: json['server_id'] as String? ?? '',
      token: json['token'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      email: json['email'] as String?,
      invitedUserId: json['invited_user_id'] as String?,
      inviterId: json['inviter_id'] as String?,
      invitedUser: json['invited_user'] is Map
          ? User.fromJson(
              Map<String, dynamic>.from(json['invited_user'] as Map),
            )
          : null,
      inviter: json['inviter'] is Map
          ? User.fromJson(Map<String, dynamic>.from(json['inviter'] as Map))
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}
