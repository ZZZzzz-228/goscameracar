import 'dart:typed_data';
import 'dart:ui';

int normalizedRotation(int degrees) => (degrees % 360 + 360) % 360;

Size rotatedFrameSize(Size size, int rotation) =>
    normalizedRotation(rotation) % 180 == 0
    ? size
    : Size(size.height, size.width);

Rect rotateNormalizedBounds(Rect rect, int rotation) =>
    switch (normalizedRotation(rotation)) {
      90 => Rect.fromLTRB(1 - rect.bottom, rect.left, 1 - rect.top, rect.right),
      180 => Rect.fromLTRB(
        1 - rect.right,
        1 - rect.bottom,
        1 - rect.left,
        1 - rect.top,
      ),
      270 => Rect.fromLTRB(
        rect.top,
        1 - rect.right,
        rect.bottom,
        1 - rect.left,
      ),
      _ => rect,
    };

/// ML Kit's extra reading rotation must not move the preview/focus target.
Rect undoOcrRotation(Rect bounds, Size baseSize, int extraRotation) {
  final ocrSize = rotatedFrameSize(baseSize, extraRotation);
  final normalized = Rect.fromLTRB(
    bounds.left / ocrSize.width,
    bounds.top / ocrSize.height,
    bounds.right / ocrSize.width,
    bounds.bottom / ocrSize.height,
  );
  final restored = rotateNormalizedBounds(normalized, -extraRotation);
  return Rect.fromLTRB(
    restored.left * baseSize.width,
    restored.top * baseSize.height,
    restored.right * baseSize.width,
    restored.bottom * baseSize.height,
  );
}

/// iOS ignores ML Kit rotation metadata, so turn its BGRA buffer explicitly.
Uint8List rotateBgra({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  required int rotation,
}) {
  final angle = normalizedRotation(rotation);
  if (angle == 0) return bytes;
  if (![90, 180, 270].contains(angle) ||
      bytesPerRow < width * 4 ||
      bytes.length < bytesPerRow * height) {
    throw ArgumentError('Invalid BGRA frame');
  }
  final outputWidth = angle == 180 ? width : height;
  final output = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final (dx, dy) = switch (angle) {
        90 => (height - 1 - y, x),
        180 => (width - 1 - x, height - 1 - y),
        _ => (y, width - 1 - x),
      };
      final src = y * bytesPerRow + x * 4;
      final dst = (dy * outputWidth + dx) * 4;
      output.setRange(dst, dst + 4, bytes, src);
    }
  }
  return output;
}

/// One OCR orientation per fresh frame; keep a successful orientation so that
/// confirming a plate does not require running OCR four times on every frame.
class PlateOrientationSearch {
  int rotation = 0;
  int _partialFrames = 0;

  void observe({required bool complete, required bool partial}) {
    if (complete) {
      _partialFrames = 0;
      return;
    }
    if (partial && ++_partialFrames < 2) return;
    _partialFrames = 0;
    rotation = (rotation + 90) % 360;
  }

  void reset() {
    rotation = 0;
    _partialFrames = 0;
  }
}
