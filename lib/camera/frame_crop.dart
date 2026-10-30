import 'dart:typed_data';
import 'dart:ui';

class CroppedCameraBytes {
  const CroppedCameraBytes({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.uprightOrigin,
  });
  final Uint8List bytes;
  final int width, height, bytesPerRow;

  /// Top-left of this crop in the full, upright ML Kit coordinate system.
  final Offset uprightOrigin;
}

Rect _rotate(Rect rect, int rotation) => switch (rotation) {
  90 => Rect.fromLTRB(1 - rect.bottom, rect.left, 1 - rect.top, rect.right),
  180 => Rect.fromLTRB(
    1 - rect.right,
    1 - rect.bottom,
    1 - rect.left,
    1 - rect.top,
  ),
  270 => Rect.fromLTRB(rect.top, 1 - rect.right, rect.bottom, 1 - rect.left),
  _ => rect,
};

/// Copies a targeted region without converting the entire image to RGB.
/// NV21 dimensions and offsets stay even so the VU chroma plane remains valid.
CroppedCameraBytes? cropCameraBytes({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  required bool nv21,
  required int rotation,
  required Rect uprightCrop,
}) {
  if (width <= 0 ||
      height <= 0 ||
      !uprightCrop.isFinite ||
      uprightCrop.isEmpty) {
    return null;
  }
  final raw = _rotate(
    uprightCrop,
    (360 - rotation) % 360,
  ).intersect(const Rect.fromLTWH(0, 0, 1, 1));
  if (raw.isEmpty) return null;
  final alignment = nv21 ? 2 : 1;
  int floorAligned(double value) => value.floor() ~/ alignment * alignment;
  int ceilAligned(double value) =>
      (value.ceil() + alignment - 1) ~/ alignment * alignment;
  final left = floorAligned(raw.left * width).clamp(0, width);
  final top = floorAligned(raw.top * height).clamp(0, height);
  final right = ceilAligned(
    raw.right * width,
  ).clamp(0, width ~/ alignment * alignment);
  final bottom = ceilAligned(
    raw.bottom * height,
  ).clamp(0, height ~/ alignment * alignment);
  final cropWidth = right - left;
  final cropHeight = bottom - top;
  if (cropWidth < 2 || cropHeight < 2) return null;
  final sourceStride = nv21 ? width : bytesPerRow;
  final needed = nv21 ? width * height * 3 ~/ 2 : bytesPerRow * height;
  if (bytes.length < needed ||
      (nv21 && bytesPerRow != width) ||
      (!nv21 && bytesPerRow < width * 4) ||
      (nv21 && (width.isOdd || height.isOdd))) {
    return null;
  }
  final rowBytes = nv21 ? cropWidth : cropWidth * 4;
  final output = Uint8List(
    nv21 ? cropWidth * cropHeight * 3 ~/ 2 : rowBytes * cropHeight,
  );
  for (var row = 0; row < cropHeight; row++) {
    final offset = (top + row) * sourceStride + left * (nv21 ? 1 : 4);
    output.setRange(row * rowBytes, (row + 1) * rowBytes, bytes, offset);
  }
  if (nv21) {
    final ySize = cropWidth * cropHeight;
    for (var row = 0; row < cropHeight ~/ 2; row++) {
      final offset = width * height + (top ~/ 2 + row) * width + left;
      output.setRange(
        ySize + row * cropWidth,
        ySize + (row + 1) * cropWidth,
        bytes,
        offset,
      );
    }
  }
  final actual = _rotate(
    Rect.fromLTRB(left / width, top / height, right / width, bottom / height),
    rotation,
  );
  final swapped = rotation == 90 || rotation == 270;
  return CroppedCameraBytes(
    bytes: output,
    width: cropWidth,
    height: cropHeight,
    bytesPerRow: rowBytes,
    uprightOrigin: Offset(
      actual.left * (swapped ? height : width),
      actual.top * (swapped ? width : height),
    ),
  );
}
