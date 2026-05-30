import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:gritos_client/data/api/rest.dart';
import 'package:gritos_client/data/api/event_transport.dart';
import 'package:gritos_client/data/api/webtransport.dart';
import 'package:gritos_client/data/api/websocket.dart';
import 'package:gritos_client/services/storage_service.dart';
import 'package:gritos_client/services/connection_service.dart';
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
    const Color(0xFF2E86C1),
  );
  static final MaterialColor secondary = createMaterialColor(
    const Color(0xFFF39C12),
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

  final storageService = StorageService();
  final apiClient = ApiClient();

  String initialRoute = '/login';
  String savedTheme = await storageService.getThemeMode() ?? 'light';
  String savedTransportMode =
      await storageService.getEventTransportMode() ?? 'websocket';
  themeNotifier.value = savedTheme;
  final connectionService = ConnectionService(
    createEventTransport(savedTransportMode, apiClient),
  );

  try {
    final accessToken = await storageService.getAccessToken();
    final refreshToken = await storageService.getRefreshToken();

    if (accessToken != null && accessToken.isNotEmpty) {
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
    switch (themeName) {
      case 'dark':
        return ThemeData(
          brightness: Brightness.dark,
          primarySwatch: CustomColors.primary,
          colorScheme: ColorScheme.fromSwatch(
            primarySwatch: CustomColors.primary,
            accentColor: CustomColors.secondary,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        );
      case 'amoled':
        return ThemeData(
          brightness: Brightness.dark,
          primarySwatch: CustomColors.primary,
          scaffoldBackgroundColor: Colors.black,
          cardColor: const Color(0xFF121212),
          appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
          colorScheme: ColorScheme.fromSwatch(
            primarySwatch: CustomColors.primary,
            accentColor: CustomColors.secondary,
            brightness: Brightness.dark,
          ).copyWith(surface: const Color(0xFF121212)),
          useMaterial3: true,
        );
      default:
        return ThemeData(
          brightness: Brightness.light,
          primarySwatch: CustomColors.primary,
          colorScheme: ColorScheme.fromSwatch(
            primarySwatch: CustomColors.primary,
            accentColor: CustomColors.secondary,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        );
    }
  }
}
