import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../data/api/rest.dart';
import '../../services/storage_service.dart';
import '../../services/connection_service.dart';
import '../../services/webrtc_sfu_service.dart';
import '../../data/models/server.dart';
import '../../data/models/room.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/user.dart';
import '../../data/models/direct_room.dart';
import '../../data/models/message_page.dart';

class IncomingCall {
  final String callId;
  final String roomId;
  final String initiatorId;
  String? initiatorNickname;

  IncomingCall({
    required this.callId,
    required this.roomId,
    required this.initiatorId,
    this.initiatorNickname,
  });
}

class HomeController {
  final ApiClient apiClient;
  final ConnectionService connectionService;
  final StorageService storageService;
  final Function(String message) showMessageCallback;

  final isLoading = ValueNotifier<bool>(false);
  final isLoadingMore = ValueNotifier<bool>(false);
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
  final activeSfuService = ValueNotifier<WebRtcSfuService?>(null);
  final incomingCall = ValueNotifier<IncomingCall?>(null);
  final nicknameVersion = ValueNotifier<int>(0);
  final userCache = <String, User>{}; // userId -> User

  String? _nextCursor;
  bool _hasMore = false;
  String? _userId;
  String? _activeDirectCallId;
  bool _activeCallIsDirect = false;
  Timer? _heartbeatTimer;
  String? get currentUserId => _userId;

  Completer<MessagePage?>? _snapshotCompleter;

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

      final fetchedServers = await apiClient.getServers();
      servers.value = fetchedServers;
      
      for (var srv in fetchedServers) {
        connectionService.subscribeServer(srv.id);
      }
      
      final fetchedDirectRooms = await apiClient.getDirectRooms();
      directRooms.value = fetchedDirectRooms;

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

      _startPresenceHeartbeat();
    } catch (e) {
      errorMessage.value = "Error initializing: $e";
    }
    isLoading.value = false;
  }

  void _startPresenceHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (connectionService.isConnected) {
        // Force 'online' status if we are active in the app
        apiClient.updateProfile({'status': 'online'});
      }
      
      // If we are offline according to local state, try to refresh
      if (currentUser.value?.status == 'offline') {
        apiClient.getMe().then((user) {
          if (user != null && user.status != 'offline') {
            currentUser.value = user;
          }
        });
      }
    });
  }

  void _sortMessages() {
    final list = List<ChatMessage>.from(chatMessages.value);
    list.sort((a, b) => b.id.compareTo(a.id));
    chatMessages.value = list;
  }

  String getNickname(String userId) {
    if (userId == _userId) return "You";
    return userCache[userId]?.nickname ?? userId.substring(0, 8);
  }

  User? getUser(String userId) {
    return userCache[userId];
  }

  Future<void> ensureUser(String userId) async {
    if (userId == _userId || userCache.containsKey(userId)) return;
    try {
      final user = await apiClient.getUserById(userId);
      userCache[userId] = user;
      nicknameVersion.value++;
    } catch (e) {
      debugPrint("Failed to resolve user for $userId: $e");
    }
  }

  Future<void> resolveUsers(List<ChatMessage> msgs) async {
    bool updated = false;
    for (var msg in msgs) {
      if (!userCache.containsKey(msg.senderId) && msg.senderId != _userId) {
        try {
          final user = await apiClient.getUserById(msg.senderId);
          userCache[msg.senderId] = user;
          updated = true;
        } catch (_) {}
      }
    }
    if (updated) {
      nicknameVersion.value++;
      chatMessages.value = List<ChatMessage>.from(chatMessages.value);
    }
  }

  Future<void> selectServer(Server server, {String? initialRoomId}) async {
    isLoading.value = true;
    currentServer.value = server;
    currentDirectRoom.value = null;
    isDirectChat.value = false;
    rooms.value = [];
    chatMessages.value = [];
    typingUsers.value = {};
    _nextCursor = null;
    _hasMore = false;

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
    _nextCursor = null;
    _hasMore = false;

    if (activeSfuService.value != null && activeSfuService.value!.roomId != room.id) {
       // Auto-leave RTC room if we select another room? 
       // For now, let the user manually leave or stay in call while chatting.
    }

    try {
      connectionService.joinRoom(room.serverId, room.id);
      
      if (room.type == 'rtc') {
        // Automatically join SFU for RTC rooms
        await joinSfuRoom(room.id);
      }

      final page = await _fetchMessagesSnapshot(room.id, isDirect: false);
      if (page != null) {
        chatMessages.value = page.messages;
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _sortMessages();
        _markActiveRoomRead();
        resolveUsers(page.messages);
      }
      
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
    _nextCursor = null;
    _hasMore = false;

    try {
      final page = await _fetchMessagesSnapshot(dRoom.id, isDirect: true);
      if (page != null) {
        chatMessages.value = page.messages;
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _sortMessages();
        _markActiveRoomRead();
        resolveUsers(page.messages);
      }
      
      await storageService.saveLastActiveChat(
        roomId: dRoom.id,
        isDirect: true,
      );
    } catch (e) {
      errorMessage.value = "Error selecting DM: $e";
    }
    isLoading.value = false;
  }

  Future<MessagePage?> _fetchMessagesSnapshot(String roomId, {required bool isDirect}) async {
    _snapshotCompleter = Completer<MessagePage?>();
    
    if (connectionService.isConnected) {
      if (isDirect) {
        connectionService.eventTransport.getDirectMessages(roomId, limit: 25);
      } else {
        connectionService.eventTransport.getRoomMessages(roomId, limit: 25);
      }
      
      try {
        return await _snapshotCompleter!.future.timeout(const Duration(seconds: 3));
      } catch (_) {
        debugPrint("WS snapshot timeout, falling back to REST");
      }
    }
    
    if (isDirect) {
      return await apiClient.getDirectMessages(roomId, limit: 25);
    } else {
      return await apiClient.getRoomMessages(roomId, limit: 25);
    }
  }

  Future<void> loadMoreMessages() async {
    if (isLoadingMore.value || !_hasMore || _nextCursor == null) return;
    
    isLoadingMore.value = true;
    try {
      MessagePage? page;
      if (isDirectChat.value && currentDirectRoom.value != null) {
        page = await apiClient.getDirectMessages(currentDirectRoom.value!.id, cursor: _nextCursor, limit: 25);
      } else if (currentRoom.value != null) {
        page = await apiClient.getRoomMessages(currentRoom.value!.id, cursor: _nextCursor, limit: 25);
      }

      if (page != null) {
        final currentOnes = List<ChatMessage>.from(chatMessages.value);
        currentOnes.addAll(page.messages);
        chatMessages.value = currentOnes;
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _sortMessages();
        resolveUsers(page.messages);
      }
    } catch (e) {
      debugPrint("Error loading more: $e");
    }
    isLoadingMore.value = false;
  }

  void _markActiveRoomRead() {
    final roomId = isDirectChat.value ? currentDirectRoom.value?.id : currentRoom.value?.id;
    if (roomId == null || chatMessages.value.isEmpty) return;
    
    final lastMsg = chatMessages.value.first;
    if (lastMsg.senderId != _userId && lastMsg.status != "read") {
       apiClient.markMessageRead(roomId, lastMsg.id, isDirect: isDirectChat.value);
       connectionService.markMessageRead(roomId, lastMsg.id, isDirect: isDirectChat.value);
    }
  }

  Future<void> pickAndSendFile(String currentText) async {
    if (currentRoom.value == null && currentDirectRoom.value == null) return;
    
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      
      // Optimistic UI: Add a local message showing we are uploading
      final tempId = "local-upload-${DateTime.now().millisecondsSinceEpoch}";
      final roomId = isDirectChat.value ? currentDirectRoom.value!.id : currentRoom.value!.id;
      final fileName = file.path.split('/').last;
      
      final tempMsg = ChatMessage(
        id: tempId,
        roomId: roomId,
        senderId: _userId ?? "",
        content: currentText.trim().isNotEmpty ? currentText : fileName,
        type: "file",
        status: "sending",
        createdAt: DateTime.now(),
      );
      chatMessages.value = [tempMsg, ...chatMessages.value];
      _sortMessages();

      try {
        final attachment = await apiClient.uploadFile("attachments", file);
        if (attachment != null) {
          final content = currentText.trim().isNotEmpty ? currentText : attachment.originalName;
          
          bool isImg = false;
          final ext = attachment.originalName.toLowerCase().split('.').last;
          if (["jpg", "jpeg", "png", "gif", "webp", "bmp"].contains(ext)) {
            isImg = true;
          }

          // Remove the temp message before sending the real one
          chatMessages.value = chatMessages.value.where((m) => m.id != tempId).toList();

          await sendMessage(
            content, 
            attachmentIds: [attachment.id],
            type: isImg ? "image" : "file",
            mediaUrl: attachment.url,
          );
        } else {
          _markMessageError(tempId);
        }
      } catch (e) {
        debugPrint("Upload failed: $e");
        _markMessageError(tempId);
        showMessageCallback("Upload failed: $e");
      }
    }
  }

  void _markMessageError(String id) {
    chatMessages.value = chatMessages.value.map((m) {
      if (m.id == id) {
        return ChatMessage.fromJson({...m.toJson(), 'status': 'error'});
      }
      return m;
    }).toList();
  }

  Future<void> sendMessage(
    String content, {
    List<String>? attachmentIds,
    String type = "text",
    String? mediaUrl,
  }) async {
    final hasAttachments = attachmentIds != null && attachmentIds.isNotEmpty;
    if (content.trim().isEmpty && !hasAttachments) return;
    if (_userId == null) return;

    var finalContent = content;
    // satisfy server requirement for non-empty content
    if (finalContent.trim().isEmpty && hasAttachments) {
      finalContent = "Attachment";
    }

    // Optimistic UI for text-only messages
    String? tempId;
    if (!hasAttachments) {
       tempId = "local-${DateTime.now().millisecondsSinceEpoch}";
       final roomId = isDirectChat.value ? currentDirectRoom.value!.id : currentRoom.value!.id;
       final tempMsg = ChatMessage(
         id: tempId,
         roomId: roomId,
         senderId: _userId!,
         content: finalContent,
         type: type,
         status: "sending",
         createdAt: DateTime.now(),
       );
       chatMessages.value = [tempMsg, ...chatMessages.value];
       _sortMessages();
    }

    if (hasAttachments) {
      // Use REST for messages with attachments as per documentation
      try {
        if (isDirectChat.value && currentDirectRoom.value != null) {
          await apiClient.sendDirectMessage(
            currentDirectRoom.value!.id, 
            finalContent, 
            attachmentIds: attachmentIds,
            type: type,
            mediaUrl: mediaUrl,
          );
        } else if (currentRoom.value != null) {
          await apiClient.sendRoomMessage(
            currentRoom.value!.id, 
            finalContent, 
            attachmentIds: attachmentIds,
            type: type,
            mediaUrl: mediaUrl,
          );
        }
      } catch (e) {
        if (tempId != null) _markMessageError(tempId);
        showMessageCallback("Failed to send message: $e");
      }
    } else {
      // Use WebTransport for text-only messages
      try {
        if (isDirectChat.value && currentDirectRoom.value != null) {
          connectionService.directMessage(currentDirectRoom.value!.id, finalContent, attachmentIds: attachmentIds);
        } else if (currentRoom.value != null && currentServer.value != null) {
          connectionService.chat(currentServer.value!.id, currentRoom.value!.id, finalContent, attachmentIds: attachmentIds);
        }
      } catch (e) {
        if (tempId != null) _markMessageError(tempId);
        showMessageCallback("Failed to send: $e");
      }
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

  // SFU Methods
  Future<void> joinSfuRoom(String roomId, {bool isDirectCall = false}) async {
    if (activeSfuService.value?.roomId == roomId) return;
    
    // Leave previous if any (optional, maybe support multi-room later?)
    await leaveSfu();

    _activeCallIsDirect = isDirectCall;
    // We only send direct_call_start if WE are initiating the call.
    // If we are joining an existing call (accepting), we just join SFU.
    // However, joinSfuRoom is currently used for both.
    // Let's keep it simple for now, but be aware.
    final sfu = await connectionService.joinSfuRoom(roomId);
    activeSfuService.value = sfu;
  }

  Future<void> callFriend(String userId) async {
    // 1. Find or create DM room
    isLoading.value = true;
    try {
      final room = await apiClient.createDirectRoom([userId]);
      if (room != null) {
        await selectDirectRoom(room);
        _activeCallIsDirect = true;
        connectionService.directCallStart(room.id);
        await joinSfuRoom(room.id, isDirectCall: true);
      }
    } catch (e) {
      showMessageCallback("Failed to start call: $e");
    }
    isLoading.value = false;
  }

  Future<void> acceptCall() async {
    final call = incomingCall.value;
    if (call == null) return;
    
    _activeDirectCallId = call.callId;
    incomingCall.value = null;
    
    // Select the room if not already selected
    final dRoom = directRooms.value.where((r) => r.id == call.roomId).firstOrNull;
    if (dRoom != null) {
      await selectDirectRoom(dRoom);
    }
    
    await joinSfuRoom(call.roomId, isDirectCall: true);
  }

  Future<void> declineCall() async {
    final call = incomingCall.value;
    if (call == null) return;
    
    connectionService.directCallDecline(call.roomId, call.callId);
    incomingCall.value = null;
  }

  Future<void> leaveSfu() async {
    if (activeSfuService.value != null) {
      final roomId = activeSfuService.value!.roomId;
      if (_activeCallIsDirect && _activeDirectCallId != null) {
        connectionService.directCallEnd(roomId, _activeDirectCallId!);
      }
      // We need session_id for sfu_leave. For now, we use a placeholder or 
      // track it in ConnectionService. Let's use an empty string if unknown.
      connectionService.leaveSfuRoom(roomId, "");
      activeSfuService.value = null;
      _activeDirectCallId = null;
      _activeCallIsDirect = false;
    }
  }

  void toggleMic() => activeSfuService.value?.toggleMic();
  void toggleCamera() => activeSfuService.value?.toggleCamera();

  void markAsRead(String messageId) {
    final roomId = isDirectChat.value ? currentDirectRoom.value?.id : currentRoom.value?.id;
    if (roomId == null) return;
    
    final msg = chatMessages.value.where((m) => m.id == messageId).firstOrNull;
    if (msg != null && msg.status != "read" && msg.senderId != _userId) {
       connectionService.markMessageRead(roomId, messageId, isDirect: isDirectChat.value);
    }
  }

  void _stopSfuSession(String roomId) {
    connectionService.leaveSfuRoom(roomId, "");
    activeSfuService.value = null;
    _activeDirectCallId = null;
    _activeCallIsDirect = false;
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final decodedMessage = message is String ? jsonDecode(message) : message;
      final type = decodedMessage['type'];
      final data = decodedMessage['data'];

      switch (type) {
        case 'user_presence_updated':
          final userId = data['user_id'];
          final status = data['status'];
          debugPrint("HomeController: Presence update for $userId: $status");
          if (userId == _userId) {
            final updated = User.fromJson({...currentUser.value!.toJson(), 'status': status});
            currentUser.value = updated;
          }
          if (userCache.containsKey(userId)) {
            userCache[userId] = User.fromJson({...userCache[userId]!.toJson(), 'status': status});
            nicknameVersion.value++;
          }
          break;
        case 'room_messages_snapshot':
        case 'direct_messages_snapshot':
          if (_snapshotCompleter != null && !_snapshotCompleter!.isCompleted) {
            _snapshotCompleter!.complete(MessagePage.fromJson(data));
          }
          break;
        case 'room_chat_message':
          if (!isDirectChat.value && data['room_id'] == currentRoom.value?.id) {
            _processIncomingMessage(data);
          }
          break;
        case 'direct_message_created':
          if (isDirectChat.value && data['room_id'] == currentDirectRoom.value?.id) {
            _processIncomingMessage(data);
          }
          break;
        case 'typing_indicator':
          final roomId = data['room_id'];
          final activeRoomId = isDirectChat.value ? currentDirectRoom.value?.id : currentRoom.value?.id;
          if (roomId == activeRoomId) {
            final userId = data['user_id'];
            if (userId == _userId) return; // Filter out self
            
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
        case 'message_status_updated':
        case 'direct_message_status_updated':
          final roomId = data['room_id'];
          final activeRoomId = isDirectChat.value ? currentDirectRoom.value?.id : currentRoom.value?.id;
          if (roomId == activeRoomId) {
            final msgId = data['message_id'];
            final status = data['status'];
            final newList = chatMessages.value.map((m) {
              if (m.id == msgId) {
                return ChatMessage.fromJson({...m.toJson(), 'status': status});
              }
              return m;
            }).toList();
            chatMessages.value = newList;
          }
          break;
        case 'direct_call_started':
          final roomId = data['room_id'];
          final callId = data['id'];
          final initiatorId = data['initiator_id'];
          
          if (initiatorId == _userId) {
            // We started this call
            _activeDirectCallId = callId;
            _activeCallIsDirect = true;
          } else {
            // Someone else is calling us
            final call = IncomingCall(
              callId: callId,
              roomId: roomId,
              initiatorId: initiatorId,
            );
            incomingCall.value = call;
            // Try to resolve user immediately for UI
            ensureUser(initiatorId).then((_) {
              if (incomingCall.value?.callId == callId) {
                incomingCall.value = IncomingCall(
                  callId: callId,
                  roomId: roomId,
                  initiatorId: initiatorId,
                  initiatorNickname: getNickname(initiatorId),
                );
              }
            });
          }
          break;
        case 'direct_call_ended':
        case 'direct_call_declined':
          final roomId = data['room_id'];
          final callId = data['id'];
          
          if (incomingCall.value?.callId == callId) {
            incomingCall.value = null;
          }

          if (roomId == activeSfuService.value?.roomId) {
            _stopSfuSession(roomId);
          }
          break;
        case 'sfu_left':
          final roomId = data['room_id'];
          final userId = data['user_id'];
          if (userId == _userId || userId == null) {
            // We were removed from the room or room closed
            if (roomId == activeSfuService.value?.roomId) {
               _stopSfuSession(roomId);
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

  void _processIncomingMessage(Map<String, dynamic> data) {
    final chatMsg = ChatMessage.fromJson(data);
    
    // Deduplicate: replace matching optimistic message
    bool replaced = false;
    final currentMessages = List<ChatMessage>.from(chatMessages.value);
    
    for (int i = 0; i < currentMessages.length; i++) {
      final m = currentMessages[i];
      if (m.senderId == chatMsg.senderId && m.status == "sending" && (m.content == chatMsg.content || m.id.startsWith("local"))) {
        currentMessages[i] = chatMsg;
        replaced = true;
        break;
      }
    }

    if (replaced) {
      chatMessages.value = currentMessages;
    } else if (!currentMessages.any((m) => m.id == chatMsg.id)) {
      chatMessages.value = [chatMsg, ...currentMessages];
      _sortMessages();
      _markActiveRoomRead();
      resolveUsers([chatMsg]);
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
    isLoadingMore.dispose();
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
    nicknameVersion.dispose();
    _heartbeatTimer?.cancel();
  }
}
