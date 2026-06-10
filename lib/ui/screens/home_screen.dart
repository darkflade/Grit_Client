import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
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
import '../theme/app_theme_extension.dart';
import '../theme/app_spacing.dart';
import '../widgets/common/status_dot.dart';
import '../widgets/navigation/app_drawer_panel.dart';
import '../widgets/navigation/navigation_section_header.dart';
import '../widgets/navigation/server_tile.dart';
import '../widgets/navigation/direct_room_tile.dart';
import '../widgets/chat/messages_view.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/message_input_bar.dart';
import '../widgets/chat/message_attachment_card.dart';
import '../widgets/chat/pinned_messages_bar.dart';

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
  final StorageService _storageService = StorageService();

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

  Future<void> _downloadAttachment(String url, String fileName) async {
    try {
      if (Platform.isAndroid) {
        if (await Permission.manageExternalStorage.isRestricted) {
           // On some devices this might be restricted, fallback to basic
           await Permission.storage.request();
        } else {
           var status = await Permission.manageExternalStorage.status;
           if (!status.isGranted) {
             status = await Permission.manageExternalStorage.request();
           }
           if (!status.isGranted) {
             await Permission.storage.request();
           }
        }
      }

      String? downloadDir = await _storageService.getDownloadPath();
      if (downloadDir == null) {
        if (Platform.isAndroid) {
          downloadDir = '/storage/emulated/0/Download';
        } else {
          throw Exception("Download folder not set in Settings");
        }
      }

      final dir = Directory(downloadDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final savePath = p.join(downloadDir, fileName);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Downloading $fileName..."),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await widget.apiClient.downloadFile(
        url,
        savePath,
        onReceiveProgress: (count, total) {
          // Could show progress here if we wanted
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Downloaded to $savePath"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Download failed: $e"),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Color _webrtcColor(BuildContext context, RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return context.appColors.success;
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
    _controller.authInvalidated.addListener(_handleAuthInvalidated);
    _scrollController.addListener(_scrollListener);
  }

  void _handleAuthInvalidated() {
    if (!mounted || !_controller.authInvalidated.value) return;
    Navigator.pushReplacementNamed(context, '/login');
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
    _controller.authInvalidated.removeListener(_handleAuthInvalidated);
    _scrollController.dispose();
    _controller.dispose();
    _messageTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // From ~700px we show the navigation panel permanently on the left
        // and drop the Drawer; below that we keep the mobile Drawer flow.
        final isWide = constraints.maxWidth >= 700;
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
      drawer: isWide ? null : _buildDrawer(inDrawer: true),
      body: isWide
          ? Row(
              children: [
                _buildSideNavigation(),
                Expanded(child: _buildBodyStack()),
              ],
            )
          : _buildBodyStack(),
        );
      },
    );
  }

  /// Persistent navigation panel shown on the left for wide layouts.
  Widget _buildSideNavigation() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            _buildDrawerHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: _buildNavChildren(inDrawer: false),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            _buildNavFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyStack() {
    return Stack(
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
                  color: Theme.of(
                    context,
                  ).colorScheme.shadow.withValues(alpha: 0.2),
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
                    backgroundColor: context.appColors.success,
                    foregroundColor: context.appColors.onAccent,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _controller.declineCall,
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: context.appColors.onAccent,
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
        final isDirectCall = _controller.activeSfuIsDirectCall;
        final title = isDirectCall ? 'Voice call' : 'Media session';
        final leaveLabel = isDirectCall ? 'End' : 'Leave';
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
                            Text(
                              title,
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
                                              ? context.appColors.success
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
                      IconButton(
                        tooltip: 'Call debug',
                        icon: const Icon(Icons.bug_report_rounded),
                        onPressed: () => _showCallDebugSheet(sfu),
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
                          label: leaveLabel,
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
                                  ? context.appColors.success.withValues(
                                      alpha: 0.2,
                                    )
                                  : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: isSpeaking
                                  ? Border.all(
                                      color: context.appColors.success,
                                      width: 2,
                                    )
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
                                  Icon(
                                    Icons.mic_off,
                                    size: 12,
                                    color: Theme.of(context).colorScheme.error,
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
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: context.appColors.textMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawer({required bool inDrawer}) {
    return AppDrawerPanel(
      width: MediaQuery.of(context).size.width.clamp(320.0, 420.0).toDouble(),
      header: _buildDrawerHeader(),
      footer: _buildNavFooter(),
      children: _buildNavChildren(inDrawer: inDrawer),
    );
  }

  void _closeDrawerIfNeeded(bool inDrawer) {
    if (inDrawer) Navigator.pop(context);
  }

  Widget _buildNavFooter() {
    return ListTile(
      leading: Icon(
        Icons.logout_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        'Logout',
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontWeight: FontWeight.bold,
        ),
      ),
      onTap: () async {
        await _controller.logout();
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
      },
    );
  }

  List<Widget> _buildNavChildren({required bool inDrawer}) {
    return [
      ListTile(
        leading: const Icon(Icons.people_alt_rounded),
        title: const Text('Friends'),
        onTap: () {
          _closeDrawerIfNeeded(inDrawer);
          Navigator.pushNamed(context, '/friends');
        },
      ),
      const SizedBox(height: AppSpacing.sm),
      _buildServersList(inDrawer),
      const SizedBox(height: AppSpacing.md),
      _buildDirectRoomsList(inDrawer),
    ];
  }

  Widget _buildDrawerHeader() {
    return UserAccountsDrawerHeader(
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
            StatusDot(
              status: user?.status ?? "",
              size: 10,
              ringColor: Theme.of(context).colorScheme.surface,
              ringWidth: 1,
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
                  child: Icon(
                    Icons.person,
                    size: 40,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                );
              },
            );
          }
          return CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Icon(
              Icons.person,
              size: 40,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          );
        },
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
    );
  }

  Widget _buildServersList(bool inDrawer) {
    return ValueListenableBuilder<List<Server>>(
      valueListenable: _controller.servers,
      builder: (context, servers, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigationSectionHeader(
              label: 'Servers',
              actions: [
                IconButton(
                  tooltip: 'Accept invite',
                  icon: const Icon(Icons.input_rounded),
                  onPressed: _showAcceptInviteDialog,
                ),
                IconButton(
                  tooltip: 'Create server',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _showCreateServerDialog,
                ),
              ],
            ),
            ...servers.map((server) {
              return AnimatedBuilder(
                animation: Listenable.merge([
                  _controller.currentServer,
                  _controller.currentRoom,
                  _controller.isDirectChat,
                ]),
                builder: (context, _) {
                  final selected =
                      _controller.currentServer.value?.id == server.id &&
                      _controller.currentRoom.value == null &&
                      !_controller.isDirectChat.value;
                  return _buildServerNavTile(server, selected, inDrawer);
                },
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildServerNavTile(Server server, bool selected, bool inDrawer) {
    void onTap() {
      _controller.selectServer(server);
      _closeDrawerIfNeeded(inDrawer);
    }

    final url = server.iconUrl;
    if (url != null && url.isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: widget.apiClient.getFileBytes(url),
        builder: (context, snapshot) {
          final hasImage = snapshot.hasData && snapshot.data != null;
          return ServerTile(
            name: server.name,
            selected: selected,
            icon: hasImage ? MemoryImage(snapshot.data!) : null,
            onTap: onTap,
          );
        },
      );
    }
    return ServerTile(name: server.name, selected: selected, onTap: onTap);
  }

  Widget _buildDirectRoomsList(bool inDrawer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NavigationSectionHeader(label: 'Direct Messages'),
        ValueListenableBuilder<List<DirectRoom>>(
          valueListenable: _controller.directRooms,
          builder: (context, dms, _) {
            return AnimatedBuilder(
              animation: Listenable.merge([
                _controller.currentDirectRoom,
                _controller.isDirectChat,
              ]),
              builder: (context, _) {
                return Column(
                  children: dms
                      .map((dm) => _buildDirectNavTile(dm, inDrawer))
                      .toList(),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildDirectNavTile(DirectRoom dm, bool inDrawer) {
    final selected =
        _controller.currentDirectRoom.value?.id == dm.id &&
        _controller.isDirectChat.value;
    final title = dm.getDisplayName(_controller.currentUserId ?? "");

    String? status;
    String? avatarUrl;
    if (!dm.isGroup) {
      User? other;
      for (final member in dm.members) {
        if (member.id != _controller.currentUserId) {
          other = member;
          break;
        }
      }
      status = other?.status;
      avatarUrl = other?.avatarUrl;
    }

    void onTap() {
      _controller.selectDirectRoom(dm);
      _closeDrawerIfNeeded(inDrawer);
    }

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: widget.apiClient.getFileBytes(avatarUrl),
        builder: (context, snapshot) {
          final hasImage = snapshot.hasData && snapshot.data != null;
          return DirectRoomTile(
            title: title,
            selected: selected,
            status: status,
            avatar: hasImage ? MemoryImage(snapshot.data!) : null,
            onTap: onTap,
          );
        },
      );
    }
    return DirectRoomTile(
      title: title,
      selected: selected,
      status: status,
      onTap: onTap,
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
              IconButton(
                tooltip: 'Create invite',
                icon: const Icon(Icons.person_add_alt_1_rounded),
                onPressed: _showCreateInviteDialog,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildOverviewSectionHeader(
            'Rooms',
            action: IconButton(
              tooltip: 'Create room',
              icon: const Icon(Icons.add_rounded),
              onPressed: _showCreateRoomDialog,
            ),
          ),
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

  Widget _buildOverviewSectionHeader(String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          ?action,
        ],
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
            child: StatusDot(
              status: participant.online ? user.status : 'offline',
              size: 11,
              ringColor: Theme.of(context).colorScheme.surface,
            ),
          ),
        ],
      ),
      title: Text(user.nickname, overflow: TextOverflow.ellipsis),
      subtitle: Text(participant.member.role, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (participant.subscribed)
            Icon(
              Icons.radio_button_checked_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          PopupMenuButton<String>(
            tooltip: 'Member actions',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'role') {
                _showMemberRoleDialog(participant);
              } else if (value == 'remove') {
                _confirmRemoveMember(participant);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'role', child: Text('Change role')),
              PopupMenuItem(value: 'remove', child: Text('Remove member')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateServerDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create server'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, controller.text),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) {
      await _controller.createServer(name);
      if (mounted) Navigator.maybePop(context);
    }
  }

  Future<void> _showAcceptInviteDialog() async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept invite'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Invite token'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, controller.text),
            icon: const Icon(Icons.input_rounded),
            label: const Text('Accept'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (token != null) {
      await _controller.acceptServerInvite(token);
    }
  }

  Future<void> _showCreateRoomDialog() async {
    final controller = TextEditingController();
    var type = 'chat';
    final result = await showDialog<({String name, String type})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create room'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'chat',
                    icon: Icon(Icons.tag_rounded),
                    label: Text('Chat'),
                  ),
                  ButtonSegment(
                    value: 'rtc',
                    icon: Icon(Icons.graphic_eq_rounded),
                    label: Text('Media'),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (value) {
                  setDialogState(() => type = value.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(context, (name: controller.text, type: type)),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null) {
      await _controller.createRoom(result.name, type: result.type);
    }
  }

  Future<void> _showCreateInviteDialog() async {
    var role = 'member';
    int? expiresInHours = 24;
    final token = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create invite'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('Member')),
                  DropdownMenuItem(
                    value: 'moderator',
                    child: Text('Moderator'),
                  ),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => role = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: expiresInHours,
                decoration: const InputDecoration(labelText: 'Expires'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 hour')),
                  DropdownMenuItem(value: 24, child: Text('24 hours')),
                  DropdownMenuItem(value: 168, child: Text('7 days')),
                  DropdownMenuItem(value: null, child: Text('Never')),
                ],
                onChanged: (value) {
                  setDialogState(() => expiresInHours = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final inviteToken = await _controller.createServerInvite(
                  role: role,
                  expiresInHours: expiresInHours,
                );
                if (context.mounted) Navigator.pop(context, inviteToken);
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || token == null || token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Invite copied: $token')));
  }

  Future<void> _showMemberRoleDialog(ServerParticipant participant) async {
    var role = participant.member.role;
    var canInvite = participant.member.canInvite;
    var canManageRooms = participant.member.canManageRooms;
    var canManageServer = participant.member.canManageServer;

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(participant.user.nickname),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'member', child: Text('Member')),
                    DropdownMenuItem(
                      value: 'moderator',
                      child: Text('Moderator'),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'owner', child: Text('Owner')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => role = value);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Can invite'),
                  value: canInvite,
                  onChanged: (value) {
                    setDialogState(() => canInvite = value);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Can manage rooms'),
                  value: canManageRooms,
                  onChanged: (value) {
                    setDialogState(() => canManageRooms = value);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Can manage server'),
                  value: canManageServer,
                  onChanged: (value) {
                    setDialogState(() => canManageServer = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      await _controller.updateMemberRole(
        participant,
        role: role,
        canInvite: canInvite,
        canManageRooms: canManageRooms,
        canManageServer: canManageServer,
      );
    }
  }

  Future<void> _confirmRemoveMember(ServerParticipant participant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${participant.user.nickname}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.person_remove_rounded),
            label: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.removeServerMember(participant);
    }
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
              return MessagesView(
                scrollController: _scrollController,
                messages: messages,
                currentUserId: _controller.currentUserId ?? "",
                isLoading: _controller.isLoading.value,
                loadingFooter: ValueListenableBuilder<bool>(
                  valueListenable: _controller.isLoadingMore,
                  builder: (_, loading, child) => loading
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : const SizedBox.shrink(),
                ),
                itemBuilder: (msg, isMe, isFirstOfGroup) =>
                    _buildMessageBubble(msg, isMe, isFirstOfGroup),
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
        return PinnedMessagesBar(
          pinned: pins,
          onTap: _showMessageActions,
        );
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe, bool isFirstOfGroup) {
    final hasAttachments =
        msg.attachments != null && msg.attachments!.isNotEmpty;
    final hasMediaUrl = msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty;

    final attachments = <Widget>[];
    if (hasAttachments) {
      attachments.addAll(
        msg.attachments!.map(
          (a) => MessageAttachmentCard(
            attachment: a,
            apiClient: widget.apiClient,
            onDownload: _downloadAttachment,
          ),
        ),
      );
    } else if (hasMediaUrl) {
      attachments.add(
        MessageAttachmentCard(
          attachment: {
            "original_name": msg.content.isNotEmpty ? msg.content : "File",
            "url": msg.mediaUrl!,
            "size_bytes": 0,
            "content_type": msg.type == "image"
                ? "image/jpeg"
                : "application/octet-stream",
          },
          apiClient: widget.apiClient,
          onDownload: _downloadAttachment,
        ),
      );
    }

    final showAuthor =
        !isMe && isFirstOfGroup && !_controller.isDirectChat.value;

    return ValueListenableBuilder<int>(
      valueListenable: _controller.nicknameVersion,
      builder: (context, _, child) {
        return MessageBubble(
          message: msg,
          isMe: isMe,
          showAuthor: showAuthor,
          authorName: _controller.getNickname(msg.senderId),
          avatar: (!isMe && isFirstOfGroup)
              ? _buildMessageAvatar(msg.senderId)
              : null,
          attachments: attachments,
          onTap: () => _controller.markAsRead(msg.id),
          onLongPress: () => _showMessageActions(msg),
        );
      },
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

  Widget _buildInputArea() {
    return MessageInputBar(
      controller: _messageTextController,
      onSend: _send,
      onAttach: () async {
        final text = _messageTextController.text;
        await _controller.pickAndSendFile(text);
        if (mounted && text.isNotEmpty) {
          _messageTextController.clear();
          _controller.sendTypingIndicator(false);
        }
      },
      onChanged: (val) => _controller.sendTypingIndicator(val.isNotEmpty),
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
        ? context.appColors.onAccent
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

  void _showCallDebugSheet(WebRtcSfuService sfu) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            child: StreamBuilder<int>(
              stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
              initialData: 0,
              builder: (context, _) {
                return FutureBuilder<RtcDebugSnapshot>(
                  future: sfu.collectDebugSnapshot(),
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Call debug',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            data == null
                                ? 'Collecting...'
                                : 'Updated ${data.capturedAt.hour.toString().padLeft(2, '0')}:${data.capturedAt.minute.toString().padLeft(2, '0')}:${data.capturedAt.second.toString().padLeft(2, '0')}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 14),
                          if (data != null)
                            ...data.values.entries.map(
                              (entry) => _buildDebugRow(
                                context,
                                entry.key,
                                entry.value,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebugRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
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
