import 'package:flutter/material.dart';
import '../controllers/settings_controller.dart';
import '../../data/api/rest.dart';
import '../../data/models/user.dart';

class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;

  const SettingsScreen({super.key, required this.apiClient});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsController _controller;
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();
  String _selectedStatus = 'online';

  @override
  void initState() {
    super.initState();
    _controller = SettingsController(widget.apiClient);
    _controller.initialize().then((_) {
      final user = _controller.currentUser.value;
      if (user != null) {
        _nicknameController.text = user.nickname;
        _bioController.text = user.bio ?? "";
        _selectedStatus = user.status;
        setState(() {});
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ValueListenableBuilder<bool>(
        valueListenable: _controller.isLoading,
        builder: (context, isLoading, _) {
          if (isLoading && _controller.currentUser.value == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ValueListenableBuilder<String?>(
            valueListenable: _controller.errorMessage,
            builder: (context, error, _) {
              if (error != null) return Center(child: Text(error));
              return _buildForm();
            },
          );
        },
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _nicknameController,
            decoration: const InputDecoration(labelText: 'Nickname'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bioController,
            decoration: const InputDecoration(labelText: 'Bio'),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedStatus,
            decoration: const InputDecoration(labelText: 'Status'),
            items: ['online', 'offline', 'idle', 'dnd'].map((s) {
              return DropdownMenuItem(value: s, child: Text(s.toUpperCase()));
            }).toList(),
            onChanged: (val) => setState(() => _selectedStatus = val!),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _controller.isLoading.value ? null : _save,
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}
