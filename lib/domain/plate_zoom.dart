import 'dart:math' as math;
import 'dart:ui';

const fullCameraFrame = Rect.fromLTWH(0, 0, 1, 1);

Rect normalizePlateBounds(Rect bounds, Size image) {
  if (image.isEmpty || !bounds.isFinite || bounds.isEmpty) return Rect.zero;
  return Rect.fromLTRB(
    bounds.left / image.width,
    bounds.top / image.height,
    bounds.right / image.width,
    bounds.bottom / image.height,
  ).intersect(fullCameraFrame);
}

/// A translated digital zoom keeps even an off-centre plate visible.
Rect platePreviewCrop(Rect target) {
  if (target.isEmpty) return fullCameraFrame;
  final zoom = math
      .min(.62 / target.width, .42 / target.height)
      .clamp(1.0, 3.0);
  final side = 1 / zoom;
  return Rect.fromLTWH(
    (target.center.dx - side / 2).clamp(0.0, 1 - side),
    (target.center.dy - side / 2).clamp(0.0, 1 - side),
    side,
    side,
  );
}

/// Camera2 zoom crops around the sensor centre, so cap it before an edge plate
/// would leave the frame. Digital recentering handles the remaining zoom.
double plateCameraZoom(
  Rect target,
  double current,
  double minimum,
  double maximum,
) {
  if (target.isEmpty || maximum <= minimum) return current;
  final padded = target.inflate(.035).intersect(fullCameraFrame);
  final edge = [
    (.5 - padded.left).abs(),
    (.5 - padded.right).abs(),
    (.5 - padded.top).abs(),
    (.5 - padded.bottom).abs(),
  ].reduce(math.max);
  final safeFactor = edge > 0 ? .5 / edge : 1.5;
  final factor = math.min(math.min(.48 / target.width, safeFactor), 1.5);
  if (factor < 1.12) return current;
  return (current * factor).clamp(
    minimum,
    math.min(maximum, math.max(minimum, 3.0)),
  );
}

Rect plateRecognitionCrop(Rect target) {
  final horizontal = math.max(target.width * .3, .035);
  final vertical = math.max(target.height * .8, .045);
  return Rect.fromLTRB(
    target.left - horizontal,
    target.top - vertical,
    target.right + horizontal,
    target.bottom + vertical,
  ).intersect(fullCameraFrame);
}
