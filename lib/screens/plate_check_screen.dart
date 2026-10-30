import 'dart:async';
import 'package:flutter/material.dart';
import '../app.dart';
import '../data/pass_repository.dart';
import '../data/pass_api.dart';
import '../data/scan_history.dart';
import '../domain/plate_number.dart';
import '../widgets/plate_camera.dart';
import 'history_screen.dart';

class PlateCheckScreen extends StatefulWidget {
  const PlateCheckScreen({
    super.key,
    required this.repository,
    required this.history,
    this.demoMode = true,
    this.onSessionExpired,
  });
  final PassRepository repository;
  final ScanHistory history;
  final bool demoMode;
  final VoidCallback? onSessionExpired;
  @override
  State<PlateCheckScreen> createState() => _PlateCheckScreenState();
}

class _PlateCheckScreenState extends State<PlateCheckScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _historyOpen = false;
  ScanRecord? _result;
  PlateNumber? _checking;
  String? _error;
  Timer? _resultTimer;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _resultTimer?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _check(PlateNumber plate) async {
    if (_busy) return;
    _focus.unfocus();
    _resultTimer?.cancel();
    setState(() {
      _busy = true;
      _checking = plate;
      _result = null;
      _error = null;
    });
    PassDecision? decision;
    var expired = false;
    final time = DateTime.now();
    try {
      decision = await widget.repository
          .check(plate)
          .timeout(const Duration(seconds: 10));
    } on SessionExpiredException {
      expired = true;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Не удалось проверить';
    }
    final record = ScanRecord(plate: plate, time: time, decision: decision);
    // Save even when the user navigates away during the request.
    try {
      await widget.history.add(record);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить историю.')),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _checking = null;
      _result = record;
    });
    if (expired && widget.onSessionExpired != null) {
      widget.onSessionExpired!();
      return;
    }
    _resultTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _result = null;
          _error = null;
        });
      }
    });
  }

  void _manual() {
    if (_busy || !_form.currentState!.validate()) return;
    _check(PlateNumber.parse(_input.text));
  }

  void _candidate(String? body) {
    if (!_busy &&
        body != null &&
        _result != null &&
        _result!.plate.body != body) {
      _resultTimer?.cancel();
      setState(() {
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _history() async {
    setState(() => _historyOpen = true);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(history: widget.history),
      ),
    );
    if (mounted) setState(() => _historyOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = _busy ? 'Проверяем…' : _result?.label;
    final color = _busy
        ? ink
        : _result?.decision == PassDecision.allowed
        ? const Color(0xFF206341)
        : _result?.decision == PassDecision.notFound
        ? const Color(0xFF9F3431)
        : const Color(0xFF815C12);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Камера'),
        actions: [
          IconButton(
            onPressed: _history,
            tooltip: 'История',
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Stack(
                  children: [
                    PlateCamera(
                      onRecognized: _check,
                      onCandidate: _candidate,
                      active: !_busy && !_focus.hasFocus && !_historyOpen,
                      scanRound: 0,
                      demoMode: widget.demoMode,
                    ),
                    if (status != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        right: 60,
                        child: IgnorePointer(
                          child: Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .94),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '${(_checking ?? _result?.plate)?.display ?? ''} · $status',
                                maxLines: 2,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Form(
                  key: _form,
                  child: TextFormField(
                    controller: _input,
                    focusNode: _focus,
                    readOnly: _busy,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      hintText: 'А123ВС',
                      labelText: 'Номер',
                      errorMaxLines: 2,
                    ),
                    onChanged: (_) => setState(() {
                      _result = null;
                      _error = null;
                    }),
                    onFieldSubmitted: (_) => _manual(),
                    validator: (value) {
                      try {
                        PlateNumber.parse(value ?? '');
                        return null;
                      } on FormatException catch (e) {
                        return e.message;
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _manual,
                  icon: const Icon(Icons.search),
                  label: const Text('Проверить пропуск'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFF9F3431)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
