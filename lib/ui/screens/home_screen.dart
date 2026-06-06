import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../controllers/home_controller.dart';
import '../../features/calls/application/webrtc_sfu_service.dart';
import '../../data/api/rest.dart';
import '../../core/storage/storage_service.dart';
import '../../core/realtime/connection_service.dart';
import '../../data/models/server.dart';
import '../../data/models/room.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/direct_room.dart';
import '../../data/models/user.dart';
import '../../data/models/server_participant.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;
  final ConnectionService connectionService;

  const HomeScreen({
    super.key,
    required this.apiClient,
    required this.connectionService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late HomeController _controller;
  final _messageTextController = TextEditingController();
  final _scrollController = ScrollController();

  String _webrtcLabel(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return 'Connected';
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return 'Connecting';
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return 'Disconnected';
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return 'Failed';
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return 'Closed';
      default:
        return 'Preparing';
    }
  }

  Color _webrtcColor(BuildContext context, RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return const Color(0xFF14B86A);
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return Theme.of(context).colorScheme.secondary;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  @override
  void initState() {
    super.initState();
    final storageService = StorageService();
    _controller = HomeController(
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
    _scrollController.addListener(_scrollListener);
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

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return "${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}";
  }

  bool _isImage(dynamic a) {
    String type = "";
    String name = "";
    if (a is Map) {
      type = (a['content_type'] ?? a['contentType'])?.toString() ?? "";
      name = (a['original_name'] ?? a['originalName'])?.toString() ?? "";
    } else {
      type = a.contentType?.toString() ?? "";
      name = a.originalName?.toString() ?? "";
    }
    type = type.toLowerCase();
    name = name.toLowerCase();

    if (type.startsWith("image/")) return true;
    final ext = name.split('.').last;
    return ["jpg", "jpeg", "png", "gif", "webp", "bmp"].contains(ext);
  }

  bool _isVideo(dynamic a) {
    String type = "";
    String name = "";
    if (a is Map) {
      type = (a['content_type'] ?? a['contentType'])?.toString() ?? "";
      name = (a['original_name'] ?? a['originalName'])?.toString() ?? "";
    } else {
      type = a.contentType?.toString() ?? "";
      name = a.originalName?.toString() ?? "";
    }
    type = type.toLowerCase();
    name = name.toLowerCase();

    if (type.startsWith("video/")) return true;
    final ext = name.split('.').last;
    return [
      "mp4",
      "mov",
      "wmv",
      "avi",
      "avchd",
      "flv",
      "f4v",
      "swf",
      "mkv",
      "webm",
    ].contains(ext);
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _controller.loadMoreMessages();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _controller.dispose();
    _messageTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
                Theme.of(context).colorScheme.surface,
              ],
            ),
          ),
        ),
        title: AnimatedBuilder(
          animation: Listenable.merge([
            _controller.activeSfuService,
            _controller.isDirectChat,
            _controller.currentServer,
            _controller.currentRoom,
            _controller.currentDirectRoom,
          ]),
          builder: (context, _) {
            final sfu = _controller.activeSfuService.value;
            final isDirect = _controller.isDirectChat.value;
            final title = isDirect
                ? _controller.currentDirectRoom.value?.getDisplayName(
                        _controller.currentUserId ?? "",
                      ) ??
                      'Direct Message'
                : _controller.currentRoom.value?.name ??
                      _controller.currentServer.value?.name ??
                      'Gritos';
            final subtitle = sfu == null
                ? (isDirect
                      ? 'Direct chat'
                      : (_controller.currentRoom.value == null
                            ? 'Server overview'
                            : 'Messages and rooms'))
                : 'WebRTC ${_webrtcLabel(sfu.connectionStateListenable.value)}';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, overflow: TextOverflow.ellipsis),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          AnimatedBuilder(
            animation: Listenable.merge([
              _controller.isDirectChat,
              _controller.currentDirectRoom,
              _controller.currentRoom,
            ]),
            builder: (context, _) {
              final isDirect = _controller.isDirectChat.value;
              if (isDirect && _controller.currentDirectRoom.value != null) {
                return IconButton(
                  icon: const Icon(Icons.call_rounded),
                  onPressed: () {
                    final dRoom = _controller.currentDirectRoom.value!;
                    final otherUserId = dRoom.userIds.firstWhere(
                      (id) => id != _controller.currentUserId,
                      orElse: () => "",
                    );
                    if (otherUserId.isNotEmpty) {
                      _controller.callFriend(otherUserId);
                    }
                  },
                );
              }
              final currentRoom = _controller.currentRoom.value;
              if (!isDirect && currentRoom?.type == 'rtc') {
                return IconButton(
                  icon: const Icon(Icons.video_call_rounded),
                  onPressed: () => _controller.joinSfuRoom(currentRoom!.id),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              if (mounted) Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([
              _controller.isLoading,
              _controller.currentServer,
              _controller.currentRoom,
              _controller.currentDirectRoom,
              _controller.isDirectChat,
            ]),
            builder: (context, _) {
              final chatActive = _isChatActive();
              return Column(
                children: [
                  _buildActiveCallBar(),
                  Expanded(child: _buildPrimaryContent()),
                  if (chatActive) _buildTypingIndicator(),
                  if (chatActive) _buildInputArea(),
                ],
              );
            },
          ),
          _buildIncomingCallOverlay(),
        ],
      ),
    );
  }

  bool _isChatActive() {
    return _controller.isDirectChat.value ||
        _controller.currentRoom.value != null;
  }

  Widget _buildPrimaryContent() {
    if (_controller.isLoading.value &&
        _controller.chatMessages.value.isEmpty &&
        _controller.rooms.value.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isChatActive()) return _buildMessagesView();

    if (_controller.currentServer.value != null) {
      return _buildServerOverview();
    }

    return Center(
      child: Text(
        'Select a server or direct message.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildIncomingCallOverlay() {
    return ValueListenableBuilder<IncomingCall?>(
      valueListenable: _controller.incomingCall,
      builder: (context, call, _) {
        if (call == null) return const SizedBox.shrink();

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.call_rounded,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Incoming Call',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        call.initiatorNickname ?? 'Someone is calling...',
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _controller.acceptCall,
                  icon: const Icon(Icons.check_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _controller.declineCall,
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveCallBar() {
    return ValueListenableBuilder<WebRtcSfuService?>(
      valueListenable: _controller.activeSfuService,
      builder: (context, sfu, _) {
        if (sfu == null) return const SizedBox.shrink();
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Voice session',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            ValueListenableBuilder<RTCPeerConnectionState>(
                              valueListenable: sfu.connectionStateListenable,
                              builder: (context, state, _) {
                                final color = _webrtcColor(context, state);
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _buildInfoChip(
                                      context,
                                      icon: Icons.hub_rounded,
                                      label: 'WebRTC ${_webrtcLabel(state)}',
                                      color: color,
                                    ),
                                    ValueListenableBuilder<int>(
                                      valueListenable:
                                          sfu.remoteAudioTrackCount,
                                      builder: (context, remoteAudioCount, _) {
                                        return _buildInfoChip(
                                          context,
                                          icon: Icons.volume_up_rounded,
                                          label: remoteAudioCount > 0
                                              ? '$remoteAudioCount remote audio'
                                              : 'Waiting for audio',
                                          color: remoteAudioCount > 0
                                              ? const Color(0xFF14B86A)
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.outline,
                                        );
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: sfu.isMicMuted,
                          builder: (context, isMuted, _) {
                            return _buildCallAction(
                              context,
                              icon: isMuted
                                  ? Icons.mic_off_rounded
                                  : Icons.mic_rounded,
                              label: isMuted ? 'Mic off' : 'Mic on',
                              active: !isMuted,
                              onTap: _controller.toggleMic,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: sfu.isCameraOff,
                          builder: (context, isOff, _) {
                            return _buildCallAction(
                              context,
                              icon: isOff
                                  ? Icons.videocam_off_rounded
                                  : Icons.videocam_rounded,
                              label: isOff ? 'Camera off' : 'Camera on',
                              active: !isOff,
                              onTap: _controller.toggleCamera,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildCallAction(
                          context,
                          icon: Icons.tune_rounded,
                          label: 'Devices',
                          active: false,
                          onTap: () => _showCallDeviceSheet(sfu),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildCallAction(
                          context,
                          icon: Icons.call_end_rounded,
                          label: 'Leave',
                          active: false,
                          danger: true,
                          onTap: _controller.leaveSfu,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
              valueListenable: sfu.participants,
              builder: (context, participants, _) {
                if (participants.isEmpty) return const SizedBox.shrink();
                return Container(
                  height: 60,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: participants.length,
                    itemBuilder: (context, index) {
                      final userId = participants.keys.elementAt(index);
                      final state = participants[userId]!;
                      final isMuted = state['mic_muted'] == true;
                      final isCameraOff = state['camera_off'] == true;
                      unawaited(_controller.ensureUser(userId));

                      return ValueListenableBuilder<Set<String>>(
                        valueListenable: sfu.activeSpeakers,
                        builder: (context, speakers, _) {
                          final isSpeaking = speakers.contains(userId);
                          return Container(
                            margin: const EdgeInsets.only(
                              right: 12,
                              top: 8,
                              bottom: 8,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isSpeaking
                                  ? Colors.green.withValues(alpha: 0.2)
                                  : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: isSpeaking
                                  ? Border.all(color: Colors.green, width: 2)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isCameraOff ? Icons.person_off : Icons.person,
                                  size: 16,
                                  color: isSpeaking
                                      ? Theme.of(context).colorScheme.secondary
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                ValueListenableBuilder<int>(
                                  valueListenable: _controller.nicknameVersion,
                                  builder: (context, _, child) {
                                    return Text(
                                      _controller.getNickname(userId),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSpeaking
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    );
                                  },
                                ),
                                if (isMuted) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.mic_off,
                                    size: 12,
                                    color: Colors.red,
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _controller.typingUsers,
      builder: (context, users, _) {
        if (users.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                "${users.length} user${users.length > 1 ? 's are' : ' is'} typing...",
                style: const TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width.clamp(320.0, 420.0).toDouble(),
      child: Column(
        children: <Widget>[
          UserAccountsDrawerHeader(
            accountName: ValueListenableBuilder(
              valueListenable: _controller.currentUser,
              builder: (_, user, _) => Text(
                user?.nickname ?? 'Loading...',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            accountEmail: ValueListenableBuilder(
              valueListenable: _controller.currentUser,
              builder: (_, user, _) => Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _getStatusColor(user?.status ?? ""),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    user?.status.toUpperCase() ?? "",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            currentAccountPicture: ValueListenableBuilder<User?>(
              valueListenable: _controller.currentUser,
              builder: (context, user, _) {
                if (user?.avatarUrl != null) {
                  return FutureBuilder<Uint8List?>(
                    future: widget.apiClient.getFileBytes(user!.avatarUrl!),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return CircleAvatar(
                          backgroundImage: MemoryImage(snapshot.data!),
                        );
                      }
                      return CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: const Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.white,
                        ),
                      );
                    },
                  );
                }
                return CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(
                    Icons.person,
                    size: 40,
                    color: Colors.white,
                  ),
                );
              },
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(Icons.people_alt_rounded),
                  title: const Text('Friends'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/friends');
                  },
                ),
                const Divider(),
                _buildServersList(),
                const Divider(),
                _buildDirectRoomsList(),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.red),
            title: const Text(
              'Logout',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () async {
              await _controller.logout();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildServersList() {
    return ValueListenableBuilder<List<Server>>(
      valueListenable: _controller.servers,
      builder: (context, servers, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'SERVERS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            ...servers.map((server) {
              return AnimatedBuilder(
                animation: Listenable.merge([
                  _controller.currentServer,
                  _controller.currentRoom,
                ]),
                builder: (context, _) {
                  final selected =
                      _controller.currentServer.value?.id == server.id &&
                      _controller.currentRoom.value == null &&
                      !_controller.isDirectChat.value;
                  return ListTile(
                    title: Text(
                      server.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    leading: const Icon(Icons.dns_rounded),
                    selected: selected,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    onTap: () {
                      _controller.selectServer(server);
                      Navigator.pop(context);
                    },
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildDirectRoomsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'DIRECT MESSAGES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.1,
            ),
          ),
        ),
        ValueListenableBuilder<List<DirectRoom>>(
          valueListenable: _controller.directRooms,
          builder: (context, dms, _) {
            return Column(
              children: dms.map((dm) {
                return ListTile(
                  leading: const Icon(Icons.alternate_email_rounded, size: 20),
                  title: Text(
                    dm.getDisplayName(_controller.currentUserId ?? ""),
                  ),
                  selected: _controller.currentDirectRoom.value?.id == dm.id,
                  onTap: () {
                    _controller.selectDirectRoom(dm);
                    Navigator.pop(context);
                  },
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildServerOverview() {
    final server = _controller.currentServer.value;
    if (server == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: () async => _controller.selectServer(server),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Row(
            children: [
              _buildServerIcon(server, radius: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _controller.serverOnlineCount,
                      builder: (context, onlineCount, _) {
                        final total =
                            _controller.serverParticipants.value.length;
                        return Text(
                          '$onlineCount online / $total members',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildOverviewSectionHeader('Rooms'),
          ValueListenableBuilder<List<Room>>(
            valueListenable: _controller.rooms,
            builder: (context, rooms, _) {
              if (rooms.isEmpty) {
                return _buildEmptyOverviewLine('No rooms yet.');
              }
              return Column(
                children: rooms
                    .map(
                      (room) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          room.type == 'rtc'
                              ? Icons.graphic_eq_rounded
                              : Icons.tag_rounded,
                        ),
                        title: Text(room.name),
                        subtitle: Text(room.type.toUpperCase()),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _controller.selectRoom(room),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          _buildOverviewSectionHeader('Members'),
          ValueListenableBuilder<List<ServerParticipant>>(
            valueListenable: _controller.serverParticipants,
            builder: (context, participants, _) {
              if (participants.isEmpty) {
                return _buildEmptyOverviewLine('No members loaded.');
              }
              final sorted = List<ServerParticipant>.from(participants)
                ..sort((a, b) {
                  if (a.online != b.online) return a.online ? -1 : 1;
                  return a.user.nickname.compareTo(b.user.nickname);
                });
              return Column(
                children: sorted.map(_buildParticipantTile).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildEmptyOverviewLine(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildParticipantTile(ServerParticipant participant) {
    final user = participant.user;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildUserAvatar(user, radius: 20),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: participant.online
                    ? _getStatusColor(user.status)
                    : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(user.nickname, overflow: TextOverflow.ellipsis),
      subtitle: Text(participant.member.role, overflow: TextOverflow.ellipsis),
      trailing: participant.subscribed
          ? Icon(
              Icons.radio_button_checked_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
    );
  }

  Widget _buildServerIcon(Server server, {double radius = 20}) {
    if (server.iconUrl != null && server.iconUrl!.isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: widget.apiClient.getFileBytes(server.iconUrl!),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return CircleAvatar(
              radius: radius,
              backgroundImage: MemoryImage(snapshot.data!),
            );
          }
          return _defaultServerIcon(server.name, radius: radius);
        },
      );
    }
    return _defaultServerIcon(server.name, radius: radius);
  }

  Widget _defaultServerIcon(String name, {double radius = 20}) {
    final label = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }

  Widget _buildUserAvatar(User user, {double radius = 16}) {
    if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: widget.apiClient.getFileBytes(user.avatarUrl!),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return CircleAvatar(
              radius: radius,
              backgroundImage: MemoryImage(snapshot.data!),
            );
          }
          return _defaultUserAvatar(radius: radius);
        },
      );
    }
    return _defaultUserAvatar(radius: radius);
  }

  Widget _defaultUserAvatar({double radius = 16}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: Icon(
        Icons.person_rounded,
        size: radius,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }

  Widget _buildMessagesView() {
    return Column(
      children: [
        _buildPinnedMessagesBar(),
        Expanded(
          child: ValueListenableBuilder<List<ChatMessage>>(
            valueListenable: _controller.chatMessages,
            builder: (context, messages, _) {
              if (messages.isEmpty && !_controller.isLoading.value) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Text("No messages yet."),
                  ),
                );
              }
              return ListView.builder(
                controller: _scrollController,
                reverse: true,
                itemCount: messages.length + 1,
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
                itemBuilder: (context, index) {
                  if (index == messages.length) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: _controller.isLoadingMore,
                      builder: (_, loading, child) => loading
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : const SizedBox.shrink(),
                    );
                  }
                  final msg = messages[index];
                  final isMe = msg.senderId == _controller.currentUserId;
                  return _buildMessageTile(msg, isMe);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPinnedMessagesBar() {
    return ValueListenableBuilder<List<ChatMessage>>(
      valueListenable: _controller.pinnedMessages,
      builder: (context, pins, _) {
        if (pins.isEmpty) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.push_pin_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Pinned messages",
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: pins.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final message = pins[index];
                    return ActionChip(
                      avatar: const Icon(Icons.push_pin_rounded, size: 14),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          message.content.isEmpty
                              ? "Attachment"
                              : message.content,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onPressed: () => _showMessageActions(message),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageTile(ChatMessage msg, bool isMe) {
    final hasAttachments =
        msg.attachments != null && msg.attachments!.isNotEmpty;
    final hasMediaUrl = msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty;
    final isSending = msg.status == "sending";

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              _buildMessageAvatar(msg.senderId),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Card(
                margin: const EdgeInsets.symmetric(vertical: 2),
                elevation: 0,
                color: isMe
                    ? Theme.of(context).colorScheme.primary.withValues(
                        alpha: isSending ? 0.08 : 0.15,
                      )
                    : Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isMe
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                    bottomRight: isMe
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                  ),
                ),
                child: InkWell(
                  onLongPress: () => _showMessageActions(msg),
                  onTap: () => _controller.markAsRead(msg.id),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Text(
                              _controller.getNickname(msg.senderId),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        if (msg.content.isNotEmpty)
                          Text(
                            msg.content,
                            style: const TextStyle(fontSize: 15),
                          ),
                        if (hasAttachments)
                          ...msg.attachments!.map((a) => _buildAttachment(a)),
                        if (!hasAttachments && hasMediaUrl)
                          _buildAttachment({
                            "original_name": msg.content.isNotEmpty
                                ? msg.content
                                : "File",
                            "url": msg.mediaUrl!,
                            "size_bytes": 0,
                            "content_type": msg.type == "image"
                                ? "image/jpeg"
                                : "application/octet-stream",
                          }),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (msg.pinnedAt != null)
                              const Padding(
                                padding: EdgeInsets.only(right: 4.0),
                                child: Icon(
                                  Icons.push_pin_rounded,
                                  size: 10,
                                  color: Colors.orange,
                                ),
                              ),
                            Text(
                              "${msg.createdAt.hour}:${msg.createdAt.minute.toString().padLeft(2, '0')}",
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color
                                    ?.withValues(alpha: 0.5),
                              ),
                            ),
                            if (isMe)
                              Padding(
                                padding: const EdgeInsets.only(left: 4.0),
                                child: Icon(
                                  isSending
                                      ? Icons.access_time_rounded
                                      : (msg.status == "read"
                                            ? Icons.done_all_rounded
                                            : Icons.done_rounded),
                                  size: 14,
                                  color: msg.status == "read"
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageActions(ChatMessage message) {
    final isPinned = message.pinnedAt != null;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  ),
                  title: Text(isPinned ? "Unpin message" : "Pin message"),
                  onTap: () {
                    Navigator.pop(context);
                    if (isPinned) {
                      unawaited(_controller.unpinMessage(message.id));
                    } else {
                      unawaited(_controller.pinMessage(message.id));
                    }
                  },
                ),
                if (message.content.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded),
                    title: const Text("Copy text"),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Message copied"),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.done_all_rounded),
                  title: const Text("Mark as read"),
                  onTap: () {
                    Navigator.pop(context);
                    _controller.markAsRead(message.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageAvatar(String userId) {
    return ValueListenableBuilder<int>(
      valueListenable: _controller.nicknameVersion,
      builder: (context, _, child) {
        final user = _controller.getUser(userId);
        if (user?.avatarUrl != null) {
          return FutureBuilder<Uint8List?>(
            future: widget.apiClient.getFileBytes(user!.avatarUrl!),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return CircleAvatar(
                  radius: 16,
                  backgroundImage: MemoryImage(snapshot.data!),
                );
              }
              return _defaultAvatar();
            },
          );
        }
        return _defaultAvatar();
      },
    );
  }

  Widget _defaultAvatar() {
    return CircleAvatar(
      radius: 16,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(
        Icons.person,
        size: 20,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }

  Widget _buildAttachment(dynamic a) {
    final isImage = _isImage(a);
    final isVideo = _isVideo(a);

    final String urlStr = (a is Map ? a['url'] : a.url) ?? "";
    final fullUrl = urlStr.startsWith("http")
        ? urlStr
        : "${widget.apiClient.baseUrl}$urlStr";
    final String originalName =
        (a is Map
            ? (a['original_name'] ?? a['originalName'])
            : a.originalName) ??
        "File";
    final int sizeBytes =
        (a is Map ? (a['size_bytes'] ?? a['sizeBytes']) : a.sizeBytes) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        constraints: const BoxConstraints(maxWidth: 400),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isImage)
              FutureBuilder<Uint8List?>(
                future: widget.apiClient.getFileBytes(fullUrl),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      height: 180,
                      width: double.infinity,
                      color: Colors.black12,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    );
                  }
                  return Container(
                    height: 100,
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 32,
                        color: Colors.grey,
                      ),
                    ),
                  );
                },
              )
            else if (isVideo)
              Container(
                height: 180,
                width: double.infinity,
                color: Colors.black,
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.play_circle_fill_rounded,
                      size: 64,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isImage
                          ? Icons.image_rounded
                          : isVideo
                          ? Icons.movie_rounded
                          : Icons.insert_drive_file_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          originalName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (sizeBytes > 0)
                          Text(
                            _formatFileSize(sizeBytes),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.6),
                            ),
                          )
                        else
                          FutureBuilder<Map<String, dynamic>?>(
                            future: widget.apiClient.getFileMetadata(fullUrl),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return Text(
                                  "Calculating...",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withValues(alpha: 0.4),
                                  ),
                                );
                              }
                              if (snapshot.hasData &&
                                  snapshot.data != null &&
                                  snapshot.data!['size'] != null &&
                                  snapshot.data!['size'] > 0) {
                                return Text(
                                  _formatFileSize(snapshot.data!['size']),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withValues(alpha: 0.6),
                                  ),
                                );
                              }
                              return Text(
                                "0 B",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color
                                      ?.withValues(alpha: 0.4),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(
                      Icons.download_for_offline_rounded,
                      size: 22,
                    ),
                    tooltip: "Download",
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Downloading $originalName..."),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.add_circle_outline_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () async {
                final text = _messageTextController.text;
                await _controller.pickAndSendFile(text);
                if (mounted && text.isNotEmpty) {
                  _messageTextController.clear();
                  _controller.sendTypingIndicator(false);
                }
              },
            ),
            Expanded(
              child: TextField(
                controller: _messageTextController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                ),
                onChanged: (val) =>
                    _controller.sendTypingIndicator(val.isNotEmpty),
                onSubmitted: (_) => _send(),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.send_rounded,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool active,
    bool danger = false,
  }) {
    final backgroundColor = danger
        ? Theme.of(context).colorScheme.error
        : active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surface;
    final foregroundColor = danger || active
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foregroundColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCallDeviceSheet(WebRtcSfuService sfu) {
    unawaited(sfu.refreshMediaDevices());
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: ValueListenableBuilder<List<MediaDeviceInfo>>(
            valueListenable: sfu.mediaDevices,
            builder: (context, devices, _) {
              final audioInputs = devices
                  .where((d) => d.kind == 'audioinput')
                  .toList();
              final videoInputs = devices
                  .where((d) => d.kind == 'videoinput')
                  .toList();

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Call devices',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder<String?>(
                      valueListenable: sfu.selectedAudioInputId,
                      builder: (context, selectedId, _) {
                        return _buildDeviceDropdown(
                          context,
                          icon: Icons.mic_rounded,
                          label: 'Microphone',
                          selectedId: selectedId,
                          devices: audioInputs,
                          onChanged: (id) => sfu.selectAudioInput(id),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String?>(
                      valueListenable: sfu.selectedVideoInputId,
                      builder: (context, selectedId, _) {
                        return _buildDeviceDropdown(
                          context,
                          icon: Icons.videocam_rounded,
                          label: 'Camera',
                          selectedId: selectedId,
                          devices: videoInputs,
                          onChanged: (id) => sfu.selectVideoInput(id),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Camera quality',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<String>(
                      valueListenable: sfu.videoQuality,
                      builder: (context, quality, _) {
                        return Wrap(
                          spacing: 8,
                          children: ['1080p', '720p', '480p'].map((value) {
                            return ChoiceChip(
                              label: Text(value),
                              selected: quality == value,
                              onSelected: (_) => sfu.setVideoQuality(value),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<bool>(
                      valueListenable: sfu.stereoAudio,
                      builder: (context, stereo, _) {
                        return SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.spatial_audio_rounded),
                          title: const Text('Stereo capture'),
                          subtitle: const Text(
                            'Requests 2-channel 48 kHz audio when the device supports it.',
                          ),
                          value: stereo,
                          onChanged: (value) => sfu.setStereoAudio(value),
                        );
                      },
                    ),
                    TextButton.icon(
                      onPressed: sfu.refreshMediaDevices,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh devices'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDeviceDropdown(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String? selectedId,
    required List<MediaDeviceInfo> devices,
    required Future<void> Function(String? id) onChanged,
  }) {
    final selectedValue = devices.any((device) => device.deviceId == selectedId)
        ? selectedId
        : null;

    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: selectedValue,
            decoration: InputDecoration(labelText: label),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Default device'),
              ),
              ...devices.map((device) {
                final shortId = device.deviceId.length > 6
                    ? device.deviceId.substring(0, 6)
                    : device.deviceId;
                final label = device.label.isEmpty
                    ? '${device.kind ?? 'Device'} $shortId'
                    : device.label;
                return DropdownMenuItem<String?>(
                  value: device.deviceId,
                  child: Text(label, overflow: TextOverflow.ellipsis),
                );
              }),
            ],
            onChanged: (value) => unawaited(onChanged(value)),
          ),
        ),
      ],
    );
  }

  void _send() {
    if (_messageTextController.text.trim().isNotEmpty) {
      _controller.sendMessage(_messageTextController.text);
      _messageTextController.clear();
      _controller.sendTypingIndicator(false);
    }
  }
}
