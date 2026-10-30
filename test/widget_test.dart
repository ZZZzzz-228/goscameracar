import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:goscameracar/app.dart';
import 'package:goscameracar/data/pass_repository.dart';
import 'package:goscameracar/data/scan_history.dart';
import 'package:goscameracar/domain/plate_number.dart';
import 'package:goscameracar/widgets/plate_camera.dart';

class PendingRepository implements PassRepository {
  final completer = Completer<PassDecision>();
  int calls = 0;
  @override
  Future<PassDecision> check(PlateNumber plate) {
    calls++;
    return completer.future;
  }
}

Future<void> openCheck(WidgetTester tester, PassRepository repository) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(PassApp(repository: repository));
  expect(find.textContaining('Пропуск начинается'), findsNothing);
  expect(find.text('История'), findsOneWidget);
  await tester.tap(find.text('Машина'));
  await tester.pumpAndSettle();
}

void read(WidgetTester tester, String plate) => tester
    .widget<PlateCamera>(find.byType(PlateCamera))
    .onRecognized(PlateNumber.parse(plate));
Future<void> submit(WidgetTester tester, String plate) async {
  await tester.enterText(find.byType(TextFormField), plate);
  await tester.ensureVisible(find.text('Проверить пропуск'));
  await tester.tap(find.text('Проверить пропуск'));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'New cars check automatically; compact result and persistent history',
    (tester) async {
      await openCheck(tester, DemoPassRepository());
      read(tester, 'А123ВС');
      await tester.pump(const Duration(milliseconds:600));
      await tester.pumpAndSettle();
      expect(find.textContaining('· Пропуск есть'), findsOneWidget);
      expect(
        tester.widget<PlateCamera>(find.byType(PlateCamera)).active,
        isTrue,
      );
      expect(find.text('Следующая машина'), findsNothing);
      read(tester, 'В456ОР99');
      await tester.pump(const Duration(milliseconds:600));
      await tester.pumpAndSettle();
      expect(find.textContaining('· Пропуска нет'), findsOneWidget);
      final history = ScanHistory('demo');
      await history.load();
      expect(history.records.map((r) => r.plate.value), ['B456OP99', 'A123BC']);
      expect(history.records.first.decision, PassDecision.notFound);
      await tester.tap(find.byTooltip('История'));
      await tester.pumpAndSettle();
      expect(find.text('А123ВС'), findsOneWidget);
      expect(find.text('В456ОР99'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Manual correction removes an old decision and accepts no region',
    (tester) async {
      await openCheck(tester, DemoPassRepository());
      await submit(tester, 'А123ВС');
      await tester.pumpAndSettle();
      expect(find.textContaining('· Пропуск есть'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'В456ОР');
      await tester.pump();
      expect(find.textContaining('· Пропуск есть'), findsNothing);
      await submit(tester, 'В456ОР');
      await tester.pumpAndSettle();
      expect(find.textContaining('· Пропуска нет'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Invalid plate cannot call API', (tester) async {
    final repo = PendingRepository();
    await openCheck(tester, repo);
    await submit(tester, '123');
    expect(repo.calls, 0);
    expect(find.text('Введите номер, например А123ВС'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Requests stay serial; timeout saved as unknown, late answer ignored',
    (tester) async {
      final repo = PendingRepository();
      await openCheck(tester, repo);
      read(tester, 'А123ВС77');
      read(tester, 'В456ОР99');
      await tester.pump();
      expect(repo.calls, 1);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.textContaining('· Не удалось проверить'), findsOneWidget);
      repo.completer.complete(PassDecision.allowed);
      await tester.pumpAndSettle();
      expect(find.textContaining('· Пропуск есть'), findsNothing);
      final history = ScanHistory('demo');
      await history.load();
      expect(history.records.single.decision, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Leaving during a request still saves the scan', (tester) async {
    final repo = PendingRepository();
    await openCheck(tester, repo);
    read(tester, 'А123ВС');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    repo.completer.complete(PassDecision.allowed);
    await tester.pumpAndSettle();
    final history = ScanHistory('demo');
    await history.load();
    expect(history.records.single.plate.body, 'A123BC');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
