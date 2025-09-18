import 'package:flutter/material.dart';
import '../controllers/friends_controller.dart';
import '../../data/api/rest.dart';
import '../../services/storage_service.dart';
import '../../data/models/user.dart';
import '../../data/models/friend_request.dart';

class FriendsScreen extends StatefulWidget {
  final ApiClient apiClient; // Added apiClient field

  const FriendsScreen({super.key, required this.apiClient}); // Updated constructor

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late FriendsController _controller;
  final _newFriendController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Use the ApiClient passed via the widget
    final storageService = StorageService();
    _controller = FriendsController(
      widget.apiClient, // Use widget.apiClient
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
            decoration: const InputDecoration(hintText: "Enter user ID or username"),
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
            builder: (_, isLoading, __) => isLoading
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
          // Show main loading indicator only on initial full load
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
              // If not initial loading and not error, return the main content (child)
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
                        backgroundColor: Theme.of(context).colorScheme.secondary, // Using theme color
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
          // Don't show "No pending" if it's just loading for the first time
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
            return ListTile(
              leading: CircleAvatar(child: Text(request.fromUser.username.isNotEmpty ? request.fromUser.username.substring(0, 1).toUpperCase() : "?")),
              title: Text(request.fromUser.username),
              subtitle: Text('Wants to be your friend - ${request.status}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _controller.acceptFriendRequest(request.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _controller.rejectFriendRequest(request.id),
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

  Widget _buildFriendsList() {
    return ValueListenableBuilder<List<User>>(
      valueListenable: _controller.friends,
      builder: (context, friends, __) {
         if (_controller.isLoading.value && friends.isEmpty) {
          // Don't show "You have no friends" if it's just loading for the first time
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
              leading: CircleAvatar(child: Text(friend.username.isNotEmpty ? friend.username.substring(0, 1).toUpperCase() : "?")),
              title: Text(friend.username),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                onPressed: () => _controller.removeFriend(friend.id),
              ),
            );
          },
          separatorBuilder: (context, index) => const Divider(),
        );
      },
    );
  }
}
