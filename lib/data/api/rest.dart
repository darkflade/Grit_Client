import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/friend_request.dart';
import '../models/server.dart';
import '../models/server_participant.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../models/direct_room.dart';
import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/message_page.dart';
import '../models/invitation.dart';
import '../../core/config/api_endpoint.dart';

class AuthIdentityNotFoundException implements Exception {
  final String message;

  const AuthIdentityNotFoundException([
    this.message = 'Authenticated user not found on this server.',
  ]);

  @override
  String toString() => message;
}

class ApiClient {
  final Dio dio;
  String baseUrl;
  late final CookieJar cookieJar;
  void Function(ApiRequestError error)? onRequestError;

  final Map<String, Uint8List> _fileCache = {};
  final Map<String, Map<String, dynamic>> _metadataCache = {};

  ApiClient({String? baseUrl})
    : dio = Dio(),
      baseUrl = normalizeApiBaseUrl(baseUrl ?? defaultApiBaseUrl) {
    cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));
    dio.interceptors.add(_RetryInterceptor(dio, () => onRequestError));

    dio.options.baseUrl = this.baseUrl;
    dio.options.connectTimeout = const Duration(seconds: 8);
    dio.options.sendTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 12);
    dio.options.headers = {
      "Accept": "application/json",
      "Content-Type": "application/json",
    };
  }

  Future<void> updateBaseUrl(String nextBaseUrl) async {
    baseUrl = normalizeApiBaseUrl(nextBaseUrl);
    dio.options.baseUrl = baseUrl;
    _fileCache.clear();
    _metadataCache.clear();
    await cookieJar.deleteAll();
  }

  // Auth
  Future<Response> login(String email, String password) async {
    try {
      return await dio.post(
        "/api/auth/login",
        data: {"email": email, "password": password},
      );
    } catch (e) {
      debugPrint("Login error: $e");
      rethrow;
    }
  }

  Future<Response> register(
    String nickname,
    String email,
    String password,
  ) async {
    try {
      return await dio.post(
        "/api/auth/register",
        data: {"nickname": nickname, "email": email, "password": password},
      );
    } catch (e) {
      debugPrint("Register error: $e");
      rethrow;
    }
  }

  Future<Response> logout() async {
    try {
      return await dio.post("/api/auth/logout");
    } catch (e) {
      debugPrint("Logout error: $e");
      rethrow;
    }
  }

  Future<String> getWebTransportToken() async {
    final response = await dio.post("/api/auth/webtransport-token");
    final data = response.data;
    if (data is Map<String, dynamic> && data["token"] is String) {
      return data["token"] as String;
    }
    throw Exception("Invalid WebTransport token response");
  }

  Future<Map<String, dynamic>> getRtcConfig() async {
    final response = await dio.get("/api/auth/ice-servers");
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final servers = data["ice_servers"] ?? data["iceServers"];
      if (servers is List) {
        final iceServers = servers
            .whereType<Map>()
            .map((server) => Map<String, dynamic>.from(server))
            .toList();
        return {
          "iceServers": iceServers,
          "iceTransportPolicy":
              data["ice_transport_policy"] ??
              data["iceTransportPolicy"] ??
              "all",
          if (data["expires_at"] != null) "expiresAt": data["expires_at"],
          if (data["ttl_seconds"] != null) "ttlSeconds": data["ttl_seconds"],
        };
      }
    }
    throw Exception("Invalid RTC config response");
  }

  // User
  Future<User?> getMe() async {
    try {
      final res = await dio.get("/api/private/me");
      if (res.statusCode == 200 && res.data != null) {
        if (res.data is Map<String, dynamic>) {
          return User.fromJson(res.data);
        }
      }
      return null;
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          throw const AuthIdentityNotFoundException();
        }
        debugPrint("Error in getMe (${e.requestOptions.uri}): $e");
      } else {
        debugPrint("Error in getMe: $e");
      }
      return null;
    }
  }

  Future<String?> getMyId() async {
    final user = await getMe();
    return user?.id;
  }

  Future<User> getUserById(String userId) async {
    try {
      final res = await dio.get("/api/users/$userId");
      if (res.data is Map<String, dynamic>) {
        return User.fromJson(res.data);
      }
      throw Exception("Invalid user data format");
    } catch (e) {
      debugPrint("Error in getUserById: $e");
      rethrow;
    }
  }

  // Servers & Rooms
  Future<List<Server>> getServers() async {
    try {
      final res = await dio.get("/api/servers/");
      if (res.statusCode == 200 && res.data != null) {
        if (res.data is List) {
          return (res.data as List)
              .map((e) => Server.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint("Error in getServers: $e");
    }
    return [];
  }

  Future<Server?> getServerInfo(String serverId) async {
    final list = await getServers();
    for (final server in list) {
      if (server.id == serverId) return server;
    }
    return null;
  }

  Future<Server?> createServer(String name, {String? iconUrl}) async {
    try {
      final data = <String, dynamic>{"name": name};
      if (iconUrl != null && iconUrl.isNotEmpty) {
        data["icon_url"] = iconUrl;
      }
      final res = await dio.post("/api/servers/", data: data);
      if (res.data is Map<String, dynamic>) {
        return Server.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("Error in createServer: $e");
      rethrow;
    }
    return null;
  }

  Future<Server?> updateServerIcon(String serverId, String attachmentId) async {
    try {
      final res = await dio.patch(
        "/api/servers/$serverId/icon",
        data: {"attachment_id": attachmentId},
      );
      if (res.data is Map<String, dynamic>) {
        return Server.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("Error in updateServerIcon: $e");
      rethrow;
    }
    return null;
  }

  Future<List<User>> getServerBlockedUsers(String serverId) async {
    try {
      final res = await dio.get("/api/servers/$serverId/blocked");
      if (res.data is List) {
        return (res.data as List)
            .map((item) => User.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint("Error in getServerBlockedUsers: $e");
    }
    return [];
  }

  Future<List<Room>> getRooms(String serverId) async {
    try {
      final res = await dio.get("/api/servers/$serverId/rooms/");
      if (res.statusCode == 200 && res.data != null) {
        if (res.data is List) {
          return (res.data as List)
              .map((e) => Room.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint("Error in getRooms: $e");
    }
    return [];
  }

  Future<Room?> createRoom(
    String serverId,
    String name, {
    String type = "chat",
  }) async {
    try {
      final res = await dio.post(
        "/api/servers/$serverId/rooms/",
        data: {"name": name, "type": type},
      );
      if (res.data is Map<String, dynamic>) {
        return Room.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("Error in createRoom: $e");
      rethrow;
    }
    return null;
  }

  Future<ServerParticipantsResponse?> getServerParticipants(
    String serverId,
  ) async {
    try {
      final res = await dio.get("/api/servers/$serverId/participants");
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return ServerParticipantsResponse.fromJson(res.data);
      }
    } catch (e) {
      debugPrint("Error in getServerParticipants: $e");
    }
    return null;
  }

  Future<RtcRoomParticipantsResponse?> getRtcRoomParticipants(
    String serverId,
    String roomId,
  ) async {
    try {
      final res = await dio.get(
        "/api/servers/$serverId/rooms/$roomId/rtc/participants",
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return RtcRoomParticipantsResponse.fromJson(res.data);
      }
    } catch (e) {
      debugPrint("Error in getRtcRoomParticipants: $e");
    }
    return null;
  }

  Future<List<Invitation>> getServerInvitations(String serverId) async {
    try {
      final res = await dio.get("/api/servers/$serverId/invitations/");
      if (res.data is List) {
        return (res.data as List)
            .map(
              (item) =>
                  Invitation.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
      }
    } catch (e) {
      debugPrint("Error in getServerInvitations: $e");
    }
    return [];
  }

  Future<Invitation?> createServerInvitation(
    String serverId, {
    String role = "member",
    String? email,
    String? userId,
    int? expiresInHours,
  }) async {
    try {
      final data = <String, dynamic>{"role": role};
      if (email != null && email.isNotEmpty) data["email"] = email;
      if (userId != null && userId.isNotEmpty) data["user_id"] = userId;
      if (expiresInHours != null) {
        data["expires_in_hours"] = expiresInHours;
      }
      final res = await dio.post(
        "/api/servers/$serverId/invitations/",
        data: data,
      );
      if (res.data is Map<String, dynamic>) {
        return Invitation.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("Error in createServerInvitation: $e");
      rethrow;
    }
    return null;
  }

  Future<void> deleteServerInvitation(
    String serverId,
    String invitationId,
  ) async {
    try {
      await dio.delete("/api/servers/$serverId/invitations/$invitationId");
    } catch (e) {
      debugPrint("Error in deleteServerInvitation: $e");
      rethrow;
    }
  }

  Future<void> acceptServerInvitation(String token) async {
    try {
      await dio.post("/api/servers/invitations/accept", data: {"token": token});
    } catch (e) {
      debugPrint("Error in acceptServerInvitation: $e");
      rethrow;
    }
  }

  Future<void> removeServerMember(String serverId, String userId) async {
    try {
      await dio.delete("/api/servers/$serverId/members/$userId");
    } catch (e) {
      debugPrint("Error in removeServerMember: $e");
      rethrow;
    }
  }

  Future<void> updateServerMemberRole(
    String serverId,
    String userId, {
    required String role,
    bool? canInvite,
    bool? canManageRooms,
    bool? canManageServer,
  }) async {
    try {
      final data = <String, dynamic>{"role": role};
      if (canInvite != null) data["can_invite"] = canInvite;
      if (canManageRooms != null) data["can_manage_rooms"] = canManageRooms;
      if (canManageServer != null) {
        data["can_manage_server"] = canManageServer;
      }
      await dio.patch("/api/servers/$serverId/members/$userId", data: data);
    } catch (e) {
      debugPrint("Error in updateServerMemberRole: $e");
      rethrow;
    }
  }

  Future<MessagePage?> getRoomMessages(
    String roomId, {
    int limit = 25,
    String? cursor,
  }) async {
    try {
      final Map<String, dynamic> queryParameters = {"limit": limit};
      if (cursor != null) queryParameters["cursor"] = cursor;

      final res = await dio.get(
        "/api/rooms/$roomId/messages/",
        queryParameters: queryParameters,
      );
      if (res.statusCode == 200 && res.data != null) {
        return MessagePage.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("Error in getRoomMessages: $e");
    }
    return null;
  }

  // Direct Messages
  Future<List<DirectRoom>> getDirectRooms() async {
    try {
      final res = await dio.get("/api/direct/rooms");
      if (res.statusCode == 200 && res.data != null) {
        if (res.data is List) {
          return (res.data as List)
              .map((e) => DirectRoom.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint("Error in getDirectRooms: $e");
    }
    return [];
  }

  Future<MessagePage?> getDirectMessages(
    String roomId, {
    int limit = 25,
    String? cursor,
  }) async {
    try {
      final Map<String, dynamic> queryParameters = {"limit": limit};
      if (cursor != null) queryParameters["cursor"] = cursor;

      final res = await dio.get(
        "/api/direct/rooms/$roomId/messages",
        queryParameters: queryParameters,
      );
      if (res.statusCode == 200 && res.data != null) {
        return MessagePage.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("Error in getDirectMessages: $e");
    }
    return null;
  }

  Future<DirectRoom?> createDirectRoom(List<String> userIds) async {
    try {
      final res = await dio.post(
        "/api/direct/rooms",
        data: {"user_ids": userIds},
      );
      if ((res.statusCode == 200 || res.statusCode == 201) &&
          res.data != null) {
        return DirectRoom.fromJson(res.data);
      }
    } catch (e) {
      debugPrint("Error in createDirectRoom: $e");
    }
    return null;
  }

  // Friends
  Future<List<User>> getFriends(String userId) async {
    try {
      final res = await dio.get("/api/users/friends/$userId");
      if (res.statusCode == 200 && res.data != null) {
        if (res.data is List) {
          return (res.data as List)
              .map((e) => User.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint("Error in getFriends: $e");
    }
    return [];
  }

  Future<List<FriendRequest>> getFriendRequests({
    int limit = 50,
    String? cursor,
  }) async {
    try {
      final Map<String, dynamic> queryParameters = {"limit": limit};
      if (cursor != null) queryParameters["cursor"] = cursor;

      final res = await dio.get(
        "/api/users/friends/request/",
        queryParameters: queryParameters,
      );
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data;
        if (data is Map<String, dynamic> && data["requests"] is List) {
          List requests = data["requests"];
          return requests
              .map((e) => FriendRequest.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint("Error in getFriendRequests: $e");
    }
    return [];
  }

  Future<void> createFriendRequest(String friendId) async {
    try {
      await dio.post("/api/users/friends/request/$friendId");
    } catch (e) {
      debugPrint("Error in createFriendRequest: $e");
      rethrow;
    }
  }

  Future<void> acceptFriendRequest(String friendId) async {
    try {
      await dio.post("/api/users/friends/request/$friendId/accept");
    } catch (e) {
      debugPrint("Error in acceptFriendRequest: $e");
      rethrow;
    }
  }

  Future<void> rejectFriendRequest(String friendId) async {
    try {
      await dio.post("/api/users/friends/request/$friendId/reject");
    } catch (e) {
      debugPrint("Error in rejectFriendRequest: $e");
      rethrow;
    }
  }

  Future<void> deleteFriend(String friendId) async {
    try {
      await dio.delete("/api/users/friends/$friendId");
    } catch (e) {
      debugPrint("Error in deleteFriend: $e");
      rethrow;
    }
  }

  Future<void> pinMessage(String messageId) async {
    try {
      await dio.put("/api/messages/$messageId/pin");
    } catch (e) {
      debugPrint("Error in pinMessage: $e");
      rethrow;
    }
  }

  Future<void> unpinMessage(String messageId) async {
    try {
      await dio.delete("/api/messages/$messageId/pin");
    } catch (e) {
      debugPrint("Error in unpinMessage: $e");
      rethrow;
    }
  }

  Future<List<ChatMessage>> getPinnedMessages(String roomId) async {
    try {
      final res = await dio.get("/api/rooms/$roomId/pins");
      if (res.statusCode == 200 && res.data is List) {
        return (res.data as List)
            .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint("Error in getPinnedMessages: $e");
    }
    return [];
  }

  Future<void> markMessageRead(
    String roomId,
    String messageId, {
    bool isDirect = false,
  }) async {
    try {
      final path = isDirect
          ? "/api/direct/rooms/$roomId/messages/$messageId/read"
          : "/api/rooms/$roomId/messages/read-all";
      await dio.put(path);
    } catch (e) {
      debugPrint("Error in markMessageRead: $e");
    }
  }

  Future<ChatMessage?> sendRoomMessage(
    String roomId,
    String content, {
    String type = "text",
    String? mediaUrl,
    List<String>? attachmentIds,
  }) async {
    try {
      final data = <String, dynamic>{"content": content, "type": type};
      if (mediaUrl != null) data["media_url"] = mediaUrl;
      if (attachmentIds != null) data["attachment_ids"] = attachmentIds;

      debugPrint("ApiClient: sending room message to $roomId, data: $data");
      final res = await dio.post("/api/rooms/$roomId/messages/", data: data);
      debugPrint("ApiClient: room message response: ${res.statusCode}");
      if (res.data is Map<String, dynamic>) {
        return ChatMessage.fromJson(res.data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint("Error in sendRoomMessage: $e");
      rethrow;
    }
  }

  Future<ChatMessage?> sendDirectMessage(
    String roomId,
    String content, {
    String type = "text",
    String? mediaUrl,
    List<String>? attachmentIds,
  }) async {
    try {
      final data = <String, dynamic>{"content": content, "type": type};
      if (mediaUrl != null) data["media_url"] = mediaUrl;
      if (attachmentIds != null) data["attachment_ids"] = attachmentIds;

      final res = await dio.post(
        "/api/direct/rooms/$roomId/messages",
        data: data,
      );
      if (res.data is Map<String, dynamic>) {
        return ChatMessage.fromJson(res.data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint("Error in sendDirectMessage: $e");
      rethrow;
    }
  }

  Future<User?> updateProfile(Map<String, dynamic> data) async {
    try {
      final res = await dio.patch("/api/private/me", data: data);
      if (res.statusCode == 200 && res.data != null) {
        return User.fromJson(res.data);
      }
      return null;
    } catch (e) {
      debugPrint("Error in updateProfile: $e");
      return null;
    }
  }

  Future<List<User>> searchUsers(String query) async {
    try {
      final res = await dio.get(
        "/api/users/search",
        queryParameters: {"q": query},
      );
      if (res.statusCode == 200 && res.data != null) {
        if (res.data is List) {
          return (res.data as List)
              .map((e) => User.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint("Error in searchUsers: $e");
    }
    return [];
  }

  // Files
  Future<Attachment?> uploadFile(String kind, File file) async {
    try {
      String fileName = file.path.split('/').last;
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(file.path, filename: fileName),
      });

      final res = await dio.post("/api/files/$kind", data: formData);
      if (res.statusCode == 201 && res.data != null) {
        return Attachment.fromJson(res.data);
      }
      return null;
    } catch (e) {
      debugPrint("Error in uploadFile: $e");
      return null;
    }
  }

  Future<Uint8List?> getFileBytes(String url) async {
    final fullUrl = _fullFileUrl(url);

    if (_fileCache.containsKey(fullUrl)) return _fileCache[fullUrl];
    try {
      final response = await dio.get(
        fullUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode == 200) {
        final bytes = Uint8List.fromList(response.data);
        _fileCache[fullUrl] = bytes;
        _metadataCache[fullUrl] = {
          'size': bytes.length,
          'type': response.headers.value('content-type'),
        };
        return bytes;
      }
    } catch (e) {
      debugPrint("Error fetching file bytes from $fullUrl: $e");
    }
    return null;
  }

  Future<Map<String, dynamic>?> getFileMetadata(String url) async {
    final fullUrl = _fullFileUrl(url);

    if (_metadataCache.containsKey(fullUrl)) return _metadataCache[fullUrl];
    try {
      final res = await dio.head(fullUrl);
      if (res.statusCode == 200) {
        final metadata = {
          'size': int.tryParse(res.headers.value('content-length') ?? '0') ?? 0,
          'type': res.headers.value('content-type'),
        };
        _metadataCache[fullUrl] = metadata;
        return metadata;
      }
    } catch (e) {
      debugPrint("Error fetching metadata for $fullUrl: $e");
    }
    return null;
  }

  Future<void> downloadFile(
    String url,
    String savePath, {
    void Function(int count, int total)? onReceiveProgress,
  }) async {
    final fullUrl = _fullFileUrl(url);

    try {
      await dio.download(
        fullUrl,
        savePath,
        onReceiveProgress: onReceiveProgress,
      );
    } catch (e) {
      debugPrint("Error downloading file from $fullUrl to $savePath: $e");
      rethrow;
    }
  }

  Future<File?> getCachedFile(String url, {String? fileName}) async {
    final fullUrl = _fullFileUrl(url);
    final extension = p.extension(
      fileName?.trim().isNotEmpty == true
          ? fileName!
          : Uri.tryParse(fullUrl)?.path ?? '',
    );
    final cacheName = '${_stableFileKey(fullUrl)}$extension';
    final cacheDir = Directory(
      p.join(Directory.systemTemp.path, 'gritos-files'),
    );
    final file = File(p.join(cacheDir.path, cacheName));

    if (await file.exists() && await file.length() > 0) return file;

    try {
      await cacheDir.create(recursive: true);
      final response = await dio.get<List<int>>(
        fullUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode == 200 && response.data != null) {
        final bytes = Uint8List.fromList(response.data!);
        await file.writeAsBytes(bytes, flush: true);
        _fileCache[fullUrl] = bytes;
        _metadataCache[fullUrl] = {
          'size': bytes.length,
          'type': response.headers.value('content-type'),
        };
        return file;
      }
    } catch (e) {
      debugPrint("Error caching file from $fullUrl: $e");
    }
    return null;
  }

  String _fullFileUrl(String url) {
    if (url.startsWith("http")) return url;
    final cleanUrl = url.startsWith('/') ? url : '/$url';
    return "$baseUrl$cleanUrl";
  }

  String _stableFileKey(String value) {
    final bytes = utf8.encode(value);
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }
}

class ApiRequestError {
  final int? statusCode;
  final String message;

  const ApiRequestError({required this.statusCode, required this.message});
}

class _RetryInterceptor extends QueuedInterceptor {
  static const _maxRetries = 2;
  static const _retryableMethods = {
    'GET',
    'HEAD',
    'OPTIONS',
    'PUT',
    'PATCH',
    'DELETE',
  };

  final Dio _dio;
  final void Function(ApiRequestError error)? Function() _errorHandler;

  _RetryInterceptor(this._dio, this._errorHandler);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    final retryCount = request.extra['retry_count'] as int? ?? 0;

    if (retryCount >= _maxRetries ||
        !_canRetry(request) ||
        !_isTransient(err)) {
      _emitRequestError(err);
      handler.next(err);
      return;
    }

    request.extra['retry_count'] = retryCount + 1;
    await Future<void>.delayed(_retryDelay(retryCount));

    try {
      final response = await _dio.fetch<dynamic>(request);
      handler.resolve(response);
    } on DioException catch (e) {
      _emitRequestError(e);
      handler.next(e);
    } catch (e) {
      final next = DioException(
        requestOptions: request,
        error: e,
        type: DioExceptionType.unknown,
      );
      _emitRequestError(next);
      handler.next(next);
    }
  }

  void _emitRequestError(DioException err) {
    final statusCode = err.response?.statusCode;
    if (statusCode == null || statusCode < 400) return;
    if (err.requestOptions.extra['error_notice_emitted'] == true) return;
    err.requestOptions.extra['error_notice_emitted'] = true;
    _errorHandler()?.call(
      ApiRequestError(statusCode: statusCode, message: _messageForError(err)),
    );
  }

  String _messageForError(DioException err) {
    final statusCode = err.response?.statusCode;
    final data = err.response?.data;
    String? serverMessage;
    if (data is Map) {
      serverMessage =
          data['message']?.toString() ??
          data['error']?.toString() ??
          data['detail']?.toString();
    } else if (data is String && data.trim().isNotEmpty) {
      serverMessage = data.trim();
    }
    final prefix = statusCode == null ? 'Request failed' : 'HTTP $statusCode';
    return serverMessage == null ? prefix : '$prefix: $serverMessage';
  }

  bool _canRetry(RequestOptions request) {
    if (!_retryableMethods.contains(request.method.toUpperCase())) {
      return false;
    }
    return request.data is! FormData;
  }

  bool _isTransient(DioException err) {
    final statusCode = err.response?.statusCode;
    if (statusCode == 429 || (statusCode != null && statusCode >= 500)) {
      return true;
    }

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }

    final error = err.error;
    return error is SocketException ||
        error is HandshakeException ||
        error is TimeoutException;
  }

  Duration _retryDelay(int retryCount) {
    const delays = [Duration(milliseconds: 350), Duration(milliseconds: 900)];
    return delays[retryCount.clamp(0, delays.length - 1)];
  }
}
