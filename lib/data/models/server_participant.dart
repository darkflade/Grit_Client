import 'user.dart';

class ServerMember {
  final String userId;
  final String serverId;
  final String role;
  final String? roleId;
  final bool canInvite;
  final bool canManageRooms;
  final bool canManageServer;
  final DateTime? joinedAt;

  ServerMember({
    required this.userId,
    required this.serverId,
    required this.role,
    this.roleId,
    required this.canInvite,
    required this.canManageRooms,
    required this.canManageServer,
    this.joinedAt,
  });

  factory ServerMember.fromJson(Map<String, dynamic> json) {
    return ServerMember(
      userId: json['user_id'] as String? ?? '',
      serverId: json['server_id'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      roleId: json['role_id'] as String?,
      canInvite: json['can_invite'] as bool? ?? false,
      canManageRooms: json['can_manage_rooms'] as bool? ?? false,
      canManageServer: json['can_manage_server'] as bool? ?? false,
      joinedAt: json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'].toString())
          : null,
    );
  }
}

class ServerParticipant {
  final User user;
  final ServerMember member;
  final bool online;
  final bool subscribed;

  ServerParticipant({
    required this.user,
    required this.member,
    required this.online,
    required this.subscribed,
  });

  factory ServerParticipant.fromJson(Map<String, dynamic> json) {
    return ServerParticipant(
      user: User.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      member: ServerMember.fromJson(
        Map<String, dynamic>.from(json['member'] as Map? ?? {}),
      ),
      online: json['online'] as bool? ?? false,
      subscribed: json['subscribed'] as bool? ?? false,
    );
  }
}

class ServerParticipantsResponse {
  final String serverId;
  final int total;
  final int onlineCount;
  final List<ServerParticipant> participants;

  ServerParticipantsResponse({
    required this.serverId,
    required this.total,
    required this.onlineCount,
    required this.participants,
  });

  factory ServerParticipantsResponse.fromJson(Map<String, dynamic> json) {
    final participants = json['participants'] is List
        ? (json['participants'] as List)
              .map(
                (item) => ServerParticipant.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList()
        : <ServerParticipant>[];

    return ServerParticipantsResponse(
      serverId: json['server_id'] as String? ?? '',
      total: json['total'] as int? ?? participants.length,
      onlineCount: json['online_count'] as int? ?? 0,
      participants: participants,
    );
  }
}
