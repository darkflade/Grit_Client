import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../data/api/rest.dart';
import '../../services/storage_service.dart';
import '../../services/connection_service.dart';
import '../../data/models/server.dart';
import '../../data/models/room.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/user.dart';
import '../../data/models/direct_room.dart';

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
  final directRooms = ValueNotifier<List<DirectRoom>>([]);
  final currentDirectRoom = ValueNotifier<DirectRoom?>(null);
  final chatMessages = ValueNotifier<List<ChatMessage>>([]);
  final isDirectChat = ValueNotifier<bool>(false);
  final typingUsers = ValueNotifier<Set<String>>({});

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
      } catch (wsError) {
        debugPrint("WS Connection error: $wsError");
      }

      // Initial Fetch
      final fetchedServers = await apiClient.getServers();
      servers.value = fetchedServers;
      
      // Subscribe to all servers for presence updates
      for (var srv in fetchedServers) {
        connectionService.subscribeServer(srv.id);
      }
      
      final fetchedDirectRooms = await apiClient.getDirectRooms();
      directRooms.value = fetchedDirectRooms;

      // Restore State
      final lastChat = await storageService.getLastActiveChat();
      final lastServerId = lastChat['serverId'];
      final lastRoomId = lastChat['roomId'];
      final lastIsDirect = lastChat['isDirect'] as bool;

      if (lastIsDirect && lastRoomId != null) {
        final dRoom = directRooms.value.where((r) => r.id == lastRoomId).firstOrNull;
        if (dRoom != null) {
          await selectDirectRoom(dRoom);
        }
      } else if (lastServerId != null && lastRoomId != null) {
        final srv = servers.value.where((s) => s.id == lastServerId).firstOrNull;
        if (srv != null) {
          await selectServer(srv, initialRoomId: lastRoomId);
        }
      } else if (fetchedServers.isNotEmpty) {
        await selectServer(fetchedServers.first);
      } else if (fetchedDirectRooms.isNotEmpty) {
        await selectDirectRoom(fetchedDirectRooms.first);
      }
    } catch (e) {
      errorMessage.value = "Error initializing: $e";
    }
    isLoading.value = false;
  }

  void _sortMessages() {
    final list = List<ChatMessage>.from(chatMessages.value);
    // UUIDv7 is sortable lexicographically for time-ordering.
    // Newest first for reverse ListView.
    list.sort((a, b) => b.id.compareTo(a.id));
    chatMessages.value = list;
  }

  Future<void> selectServer(Server server, {String? initialRoomId}) async {
    isLoading.value = true;
    currentServer.value = server;
    currentDirectRoom.value = null;
    isDirectChat.value = false;
    rooms.value = [];
    chatMessages.value = [];
    typingUsers.value = {};

    try {
      connectionService.subscribeServer(server.id);
      final fetchedRooms = await apiClient.getRooms(server.id);
      rooms.value = fetchedRooms;
      
      if (fetchedRooms.isNotEmpty) {
        final roomToSelect = initialRoomId != null 
            ? fetchedRooms.where((r) => r.id == initialRoomId).firstOrNull ?? fetchedRooms.first
            : fetchedRooms.first;
        await selectRoom(roomToSelect);
      }
    } catch (e) {
      errorMessage.value = "Error selecting server: $e";
    }
    isLoading.value = false;
  }

  Future<void> selectRoom(Room room) async {
    isLoading.value = true;
    currentRoom.value = room;
    chatMessages.value = [];
    typingUsers.value = {};

    try {
      connectionService.joinRoom(room.serverId, room.id);
      final fetchedMessages = await apiClient.getRoomMessages(room.id);
      chatMessages.value = fetchedMessages;
      _sortMessages();
      
      await storageService.saveLastActiveChat(
        serverId: room.serverId,
        roomId: room.id,
        isDirect: false,
      );
    } catch (e) {
      errorMessage.value = "Error selecting room: $e";
    }
    isLoading.value = false;
  }

  Future<void> selectDirectRoom(DirectRoom dRoom) async {
    isLoading.value = true;
    currentDirectRoom.value = dRoom;
    currentServer.value = null;
    currentRoom.value = null;
    isDirectChat.value = true;
    chatMessages.value = [];
    typingUsers.value = {};

    try {
      final fetchedMessages = await apiClient.getDirectMessages(dRoom.id);
      chatMessages.value = fetchedMessages;
      _sortMessages();
      
      await storageService.saveLastActiveChat(
        roomId: dRoom.id,
        isDirect: true,
      );
    } catch (e) {
      errorMessage.value = "Error selecting DM: $e";
    }
    isLoading.value = false;
  }

  Future<void> pickAndSendFile() async {
    if (currentRoom.value == null && currentDirectRoom.value == null) return;
    
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      isLoading.value = true;
      try {
        final attachment = await apiClient.uploadFile("attachments", file);
        if (attachment != null) {
          sendMessage("", attachmentIds: [attachment.id]);
        }
      } catch (e) {
        showMessageCallback("Upload failed: $e");
      }
      isLoading.value = false;
    }
  }

  void sendMessage(String content, {List<String>? attachmentIds}) {
    if (content.trim().isEmpty && (attachmentIds == null || attachmentIds.isEmpty)) return;
    if (_userId == null) return;

    if (isDirectChat.value && currentDirectRoom.value != null) {
      connectionService.directMessage(currentDirectRoom.value!.id, content, attachmentIds: attachmentIds);
    } else if (currentRoom.value != null && currentServer.value != null) {
      connectionService.chat(currentServer.value!.id, currentRoom.value!.id, content, attachmentIds: attachmentIds);
    }
  }

  void sendTypingIndicator(bool isTyping) {
    final roomId = isDirectChat.value ? currentDirectRoom.value?.id : currentRoom.value?.id;
    if (roomId == null) return;
    connectionService.sendTypingIndicator(roomId, isTyping, scope: isDirectChat.value ? "direct" : "room");
  }

  void pinMessage(String messageId) {
    final roomId = isDirectChat.value ? currentDirectRoom.value?.id : currentRoom.value?.id;
    if (roomId == null) return;
    connectionService.pinMessage(roomId, messageId, isDirect: isDirectChat.value);
  }

  void markAsRead(String messageId) {
    final roomId = isDirectChat.value ? currentDirectRoom.value?.id : currentRoom.value?.id;
    if (roomId == null) return;
    connectionService.markMessageRead(roomId, messageId, isDirect: isDirectChat.value);
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final decodedMessage = message is String ? jsonDecode(message) : message;
      final type = decodedMessage['type'];
      final data = decodedMessage['data'];

      switch (type) {
        case 'room_chat_message':
          if (!isDirectChat.value && data['room_id'] == currentRoom.value?.id) {
            final chatMsg = ChatMessage.fromJson(data);
            if (!chatMessages.value.any((m) => m.id == chatMsg.id)) {
              chatMessages.value = [chatMsg, ...chatMessages.value];
              _sortMessages();
            }
          }
          break;
        case 'direct_message_created':
          if (isDirectChat.value && data['room_id'] == currentDirectRoom.value?.id) {
            final chatMsg = ChatMessage.fromJson(data);
            if (!chatMessages.value.any((m) => m.id == chatMsg.id)) {
              chatMessages.value = [chatMsg, ...chatMessages.value];
              _sortMessages();
            }
          }
          break;
        case 'typing_indicator':
          final roomId = data['room_id'];
          final activeRoomId = isDirectChat.value ? currentDirectRoom.value?.id : currentRoom.value?.id;
          if (roomId == activeRoomId) {
            final userId = data['user_id'];
            final isTyping = data['is_typing'];
            final newSet = Set<String>.from(typingUsers.value);
            if (isTyping) {
              newSet.add(userId);
            } else {
              newSet.remove(userId);
            }
            typingUsers.value = newSet;
          }
          break;
        case 'user_presence_updated':
          // Update presence in our models
          final userId = data['user_id'];
          final status = data['status'];
          
          // Update DM members
          for (var dr in directRooms.value) {
            for (var m in dr.members) {
              if (m.id == userId) {
                // This is a bit complex as members are in a list. 
                // In a real app we'd have a User cache.
                // For now, let's just trigger a UI update if needed.
              }
            }
          }
          break;
        case 'error':
          showMessageCallback("Error: ${data['message']}");
          break;
      }
    } catch (e) {
      debugPrint("Error processing WS: $e");
    }
  }

  Future<void> logout() async {
    isLoading.value = true;
    try {
      await apiClient.logout();
    } catch (_) {}
    await storageService.clearAllAuthData();
    connectionService.disconnect();
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
    directRooms.dispose();
    currentDirectRoom.dispose();
    chatMessages.dispose();
    isDirectChat.dispose();
    typingUsers.dispose();
  }
}
