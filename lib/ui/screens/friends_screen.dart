import 'package:flutter/material.dart';
import '../controllers/friends_controller.dart';
import '../../data/api/rest.dart';
import '../../services/storage_service.dart';
import '../../services/connection_service.dart';
import '../../data/models/user.dart';
import '../../data/models/friend_request.dart';

class FriendsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final ConnectionService connectionService;

  const FriendsScreen({
    super.key, 
    required this.apiClient,
    required this.connectionService,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late FriendsController _controller;
  final _newFriendController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final storageService = StorageService();
    _controller = FriendsController(
      widget.apiClient,
      widget.connectionService,
      storageService,
      (message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      },
    );
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _newFriendController.dispose();
    super.dispose();
  }

  void _sendFriendRequestDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send Friend Request'),
          content: TextField(
            controller: _newFriendController,
            decoration: const InputDecoration(hintText: "Enter user ID or nickname"),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Send'),
              onPressed: () {
                if (_newFriendController.text.isNotEmpty) {
                  _controller.sendFriendRequest(_newFriendController.text);
                  _newFriendController.clear();
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends & Requests'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _controller.isLoading,
            builder: (_, isLoading, _) => isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _controller.initialize(),
                  ),
          ),
        ],
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: _controller.isLoading,
        builder: (context, isLoading, child) {
          if (isLoading && _controller.friends.value.isEmpty && _controller.friendRequests.value.isEmpty) {
             return const Center(child: CircularProgressIndicator());
          }
          return ValueListenableBuilder<String?>(
            valueListenable: _controller.errorMessage,
            builder: (context, error, __) {
              if (error != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Error: $error\nPull to refresh or try again later.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return child!;
            },
          );
        },
        child: RefreshIndicator(
          onRefresh: () => _controller.initialize(),
          child: ListView(
            padding: const EdgeInsets.all(8.0),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                child: Text('Friend Requests', style: Theme.of(context).textTheme.titleLarge),
              ),
              _buildFriendRequestsList(),
              const Divider(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Your Friends', style: Theme.of(context).textTheme.titleLarge),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Friend'),
                      onPressed: _sendFriendRequestDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              _buildFriendsList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendRequestsList() {
    return ValueListenableBuilder<List<FriendRequest>>(
      valueListenable: _controller.friendRequests,
      builder: (context, requests, __) {
        if (_controller.isLoading.value && requests.isEmpty) {
          return const SizedBox.shrink(); 
        }
        if (requests.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: Text('No pending friend requests.')),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            final otherUser = request.initiatorId == _controller.currentUserId ? request.friend : request.initiator;
            return ListTile(
              leading: CircleAvatar(child: Text(otherUser.nickname.isNotEmpty ? otherUser.nickname.substring(0, 1).toUpperCase() : "?")),
              title: Text(otherUser.nickname),
              subtitle: Text(request.initiatorId == _controller.currentUserId ? 'Outgoing request' : 'Incoming request'),
              trailing: request.initiatorId != _controller.currentUserId ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _controller.acceptFriendRequest(request.initiatorId),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _controller.rejectFriendRequest(request.initiatorId),
                  ),
                ],
              ) : null,
            );
          },
          separatorBuilder: (context, index) => const Divider(),
        );
      },
    );
  }

  Widget _buildFriendsList() {
    return ValueListenableBuilder<List<User>>(
      valueListenable: _controller.friends,
      builder: (context, friends, __) {
         if (_controller.isLoading.value && friends.isEmpty) {
          return const SizedBox.shrink(); 
        }
        if (friends.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: Text('You have no friends yet. Add some!')),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: friends.length,
          itemBuilder: (context, index) {
            final friend = friends[index];
            return ListTile(
              leading: CircleAvatar(child: Text(friend.nickname.isNotEmpty ? friend.nickname.substring(0, 1).toUpperCase() : "?")),
              title: Text(friend.nickname),
              subtitle: Text(friend.status.toUpperCase()),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chat, color: Colors.blue),
                    onPressed: () async {
                      final room = await _controller.startDirectChat(friend.id);
                      if (room != null && mounted) {
                        Navigator.pushReplacementNamed(context, '/home');
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                    onPressed: () => _controller.removeFriend(friend.id),
                  ),
                ],
              ),
            );
          },
          separatorBuilder: (context, index) => const Divider(),
        );
      },
    );
  }
}
