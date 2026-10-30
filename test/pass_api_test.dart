import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:goscameracar/data/pass_api.dart';
import 'package:goscameracar/data/pass_repository.dart';
import 'package:goscameracar/domain/plate_number.dart';

void main() {
  final token = 'a' * 64;
  final plate = PlateNumber.parse('А123ВС77');

  test(
    'Login and checks use HTTPS, canonical plate and a bearer token',
    () async {
      final api = PassApi(
        client: MockClient((request) async {
          expect(request.url.scheme, 'https');
          if (request.url.queryParameters['action'] == 'login') {
            expect(jsonDecode(request.body), {
              'username': 'guard',
              'password': 'sample',
            });
            return http.Response(jsonEncode({'token': token}), 200);
          }
          expect(request.headers['Authorization'], 'Bearer $token');
          expect(jsonDecode(request.body), {'plate': 'A123BC77'});
          return http.Response(
            '{"plate":"A123BC77","decision":"allowed"}',
            200,
          );
        }),
      );
      addTearDown(api.close);
      await api.login(' guard ', 'sample');
      expect(await api.check(plate), PassDecision.allowed);
    },
  );

  test('Only an explicit not_found response means no pass', () async {
    final responses = [
      http.Response('{"plate":"A123BC77","decision":"not_found"}', 200),
      http.Response('{"plate":"B456OP99","decision":"allowed"}', 200),
      http.Response('{"plate":"A123BC77","decision":"unknown"}', 200),
      http.Response('<html>Proxy error</html>', 502),
      http.Response('not json', 200),
      http.Response('{}', 429),
    ];
    final api = PassApi(
      client: MockClient(
        (request) async => request.url.queryParameters['action'] == 'login'
            ? http.Response(jsonEncode({'token': token}), 200)
            : responses.removeAt(0),
      ),
    );
    addTearDown(api.close);
    await api.login('guard', 'sample');
    expect(await api.check(plate), PassDecision.notFound);
    for (var index = 0; index < 5; index++) {
      await expectLater(api.check(plate), throwsA(isA<ApiException>()));
    }
  });

  test(
    'Expired sessions clear access instead of returning a decision',
    () async {
      final api = PassApi(
        client: MockClient(
          (request) async => request.url.queryParameters['action'] == 'login'
              ? http.Response(jsonEncode({'token': token}), 200)
              : http.Response('{}', 401),
        ),
      );
      addTearDown(api.close);
      await api.login('guard', 'sample');
      await expectLater(
        api.check(plate),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(api.signedIn, isFalse);
    },
  );

  test('Network errors cannot grant or deny access', () async {
    final api = PassApi(
      client: MockClient((request) async {
        if (request.url.queryParameters['action'] == 'login') {
          return http.Response(jsonEncode({'token': token}), 200);
        }
        throw http.ClientException('offline');
      }),
    );
    addTearDown(api.close);
    await api.login('guard', 'sample');
    await expectLater(api.check(plate), throwsA(isA<ApiException>()));
  });

  test('Logout clears local access and requests token revocation', () async {
    var revoked = false;
    final api = PassApi(
      client: MockClient((request) async {
        if (request.url.queryParameters['action'] == 'login') {
          return http.Response(jsonEncode({'token': token}), 200);
        }
        expect(request.url.queryParameters['action'], 'logout');
        expect(request.headers['Authorization'], 'Bearer $token');
        revoked = true;
        return http.Response('{"status":"ok"}', 200);
      }),
    );
    addTearDown(api.close);
    await api.login('guard', 'sample');
    await api.logout();
    expect(revoked, isTrue);
    expect(api.signedIn, isFalse);
  });

  test('Rejects an insecure API endpoint', () {
    expect(
      () => PassApi(baseUrl: Uri.parse('http://example.test/api.php')),
      throwsArgumentError,
    );
  });
}
