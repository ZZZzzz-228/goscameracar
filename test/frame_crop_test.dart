import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:goscameracar/camera/frame_crop.dart';

void main() {
  test('NV21 crop preserves Y pixels and VU pairs', () {
    final source = Uint8List.fromList(
      List.generate(8 * 4 * 3 ~/ 2, (index) => index),
    );
    final crop = cropCameraBytes(
      bytes: source,
      width: 8,
      height: 4,
      bytesPerRow: 8,
      nv21: true,
      rotation: 0,
      uprightCrop: const Rect.fromLTWH(.25, 0, .5, 1),
    )!;
    expect(crop.width, 4);
    expect(crop.height, 4);
    expect(crop.bytes, [
      2,
      3,
      4,
      5,
      10,
      11,
      12,
      13,
      18,
      19,
      20,
      21,
      26,
      27,
      28,
      29,
      34,
      35,
      36,
      37,
      42,
      43,
      44,
      45,
    ]);
    expect(crop.uprightOrigin, const Offset(2, 0));
  });

  test('Rotated crop maps recognition coordinates back to the full image', () {
    final source = Uint8List(8 * 4 * 3 ~/ 2);
    final crop = cropCameraBytes(
      bytes: source,
      width: 8,
      height: 4,
      bytesPerRow: 8,
      nv21: true,
      rotation: 90,
      uprightCrop: const Rect.fromLTWH(0, .25, 1, .5),
    )!;
    expect(crop.width, 4);
    expect(crop.height, 4);
    expect(crop.uprightOrigin, const Offset(0, 2));
    for (final rotation in [0, 90, 180, 270]) {
      final full = cropCameraBytes(
        bytes: source,
        width: 8,
        height: 4,
        bytesPerRow: 8,
        nv21: true,
        rotation: rotation,
        uprightCrop: const Rect.fromLTWH(0, 0, 1, 1),
      )!;
      expect(full.bytes, source);
      expect(full.uprightOrigin, Offset.zero);
    }
  });

  test('BGRA crop handles row padding without mixing adjacent rows', () {
    final source = Uint8List.fromList(List.generate(40, (index) => index));
    final crop = cropCameraBytes(
      bytes: source,
      width: 4,
      height: 2,
      bytesPerRow: 20,
      nv21: false,
      rotation: 0,
      uprightCrop: const Rect.fromLTWH(.5, 0, .5, 1),
    )!;
    expect(crop.bytes, [
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      28,
      29,
      30,
      31,
      32,
      33,
      34,
      35,
    ]);
    expect(crop.bytesPerRow, 8);
  });

  test('Invalid or truncated buffers fall back to full-frame recognition', () {
    expect(
      cropCameraBytes(
        bytes: Uint8List(2),
        width: 8,
        height: 4,
        bytesPerRow: 8,
        nv21: true,
        rotation: 0,
        uprightCrop: const Rect.fromLTWH(0, 0, 1, 1),
      ),
      isNull,
    );
    expect(
      cropCameraBytes(
        bytes: Uint8List(48),
        width: 8,
        height: 4,
        bytesPerRow: 8,
        nv21: true,
        rotation: 0,
        uprightCrop: Rect.zero,
      ),
      isNull,
    );
  });
}
