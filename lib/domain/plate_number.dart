/// Standard Russian passenger-car plate, stored using Latin lookalikes.
/// OCR guesses (such as O -> 0) must be confirmed instead of silently applied.
class PlateNumber {
  const PlateNumber._(this.value);

  final String value;
  String get body => value.substring(0, 6);

  static const _letters = {
    'А': 'A',
    'В': 'B',
    'Е': 'E',
    'К': 'K',
    'М': 'M',
    'Н': 'H',
    'О': 'O',
    'Р': 'P',
    'С': 'C',
    'Т': 'T',
    'У': 'Y',
    'Х': 'X',
  };

  static PlateNumber parse(String input) {
    final compact = input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    final normalized = compact.split('').map((c) => _letters[c] ?? c).join();
    if (!RegExp(
      r'^[ABEKMHOPCTYX][0-9]{3}[ABEKMHOPCTYX]{2}([0-9]{2,3})?$',
    ).hasMatch(normalized)) {
      throw const FormatException('Введите номер, например А123ВС');
    }
    return PlateNumber._(normalized);
  }

  String get display => value.split('').map((character) {
    for (final entry in _letters.entries) {
      if (entry.value == character) return entry.key;
    }
    return character;
  }).join();
}
