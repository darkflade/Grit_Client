import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/settings_controller.dart';
import '../../data/api/rest.dart';
import '../../main.dart';
import '../../core/realtime/connection_service.dart';

class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final ConnectionService connectionService;

  const SettingsScreen({
    super.key,
    required this.apiClient,
    required this.connectionService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsController _controller;
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();
  String _selectedStatus = 'online';
  String _selectedTheme = 'light';
  String _selectedTransport = 'websocket';

  @override
  void initState() {
    super.initState();
    _selectedTheme = themeNotifier.value;
    _controller = SettingsController(
      widget.apiClient,
      widget.connectionService,
    );
    _controller.initialize().then((_) {
      final user = _controller.currentUser.value;
      _selectedTransport = _controller.transportMode.value;
      if (user != null) {
        _nicknameController.text = user.nickname;
        _bioController.text = user.bio ?? "";
        _selectedStatus = user.status;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final success = await _controller.updateProfile(
      nickname: _nicknameController.text,
      bio: _bioController.text,
      status: _selectedStatus,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ValueListenableBuilder<bool>(
        valueListenable: _controller.isLoading,
        builder: (context, isLoading, _) {
          return _buildContent();
        },
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildConnectionStatus(),
          ValueListenableBuilder<String?>(
            valueListenable: _controller.errorMessage,
            builder: (context, error, _) {
              if (error == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Profile'),
          if (_controller.currentUser.value == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                'Profile is unavailable offline.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          _buildCard([
            _buildTextField('Nickname', _nicknameController),
            const Divider(height: 1),
            _buildTextField('Bio', _bioController, maxLines: 3),
            const Divider(height: 1),
            _buildDropdown(
              'Status',
              _selectedStatus,
              ['online', 'offline', 'idle', 'dnd'],
              (val) {
                setState(() => _selectedStatus = val!);
              },
            ),
          ]),
          const SizedBox(height: 24),
          _buildSectionHeader('Appearance'),
          _buildCard([
            _buildDropdown(
              'Theme',
              _selectedTheme,
              ['light', 'dark', 'amoled'],
              (val) {
                setState(() => _selectedTheme = val!);
                unawaited(_controller.updateTheme(val!));
              },
            ),
          ]),
          const SizedBox(height: 24),
          _buildSectionHeader('Network'),
          _buildCard([
            SwitchListTile(
              secondary: const Icon(Icons.swap_horiz),
              title: const Text('WebTransport'),
              subtitle: Text(
                _selectedTransport == 'webtransport'
                    ? 'Active'
                    : 'Using WebSocket',
              ),
              value: _selectedTransport == 'webtransport',
              onChanged: (enabled) {
                final mode = enabled ? 'webtransport' : 'websocket';
                setState(() => _selectedTransport = mode);
                unawaited(_controller.updateTransportMode(mode));
              },
            ),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _controller.isLoading.value ? null : _save,
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: const Text('Save Profile Changes'),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
        items: options
            .map(
              (s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase())),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Card(
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Real-time Connection',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_controller.currentTransport} • ${_controller.connectionState}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            _buildStatusDot(_controller.connectionState),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDot(String state) {
    Color color = Colors.grey;
    if (state == "Connected") color = Colors.green;
    if (state.contains("Connecting")) color = Colors.orange;
    if (state == "Error") color = Colors.red;

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
