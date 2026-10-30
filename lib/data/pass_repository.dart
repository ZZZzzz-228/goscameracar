import '../domain/plate_number.dart';

enum PassDecision { allowed, notFound }

abstract interface class PassRepository {
  Future<PassDecision> check(PlateNumber plate);
}

/// Local demonstration only. Replace with an authenticated HTTPS repository
/// when the server is ready; never fall back to this list after a network error.
class DemoPassRepository implements PassRepository {
  static const _plates = {'A123BC77', 'M777MM125'};

  @override
  Future<PassDecision> check(PlateNumber plate) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    return _plates.any((value) => value.startsWith(plate.body))
        ? PassDecision.allowed
        : PassDecision.notFound;
  }
}
