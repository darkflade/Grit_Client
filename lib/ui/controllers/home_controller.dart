import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // For ValueNotifier

import '../../data/api/rest.dart';
import '../../data/api/websocket.dart';
import '../../services/storage_service.dart';
import '../../data/models/server.dart';
import '../../data/models/room.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/user.dart';

class HomeController {
  final ApiClient apiClient;
  final StorageService storageService;
  late final WsClient wsClient;
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
  String? get currentUserId => _userId; // Added public getter for userId

  HomeController(this.apiClient, this.storageService, this.showMessageCallback) {
    wsClient = WsClient(apiClient: apiClient);
  }

  Future<void> initialize() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      _userId = await storageService.getUserData();
      if (_userId == null) {
        _userId = await apiClient.getMyId();
        if (_userId != null) {
          await storageService.saveUserData(_userId!); 
        } else {
           errorMessage.value = "Failed to identify user. Please try logging in again.";
           isLoading.value = false;
           // Consider calling logout() or navigating to login here
           return;
        }
      }
      // Optionally, fetch full User object if needed by more parts of the UI
      // if (_userId != null && currentUser.value == null) {
      //   currentUser.value = await apiClient.getUserById(_userId!);
      // }

      await wsClient.connect();
      wsClient.listen(_handleWebSocketMessage);
      debugPrint("WebSocket connected and listening.");

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
    currentServer.value = server;
    currentRoom.value = null; 
    chatMessages.value = []; 
    rooms.value = [];
    try {
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
      wsClient.sendMessage("unsubscribe_room", {"room_id": currentRoom.value!.id});
    }
    currentRoom.value = room;
    chatMessages.value = [];
    try {
      wsClient.sendMessage("subscribe_room", {"room_id": room.id});
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
    if (currentRoom.value == null) {
      showMessageCallback("No room selected to send a message.");
      return;
    }
    if (_userId == null) {
      showMessageCallback("User not identified. Cannot send message.");
      return;
    }
    final messagePayload = {
      "room_id": currentRoom.value!.id,
      "content": content.trim(),
    };
    wsClient.sendMessage("send_message", messagePayload);
    // Add optimistic update if ChatMessage model supports it and _userId is available for senderId
    // final optimisticMessage = ChatMessage(
    //   id: DateTime.now().millisecondsSinceEpoch.toString(), // Temporary ID
    //   roomId: currentRoom.value!.id,
    //   senderId: _userId!, 
    //   content: content.trim(),
    //   createdAt: DateTime.now(),
    //   type: 'text' // Assuming default type
    // );
    // chatMessages.value = [optimisticMessage, ...chatMessages.value];
  }

  void _handleWebSocketMessage(dynamic message) {
    debugPrint("WS Message Received: $message");
    try {
      final decodedMessage = jsonDecode(message);
      final type = decodedMessage['type'];
      final data = decodedMessage['data'];
      if (type == 'new_message' && data['room_id'] == currentRoom.value?.id) {
        final chatMsg = ChatMessage.fromJson(data);
        // Prevent adding duplicate if optimistic update was used by checking message ID
        if (!chatMessages.value.any((m) => m.id == chatMsg.id)) {
          chatMessages.value = [chatMsg, ...chatMessages.value];
        }
      }
    } catch (e) {
      debugPrint("Error processing WS message: $e. Message was: $message");
    }
  }

  Future<void> logout() async {
    isLoading.value = true;
    try {
      await apiClient.logout();
      await storageService.clearAll();
      wsClient.close();
      currentServer.value = null;
      currentRoom.value = null;
      servers.value = [];
      rooms.value = [];
      chatMessages.value = [];
      currentUser.value = null;
      _userId = null;
    } catch (e) {
      debugPrint("Error during logout: $e");
      errorMessage.value = "Logout failed: $e";
    }
    isLoading.value = false;
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
    wsClient.close();
  }
}
