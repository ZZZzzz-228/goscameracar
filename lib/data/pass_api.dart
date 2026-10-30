import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/plate_number.dart';
import 'pass_repository.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
}

class SessionExpiredException extends ApiException {
  const SessionExpiredException() : super('Войдите в приложение заново.');
}

class PassApi implements PassRepository {
  PassApi({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          Uri.parse(
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'https://cv339126.tw1.ru/goscameracar/api.php',
            ),
          ) {
    if (_baseUrl.scheme != 'https' ||
        _baseUrl.host.isEmpty ||
        _baseUrl.userInfo.isNotEmpty) {
      throw ArgumentError('API requires an HTTPS URL without credentials.');
    }
  }

  final http.Client _client;
  final Uri _baseUrl;
  String? _token;
  String accountName = '';
  bool get signedIn => _token != null;

  Future<void> login(String username, String password) async {
    final body = await _request('login', {
      'username': username.trim(),
      'password': password,
    });
    final token = body['token'];
    if (token is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      throw const ApiException('Сервер вернул некорректный ответ.');
    }
    _token = token;
    accountName = username.trim().toLowerCase();
  }

  @override
  Future<PassDecision> check(PlateNumber plate) async {
    final token = _token;
    if (token == null) throw const SessionExpiredException();
    final body = await _request('check', {'plate': plate.value}, token: token);
    if (body['plate'] != plate.value) {
      throw const ApiException(
        'Ответ сервера относится к другому номеру. Повторите проверку.',
      );
    }
    return switch (body['decision']) {
      'allowed' => PassDecision.allowed,
      'not_found' => PassDecision.notFound,
      _ => throw const ApiException(
        'Сервер вернул неизвестный статус пропуска.',
      ),
    };
  }

  Future<void> logout() async {
    final token = _token;
    clearSession();
    if (token != null) await _request('logout', {}, token: token);
  }

  void clearSession() => _token = null;
  void close() => _client.close();

  Future<Map<String, dynamic>> _request(
    String action,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    try {
      final response = await _client
          .post(
            _baseUrl.replace(queryParameters: {'action': action}),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 401) {
        if (action != 'login') {
          if (_token == token) clearSession();
          throw const SessionExpiredException();
        }
        throw const ApiException('Неверный логин или пароль.');
      }
      if (response.statusCode == 429) {
        throw const ApiException(
          'Слишком много запросов. Подождите и повторите попытку.',
        );
      }
      if (response.statusCode != 200) {
        throw const ApiException(
          'Сервис временно недоступен. Повторите попытку.',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return decoded;
    } on TimeoutException {
      throw const ApiException(
        'Сервер не ответил. Проверьте интернет и повторите попытку.',
      );
    } on http.ClientException {
      throw const ApiException('Нет связи с сервером. Проверьте интернет.');
    } on FormatException {
      throw const ApiException('Сервер вернул некорректный ответ.');
    }
  }
}
