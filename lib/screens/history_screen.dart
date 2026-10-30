import 'package:flutter/material.dart';
import '../data/scan_history.dart';
import '../data/pass_repository.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.history});
  final ScanHistory history;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<void> _loading;
  @override
  void initState() {
    super.initState();
    _loading = widget.history.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('История')),
    body: FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Не удалось загрузить историю.'));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListenableBuilder(
          listenable: widget.history,
          builder: (context, _) {
            final records = widget.history.records;
            if (records.isEmpty) {
              return const Center(child: Text('История пока пуста'));
            }
            return ListView.separated(
              itemCount: records.length,
              padding: const EdgeInsets.all(16),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final r = records[index], t = r.time.toLocal();
                String two(int n) => n.toString().padLeft(2, '0');
                final color = switch (r.decision) {
                  PassDecision.allowed => const Color(0xFF206341),
                  PassDecision.notFound => const Color(0xFF9F3431),
                  null => const Color(0xFF815C12),
                };
                return ListTile(
                  leading: Icon(
                    r.decision == PassDecision.allowed
                        ? Icons.check_circle_outline
                        : r.decision == null
                        ? Icons.help_outline
                        : Icons.cancel_outlined,
                    color: color,
                  ),
                  title: Text(
                    r.plate.display,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${r.label}\n${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
                  ),
                  isThreeLine: true,
                );
              },
            );
          },
        );
      },
    ),
  );
}
