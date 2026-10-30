import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/pass_api.dart';
import 'home_screen.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _api = PassApi();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _api.close();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.login(_username.text, _password.text);
      if (!mounted) return;
      _password.clear();
      setState(() {});
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showLogin({bool expired = false}) {
    _api.clearSession();
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _error = expired ? 'Сессия истекла. Войдите снова.' : null);
  }

  void _logout() {
    // Local logout is immediate. An unreachable server token still expires
    // automatically; no token or password is persisted on the device.
    unawaited(_api.logout().catchError((Object _) {}));
    _showLogin();
  }

  @override
  Widget build(BuildContext context) {
    if (_api.signedIn) {
      return HomeScreen(
        repository: _api,
        demoMode: false,
        onLogout: _logout,
        onSessionExpired: () => _showLogin(expired: true),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(28),
              children: [
                const Icon(Icons.shield_outlined, size: 52, color: ink),
                const SizedBox(height: 28),
                Form(
                  key: _form,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _username,
                        enabled: !_busy,
                        decoration: const InputDecoration(labelText: 'Логин'),
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Введите логин'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _hidePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          suffixIcon: IconButton(
                            tooltip: _hidePassword
                                ? 'Показать пароль'
                                : 'Скрыть пароль',
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _hidePassword = !_hidePassword),
                          ),
                        ),
                        onFieldSubmitted: (_) => _login(),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Введите пароль'
                            : null,
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFF9F3431)),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: Text(_busy ? 'Входим…' : 'Войти'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
