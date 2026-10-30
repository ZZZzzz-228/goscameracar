import 'package:flutter/material.dart';
import '../app.dart';
import '../data/pass_api.dart';
import '../data/pass_repository.dart';
import '../data/scan_history.dart';
import 'plate_check_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    this.demoMode = true,
    this.onLogout,
    this.onSessionExpired,
  });
  final PassRepository repository;
  final bool demoMode;
  final VoidCallback? onLogout, onSessionExpired;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ScanHistory _history = ScanHistory(
    widget.repository is PassApi
        ? (widget.repository as PassApi).accountName
        : 'demo',
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Автопропуск'),
      actions: [
        if (widget.onLogout != null)
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout),
          ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined, size: 88, color: ink),
                const SizedBox(height: 40),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: ink,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlateCheckScreen(
                        repository: widget.repository,
                        history: _history,
                        demoMode: widget.demoMode,
                        onSessionExpired: widget.onSessionExpired,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.directions_car_outlined),
                  label: const Text('Машина'),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HistoryScreen(history: _history),
                    ),
                  ),
                  icon: const Icon(Icons.history),
                  label: const Text('История'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
