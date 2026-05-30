import 'package:flutter_test/flutter_test.dart';

import 'package:gritos_client/data/api/rest.dart';
import 'package:gritos_client/data/api/websocket.dart';
import 'package:gritos_client/main.dart';
import 'package:gritos_client/services/connection_service.dart';

void main() {
  testWidgets('shows login screen', (WidgetTester tester) async {
    final apiClient = ApiClient();
    final connectionService = ConnectionService(WsClient(apiClient: apiClient));

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
