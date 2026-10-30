import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:goscameracar/domain/plate_zoom.dart';

void main() {
  test('Small centred plates request bounded hardware zoom', () {
    const plate = Rect.fromLTWH(.42, .45, .16, .04);
    expect(plateCameraZoom(plate, 1, 1, 10), 1.5);
    expect(plateCameraZoom(plate, 2.8, 1, 10), 3);
    expect(plateCameraZoom(plate, 1, 1, 1), 1);
  });

  test(
    'Off-centre plates stay in view instead of being cropped by the lens',
    () {
      for (final plate in [
        const Rect.fromLTWH(.01, .3, .15, .05),
        const Rect.fromLTWH(.84, .3, .15, .05),
      ]) {
        expect(plateCameraZoom(plate, 1, 1, 10), 1);
        final crop = platePreviewCrop(plate);
        expect(crop.left <= plate.left && crop.right >= plate.right, isTrue);
        expect(crop.top <= plate.top && crop.bottom >= plate.bottom, isTrue);
        expect(crop.width, lessThan(1));
      }
    },
  );

  test(
    'Large plates are not overzoomed and crops stay in image boundaries',
    () {
      const plate = Rect.fromLTWH(.05, .4, .9, .15);
      expect(plateCameraZoom(plate, 1.5, 1, 10), 1.5);
      expect(platePreviewCrop(plate), fullCameraFrame);
      expect(plateRecognitionCrop(plate).left, 0);
      expect(plateRecognitionCrop(plate).right, 1);
    },
  );

  test('Target normalization clips OCR bounding boxes to the full frame', () {
    expect(
      normalizePlateBounds(
        const Rect.fromLTWH(-10, 100, 210, 60),
        const Size(1000, 500),
      ),
      const Rect.fromLTRB(0, .2, .2, .32),
    );
    expect(normalizePlateBounds(Rect.zero, Size.zero), Rect.zero);
  });
}
