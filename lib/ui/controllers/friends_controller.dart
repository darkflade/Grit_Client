import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // For ValueNotifier

import '../../data/api/rest.dart';
import '../../services/storage_service.dart';
import '../../data/models/user.dart';
import '../../data/models/friend_request.dart';

class FriendsController {
  final ApiClient apiClient;
  final StorageService storageService;
  final Function(String message) showMessageCallback;

  // State Notifiers
  final isLoading = ValueNotifier<bool>(false);
  final errorMessage = ValueNotifier<String?>(null);
  final friends = ValueNotifier<List<User>>([]);
  final friendRequests = ValueNotifier<List<FriendRequest>>([]);

  String? _currentUserId;

  FriendsController(this.apiClient, this.storageService, this.showMessageCallback);

  Future<void> initialize() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      _currentUserId = await storageService.getUserData(); // Assuming this stores the user ID
      if (_currentUserId == null) {
        _currentUserId = await apiClient.getMyId();
        if (_currentUserId != null) {
          await storageService.saveUserData(_currentUserId!); // Save if fetched now
        } else {
          errorMessage.value = "Could not identify current user.";
          isLoading.value = false;
          return;
        }
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
      errorMessage.value = "Could not load friends: $e";
      friends.value = []; // Clear on error
    }
  }

  Future<void> _fetchFriendRequests() async {
    // Assuming getFriendRequests() implicitly knows the current user from cookies
    try {
      final fetchedRequests = await apiClient.getFriendRequests();
      friendRequests.value = fetchedRequests;
    } catch (e) {
      debugPrint("Error fetching friend requests: $e");
      errorMessage.value = "Could not load friend requests: $e";
      friendRequests.value = []; // Clear on error
    }
  }

  Future<void> acceptFriendRequest(String friendRequestId) async {
    isLoading.value = true;
    try {
      await apiClient.acceptFriendRequest(friendRequestId);
      showMessageCallback("Friend request accepted.");
      // Refresh both lists
      await Future.wait([
        _fetchFriends(),
        _fetchFriendRequests(),
      ]);
    } catch (e) {
      debugPrint("Error accepting friend request: $e");
      showMessageCallback("Failed to accept friend request: $e");
    }
    isLoading.value = false;
  }

  Future<void> rejectFriendRequest(String friendRequestId) async {
    isLoading.value = true;
    try {
      await apiClient.rejectFriendRequest(friendRequestId);
      showMessageCallback("Friend request rejected.");
      await _fetchFriendRequests(); // Refresh requests list
    } catch (e) {
      debugPrint("Error rejecting friend request: $e");
      showMessageCallback("Failed to reject friend request: $e");
    }
    isLoading.value = false;
  }

  Future<void> removeFriend(String friendId) async {
    isLoading.value = true;
    try {
      await apiClient.deleteFriend(friendId);
      showMessageCallback("Friend removed.");
      await _fetchFriends(); // Refresh friends list
    } catch (e) {
      debugPrint("Error removing friend: $e");
      showMessageCallback("Failed to remove friend: $e");
    }
    isLoading.value = false;
  }

  Future<void> sendFriendRequest(String userIdOrUsername) async {
    // Assuming createFriendRequest takes a user ID.
    // You might need a way to resolve username to ID first if API requires ID.
    isLoading.value = true;
    try {
      // For simplicity, assuming userIdOrUsername is the ID the API expects.
      // In a real app, you might search for a user by username then get their ID.
      await apiClient.createFriendRequest(userIdOrUsername);
      showMessageCallback("Friend request sent.");
      // Potentially refresh outgoing requests if you display them, or just give feedback.
    } catch (e) {
      debugPrint("Error sending friend request: $e");
      showMessageCallback("Failed to send friend request: $e");
    }
    isLoading.value = false;
  }

  void dispose() {
    isLoading.dispose();
    errorMessage.dispose();
    friends.dispose();
    friendRequests.dispose();
    debugPrint("FriendsController disposed.");
  }
}
