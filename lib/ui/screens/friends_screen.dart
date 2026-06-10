import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../controllers/friends_controller.dart';
import '../../data/api/rest.dart';
import '../../core/storage/storage_service.dart';
import '../../core/realtime/connection_service.dart';
import '../../data/models/user.dart';
import '../../data/models/friend_request.dart';
import '../theme/app_theme_extension.dart';
import '../theme/app_spacing.dart';
import '../widgets/common/app_avatar.dart';
import '../widgets/common/app_card.dart';
import '../widgets/common/app_empty_state.dart';
import '../widgets/common/app_badge.dart';
import '../widgets/common/app_text_field.dart';
import '../widgets/common/section_header.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends'), centerTitle: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: AppTextField(
              controller: _searchController,
              hint: 'Search people...',
              prefixIcon: Icons.search_rounded,
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
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _controller.searchUsers("");
                        },
                      ),
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
                      return AppEmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'Something went wrong',
                        description: error,
                      );
                    }
                    return child!;
                  },
                );
              },
              child: RefreshIndicator(
                onRefresh: () => _controller.initialize(),
                child: AnimatedBuilder(
                  animation: _searchController,
                  builder: (context, _) {
                    final query = _searchController.text.trim();
                    return ListView(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                      children: query.isNotEmpty
                          ? [_buildSearchSection()]
                          : [
                              _buildFriendRequestsSection(),
                              _buildFriendsSection(),
                            ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  /// A section: an uppercase [SectionHeader] (with optional count badge) and a
  /// body — either a card with user tiles or a standalone empty state.
  Widget _buildSection({
    required String title,
    int? count,
    required Widget body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: title,
          trailing: (count != null && count > 0)
              ? AppBadge(count: count, variant: AppBadgeVariant.accent)
              : null,
        ),
        body,
      ],
    );
  }

  /// Wraps a list of user tiles in a single rounded card.
  Widget _buildTilesCard(List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: AppCard(
        padding: EdgeInsets.zero,
        clipContent: true,
        child: Column(children: tiles),
      ),
    );
  }

  Widget _buildSearchSection() {
    return ValueListenableBuilder<List<User>>(
      valueListenable: _controller.searchResults,
      builder: (context, results, _) {
        if (results.isNotEmpty) {
          return _buildSection(
            title: 'Search Results',
            body: _buildTilesCard(
              results
                  .map(
                    (user) =>
                        _buildUserTile(user, trailing: _buildAddButton(user)),
                  )
                  .toList(),
            ),
          );
        }
        return ValueListenableBuilder<bool>(
          valueListenable: _controller.isSearching,
          builder: (context, searching, _) {
            if (searching) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return const AppEmptyState(
              icon: Icons.person_search_rounded,
              title: 'No people found',
              description: 'Try a different name or username.',
            );
          },
        );
      },
    );
  }

  Widget _buildFriendRequestsSection() {
    return ValueListenableBuilder<List<FriendRequest>>(
      valueListenable: _controller.friendRequests,
      builder: (context, requests, _) {
        if (requests.isEmpty) {
          return _buildSection(
            title: 'Pending Requests',
            body: const AppEmptyState(
              icon: Icons.mark_email_read_outlined,
              title: 'No pending requests',
              description: 'Incoming friend requests will appear here.',
            ),
          );
        }
        return _buildSection(
          title: 'Pending Requests',
          count: requests.length,
          body: _buildTilesCard(
            requests.map((request) {
              final otherUser =
                  request.initiatorId == _controller.currentUserId
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
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildFriendsSection() {
    return ValueListenableBuilder<List<User>>(
      valueListenable: _controller.friends,
      builder: (context, friends, _) {
        if (friends.isEmpty) {
          return _buildSection(
            title: 'Friends',
            body: const AppEmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No friends yet',
              description: 'Search for people above to add friends.',
            ),
          );
        }
        return _buildSection(
          title: 'Friends',
          count: friends.length,
          body: _buildTilesCard(
            friends
                .map(
                  (friend) =>
                      _buildUserTile(friend, trailing: _buildFriendActions(friend)),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildUserTile(User user, {String? subtitle, Widget? trailing}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: user.avatarUrl != null
          ? FutureBuilder<Uint8List?>(
              future: widget.apiClient.getFileBytes(user.avatarUrl!),
              builder: (context, snapshot) {
                final hasImage = snapshot.hasData && snapshot.data != null;
                return AppAvatar(
                  name: user.nickname,
                  image: hasImage ? MemoryImage(snapshot.data!) : null,
                  status: user.status,
                );
              },
            )
          : AppAvatar(name: user.nickname, status: user.status),
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
          icon: Icon(Icons.check_circle, color: context.appColors.success),
          onPressed: () => _controller.acceptFriendRequest(request.initiatorId),
        ),
        IconButton(
          icon: Icon(Icons.cancel, color: Theme.of(context).colorScheme.error),
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
              leading: Icon(
                Icons.person_remove,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Remove Friend',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
