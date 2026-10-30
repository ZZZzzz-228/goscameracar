import 'package:flutter_test/flutter_test.dart';
import 'package:goscameracar/data/pass_repository.dart';
import 'package:goscameracar/domain/plate_number.dart';

void main() {
  test('Russian, Latin and mixed input use the same database key', () {
    for (final input in ['А123ВС77', 'a123bc77', ' А 123 BС-77 ']) {
      expect(PlateNumber.parse(input).value, 'A123BC77');
      expect(PlateNumber.parse(input).display, 'А123ВС77');
    }
  });

  test('Supports a three-digit region', () {
    expect(PlateNumber.parse('М777ММ125').value, 'M777MM125');
  });

  test('Rejects invalid plates and ambiguous OCR substitutions', () {
    for (final input in [
      '',
      '123',
      'Z123BC77',
      'А12ЗВС77',
      'А123ВС7',
      'А123ВС7777',
      'А123ВС77!',
      'А123ВС77RUS',
    ]) {
      expect(
        () => PlateNumber.parse(input),
        throwsFormatException,
        reason: input,
      );
    }
  });

  test(
    'Checks membership, including a valid plate absent from the list',
    () async {
      final repository = DemoPassRepository();
      expect(
        await repository.check(PlateNumber.parse('А123ВС77')),
        PassDecision.allowed,
      );
      expect(
        await repository.check(PlateNumber.parse('М777ММ125')),
        PassDecision.allowed,
      );
      expect(
        await repository.check(PlateNumber.parse('В456ОР99')),
        PassDecision.notFound,
      );
    },
  );
}
