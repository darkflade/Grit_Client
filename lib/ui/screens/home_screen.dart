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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
    _controller.initialize();
  }

  @override
  void dispose() {
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
              return Text(dRoom?.getDisplayName(_controller.currentUserId ?? "") ?? 'Direct Message');
            }
            return Text(_controller.currentRoom.value?.name ?? _controller.currentServer.value?.name ?? 'Gritos');
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
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
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
              builder: (_, user, _) => Text(user?.status.toUpperCase() ?? ''),
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
                onExpansionChanged: (exp) { if (exp) _controller.selectServer(server); },
                children: [
                  ValueListenableBuilder<List<Room>>(
                    valueListenable: _controller.rooms,
                    builder: (context, rooms, _) {
                      return Column(
                        children: rooms.map((room) => ListTile(
                          title: Text(room.name),
                          selected: _controller.currentRoom.value?.id == room.id,
                          onTap: () { _controller.selectRoom(room); Navigator.pop(context); },
                        )).toList(),
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
            child: Text('Direct Messages', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      title: Text(dm.getDisplayName(_controller.currentUserId ?? "")),
                      selected: _controller.currentDirectRoom.value?.id == dm.id,
                      onTap: () { _controller.selectDirectRoom(dm); Navigator.pop(context); },
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
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            final isMe = msg.senderId == _controller.currentUserId;
            return _buildMessageTile(msg, isMe);
          },
        );
      },
    );
  }

  Widget _buildMessageTile(ChatMessage msg, bool isMe) {
    final hasAttachments = msg.attachments != null && msg.attachments!.isNotEmpty;
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: isMe ? Colors.blue[100] : Colors.grey[200],
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
                        isMe ? "You" : msg.senderId.substring(0, 8),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.grey),
                      ),
                      if (msg.pinnedAt != null) 
                        const Padding(
                          padding: EdgeInsets.only(left: 4.0),
                          child: Icon(Icons.push_pin, size: 10, color: Colors.orange),
                        ),
                    ],
                  ),
                  if (msg.content.isNotEmpty) Text(msg.content),
                  if (hasAttachments) ...msg.attachments!.map((a) => _buildAttachment(a)),
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
                            color: msg.status == "read" ? Colors.blue : Colors.grey,
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
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                "${widget.apiClient.baseUrl}${a.url}",
                headers: {"Cookie": "access_token=..."}, // This needs a proper fix with a custom ImageProvider
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file, size: 16),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    a.originalName,
                    style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
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
            onPressed: _controller.pickAndSendFile
          ),
          Expanded(
            child: TextField(
              controller: _messageTextController,
              decoration: const InputDecoration(hintText: 'Type a message...'),
              onChanged: (val) => _controller.sendTypingIndicator(val.isNotEmpty),
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
