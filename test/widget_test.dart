import 'package:flutter_test/flutter_test.dart';

import 'package:gritos_client/data/api/rest.dart';
import 'package:gritos_client/core/realtime/websocket_transport.dart';
import 'package:gritos_client/main.dart';
import 'package:gritos_client/core/realtime/connection_service.dart';

void main() {
  testWidgets('shows login screen', (WidgetTester tester) async {
    final apiClient = ApiClient();
    final connectionService = ConnectionService(
      WsClient(apiClient: apiClient),
      apiClient: apiClient,
    );

    await tester.pumpWidget(
      MyApp(
        initialRoute: '/login',
        apiClient: apiClient,
        connectionService: connectionService,
      ),
    );

    expect(find.text('Login'), findsWidgets);
  });
}
