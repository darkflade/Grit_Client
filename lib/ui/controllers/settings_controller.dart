import 'package:flutter/foundation.dart';
import '../../data/api/rest.dart';
import '../../data/api/webtransport.dart';
import '../../data/api/websocket.dart';
import '../../data/models/user.dart';
import '../../services/connection_service.dart';
import '../../services/storage_service.dart';
import '../../main.dart';

class SettingsController {
  final ApiClient apiClient;
  final ConnectionService connectionService;
  final StorageService storageService = StorageService();

  final isLoading = ValueNotifier<bool>(false);
  final errorMessage = ValueNotifier<String?>(null);
  final currentUser = ValueNotifier<User?>(null);
  final transportMode = ValueNotifier<String>('websocket');

  SettingsController(this.apiClient, this.connectionService);

  Future<void> initialize() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      transportMode.value =
          await storageService.getEventTransportMode() ?? 'websocket';
      final user = await apiClient.getMe();
      if (user != null) {
        currentUser.value = user;
      } else {
        errorMessage.value = "Failed to load profile.";
      }
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
  }
}
