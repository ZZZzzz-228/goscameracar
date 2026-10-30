import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:integration_test/integration_test.dart';
import 'package:goscameracar/camera/frame_orientation.dart';
import 'package:goscameracar/camera/oriented_input.dart';
import 'package:goscameracar/domain/plate_recognition.dart';

Future<InputImage> makePlateImage(double degrees) async {
  const width = 720, height = 720;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, width * 1.0, height * 1.0),
    Paint()..color = Colors.grey,
  );
  canvas.translate(360, 360);
  canvas.rotate(degrees * math.pi / 180);
  canvas.drawRect(
    const Rect.fromLTWH(-280, -80, 560, 160),
    Paint()..color = Colors.white,
  );
  final text = TextPainter(
    text: const TextSpan(
      text: 'A123BC77',
      style: TextStyle(
        fontSize: 82,
        fontFamily: 'sans-serif',
        fontWeight: FontWeight.w600,
        color: Colors.black,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final rgba = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  final nv21 = Uint8List(width * height * 3 ~/ 2);
  for (var i = 0; i < width * height; i++) {
    nv21[i] =
        ((66 * rgba[i * 4] +
                129 * rgba[i * 4 + 1] +
                25 * rgba[i * 4 + 2] +
                128) >>
            8) +
        16;
  }
  nv21.fillRange(width * height, nv21.length, 128);
  image.dispose();
  picture.dispose();
  text.dispose();
  return InputImage.fromBytes(
    bytes: nv21,
    metadata: InputImageMetadata(
      size: const Size(720, 720),
      rotation: InputImageRotation.rotation0deg,
      format: InputImageFormat.nv21,
      bytesPerRow: width,
    ),
  );
}

PlateAnalysis analyzeNative(RecognizedText result) => analyzePlateText(
  result.blocks
      .expand((block) => block.lines)
      .map(
        (line) => PlateTextLine(
          line.text,
          left: line.boundingBox.left,
          top: line.boundingBox.top,
          width: line.boundingBox.width,
          height: line.boundingBox.height,
          corners: line.cornerPoints
              .map((p) => Offset(p.x.toDouble(), p.y.toDouble()))
              .toList(),
        ),
      )
      .toList(),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native OCR finds tilted and inverted plates and preserves focus geometry',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Проверка углов распознавания')),
        ),
      );
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final failures = <int>[];
      try {
        for (final angle in [
          0,
          15,
          30,
          45,
          60,
          75,
          90,
          120,
          135,
          150,
          180,
          210,
          225,
          240,
          270,
          300,
          315,
          330,
        ]) {
          final input = await makePlateImage(angle.toDouble());
          final search = PlateOrientationSearch();
          var found = false;
          final watch = Stopwatch()..start();
          for (var attempt = 0; attempt < 4; attempt++) {
            final rotation = search.rotation;
            final analysis = analyzeNative(
              await recognizer.processImage(
                await orientPlateInput(input, rotation),
              ),
            );
            if (analysis.candidates.contains('A123BC77')) {
              final restored = undoOcrRotation(
                analysis.zoomTarget!.bounds,
                const Size(720, 720),
                rotation,
              );
              expect(
                (restored.center - const Offset(360, 360)).distance,
                lessThan(50),
              );
              found = true;
              search.observe(complete: true, partial: true);
              expect(search.rotation, rotation);
              break;
            }
            search.observe(complete: false, partial: false);
          }
          debugPrint(
            'Angle $angle: $found, ${watch.elapsedMilliseconds}ms, OCR rotation ${search.rotation}',
          );
          if (!found) failures.add(angle);
        }
        expect(
          failures,
          isEmpty,
          reason: 'Unrecognized synthetic plate angles',
        );
      } finally {
        await recognizer.close();
      }
    },
  );
}
