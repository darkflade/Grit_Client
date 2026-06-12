import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../controllers/settings_controller.dart';
import '../../data/api/rest.dart';
import '../../main.dart';
import '../../core/realtime/connection_service.dart';
import '../../core/config/api_endpoint.dart';
import '../theme/app_spacing.dart';
import '../widgets/common/app_button.dart';
import '../widgets/common/app_card.dart';
import '../widgets/common/app_text_field.dart';
import '../widgets/common/section_header.dart';
import '../widgets/common/status_dot.dart';

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
  final _customApiController = TextEditingController();
  String _selectedStatus = 'online';
  String _selectedTheme = 'light';
  String _selectedTransport = 'websocket';
  String _selectedApiBaseUrl = defaultApiBaseUrl;
  String _selectedWebRtc = 'native';
  String _selectedIceMode = 'auto';
  String _selectedAudioOutput = 'speaker';
  String? _downloadPath;

  @override
  void initState() {
    super.initState();
    // Only Light / Dark are exposed in the UI; a legacy stored 'amoled' value
    // is normalized to 'dark' so saved settings keep working.
    _selectedTheme = normalizeThemeMode(themeNotifier.value);
    _controller = SettingsController(
      widget.apiClient,
      widget.connectionService,
    );
    _controller.initialize().then((_) {
      final user = _controller.currentUser.value;
      _selectedTransport = _controller.transportMode.value;
      _selectedApiBaseUrl = _controller.apiBaseUrl.value;
      _selectedWebRtc = _controller.webRtcImplementation.value;
      _selectedIceMode = _controller.webRtcIceMode.value;
      _selectedAudioOutput = _controller.callAudioOutput.value;
      _downloadPath = _controller.downloadPath.value;

      if (user != null) {
        _nicknameController.text = user.nickname;
        _bioController.text = user.bio ?? "";
        _selectedStatus = user.status;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    _customApiController.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<String> get _apiEndpointOptions {
    final values = <String>{
      ...defaultApiEndpoints.map((endpoint) => endpoint.baseUrl),
      ..._controller.customApiBaseUrls.value,
    }.toList();
    if (!values.contains(_selectedApiBaseUrl)) {
      values.add(_selectedApiBaseUrl);
    }
    return values;
  }

  Future<void> _addCustomApiEndpoint() async {
    try {
      final normalized = await _controller.addCustomApiBaseUrl(
        _customApiController.text,
      );
      if (!mounted) return;
      setState(() {
        _selectedApiBaseUrl = normalized;
        _customApiController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Endpoint added: $normalized'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _applyApiEndpoint() async {
    try {
      await _controller.updateApiBaseUrl(_selectedApiBaseUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backend changed. Sign in again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickDownloadPath() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() => _downloadPath = result);
      await _controller.updateDownloadPath(result);
    }
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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Connection ----------------------------------------------------
                _buildSectionHeader('Connection'),
                _buildConnectionStatus(),
                ValueListenableBuilder<String?>(
                  valueListenable: _controller.errorMessage,
                  builder: (context, error, _) {
                    if (error == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(
                        error,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xxl),

                // ---- Profile -------------------------------------------------------
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
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Save Profile Changes',
                  fullWidth: true,
                  loading: _controller.isLoading.value,
                  onPressed: _save,
                ),
                const SizedBox(height: AppSpacing.xxl),

                // ---- Appearance ----------------------------------------------------
                _buildSectionHeader('Appearance'),
                _buildCard([_buildThemeSelector()]),
                const SizedBox(height: AppSpacing.xxl),

                // ---- Network -------------------------------------------------------
                _buildSectionHeader('Network'),
                _buildCard([
                  _buildApiEndpointDropdown(),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _customApiController,
                            label: 'Custom API domain',
                            hint: 'custom.api.diogen.space',
                            filled: false,
                            keyboardType: TextInputType.url,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        AppButton(
                          label: 'Add',
                          variant: AppButtonVariant.secondary,
                          onPressed: _addCustomApiEndpoint,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.dns_rounded),
                    title: const Text('Backend API'),
                    subtitle: Text(
                      'Current: ${_controller.apiBaseUrl.value}\nChanging backend clears local auth.',
                    ),
                    trailing: AppButton(
                      label: 'Apply',
                      onPressed:
                          _selectedApiBaseUrl == _controller.apiBaseUrl.value
                          ? null
                          : _applyApiEndpoint,
                    ),
                  ),
                  const Divider(height: 1),
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
                const SizedBox(height: AppSpacing.xxl),

                // ---- Media & Calls -------------------------------------------------
                _buildSectionHeader('Media & Calls'),
                _buildCard([
                  _buildDropdown(
                    'WebRTC Implementation',
                    _selectedWebRtc,
                    ['native', 'flutter'],
                    (val) {
                      if (val == null) return;
                      setState(() => _selectedWebRtc = val);
                      unawaited(_controller.updateWebRtcImplementation(val));
                    },
                  ),
                  const Divider(height: 1),
                  _buildDropdown(
                    'ICE Mode',
                    _selectedIceMode,
                    ['auto', 'directOnly', 'turnOnly'],
                    (val) {
                      if (val == null) return;
                      setState(() => _selectedIceMode = val);
                      unawaited(_controller.updateWebRtcIceMode(val));
                    },
                  ),
                  const Divider(height: 1),
                  _buildDropdown(
                    'Call Output',
                    _selectedAudioOutput,
                    ['speaker', 'earpiece'],
                    (val) {
                      if (val == null) return;
                      setState(() => _selectedAudioOutput = val);
                      unawaited(_controller.updateCallAudioOutput(val));
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('Download Folder'),
                    subtitle: Text(_downloadPath ?? 'Not set (using default)'),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: _pickDownloadPath,
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.xxxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Light / Dark switch. Only these two modes are exposed; a legacy stored
  /// 'amoled' value is normalized to 'dark' before reaching this control.
  Widget _buildThemeSelector() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text('Theme', style: Theme.of(context).textTheme.bodyLarge),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'light',
                label: Text('Light'),
                icon: Icon(Icons.light_mode_rounded),
              ),
              ButtonSegment<String>(
                value: 'dark',
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode_rounded),
              ),
            ],
            selected: {_selectedTheme},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              final mode = selection.first;
              setState(() => _selectedTheme = mode);
              unawaited(_controller.updateTheme(mode));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return SectionHeader(
      label: title,
      padding: const EdgeInsets.only(left: 8, bottom: 8),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return AppCard(
      padding: EdgeInsets.zero,
      clipContent: true,
      child: Column(children: children),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: AppTextField(
        controller: controller,
        label: label,
        maxLines: maxLines,
        filled: false,
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
              (s) => DropdownMenuItem(value: s, child: Text(_optionLabel(s))),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  String _optionLabel(String value) {
    return switch (value) {
      'auto' => 'Auto',
      'directOnly' => 'Direct only',
      'turnOnly' => 'TURN only',
      'speaker' => 'Speaker',
      'earpiece' => 'Earpiece',
      _ => value.toUpperCase(),
    };
  }

  Widget _buildApiEndpointDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedApiBaseUrl,
        decoration: const InputDecoration(
          labelText: 'Backend endpoint',
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
        items: _apiEndpointOptions
            .map(
              (endpoint) =>
                  DropdownMenuItem(value: endpoint, child: Text(endpoint)),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() => _selectedApiBaseUrl = value);
        },
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bolt_rounded, color: scheme.onPrimary),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Real-time Connection',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_controller.currentTransport} • ${_controller.connectionState}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _buildStatusDot(_controller.connectionState),
        ],
      ),
    );
  }

  Widget _buildStatusDot(String state) {
    // Map the realtime connection state onto the shared presence palette:
    // Connected -> online (success), Connecting -> idle (warning),
    // Error -> dnd (error), otherwise -> offline (muted).
    final String status;
    if (state == "Connected") {
      status = 'online';
    } else if (state.contains("Connecting")) {
      status = 'idle';
    } else if (state == "Error") {
      status = 'dnd';
    } else {
      status = 'offline';
    }
    return StatusDot(status: status);
  }
}
