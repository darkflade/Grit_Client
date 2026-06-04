import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../data/api/rest.dart';
import '../../core/realtime/webtransport_transport.dart';
import '../../core/realtime/websocket_transport.dart';
import '../../data/models/user.dart';
import '../../core/realtime/connection_service.dart';
import '../../core/storage/storage_service.dart';
import '../../main.dart';

class SettingsController {
  final ApiClient apiClient;
  final ConnectionService connectionService;
  final StorageService storageService = StorageService();

  final isLoading = ValueNotifier<bool>(false);
  final errorMessage = ValueNotifier<String?>(null);
  final currentUser = ValueNotifier<User?>(null);
  final transportMode = ValueNotifier<String>('websocket');

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
      final user = await apiClient.getMe();
      if (user != null) {
        _userId = user.id;
        currentUser.value = user;
      } else {
        errorMessage.value = "Failed to load profile.";
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
    themeNotifier.value = mode;
  }

  Future<void> updateTransportMode(String mode) async {
    await storageService.saveEventTransportMode(mode);
    transportMode.value = mode;
    connectionService.setTransport(
      mode == 'webtransport'
          ? WebTransportClient(apiClient: apiClient)
          : WsClient(apiClient: apiClient),
    );
  }

  void dispose() {
    isLoading.dispose();
    errorMessage.dispose();
    currentUser.dispose();
    transportMode.dispose();
    _wsSubscription?.cancel();
  }
}
