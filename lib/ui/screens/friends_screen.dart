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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
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
      appBar: AppBar(
        title: const Text('Friends & Requests'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by nickname...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _controller.searchUsers("");
                  },
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => _controller.searchUsers(val),
            ),
          ),
        ),
      ),
      body: ValueListenableBuilder<bool>(
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
            padding: const EdgeInsets.all(8.0),
            children: <Widget>[
              _buildSearchResults(),
              _buildSectionTitle('Friend Requests'),
              _buildFriendRequestsList(),
              const Divider(height: 30),
              _buildSectionTitle('Your Friends'),
              _buildFriendsList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
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
            _buildSectionTitle('Search Results'),
            ...results.map(
              (user) => ListTile(
                leading: Stack(
                  children: [
                    CircleAvatar(child: Text(user.nickname[0].toUpperCase())),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getStatusColor(user.status),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                title: Text(user.nickname),
                subtitle: Text(user.status.toUpperCase()),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _controller.sendFriendRequest(user.id),
                  child: const Text("Add"),
                ),
              ),
            ),
            const Divider(),
          ],
        );
      },
    );
  }

  Widget _buildFriendRequestsList() {
    return ValueListenableBuilder<List<FriendRequest>>(
      valueListenable: _controller.friendRequests,
      builder: (context, requests, _) {
        if (requests.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No pending requests.'),
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            final otherUser = request.initiatorId == _controller.currentUserId
                ? request.friend
                : request.initiator;
            return ListTile(
              leading: CircleAvatar(
                child: Text(otherUser.nickname[0].toUpperCase()),
              ),
              title: Text(otherUser.nickname),
              subtitle: Text(
                request.initiatorId == _controller.currentUserId
                    ? 'Outgoing request'
                    : 'Incoming request',
              ),
              trailing: request.initiatorId != _controller.currentUserId
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () => _controller.acceptFriendRequest(
                            request.initiatorId,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => _controller.rejectFriendRequest(
                            request.initiatorId,
                          ),
                        ),
                      ],
                    )
                  : null,
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
      builder: (context, friends, _) {
        if (friends.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No friends yet.'),
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: friends.length,
          itemBuilder: (context, index) {
            final friend = friends[index];
            return ListTile(
              leading: Stack(
                children: [
                  CircleAvatar(child: Text(friend.nickname[0].toUpperCase())),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _getStatusColor(friend.status),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              title: Text(friend.nickname),
              subtitle: Text(friend.status.toUpperCase()),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chat, color: Colors.blue),
                    onPressed: () async {
                      final room = await _controller.startDirectChat(friend.id);
                      if (!context.mounted) return;
                      if (room != null) {
                        Navigator.pushReplacementNamed(context, '/home');
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.redAccent,
                    ),
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
