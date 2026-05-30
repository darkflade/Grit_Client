import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

import '../models/friend_request.dart';
import '../models/server.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../models/direct_room.dart';
import '../models/attachment.dart';
import '../models/message_page.dart';

class ApiClient {
  final Dio dio;
  final String baseUrl = "https://api.diogen.space";
  late final CookieJar cookieJar;

  ApiClient() : dio = Dio() {
    cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));

    dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint(o.toString()),
      ),
    );

    dio.options.baseUrl = baseUrl;
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 10);
    dio.options.headers = {
      "Accept": "application/json",
      "Content-Type": "application/json",
    };
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
      debugPrint("Error in getMe: $e");
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
    }
  }

  Future<void> unpinMessage(String messageId) async {
    try {
      await dio.delete("/api/messages/$messageId/pin");
    } catch (e) {
      debugPrint("Error in unpinMessage: $e");
    }
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
    try {
      final response = await dio.get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode == 200) {
        return Uint8List.fromList(response.data);
      }
    } catch (e) {
      debugPrint("Error fetching file bytes: $e");
    }
    return null;
  }
}
