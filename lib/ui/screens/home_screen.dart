import 'package:flutter/material.dart';
import '../controllers/home_controller.dart';
import '../../data/api/rest.dart';
import '../../services/storage_service.dart';
import '../../services/connection_service.dart';
import '../../data/models/server.dart';
import '../../data/models/room.dart';
import '../../data/models/chat_message.dart';

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
    _messageTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<Room?>(
          valueListenable: _controller.currentRoom,
          builder: (_, room, __) {
            if (room != null) return Text(room.name);
            return ValueListenableBuilder<Server?>(
              valueListenable: _controller.currentServer,
              builder: (_, server, __) {
                return Text(server?.name ?? 'Home');
              },
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _controller.logout();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: ValueListenableBuilder<bool>(
        valueListenable: _controller.isLoading,
        builder: (context, isLoading, child) {
          if (isLoading && _controller.chatMessages.value.isEmpty && _controller.currentRoom.value == null && _controller.servers.value.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return ValueListenableBuilder<String?>(
            valueListenable: _controller.errorMessage,
            builder: (context, error, __) {
              if (error != null) {
                return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Error: $error', textAlign: TextAlign.center),
                    ));
              }
              return child!;
            },
          );
        },
        child: ValueListenableBuilder<Room?>(
          valueListenable: _controller.currentRoom,
          builder: (context, room, __) {
            if (room == null && _controller.currentServer.value != null && !_controller.isLoading.value) {
                return const Center(child: Text('Select a room from the drawer.'));
            }
            if (room == null && _controller.currentServer.value == null && !_controller.isLoading.value && _controller.servers.value.isEmpty) {
                 return const Center(child: Text('No servers available. Pull drawer to refresh.'));
            }
             if (room == null && _controller.currentServer.value == null && _controller.isLoading.value ){
              return const Center(child: CircularProgressIndicator());
            }
            return _buildMessagesView();
          },
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: const Text('Gritos', style: TextStyle(color: Colors.white, fontSize: 24)),
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
          ValueListenableBuilder<List<Server>>(
            valueListenable: _controller.servers,
            builder: (context, servers, __) {
              if (_controller.isLoading.value && servers.isEmpty) {
                return const Expanded(child: Center(child: CircularProgressIndicator()));
              }
              if (servers.isEmpty) {
                return const ListTile(title: Text('No servers available. Pull to refresh.'));
              }
              return Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: servers.length,
                  itemBuilder: (context, index) {
                    final server = servers[index];
                    return ValueListenableBuilder<Server?>(
                        valueListenable: _controller.currentServer,
                        builder: (context, currentServer, _)=> ExpansionTile(
                        key: PageStorageKey('server_${server.id}'),
                        initiallyExpanded: server.id == currentServer?.id,
                        leading: const Icon(Icons.dns),
                        title: Text(server.name, style: TextStyle(fontWeight: server.id == currentServer?.id ? FontWeight.bold : FontWeight.normal)),
                        onExpansionChanged: (isExpanding) {
                          if (isExpanding && server.id != currentServer?.id) {
                             _controller.selectServer(server);
                          } else if (isExpanding && server.id == currentServer?.id && _controller.rooms.value.isEmpty){
                            _controller.selectServer(server);
                          }
                        },
                        children: <Widget>[
                          ValueListenableBuilder<Server?>(
                            valueListenable: _controller.currentServer,
                            builder: (context, activeServer, __) {
                              if (activeServer?.id != server.id) {
                                return const SizedBox.shrink(); 
                              }
                              return ValueListenableBuilder<List<Room>>(
                                valueListenable: _controller.rooms,
                                builder: (context, rooms, __) {
                                  if (_controller.isLoading.value && rooms.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 20.0),
                                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                    );
                                  }
                                  if (rooms.isEmpty) {
                                    return const ListTile(title: Text('No rooms in this server.', style: TextStyle(fontStyle: FontStyle.italic)), contentPadding: EdgeInsets.only(left: 40.0));
                                  }
                                  return Column(
                                    children: rooms.map((room) {
                                      return ValueListenableBuilder<Room?>(
                                        valueListenable: _controller.currentRoom,
                                        builder: (context, currentRoom, _) => ListTile(
                                          leading: const Icon(Icons.chat_bubble_outline, size: 18),
                                          title: Text(room.name, style: TextStyle(fontWeight: room.id == currentRoom?.id ? FontWeight.bold : FontWeight.normal)),
                                          selected: room.id == currentRoom?.id,
                                          onTap: () {
                                            _controller.selectRoom(room);
                                            Navigator.pop(context); 
                                          },
                                          contentPadding: const EdgeInsets.only(left: 40.0, right: 16.0),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              );
                            }
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesView() {
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<List<ChatMessage>>(
            valueListenable: _controller.chatMessages,
            builder: (context, messages, __) {
              if (_controller.isLoading.value && messages.isEmpty && _controller.currentRoom.value != null) {
                 return const Center(child: CircularProgressIndicator());
              }
              if (messages.isEmpty && _controller.currentRoom.value != null) {
                return const Center(child: Text('No messages yet. Send one!'));
              }
              if (_controller.currentRoom.value == null) {
                return const SizedBox.shrink(); 
              }
              return ListView.builder(
                reverse: true, 
                itemCount: messages.length,
                padding: const EdgeInsets.all(8.0),
                itemBuilder: (context, index) {
                  final message = messages[index]; 
                  final isMe = message.senderId == _controller.currentUserId;

                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Card(
                      elevation: 1,
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      color: isMe ? Theme.of(context).primaryColorLight.withOpacity(0.7) : Theme.of(context).cardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.senderId,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isMe ? Colors.black54 : Theme.of(context).textTheme.bodySmall?.color),
                            ),
                            const SizedBox(height: 4),
                            Text(message.content),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageTextController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendMessage(), 
                ),
              ),
              ValueListenableBuilder<Room?>(
                valueListenable: _controller.currentRoom,
                builder: (context, currentRoom, _) => IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: currentRoom != null ? _sendMessage : null, 
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _sendMessage() {
    if (_messageTextController.text.trim().isNotEmpty) {
      _controller.sendMessage(_messageTextController.text);
      _messageTextController.clear();
    }
  }
}
