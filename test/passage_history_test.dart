import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:goscameracar/domain/plate_recognition.dart';
import 'package:goscameracar/domain/plate_number.dart';
import 'package:goscameracar/data/scan_history.dart';
import 'package:goscameracar/data/pass_repository.dart';

void main() {
  test(
    'Continuous stream suppresses a stationary car and accepts the next one',
    () {
      final t = PlatePassageTracker();
      final now = DateTime(2026);
      expect(t.observe({'A123BC'}, now), isNull);
      expect(t.confirming, isTrue);
      expect(
        t.observe({
          'A123BC77',
        }, now.add(const Duration(milliseconds: 80)))?.body,
        'A123BC',
      );
      for (var i = 1; i < 20; i++) {
        expect(t.observe({'A123BC99'}, now.add(Duration(seconds: i))), isNull);
        expect(t.confirming, isFalse);
      }
      expect(
        t.observe({'B456OP'}, now.add(const Duration(seconds: 20))),
        isNull,
      );
      expect(
        t.observe({'B456OP99'}, now.add(const Duration(seconds: 21)))?.body,
        'B456OP',
      );
      t.observe({}, now.add(const Duration(seconds: 22)));
      t.observe({}, now.add(const Duration(seconds: 23)));
      expect(
        t.observe({'B456OP'}, now.add(const Duration(seconds: 24))),
        isNull,
      );
      expect(
        t.observe({
          'B456OP',
        }, now.add(const Duration(milliseconds: 24080)))?.body,
        'B456OP',
      );
    },
  );
  test(
    'History persists all outcomes, separates accounts and serializes saves',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = ScanHistory('security');
      await Future.wait([
        store.add(
          ScanRecord(
            plate: PlateNumber.parse('A123BC'),
            time: DateTime(2026),
            decision: PassDecision.allowed,
          ),
        ),
        store.add(
          ScanRecord(
            plate: PlateNumber.parse('B456OP99'),
            time: DateTime(2026, 1, 2),
          ),
        ),
      ]);
      final restored = ScanHistory('security');
      await restored.load();
      expect(restored.records.length, 2);
      expect(restored.records.first.decision, isNull);
      expect(restored.records.last.decision, PassDecision.allowed);
      final other = ScanHistory('another');
      await other.load();
      expect(other.records, isEmpty);
    },
  );
}
