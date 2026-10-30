import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/plate_number.dart';
import 'pass_repository.dart';

class ScanRecord {
  const ScanRecord({required this.plate, required this.time, this.decision});
  final PlateNumber plate;
  final DateTime time;
  final PassDecision? decision;
  String get label => switch (decision) {
    PassDecision.allowed => 'Пропуск есть',
    PassDecision.notFound => 'Пропуска нет',
    null => 'Не удалось проверить',
  };
  Map<String, Object?> toJson() => {
    'plate': plate.value,
    'time': time.toUtc().toIso8601String(),
    'decision': decision?.name,
  };
  factory ScanRecord.fromJson(Map<String, dynamic> json) => ScanRecord(
    plate: PlateNumber.parse(json['plate'] as String),
    time: DateTime.parse(json['time'] as String),
    decision: switch (json['decision']) {
      'allowed' => PassDecision.allowed,
      'notFound' => PassDecision.notFound,
      _ => null,
    },
  );
}

/// Per-account history on this device, including attempts with network errors.
class ScanHistory extends ChangeNotifier {
  ScanHistory(this.account);
  final String account;
  final List<ScanRecord> _records = [];
  List<ScanRecord> get records => List.unmodifiable(_records);
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  String get _key => 'scan_history_v1_${Uri.encodeComponent(account)}';
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      final data = jsonDecode(raw) as List;
      _records.addAll(
        data.map(
          (v) => ScanRecord.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
    }
    notifyListeners();
  }

  Future<void> add(ScanRecord record) {
    final result = _writes.then((_) async {
      await load();
      _records.insert(0, record);
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        _key,
        jsonEncode(_records.map((v) => v.toJson()).toList()),
      )) {
        throw StateError('History could not be saved');
      }
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
