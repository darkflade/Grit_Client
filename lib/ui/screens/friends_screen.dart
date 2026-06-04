import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../controllers/friends_controller.dart';
import '../../data/api/rest.dart';
import '../../core/storage/storage_service.dart';
import '../../core/realtime/connection_service.dart';
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
  final _searchController = TextEditingController();

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
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return Colors.green;
      case 'idle':
        return Colors.orange;
      case 'dnd':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends'), centerTitle: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search people...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: ValueListenableBuilder<bool>(
                  valueListenable: _controller.isSearching,
                  builder: (context, loading, _) => loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _controller.searchUsers("");
                          },
                        ),
                ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (val) => _controller.searchUsers(val),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: _controller.isLoading,
              builder: (context, isLoading, child) {
                if (isLoading &&
                    _controller.friends.value.isEmpty &&
                    _controller.friendRequests.value.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ValueListenableBuilder<String?>(
                  valueListenable: _controller.errorMessage,
                  builder: (context, error, _) {
                    if (error != null) {
                      return Center(child: Text('Error: $error'));
                    }
                    return child!;
                  },
                );
              },
              child: RefreshIndicator(
                onRefresh: () => _controller.initialize(),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: <Widget>[
                    _buildSearchResults(),
                    _buildFriendRequestsList(),
                    _buildFriendsList(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {int? count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Theme.of(
                context,
              ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
              letterSpacing: 1.1,
            ),
          ),
          if (count != null && count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return ValueListenableBuilder<List<User>>(
      valueListenable: _controller.searchResults,
      builder: (context, results, _) {
        if (results.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Search Results'),
            ...results.map(
              (user) => _buildUserTile(user, trailing: _buildAddButton(user)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFriendRequestsList() {
    return ValueListenableBuilder<List<FriendRequest>>(
      valueListenable: _controller.friendRequests,
      builder: (context, requests, _) {
        if (requests.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Pending Requests', count: requests.length),
            ...requests.map((request) {
              final otherUser = request.initiatorId == _controller.currentUserId
                  ? request.friend
                  : request.initiator;
              final isIncoming =
                  request.initiatorId != _controller.currentUserId;
              return _buildUserTile(
                otherUser,
                subtitle: isIncoming
                    ? 'Sent you a request'
                    : 'Waiting for response',
                trailing: isIncoming ? _buildRequestActions(request) : null,
              );
            }),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildFriendsList() {
    return ValueListenableBuilder<List<User>>(
      valueListenable: _controller.friends,
      builder: (context, friends, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Friends', count: friends.length),
            if (friends.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No friends yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ...friends.map(
                (friend) => _buildUserTile(
                  friend,
                  trailing: _buildFriendActions(friend),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUserTile(User user, {String? subtitle, Widget? trailing}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          if (user.avatarUrl != null)
            FutureBuilder<Uint8List?>(
              future: widget.apiClient.getFileBytes(user.avatarUrl!),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return CircleAvatar(
                    radius: 24,
                    backgroundImage: MemoryImage(snapshot.data!),
                  );
                }
                return _buildDefaultAvatar(user);
              },
            )
          else
            _buildDefaultAvatar(user),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _getStatusColor(user.status),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        user.nickname,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle ?? user.status.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(
            context,
          ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
        ),
      ),
      trailing: trailing,
    );
  }

  Widget _buildDefaultAvatar(User user) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.1),
      child: Text(
        user.nickname[0].toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildAddButton(User user) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(60, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        elevation: 0,
      ),
      onPressed: () => _controller.sendFriendRequest(user.id),
      child: const Text(
        "Add",
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildRequestActions(FriendRequest request) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.check_circle, color: Colors.green),
          onPressed: () => _controller.acceptFriendRequest(request.initiatorId),
        ),
        IconButton(
          icon: const Icon(Icons.cancel, color: Colors.red),
          onPressed: () => _controller.rejectFriendRequest(request.initiatorId),
        ),
      ],
    );
  }

  Widget _buildFriendActions(User friend) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.chat_bubble_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () async {
            final room = await _controller.startDirectChat(friend.id);
            if (room != null && mounted) {
              Navigator.pushReplacementNamed(context, '/home');
            }
          },
        ),
        IconButton(
          icon: Icon(
            Icons.call_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () async {
            final room = await _controller.startDirectCall(friend.id);
            if (room != null && mounted) {
              Navigator.pushReplacementNamed(context, '/home');
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.more_vert, size: 20),
          onPressed: () => _showFriendMenu(friend),
        ),
      ],
    );
  }

  void _showFriendMenu(User friend) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_remove, color: Colors.red),
              title: const Text(
                'Remove Friend',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _controller.removeFriend(friend.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
