import 'dart:math' as math;
import 'dart:ui';

import 'plate_number.dart';

/// OCR geometry joins a detached region and guides zoom and the next crop.
class PlateTextLine {
  const PlateTextLine(
    this.text, {
    this.left = 0,
    this.top = 0,
    this.width = 0,
    this.height = 0,
    this.corners = const [],
  });
  final String text;
  final double left, top, width, height;
  final List<Offset> corners;

  Rect get bounds => Rect.fromLTWH(left, top, width, height);

  List<Offset> get points => corners.length == 4
      ? corners
      : [
          bounds.topLeft,
          bounds.topRight,
          bounds.bottomRight,
          bounds.bottomLeft,
        ];

  Offset get textAxis {
    final edge = points[1] - points[0];
    return edge.distance > 0 ? edge / edge.distance : const Offset(1, 0);
  }

  Rect projectOn(Offset axis) {
    final normal = Offset(-axis.dy, axis.dx);
    double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
    final xs = points.map((p) => dot(p, axis));
    final ys = points.map((p) => dot(p, normal));
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }
}

class PlateTarget {
  const PlateTarget(this.bounds, {this.plate});
  final Rect bounds;
  final String? plate;
}

class PlateAnalysis {
  const PlateAnalysis(this.candidates, this.targets);
  final Set<String> candidates;
  final List<PlateTarget> targets;

  PlateTarget? get zoomTarget {
    if (candidates.length > 1) return null;
    final valid = targets.where((target) => !target.bounds.isEmpty).toList();
    return valid.length == 1 ? valid.single : null;
  }
}

Set<String> findPlateCandidates(List<PlateTextLine> lines) =>
    analyzePlateText(lines).candidates;

PlateAnalysis analyzePlateText(List<PlateTextLine> lines) {
  final candidates = <String>{};
  final targets = <PlateTarget>[];
  String compact(String value) => value
      .toUpperCase()
      .replaceAll(RegExp(r'[\s\-]'), '')
      .replaceFirst(RegExp(r'(RUS|РУС)$'), '');
  bool add(String text, Rect bounds) {
    try {
      final plate = PlateNumber.parse(text).value;
      candidates.add(plate);
      targets.add(PlateTarget(bounds, plate: plate));
      return true;
    } on FormatException {
      return false;
    }
  }

  for (final line in lines) {
    final text = compact(line.text);
    if (text.length != 6 && add(text, line.bounds)) continue;
    final isBody = RegExp(
      r'^[ABEKMHOPCTYXАВЕКМНОРСТУХ][0-9]{3}[ABEKMHOPCTYXАВЕКМНОРСТУХ]{2}$',
    ).hasMatch(text);
    if (line.width <= 0 || line.height <= 0) {
      if (isBody) add(text, line.bounds);
      continue;
    }
    final oriented = line.projectOn(line.textAxis);
    var joined = false;
    for (final region in isBody ? lines : <PlateTextLine>[]) {
      final suffix = compact(region.text);
      if (!RegExp(r'^[0-9]{2,3}$').hasMatch(suffix)) continue;
      final projectedRegion = region.projectOn(line.textAxis);
      final horizontalGap = projectedRegion.left - oriented.right;
      final verticalGap = (projectedRegion.center.dy - oriented.center.dy)
          .abs();
      final parallel =
          (line.textAxis.dx * region.textAxis.dx +
                  line.textAxis.dy * region.textAxis.dy)
              .abs() >
          .8;
      if (parallel &&
          horizontalGap >= -oriented.height * .25 &&
          horizontalGap <= oriented.height * 1.5 &&
          verticalGap <= oriented.height * .6) {
        joined =
            add(text + suffix, line.bounds.expandToInclude(region.bounds)) ||
            joined;
      }
    }
    // A fragment can guide the camera, but cannot grant or deny a pass.
    if (isBody && !joined) {
      add(text, line.bounds);
      continue;
    }
    final looksLikePlate = RegExp(
      r'^[ABEKMHOPCTYXАВЕКМНОРСТУХ][0-9]{2,3}[ABEKMHOPCTYXАВЕКМНОРСТУХ]{1,2}[0-9]{0,3}$',
    ).hasMatch(text);
    final ratio = oriented.width / oriented.height;
    if (!joined && looksLikePlate && ratio >= 2 && ratio <= 12) {
      targets.add(PlateTarget(line.bounds));
    }
  }
  return PlateAnalysis(candidates, targets);
}

/// Require the same unambiguous plate in two separate processed frames.
class PlateStabilityTracker {
  String? _candidate;
  DateTime? _lastSeen;
  int _count = 0;

  PlateNumber? observe(Set<String> candidates, DateTime now) {
    if (candidates.length != 1) {
      reset();
      return null;
    }
    final candidate = PlateNumber.parse(candidates.single).body;
    if (_candidate != candidate ||
        _lastSeen == null ||
        now.difference(_lastSeen!) > const Duration(seconds: 1)) {
      _candidate = candidate;
      _count = 0;
    }
    _lastSeen = now;
    _count++;
    return _count >= 2 ? PlateNumber.parse(candidates.single) : null;
  }

  void reset() {
    _candidate = null;
    _lastSeen = null;
    _count = 0;
  }
}

/// Suppress a stationary car; re-arm after it leaves or a different car arrives.
class PlatePassageTracker {
  final _stability = PlateStabilityTracker();
  String? _lastBody;
  DateTime? _lastSeen;
  bool confirming = false;

  PlateNumber? observe(Set<String> candidates, DateTime now) {
    final same = candidates.any((p) => PlateNumber.parse(p).body == _lastBody);
    if (same) {
      confirming = false;
      _lastSeen = now;
      _stability.reset();
      return null;
    }
    if (_lastSeen != null &&
        now.difference(_lastSeen!) >= const Duration(milliseconds: 1500)) {
      _lastBody = null;
    }
    final plate = _stability.observe(candidates, now);
    confirming = candidates.length == 1 && plate == null;
    if (plate != null) {
      _lastBody = plate.body;
      _lastSeen = now;
    }
    return plate;
  }

  void reset() {
    _stability.reset();
    confirming = false;
  }
}
