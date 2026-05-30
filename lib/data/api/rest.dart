import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:flutter/foundation.dart';

import '../models/friend_request.dart';
import '../models/server.dart';
import '../models/room.dart';
import '../models/chat_message.dart';
import '../models/user.dart';

class ApiClient {
  final Dio dio;
  final String baseUrl = "https://api.diogen.space";
  late final CookieJar cookieJar;

  ApiClient() : dio = Dio() {
    dio.httpClientAdapter = NativeAdapter();

    cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));

    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (o) => debugPrint(o.toString()),
    ));

    dio.options.baseUrl = baseUrl;
    dio.options.connectTimeout = const Duration(seconds: 5);
    dio.options.receiveTimeout = const Duration(seconds: 5);
    dio.options.headers = {
      "Accept": "application/json",
      "Content-Type": "application/json",
    };
  }

  // Auth
  Future<Response> login(String email, String password) async {
    return await dio.post("/api/auth/login", data: {
      "email": email,
      "password": password,
    });
  }

  Future<Response> register(String nickname, String email, String password) async {
    return await dio.post("/api/auth/register", data: {
      "nickname": nickname,
      "email": email,
      "password": password,
    });
  }

  Future<Response> logout() async {
    return await dio.post("/api/auth/logout");
  }

  // User
  Future<User?> getMe() async {
    try {
      final res = await dio.get("/api/private/me");
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data["data"];
        if (data is Map<String, dynamic>) {
          return User.fromJson(data);
        } else {
          debugPrint("getMe: 'data' is not a Map: $data");
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
    final res = await dio.get("/api/users/$userId");
    final data = res.data["data"];
    if (data is Map<String, dynamic>) {
      return User.fromJson(data);
    }
    throw Exception("Failed to parse user data for $userId");
  }

  // Servers & Rooms
  Future<List<Server>> getServers() async {
    try {
      final res = await dio.get("/api/servers/");
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data["data"];
        if (data is List) {
          return data.map((e) => Server.fromJson(e as Map<String, dynamic>)).toList();
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
        final data = res.data["data"];
        if (data is List) {
          return data.map((e) => Room.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint("Error in getRooms: $e");
    }
    return [];
  }

  Future<List<ChatMessage>> getRoomMessages(String roomId, {int limit = 50, String? cursor}) async {
    try {
      final Map<String, dynamic> queryParameters = {"limit": limit};
      if (cursor != null) queryParameters["cursor"] = cursor;

      final res = await dio.get("/api/rooms/$roomId/messages/", queryParameters: queryParameters);
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data["data"];
        if (data is Map<String, dynamic> && data["messages"] is List) {
          List messages = data["messages"];
          return messages.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint("Error in getRoomMessages: $e");
    }
    return [];
  }

  // Friends
  Future<List<User>> getFriends(String userId) async {
    try {
      final res = await dio.get("/api/users/friends/$userId");
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data["data"];
        if (data is List) {
          return data.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint("Error in getFriends: $e");
    }
    return [];
  }

  Future<List<FriendRequest>> getFriendRequests({int limit = 50, String? cursor}) async {
    try {
      final Map<String, dynamic> queryParameters = {"limit": limit};
      if (cursor != null) queryParameters["cursor"] = cursor;

      final res = await dio.get("/api/users/friends/request/", queryParameters: queryParameters);
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data["data"];
        if (data is Map<String, dynamic> && data["requests"] is List) {
          List requests = data["requests"];
          return requests.map((e) => FriendRequest.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint("Error in getFriendRequests: $e");
    }
    return [];
  }

  Future<void> createFriendRequest(String friendId) async {
    await dio.post("/api/users/friends/request/$friendId");
  }

  Future<void> acceptFriendRequest(String friendId) async {
    await dio.post("/api/users/friends/request/$friendId/accept");
  }

  Future<void> rejectFriendRequest(String friendId) async {
    await dio.post("/api/users/friends/request/$friendId/reject");
  }

  Future<void> deleteFriend(String friendId) async {
    await dio.delete("/api/users/friends/$friendId");
  }

  Future<List<User>> searchUsers(String query) async {
    try {
      final res = await dio.get("/api/users/search", queryParameters: {"q": query});
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data["data"];
        if (data is List) {
          return data.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint("Error in searchUsers: $e");
    }
    return [];
  }
}
