import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:cookie_jar/cookie_jar.dart'; // Needed for Cookie type

import '../../data/api/rest.dart';
import '../../core/storage/storage_service.dart';

class LoginController {
  final ApiClient apiClient;
  final StorageService storageService;
  String? errorMessage;

  LoginController(this.apiClient, this.storageService);

  Future<bool> _handleSuccessfulAuth() async {
    try {
      // The CookieManager has now processed the response headers and updated the cookieJar.
      final cookies = await apiClient.cookieJar.loadForRequest(
        Uri.parse(apiClient.baseUrl),
      );

      String? accessToken;
      String? refreshToken;

      for (Cookie cookie in cookies) {
        if (cookie.name == 'access_token') {
          accessToken = cookie.value;
        }
        if (cookie.name == 'refresh_token') {
          refreshToken = cookie.value;
        }
      }

      if (accessToken != null) {
        await storageService.saveAccessToken(accessToken);
        debugPrint("Access token saved.");
      } else {
        debugPrint("Access token not found in cookies after auth.");
      }
      if (refreshToken != null) {
        await storageService.saveRefreshToken(refreshToken);
        debugPrint("Refresh token saved.");
      } else {
        debugPrint("Refresh token not found in cookies after auth.");
      }

      // Optionally save user ID immediately after login/register if API allows
      // final userId = await apiClient.getMyId();
      // if (userId != null) {
      //   await storageService.saveUserData(userId);
      // }

      return accessToken !=
          null; // Consider successful if at least access token is found
    } catch (e) {
      debugPrint("Error saving tokens: $e");
      errorMessage = "Error processing authentication tokens.";
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    errorMessage = null;
    try {
      final response = await apiClient.login(email, password);
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        return await _handleSuccessfulAuth();
      } else {
        errorMessage =
            "Login failed: ${response.statusCode} - ${response.data?['message'] ?? response.statusMessage}";
        return false;
      }
    } on DioException catch (e) {
      debugPrint("Login DioError: ${e.message}");
      if (e.response != null) {
        debugPrint("Login DioError response data: ${e.response?.data}");
        errorMessage =
            "Login failed: ${e.response?.data?['message'] ?? e.message}";
      } else {
        errorMessage = "Login failed: Network error or server unreachable.";
      }
      return false;
    } catch (e) {
      debugPrint("Login general error: $e");
      errorMessage = "An unexpected error occurred during login.";
      return false;
    }
  }

  Future<bool> register(String nickname, String email, String password) async {
    errorMessage = null;
    try {
      final response = await apiClient.register(nickname, email, password);
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        // Assuming registration might also log the user in and set cookies
        return await _handleSuccessfulAuth();
      } else {
        errorMessage =
            "Registration failed: ${response.statusCode} - ${response.data?['message'] ?? response.statusMessage}";
        return false;
      }
    } on DioException catch (e) {
      debugPrint("Register DioError: ${e.message}");
      if (e.response != null) {
        debugPrint("Register DioError response data: ${e.response?.data}");
        errorMessage =
            "Registration failed: ${e.response?.data?['message'] ?? e.message}";
      } else {
        errorMessage =
            "Registration failed: Network error or server unreachable.";
      }
      return false;
    } catch (e) {
      debugPrint("Register general error: $e");
      errorMessage = "An unexpected error occurred during registration.";
      return false;
    }
  }
}
