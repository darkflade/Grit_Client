import 'package:flutter/material.dart';
import 'package:cookie_jar/cookie_jar.dart'; // For Cookie object
import 'package:gritos_client/data/api/rest.dart';    // Added for ApiClient
import 'package:gritos_client/services/storage_service.dart';
import 'package:gritos_client/ui/screens/login_screen.dart';
import 'package:gritos_client/ui/screens/home_screen.dart';
import 'package:gritos_client/ui/screens/friends_screen.dart';
import 'package:flutter/foundation.dart'; // For debugPrint

// Your custom theme code (as per your image)
MaterialColor createMaterialColor(Color color) {
  List strengths = <double>[.05];
  Map<int, Color> swatch = {};
  final int r = color.red, g = color.green, b = color.blue;

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
  return MaterialColor(color.value, swatch);
}

class CustomColors {
  static final MaterialColor primary = createMaterialColor(const Color(0xFF2E86C1));
  static final MaterialColor secondary = createMaterialColor(const Color(0xFFF39C12));
  // Add other custom colors here
}
// End of custom theme code

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageService = StorageService();
  final apiClient = ApiClient(); 
  String initialRoute = '/login';

  try {
    final accessToken = await storageService.getAccessToken();
    final refreshToken = await storageService.getRefreshToken();

    if (accessToken != null && accessToken.isNotEmpty) {
      debugPrint("Access token found, attempting to load into CookieJar.");
      final cookieUri = Uri.parse(apiClient.baseUrl);
      List<Cookie> cookiesToLoad = [];
      
      final accessCookie = Cookie(HttpHeaders.ACCESS_TOKEN, accessToken);
      accessCookie.domain = cookieUri.host;
      accessCookie.path = "/"; 
      cookiesToLoad.add(accessCookie);

      if (refreshToken != null && refreshToken.isNotEmpty) {
        debugPrint("Refresh token found, attempting to load into CookieJar.");
        final refreshCookie = Cookie(HttpHeaders.REFRESH_TOKEN, refreshToken);
        refreshCookie.domain = cookieUri.host;
        refreshCookie.path = "/";
        cookiesToLoad.add(refreshCookie);
      }
      
      await apiClient.cookieJar.saveFromResponse(cookieUri, cookiesToLoad);
      debugPrint("Cookies loaded into jar for URI: $cookieUri");
      initialRoute = '/home';
    } else {
      debugPrint("No stored access token found. Proceeding to login.");
    }
  } catch (e) {
    debugPrint("Error during token reloading: $e");
    initialRoute = '/login';
  }

  runApp(MyApp(initialRoute: initialRoute, apiClient: apiClient));
}

class HttpHeaders {
  static const String ACCESS_TOKEN = "access_token";
  static const String REFRESH_TOKEN = "refresh_token";
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  final ApiClient apiClient;

  const MyApp({super.key, required this.initialRoute, required this.apiClient});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gritos Client',
      theme: ThemeData(
        primarySwatch: CustomColors.primary, // Using your custom primary color
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: CustomColors.primary,
          accentColor: CustomColors.secondary, // Using your custom secondary color
          brightness: Brightness.light, // Or Brightness.dark based on your theme
        ),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      routes: {
        // Pass the apiClient instance to the screens
        '/login': (context) => LoginScreen(apiClient: apiClient),
        '/home': (context) => HomeScreen(apiClient: apiClient),
        '/friends': (context) => FriendsScreen(apiClient: apiClient),
      },
    );
  }
}
