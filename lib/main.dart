import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:gritos_client/data/api/rest.dart';
import 'package:gritos_client/core/realtime/event_transport.dart';
import 'package:gritos_client/core/realtime/webtransport_transport.dart';
import 'package:gritos_client/core/realtime/websocket_transport.dart';
import 'package:gritos_client/core/storage/storage_service.dart';
import 'package:gritos_client/core/realtime/connection_service.dart';
import 'package:gritos_client/core/config/api_endpoint.dart';
import 'package:gritos_client/ui/screens/login_screen.dart';
import 'package:gritos_client/ui/screens/home_screen.dart';
import 'package:gritos_client/ui/screens/friends_screen.dart';
import 'package:gritos_client/ui/screens/settings_screen.dart';
import 'package:gritos_client/ui/theme/app_theme.dart';

/// Holds the currently selected theme mode name ('light' or 'dark').
///
/// Legacy 'amoled' values persisted by older builds are mapped to 'dark' on
/// read so saved settings keep working after the design-system migration.
final themeNotifier = ValueNotifier<String>('light');

/// Normalizes a stored theme name to a value the current theme system knows.
/// 'amoled' is temporarily mapped onto 'dark' to avoid breaking saved prefs.
String normalizeThemeMode(String? mode) {
  switch (mode) {
    case 'dark':
    case 'amoled':
      return 'dark';
    case 'light':
    default:
      return 'light';
  }
}

EventTransport createEventTransport(String mode, ApiClient apiClient) {
  if (mode == 'webtransport') {
    return WebTransportClient(apiClient: apiClient);
  }
  return WsClient(apiClient: apiClient);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeWebRtcAudio();

  final storageService = StorageService();
  final savedApiBaseUrl =
      await storageService.getApiBaseUrl() ?? defaultApiBaseUrl;
  final apiClient = ApiClient(baseUrl: savedApiBaseUrl);

  String initialRoute = '/login';
  String savedTheme = normalizeThemeMode(await storageService.getThemeMode());
  String savedTransportMode =
      await storageService.getEventTransportMode() ?? 'websocket';
  themeNotifier.value = savedTheme;
  final connectionService = ConnectionService(
    createEventTransport(savedTransportMode, apiClient),
    apiClient: apiClient,
  );

  try {
    final accessToken = await storageService.getAccessToken();
    final refreshToken = await storageService.getRefreshToken();
    final authApiBaseUrl = await storageService.getAuthApiBaseUrl();

    if (accessToken != null && accessToken.isNotEmpty) {
      if (authApiBaseUrl != null && authApiBaseUrl != apiClient.baseUrl) {
        await storageService.clearAllAuthData();
        await apiClient.cookieJar.deleteAll();
        initialRoute = '/login';
      } else {
        final cookieUri = Uri.parse(apiClient.baseUrl);
        List<Cookie> cookiesToLoad = [];

        final accessCookie = Cookie("access_token", accessToken);
        accessCookie.domain = cookieUri.host;
        accessCookie.path = "/";
        cookiesToLoad.add(accessCookie);

        if (refreshToken != null && refreshToken.isNotEmpty) {
          final refreshCookie = Cookie("refresh_token", refreshToken);
          refreshCookie.domain = cookieUri.host;
          refreshCookie.path = "/";
          cookiesToLoad.add(refreshCookie);
        }

        await apiClient.cookieJar.saveFromResponse(cookieUri, cookiesToLoad);
        initialRoute = '/home';
        try {
          await apiClient.getMe();
        } on AuthIdentityNotFoundException {
          await storageService.clearAllAuthData();
          await apiClient.cookieJar.deleteAll();
          initialRoute = '/login';
        }
      }
    }
  } catch (e) {
    debugPrint("Error during token reloading: $e");
    initialRoute = '/login';
  }

  runApp(
    MyApp(
      initialRoute: initialRoute,
      apiClient: apiClient,
      connectionService: connectionService,
    ),
  );
}

Future<void> _initializeWebRtcAudio() async {
  if (!WebRTC.platformIsAndroid) return;

  await WebRTC.initialize(
    options: {
      'androidAudioConfiguration': AndroidAudioConfiguration.communication
          .toMap(),
      'bypassVoiceProcessing': false,
      'audioSampleRate': 48000,
      'audioOutputSampleRate': 48000,
    },
  );
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  final ApiClient apiClient;
  final ConnectionService connectionService;

  const MyApp({
    super.key,
    required this.initialRoute,
    required this.apiClient,
    required this.connectionService,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: themeNotifier,
      builder: (context, currentTheme, _) {
        return MaterialApp(
          title: 'Gritos Client',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: normalizeThemeMode(currentTheme) == 'dark'
              ? ThemeMode.dark
              : ThemeMode.light,
          initialRoute: initialRoute,
          onGenerateRoute: (settings) {
            if (settings.name == '/login') {
              return MaterialPageRoute(
                builder: (context) => LoginScreen(apiClient: apiClient),
              );
            }
            if (settings.name == '/home') {
              return MaterialPageRoute(
                builder: (context) => HomeScreen(
                  apiClient: apiClient,
                  connectionService: connectionService,
                ),
              );
            }
            if (settings.name == '/friends') {
              return MaterialPageRoute(
                builder: (context) => FriendsScreen(
                  apiClient: apiClient,
                  connectionService: connectionService,
                ),
              );
            }
            if (settings.name == '/settings') {
              return MaterialPageRoute(
                builder: (context) => SettingsScreen(
                  apiClient: apiClient,
                  connectionService: connectionService,
                ),
              );
            }
            return null;
          },
        );
      },
    );
  }
}

