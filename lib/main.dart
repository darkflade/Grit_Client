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

MaterialColor createMaterialColor(Color color) {
  final strengths = <double>[.05];
  final swatch = <int, Color>{};
  final int r = (color.r * 255.0).round().clamp(0, 255).toInt();
  final int g = (color.g * 255.0).round().clamp(0, 255).toInt();
  final int b = (color.b * 255.0).round().clamp(0, 255).toInt();

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  for (var strength in strengths) {
    final double ds = 0.5 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  }
  return MaterialColor(color.toARGB32(), swatch);
}

class CustomColors {
  static final MaterialColor primary = createMaterialColor(
    const Color(0xFF136F63),
  );
  static final MaterialColor secondary = createMaterialColor(
    const Color(0xFFFFB703),
  );
}

final themeNotifier = ValueNotifier<String>('light');

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
  String savedTheme = await storageService.getThemeMode() ?? 'light';
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
          theme: _getThemeData(currentTheme),
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

  ThemeData _getThemeData(String themeName) {
    ThemeData buildTheme({
      required Brightness brightness,
      required Color scaffoldBackgroundColor,
      required Color surface,
      Color? appBarBackground,
    }) {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF136F63),
        brightness: brightness,
      ).copyWith(secondary: const Color(0xFFFFB703), surface: surface);

      return ThemeData(
        brightness: brightness,
        primarySwatch: CustomColors.primary,
        colorScheme: scheme,
        scaffoldBackgroundColor: scaffoldBackgroundColor,
        cardColor: surface,
        appBarTheme: AppBarTheme(
          backgroundColor: appBarBackground ?? Colors.transparent,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          centerTitle: false,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: scheme.surfaceContainerHighest,
          contentTextStyle: TextStyle(color: scheme.onSurface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(color: scheme.primary, width: 1.2),
          ),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        useMaterial3: true,
      );
    }

    switch (themeName) {
      case 'dark':
        return buildTheme(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF081C1A),
          surface: const Color(0xFF102927),
        );
      case 'amoled':
        return buildTheme(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          surface: const Color(0xFF101513),
          appBarBackground: Colors.black,
        );
      default:
        return buildTheme(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF4F8F6),
          surface: Colors.white,
        );
    }
  }
}
