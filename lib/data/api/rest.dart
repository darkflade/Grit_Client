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
  final String baseUrl = "https://vimh.evilempty.space";
  late final CookieJar cookieJar;

  ApiClient() : dio = Dio() {
    dio.httpClientAdapter = NativeAdapter();

    cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));

    // Add a logging interceptor for debugging
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
  // ****** UPDATED: Auth Routes ******
  Future<Response> login(String email, String password) async {
    return await dio.post("/api/auth/login", data: {
      "email": email,
      "password": password,
    });
  }

  Future<Response> register(String username, String email, String password) async {
    return await dio.post("/api/auth/register", data: {
      "username": username,
      "email": email,
      "password": password,
    });
  }

  Future<Response> logout() async {
    return await dio.post("/api/auth/logout");
  }

  // ****** UPDATED: User Route ******
  Future<String?> getMyId() async {
    try {
      final res = await dio.get("/api/private/me");
      if (res.statusCode == 200 && res.data != null) {
        // Assuming the response is {"data": {"user": {"sub": "user-id-string"}}}
        final Map<String, dynamic> data = res.data["data"];
        if (data.containsKey("id") && data["id"] is String) {
          return data["id"];
        }
      }
      return null;
    } catch (e) {
      debugPrint("Error in getMyId: $e");
      if (e is DioError) {
        debugPrint("DioError response: ${e.response}");
      }
      return null;
    }
  }
  // ****** UPDATED: Server/Room Routes ******
  Future<List<Server>> getServers() async {
    final res = await dio.get("/api/servers/");
    if (res.statusCode == 200 && res.data != null) {
      List data = res.data["data"];
      return data.map((e) => Server.fromJson(e)).toList();
    }
    return [];
  }

  Future<List<Room>> getRooms(String serverId) async {
    final res = await dio.get("/api/servers/$serverId/rooms/");
    if (res.statusCode == 200 && res.data != null) {
      List data = res.data["data"];
      return data.map((e) => Room.fromJson(e)).toList();
    }
    return [];
  }

  Future<List<ChatMessage>> getRoomMessages(String roomId) async {
    final res = await dio.get("/api/rooms/$roomId/messages/");
    if (res.statusCode == 200 && res.data != null) {
      List data = res.data["data"];
      return data.map((e) => ChatMessage.fromJson(e)).toList();
    }
    return [];
  }

  // ****** NEW: User and Friend methods ******
  Future<User> getUserById(String userId) async {
    final res = await dio.get("/api/users/$userId");
    return User.fromJson(res.data["data"]);
  }

  Future<List<User>> getFriends(String userId) async {
    final res = await dio.get("/api/private/friends/$userId");
    if (res.statusCode == 200) {
      final data = res.data["data"];
      return getMultipleUsersByIDs(data);
    }
    return [];
  }

  Future<void> deleteFriend(String friendId) async {
    await dio.delete("/api/users/friends/$friendId");
  }

  Future<void> blockUser(String friendId) async {
    await dio.post("/api/users/friends/$friendId/block");
  }

  Future<List<User>> getMultipleUsersByIDs(final dynamic ids) async {
    if (ids is List) {
      final users = <User>[];
      for (final id in ids) {
        final user = await getUserById(id.toString());
        users.add(user);
      }
      return users;
    }
    return [];
  }

  Future<List<FriendRequest>> getFriendRequests() async {
    final res = await dio.get("/api/users/friends/request/");
    if (res.statusCode == 200) {
      final data = res.data["data"];
      final users = await getMultipleUsersByIDs(data);
      final friendRequests = <FriendRequest>[];
      for (final user in users){
        friendRequests.add(
          FriendRequest(
            id: user.id,
            fromUser: user,
            status: "pending",
            createdAt: DateTime.now(),
          ),
        );
      }

      return friendRequests;
    }
    return [];
  }


  Future<void> createFriendRequest(String friendId) async {
    await dio.post("/api/users/friends/request/$friendId");
  }

  Future<void> acceptFriendRequest(String friendId) async {
    try {
      final response = await dio.post(
        "/api/users/friends/request/$friendId/accept",
        options: Options(responseType: ResponseType.plain), // <-- скажи Dio не парсить JSON
      );
      debugPrint("OK: ${response.data}");
    } on DioException catch (e) {
      if (e.response != null) {
        debugPrint("Server error : ${e.response?.statusCode} - ${e.response?.data}");
      } else {
        debugPrint("Some shit is happened $e"); // Сюда заходит и тут херня
      }
    } catch (e) {
      debugPrint("Deep shit happend $e");
      rethrow;
    }
  }

  Future<void> rejectFriendRequest(String friendId) async {
    await dio.post("/api/users/friends/request/$friendId/reject");
  }
}