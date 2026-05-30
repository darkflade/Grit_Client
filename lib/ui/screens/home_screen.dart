import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../controllers/home_controller.dart';
import '../../data/api/rest.dart';
import '../../services/storage_service.dart';
import '../../services/connection_service.dart';
import '../../data/models/server.dart';
import '../../data/models/room.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/direct_room.dart';

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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
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
        title: ValueListenableBuilder<bool>(
          valueListenable: _controller.isDirectChat,
          builder: (context, isDirect, _) {
            if (isDirect) {
              final dRoom = _controller.currentDirectRoom.value;
              return Text(
                dRoom?.getDisplayName(_controller.currentUserId ?? "") ??
                    'Direct Message',
              );
            }
            return Text(
              _controller.currentRoom.value?.name ??
                  _controller.currentServer.value?.name ??
                  'Gritos',
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              if (mounted) Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: _controller.isLoading,
              builder: (context, isLoading, child) {
                if (isLoading && _controller.chatMessages.value.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return child!;
              },
              child: _buildMessagesView(),
            ),
          ),
          _buildTypingIndicator(),
          _buildInputArea(),
        ],
      ),
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
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
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
      child: Column(
        children: <Widget>[
          UserAccountsDrawerHeader(
            accountName: ValueListenableBuilder(
              valueListenable: _controller.currentUser,
              builder: (_, user, _) => Text(user?.nickname ?? 'Loading...'),
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
                  Text(user?.status.toUpperCase() ?? ""),
                ],
              ),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: const Icon(Icons.person, size: 40),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.people),
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
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
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
    return Expanded(
      flex: 2,
      child: ValueListenableBuilder<List<Server>>(
        valueListenable: _controller.servers,
        builder: (context, servers, _) {
          return ListView.builder(
            itemCount: servers.length,
            itemBuilder: (context, index) {
              final server = servers[index];
              return ExpansionTile(
                title: Text(server.name),
                leading: const Icon(Icons.dns),
                onExpansionChanged: (exp) {
                  if (exp) _controller.selectServer(server);
                },
                children: [
                  ValueListenableBuilder<List<Room>>(
                    valueListenable: _controller.rooms,
                    builder: (context, rooms, _) {
                      return Column(
                        children: rooms
                            .map(
                              (room) => ListTile(
                                title: Text(room.name),
                                selected:
                                    _controller.currentRoom.value?.id ==
                                    room.id,
                                onTap: () {
                                  _controller.selectRoom(room);
                                  Navigator.pop(context);
                                },
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDirectRoomsList() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Direct Messages',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<List<DirectRoom>>(
              valueListenable: _controller.directRooms,
              builder: (context, dms, _) {
                return ListView.builder(
                  itemCount: dms.length,
                  itemBuilder: (context, index) {
                    final dm = dms[index];
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(
                        dm.getDisplayName(_controller.currentUserId ?? ""),
                      ),
                      selected:
                          _controller.currentDirectRoom.value?.id == dm.id,
                      onTap: () {
                        _controller.selectDirectRoom(dm);
                        Navigator.pop(context);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesView() {
    return ValueListenableBuilder<List<ChatMessage>>(
      valueListenable: _controller.chatMessages,
      builder: (context, messages, _) {
        if (messages.isEmpty && !_controller.isLoading.value) {
          return const Center(child: Text("No messages yet."));
        }
        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          itemCount: messages.length + 1,
          itemBuilder: (context, index) {
            if (index == messages.length) {
              return ValueListenableBuilder<bool>(
                valueListenable: _controller.isLoadingMore,
                builder: (_, loading, _) => loading
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
    );
  }

  Widget _buildMessageTile(ChatMessage msg, bool isMe) {
    final hasAttachments =
        msg.attachments != null && msg.attachments!.isNotEmpty;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: isMe
              ? (Theme.of(context).brightness == Brightness.dark
                    ? Colors.blue[900]
                    : Colors.blue[100])
              : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[200]),
          child: InkWell(
            onLongPress: () => _controller.pinMessage(msg.id),
            onTap: () => _controller.markAsRead(msg.id),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _controller.getNickname(msg.senderId),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                      if (msg.pinnedAt != null)
                        const Padding(
                          padding: EdgeInsets.only(left: 4.0),
                          child: Icon(
                            Icons.push_pin,
                            size: 10,
                            color: Colors.orange,
                          ),
                        ),
                    ],
                  ),
                  if (msg.content.isNotEmpty) Text(msg.content),
                  if (hasAttachments)
                    ...msg.attachments!.map((a) => _buildAttachment(a)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${msg.createdAt.hour}:${msg.createdAt.minute.toString().padLeft(2, '0')}",
                        style: const TextStyle(fontSize: 8, color: Colors.grey),
                      ),
                      if (isMe)
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Icon(
                            msg.status == "read" ? Icons.done_all : Icons.check,
                            size: 10,
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
    );
  }

  Widget _buildAttachment(dynamic a) {
    final isImage = a.contentType?.startsWith("image/") ?? false;
    final isVideo = a.contentType?.startsWith("video/") ?? false;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FutureBuilder<Uint8List?>(
                future: widget.apiClient.getFileBytes(a.url),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      height: 100,
                      width: 200,
                      color: Colors.black12,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    return Image.memory(snapshot.data!);
                  }
                  return const Icon(Icons.broken_image);
                },
              ),
            )
          else if (isVideo)
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_fill,
                      size: 40,
                      color: Colors.white70,
                    ),
                    Text(
                      a.originalName,
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file, size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      a.originalName,
                      style: const TextStyle(
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.download, size: 16),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Downloading ${a.originalName}..."),
                        ),
                      );
                      // In a real app, use path_provider and dio.download
                    },
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _controller.pickAndSendFile,
          ),
          Expanded(
            child: TextField(
              controller: _messageTextController,
              decoration: const InputDecoration(hintText: 'Type a message...'),
              onChanged: (val) =>
                  _controller.sendTypingIndicator(val.isNotEmpty),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(icon: const Icon(Icons.send), onPressed: _send),
        ],
      ),
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
