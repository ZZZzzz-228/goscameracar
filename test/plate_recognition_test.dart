import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:goscameracar/domain/plate_recognition.dart';

void main() {
  test('A detached region follows the text baseline at every tilt', () {
    for (final degrees in [0, 30, 45, 60, 90, 135, 180, 225, 270, 315]) {
      final angle = degrees * math.pi / 180;
      PlateTextLine turn(String text, Rect rect) {
        final corners =
            [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft]
                .map(
                  (p) => Offset(
                    500 + p.dx * math.cos(angle) - p.dy * math.sin(angle),
                    500 + p.dx * math.sin(angle) + p.dy * math.cos(angle),
                  ),
                )
                .toList();
        final xs = corners.map((p) => p.dx), ys = corners.map((p) => p.dy);
        final box = Rect.fromLTRB(
          xs.reduce(math.min),
          ys.reduce(math.min),
          xs.reduce(math.max),
          ys.reduce(math.max),
        );
        return PlateTextLine(
          text,
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
          corners: corners,
        );
      }

      final body = turn('A123BC', const Rect.fromLTWH(0, 0, 240, 60));
      final region = turn('77', const Rect.fromLTWH(255, 5, 60, 40));
      final farRegion = turn('77', const Rect.fromLTWH(255, 130, 60, 40));
      expect(findPlateCandidates([body, region]), {
        'A123BC77',
      }, reason: '$degrees degrees');
      expect(findPlateCandidates([body, farRegion]), {'A123BC'});
      expect(analyzePlateText([body]).zoomTarget, isNotNull);
    }
  });
  test(
    'Reads complete plates and country suffix without guessing characters',
    () {
      expect(
        findPlateCandidates(const [
          PlateTextLine('а 123 вс 77 RUS'),
          PlateTextLine('М777ММ125'),
        ]),
        {'A123BC77', 'M777MM125'},
      );
      expect(
        findPlateCandidates(const [
          PlateTextLine('A12OBC77'),
          PlateTextLine('A123BC7777'),
        ]),
        isEmpty,
      );
    },
  );

  test('Joins a separate region only when it is beside the main plate', () {
    const body = PlateTextLine(
      'А123ВС',
      left: 10,
      top: 20,
      width: 240,
      height: 60,
    );
    expect(
      findPlateCandidates(const [
        body,
        PlateTextLine('77', left: 270, top: 20, width: 60, height: 40),
      ]),
      {'A123BC77'},
    );
    expect(
      findPlateCandidates(const [
        body,
        PlateTextLine('77', left: 270, top: 180, width: 60, height: 40),
      ]),
      {'A123BC'},
    );
    expect(
      findPlateCandidates(const [
        body,
        PlateTextLine('77', left: 600, top: 20, width: 60, height: 40),
      ]),
      {'A123BC'},
    );
  });

  test(
    'Two consistent frames confirm a plate without the previous long delay',
    () {
      final tracker = PlateStabilityTracker();
      final start = DateTime(2026);
      expect(tracker.observe({'A123BC77'}, start), isNull);
      expect(
        tracker.observe({
          'A123BC77',
        }, start.add(const Duration(milliseconds: 140)))?.value,
        'A123BC77',
      );
    },
  );

  test('Partial OCR guides zoom without becoming an access decision', () {
    final analysis = analyzePlateText(const [
      PlateTextLine('A123B', left: 10, top: 40, width: 120, height: 30),
    ]);
    expect(analysis.candidates, isEmpty);
    expect(analysis.zoomTarget, isNotNull);
    expect(analysis.zoomTarget!.plate, isNull);
  });

  test('Separate region is included in the zoom target', () {
    final analysis = analyzePlateText(const [
      PlateTextLine('A123BC', left: 10, top: 20, width: 240, height: 60),
      PlateTextLine('77', left: 270, top: 20, width: 60, height: 40),
    ]);
    expect(analysis.zoomTarget!.bounds.right, 330);
    expect(analysis.candidates, {'A123BC77'});
  });

  test('Two plates do not cause zoom toward an arbitrary car', () {
    final analysis = analyzePlateText(const [
      PlateTextLine('A123BC77', left: 10, top: 20, width: 240, height: 60),
      PlateTextLine('M777MM125', left: 300, top: 20, width: 240, height: 60),
    ]);
    expect(analysis.zoomTarget, isNull);
  });

  test(
    'Multiple cars, missing frames, another plate and a time gap reset stability',
    () {
      final tracker = PlateStabilityTracker();
      var now = DateTime(2026);
      void prime() {
        tracker.observe({'A123BC77'}, now);
        tracker.observe({'A123BC77'}, now);
      }

      for (final candidates in [
        <String>{},
        {'A123BC77', 'M777MM125'},
        {'M777MM125'},
      ]) {
        tracker.reset();
        prime();
        expect(tracker.observe(candidates, now), isNull);
        expect(tracker.observe({'A123BC77'}, now), isNull);
      }
      tracker.reset();
      prime();
      now = now.add(const Duration(seconds: 3));
      expect(tracker.observe({'A123BC77'}, now), isNull);
    },
  );
}
