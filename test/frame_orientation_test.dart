import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:goscameracar/camera/frame_orientation.dart';

void main() {
  test(
    'OCR boxes return to the same off-centre preview target for every rotation',
    () {
      const size = Size(1280, 720);
      const target = Rect.fromLTWH(.12, .6, .28, .08);
      for (final angle in [0, 90, 180, 270]) {
        final rotated = rotateNormalizedBounds(target, angle);
        final ocrSize = rotatedFrameSize(size, angle);
        final pixels = Rect.fromLTRB(
          rotated.left * ocrSize.width,
          rotated.top * ocrSize.height,
          rotated.right * ocrSize.width,
          rotated.bottom * ocrSize.height,
        );
        final restored = undoOcrRotation(pixels, size, angle);
        expect(restored.left, closeTo(target.left * size.width, .001));
        expect(restored.top, closeTo(target.top * size.height, .001));
        expect(restored.width, closeTo(target.width * size.width, .001));
        expect(restored.height, closeTo(target.height * size.height, .001));
      }
    },
  );

  test('iOS BGRA rotation preserves all channels and skips row padding', () {
    final bytes = Uint8List(32);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 3; x++) {
        final value = 1 + y * 3 + x;
        bytes.setRange(y * 16 + x * 4, y * 16 + x * 4 + 4, [
          value,
          value + 10,
          value + 20,
          255,
        ]);
      }
    }
    for (final entry in {
      90: [4, 1, 5, 2, 6, 3],
      180: [6, 5, 4, 3, 2, 1],
      270: [3, 6, 2, 5, 1, 4],
    }.entries) {
      final rotated = rotateBgra(
        bytes: bytes,
        width: 3,
        height: 2,
        bytesPerRow: 16,
        rotation: entry.key,
      );
      expect(
        rotated,
        entry.value
            .expand((value) => [value, value + 10, value + 20, 255])
            .toList(),
      );
    }
  });

  test(
    'Search covers all four orientations, holds a read and escapes partial text',
    () {
      final search = PlateOrientationSearch();
      for (final angle in [0, 90, 180, 270]) {
        expect(search.rotation, angle);
        search.observe(complete: false, partial: false);
      }
      search.observe(complete: false, partial: false);
      expect(search.rotation, 90);
      search.observe(complete: true, partial: true);
      expect(search.rotation, 90);
      search.observe(complete: false, partial: true);
      expect(search.rotation, 90);
      search.observe(complete: false, partial: true);
      expect(search.rotation, 180);
      search.reset();
      expect(search.rotation, 0);
    },
  );
}
