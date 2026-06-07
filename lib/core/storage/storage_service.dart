import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  final _storage = const FlutterSecureStorage();

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _authApiBaseUrlKey = 'auth_api_base_url';
  static const String _userDataKey = 'user_data';
  static const String _lastActiveServerIdKey = 'last_active_server_id';
  static const String _lastActiveRoomIdKey = 'last_active_room_id';
  static const String _lastActiveIsDirectKey = 'last_active_is_direct';
  static const String _themeModeKey = 'theme_mode';
  static const String _eventTransportModeKey = 'event_transport_mode';
  static const String _apiBaseUrlKey = 'api_base_url';
  static const String _customApiBaseUrlsKey = 'custom_api_base_urls';

  // Access Token
  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _accessTokenKey, value: token);
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }

  Future<void> deleteAccessToken() async {
    await _storage.delete(key: _accessTokenKey);
  }

  // Refresh Token
  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshTokenKey, value: token);
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  Future<void> deleteRefreshToken() async {
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<void> saveAuthApiBaseUrl(String baseUrl) async {
    await _storage.write(key: _authApiBaseUrlKey, value: baseUrl);
  }

  Future<String?> getAuthApiBaseUrl() async {
    return await _storage.read(key: _authApiBaseUrlKey);
  }

  Future<void> deleteAuthApiBaseUrl() async {
    await _storage.delete(key: _authApiBaseUrlKey);
  }

  // User Data
  Future<void> saveUserData(String userData) async {
    await _storage.write(key: _userDataKey, value: userData);
  }

  Future<String?> getUserData() async {
    return await _storage.read(key: _userDataKey);
  }

  Future<void> deleteUserData() async {
    await _storage.delete(key: _userDataKey);
  }

  // Last Active Chat
  Future<void> saveLastActiveChat({
    String? serverId,
    String? roomId,
    bool isDirect = false,
  }) async {
    if (serverId != null) {
      await _storage.write(key: _lastActiveServerIdKey, value: serverId);
    } else {
      await _storage.delete(key: _lastActiveServerIdKey);
    }

    if (roomId != null) {
      await _storage.write(key: _lastActiveRoomIdKey, value: roomId);
    } else {
      await _storage.delete(key: _lastActiveRoomIdKey);
    }

    await _storage.write(
      key: _lastActiveIsDirectKey,
      value: isDirect.toString(),
    );
  }

  Future<Map<String, dynamic>> getLastActiveChat() async {
    final serverId = await _storage.read(key: _lastActiveServerIdKey);
    final roomId = await _storage.read(key: _lastActiveRoomIdKey);
    final isDirectStr = await _storage.read(key: _lastActiveIsDirectKey);
    return {
      'serverId': serverId,
      'roomId': roomId,
      'isDirect': isDirectStr == 'true',
    };
  }

  // Theme Mode
  Future<void> saveThemeMode(String mode) async {
    await _storage.write(key: _themeModeKey, value: mode);
  }

  Future<String?> getThemeMode() async {
    return await _storage.read(key: _themeModeKey);
  }

  Future<void> saveEventTransportMode(String mode) async {
    await _storage.write(key: _eventTransportModeKey, value: mode);
  }

  Future<String?> getEventTransportMode() async {
    return await _storage.read(key: _eventTransportModeKey);
  }

  Future<void> saveApiBaseUrl(String baseUrl) async {
    await _storage.write(key: _apiBaseUrlKey, value: baseUrl);
  }

  Future<String?> getApiBaseUrl() async {
    return await _storage.read(key: _apiBaseUrlKey);
  }

  Future<void> saveCustomApiBaseUrls(List<String> baseUrls) async {
    await _storage.write(
      key: _customApiBaseUrlsKey,
      value: jsonEncode(baseUrls),
    );
  }

  Future<List<String>> getCustomApiBaseUrls() async {
    final raw = await _storage.read(key: _customApiBaseUrlsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  // Clear all
  Future<void> clearAllAuthData() async {
    await deleteAccessToken();
    await deleteRefreshToken();
    await deleteAuthApiBaseUrl();
    await deleteUserData();
    await _storage.delete(key: _lastActiveServerIdKey);
    await _storage.delete(key: _lastActiveRoomIdKey);
    await _storage.delete(key: _lastActiveIsDirectKey);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
