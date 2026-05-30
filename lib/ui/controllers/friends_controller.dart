import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/api/rest.dart';
import '../../services/storage_service.dart';
import '../../services/connection_service.dart';
import '../../data/models/user.dart';
import '../../data/models/friend_request.dart';

class FriendsController {
  final ApiClient apiClient;
  final ConnectionService connectionService;
  final StorageService storageService;
  final Function(String message) showMessageCallback;

  final isLoading = ValueNotifier<bool>(false);
  final errorMessage = ValueNotifier<String?>(null);
  final friends = ValueNotifier<List<User>>([]);
  final friendRequests = ValueNotifier<List<FriendRequest>>([]);

  String? _currentUserId;
  String? get currentUserId => _currentUserId;

  FriendsController(this.apiClient, this.connectionService, this.storageService, this.showMessageCallback);

  Future<void> initialize() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      _currentUserId = await storageService.getUserData();
      if (_currentUserId == null) {
        final user = await apiClient.getMe();
        if (user != null) {
          _currentUserId = user.id;
          await storageService.saveUserData(_currentUserId!);
        } else {
          errorMessage.value = "Could not identify current user.";
          isLoading.value = false;
          return;
        }
      }

      try {
        await connectionService.connect();
        connectionService.messageStream.listen(_handleWebSocketMessage);
      } catch (wsError) {
        debugPrint("FriendsController: WS connection error: $wsError");
      }

      await Future.wait([
        _fetchFriends(),
        _fetchFriendRequests(),
      ]);
    } catch (e) {
      debugPrint("FriendsController initialization error: $e");
      errorMessage.value = "Error initializing friends: $e";
    }
    isLoading.value = false;
  }

  Future<void> _fetchFriends() async {
    if (_currentUserId == null) return;
    try {
      final fetchedFriends = await apiClient.getFriends(_currentUserId!);
      friends.value = fetchedFriends;
    } catch (e) {
      debugPrint("Error fetching friends: $e");
      friends.value = [];
    }
  }

  Future<void> _fetchFriendRequests() async {
    try {
      final fetchedRequests = await apiClient.getFriendRequests();
      friendRequests.value = fetchedRequests;
    } catch (e) {
      debugPrint("Error fetching friend requests: $e");
      friendRequests.value = [];
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final decodedMessage = message is String ? jsonDecode(message) : message;
      final type = decodedMessage['type'];
      final data = decodedMessage['data'];

      switch (type) {
        case 'friend_request_received':
          final request = FriendRequest.fromJson(data);
          // Check if it's for us or from us (though friend_request_received usually means incoming)
          if (!friendRequests.value.any((r) => r.initiatorId == request.initiatorId && r.friendId == request.friendId)) {
            friendRequests.value = [request, ...friendRequests.value];
            final otherUser = request.initiatorId == _currentUserId ? request.friend : request.initiator;
            showMessageCallback("Friend request update: ${otherUser.nickname}");
          }
          break;
        case 'friend_request_accepted':
          _fetchFriends();
          _fetchFriendRequests();
          break;
        case 'friend_removed':
          _fetchFriends();
          break;
      }
    } catch (e) {
      debugPrint("FriendsController error processing WS message: $e");
    }
  }

  Future<void> acceptFriendRequest(String friendId) async {
    isLoading.value = true;
    try {
      await apiClient.acceptFriendRequest(friendId);
      showMessageCallback("Friend request accepted.");
      await Future.wait([
        _fetchFriends(),
        _fetchFriendRequests(),
      ]);
    } catch (e) {
      debugPrint("Error accepting friend request: $e");
      showMessageCallback("Failed to accept friend request.");
    }
    isLoading.value = false;
  }

  Future<void> rejectFriendRequest(String friendId) async {
    isLoading.value = true;
    try {
      await apiClient.rejectFriendRequest(friendId);
      showMessageCallback("Friend request rejected.");
      await _fetchFriendRequests();
    } catch (e) {
      debugPrint("Error rejecting friend request: $e");
      showMessageCallback("Failed to reject friend request.");
    }
    isLoading.value = false;
  }

  Future<void> removeFriend(String friendId) async {
    isLoading.value = true;
    try {
      await apiClient.deleteFriend(friendId);
      showMessageCallback("Friend removed.");
      await _fetchFriends();
    } catch (e) {
      debugPrint("Error removing friend: $e");
      showMessageCallback("Failed to remove friend.");
    }
    isLoading.value = false;
  }

  Future<void> sendFriendRequest(String userIdOrNickname) async {
    isLoading.value = true;
    try {
      await apiClient.createFriendRequest(userIdOrNickname);
      showMessageCallback("Friend request sent.");
    } catch (e) {
      debugPrint("Error sending friend request: $e");
      showMessageCallback("Failed to send friend request.");
    }
    isLoading.value = false;
  }

  void dispose() {
    isLoading.dispose();
    errorMessage.dispose();
    friends.dispose();
    friendRequests.dispose();
  }
}
