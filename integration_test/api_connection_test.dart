import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:goscameracar/data/pass_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Device reaches the live HTTPS API and authentication endpoint', (
    tester,
  ) async {
    final client = http.Client();
    final api = PassApi(client: client);
    try {
      final response = await client
          .get(
            Uri.parse(
              'https://cv339126.tw1.ru/goscameracar/api.php?action=health',
            ),
          )
          .timeout(const Duration(seconds: 15));
      expect(response.statusCode, 200);
      expect(response.body, contains('"status":"ok"'));
      // Intentionally invalid credentials exercise login without embedding a
      // real password or token in the test APK.
      await expectLater(
        api.login('__connectivity_test__', 'intentionally-invalid'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Неверный логин или пароль.',
          ),
        ),
      );
    } finally {
      api.close();
    }
  });
}
