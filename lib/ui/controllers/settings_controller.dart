import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../data/api/rest.dart';
import '../../core/realtime/webtransport_transport.dart';
import '../../core/realtime/websocket_transport.dart';
import '../../data/models/user.dart';
import '../../core/realtime/connection_service.dart';
import '../../core/storage/storage_service.dart';
import '../../core/config/api_endpoint.dart';
import '../../main.dart';

class SettingsController {
  final ApiClient apiClient;
  final ConnectionService connectionService;
  final StorageService storageService = StorageService();

  final isLoading = ValueNotifier<bool>(false);
  final errorMessage = ValueNotifier<String?>(null);
  final currentUser = ValueNotifier<User?>(null);
  final transportMode = ValueNotifier<String>('websocket');
  final apiBaseUrl = ValueNotifier<String>(defaultApiBaseUrl);
  final customApiBaseUrls = ValueNotifier<List<String>>([]);
  final webRtcImplementation = ValueNotifier<String>('native');
  final forceRelay = ValueNotifier<bool>(false);
  final downloadPath = ValueNotifier<String?>(null);

  String? _userId;
  StreamSubscription? _wsSubscription;

  // Connection status info
  String get currentTransport => connectionService.eventTransport.transportType;
  String get connectionState =>
      connectionService.eventTransport.connectionState;

  SettingsController(this.apiClient, this.connectionService);

  Future<void> initialize() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      transportMode.value =
          await storageService.getEventTransportMode() ?? 'websocket';
      apiBaseUrl.value =
          await storageService.getApiBaseUrl() ?? defaultApiBaseUrl;
      final normalizedCustomUrls = <String>{};
      for (final rawUrl in await storageService.getCustomApiBaseUrls()) {
        try {
          normalizedCustomUrls.add(normalizeApiBaseUrl(rawUrl));
        } catch (_) {}
      }
      customApiBaseUrls.value = normalizedCustomUrls.toList();
      webRtcImplementation.value =
          await storageService.getWebRtcImplementation() ?? 'native';
      forceRelay.value = await storageService.getForceRelay();
      downloadPath.value = await storageService.getDownloadPath();

      try {
        final user = await apiClient.getMe();
        if (user != null) {
          _userId = user.id;
          currentUser.value = user;
        }
      } on AuthIdentityNotFoundException {
        await storageService.clearAllAuthData();
        await apiClient.cookieJar.deleteAll();
        connectionService.disconnect();
        errorMessage.value =
            "Session belongs to another server or deleted user. Please sign in again.";
      } catch (e) {
        debugPrint("Settings profile load failed: $e");
      }

      _wsSubscription?.cancel();
      _wsSubscription = connectionService.messageStream.listen(
        _handleWebSocketMessage,
      );
    } catch (e) {
      errorMessage.value = "Error: $e";
    }
    isLoading.value = false;
  }

  Future<bool> updateProfile({
    String? nickname,
    String? bio,
    String? status,
  }) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      if (currentUser.value == null) {
        errorMessage.value = "Profile changes require a connection.";
        isLoading.value = false;
        return false;
      }

      final Map<String, dynamic> data = {};
      if (nickname != null) data['nickname'] = nickname;
      if (bio != null) data['bio'] = bio;
      if (status != null) data['status'] = status;

      final updatedUser = await apiClient.updateProfile(data);
      if (updatedUser != null) {
        currentUser.value = updatedUser;
        isLoading.value = false;
        return true;
      } else {
        errorMessage.value = "Failed to update profile.";
      }
    } catch (e) {
      errorMessage.value = "Error: $e";
    }
    isLoading.value = false;
    return false;
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final decoded = message is String ? jsonDecode(message) : message;
      if (decoded['type'] == 'user_presence_updated') {
        final data = decoded['data'];
        if (data['user_id'] == _userId && currentUser.value != null) {
          currentUser.value = User.fromJson({
            ...currentUser.value!.toJson(),
            'status': data['status'],
          });
        }
      }
    } catch (_) {}
  }

  Future<void> updateTheme(String mode) async {
    await storageService.saveThemeMode(mode);
    themeNotifier.value = normalizeThemeMode(mode);
  }

  Future<void> updateTransportMode(String mode) async {
    await storageService.saveEventTransportMode(mode);
    transportMode.value = mode;
    unawaited(
      connectionService.setTransport(
        mode == 'webtransport'
            ? WebTransportClient(apiClient: apiClient)
            : WsClient(apiClient: apiClient),
      ),
    );
  }

  Future<String> addCustomApiBaseUrl(String input) async {
    final normalized = normalizeApiBaseUrl(input);
    final defaultUrls = defaultApiEndpoints.map((e) => e.baseUrl).toSet();
    final custom = customApiBaseUrls.value.toSet();
    if (!defaultUrls.contains(normalized)) {
      custom.add(normalized);
      final next = custom.toList();
      customApiBaseUrls.value = next;
      await storageService.saveCustomApiBaseUrls(next);
    }
    return normalized;
  }

  Future<void> updateApiBaseUrl(String input) async {
    final normalized = normalizeApiBaseUrl(input);
    await storageService.saveApiBaseUrl(normalized);
    await storageService.clearAllAuthData();
    await apiClient.updateBaseUrl(normalized);
    apiBaseUrl.value = normalized;

    connectionService.disconnect();
    final mode = await storageService.getEventTransportMode() ?? 'websocket';
    await connectionService.setTransport(createEventTransport(mode, apiClient));
  }

  Future<void> updateWebRtcImplementation(String value) async {
    await storageService.saveWebRtcImplementation(value);
    webRtcImplementation.value = value;
  }

  Future<void> updateForceRelay(bool value) async {
    await storageService.saveForceRelay(value);
    forceRelay.value = value;
  }

  Future<void> updateDownloadPath(String? path) async {
    if (path == null) return;
    await storageService.saveDownloadPath(path);
    downloadPath.value = path;
  }

  void dispose() {
    isLoading.dispose();
    errorMessage.dispose();
    currentUser.dispose();
    transportMode.dispose();
    apiBaseUrl.dispose();
    customApiBaseUrls.dispose();
    webRtcImplementation.dispose();
    forceRelay.dispose();
    downloadPath.dispose();
    _wsSubscription?.cancel();
  }
}
