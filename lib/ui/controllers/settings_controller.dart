import 'package:flutter/foundation.dart';
import '../../data/api/rest.dart';
import '../../data/models/user.dart';

class SettingsController {
  final ApiClient apiClient;

  final isLoading = ValueNotifier<bool>(false);
  final errorMessage = ValueNotifier<String?>(null);
  final currentUser = ValueNotifier<User?>(null);

  SettingsController(this.apiClient);

  Future<void> initialize() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
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

  Future<bool> updateProfile({String? nickname, String? bio, String? status}) async {
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

  void dispose() {
    isLoading.dispose();
    errorMessage.dispose();
    currentUser.dispose();
  }
}
