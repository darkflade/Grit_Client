import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/api/rest.dart';
import '../../services/storage_service.dart';
import '../../services/connection_service.dart';
import '../../data/models/server.dart';
import '../../data/models/room.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/user.dart';

class HomeController {
  final ApiClient apiClient;
  final ConnectionService connectionService;
  final StorageService storageService;
  final Function(String message) showMessageCallback;

  final isLoading = ValueNotifier<bool>(false);
  final errorMessage = ValueNotifier<String?>(null);
  final currentUser = ValueNotifier<User?>(null);
  final servers = ValueNotifier<List<Server>>([]);
  final currentServer = ValueNotifier<Server?>(null);
  final rooms = ValueNotifier<List<Room>>([]);
  final currentRoom = ValueNotifier<Room?>(null);
  final chatMessages = ValueNotifier<List<ChatMessage>>([]);

  String? _userId;
  String? get currentUserId => _userId;

  HomeController(this.apiClient, this.connectionService, this.storageService, this.showMessageCallback);

  Future<void> initialize() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final user = await apiClient.getMe();
      if (user != null) {
        _userId = user.id;
        currentUser.value = user;
        await storageService.saveUserData(_userId!);
      } else {
        errorMessage.value = "Failed to identify user. Please try logging in again.";
        isLoading.value = false;
        return;
      }

      try {
        await connectionService.connect();
        connectionService.messageStream.listen(_handleWebSocketMessage);
        debugPrint("WS: Connected and listening via ConnectionService.");
      } catch (wsError) {
        debugPrint("WS Connection error: $wsError");
        showMessageCallback("Failed to connect to real-time service. Chat might not work.");
      }

      final fetchedServers = await apiClient.getServers();
      servers.value = fetchedServers;

      if (fetchedServers.isNotEmpty) {
        await selectServer(fetchedServers.first);
      } else {
        showMessageCallback("No servers found.");
        isLoading.value = false;
      }
    } catch (e) {
      debugPrint("Initialization error: $e");
      errorMessage.value = "Error initializing: $e";
      isLoading.value = false;
    }
  }

  Future<void> selectServer(Server server) async {
    if (currentServer.value == server && rooms.value.isNotEmpty) return;
    isLoading.value = true;
    errorMessage.value = null;

    if (currentServer.value != null) {
      connectionService.unsubscribeServer(currentServer.value!.id);
    }

    currentServer.value = server;
    currentRoom.value = null;
    chatMessages.value = [];
    rooms.value = [];

    try {
      connectionService.subscribeServer(server.id);
      final fetchedRooms = await apiClient.getRooms(server.id);
      rooms.value = fetchedRooms;
      if (fetchedRooms.isNotEmpty) {
        await selectRoom(fetchedRooms.first);
      } else {
        showMessageCallback("No rooms found in this server.");
        isLoading.value = false;
      }
    } catch (e) {
      debugPrint("Error selecting server or fetching rooms: $e");
      errorMessage.value = "Error selecting server: $e";
      isLoading.value = false;
    }
  }

  Future<void> selectRoom(Room room) async {
    if (currentRoom.value == room && chatMessages.value.isNotEmpty && !isLoading.value) return;
    isLoading.value = true;
    errorMessage.value = null;

    if (currentRoom.value != null) {
      connectionService.leaveRoom(currentRoom.value!.id);
    }

    currentRoom.value = room;
    chatMessages.value = [];

    try {
      connectionService.joinRoom(room.serverId, room.id);
      final fetchedMessages = await apiClient.getRoomMessages(room.id);
      chatMessages.value = fetchedMessages.reversed.toList();
    } catch (e) {
      debugPrint("Error selecting room or fetching messages: $e");
      errorMessage.value = "Error selecting room: $e";
    }
    isLoading.value = false;
  }

  void sendMessage(String content) {
    if (content.trim().isEmpty) return;
    if (currentRoom.value == null || currentServer.value == null) {
      showMessageCallback("No room or server selected to send a message.");
      return;
    }
    if (_userId == null) {
      showMessageCallback("User not identified. Cannot send message.");
      return;
    }

    if (connectionService.isConnected) {
      connectionService.chat(currentServer.value!.id, currentRoom.value!.id, content.trim());
    } else {
      showMessageCallback("Not connected to server. Message not sent.");
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final decodedMessage = message is String ? jsonDecode(message) : message;
      final type = decodedMessage['type'];
      final data = decodedMessage['data'];

      switch (type) {
        case 'room_chat_message':
          if (data['room_id'] == currentRoom.value?.id) {
            final chatMsg = ChatMessage.fromJson(data);
            if (!chatMessages.value.any((m) => m.id == chatMsg.id)) {
              chatMessages.value = [chatMsg, ...chatMessages.value];
            }
          }
          break;
        case 'error':
          showMessageCallback("Server error: ${data['message']}");
          break;
      }
    } catch (e) {
      debugPrint("Error processing WS message: $e");
    }
  }

  Future<void> logout() async {
    isLoading.value = true;
    try {
      await apiClient.logout();
    } catch (e) {
      debugPrint("Error calling logout API: $e");
    } finally {
      await storageService.clearAll();
      connectionService.disconnect();
      currentServer.value = null;
      currentRoom.value = null;
      servers.value = [];
      rooms.value = [];
      chatMessages.value = [];
      currentUser.value = null;
      _userId = null;
      isLoading.value = false;
    }
  }

  void dispose() {
    isLoading.dispose();
    errorMessage.dispose();
    currentUser.dispose();
    servers.dispose();
    currentServer.dispose();
    rooms.dispose();
    currentRoom.dispose();
    chatMessages.dispose();
  }
}
