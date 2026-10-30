import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:integration_test/integration_test.dart';
import 'package:goscameracar/domain/plate_recognition.dart';
import 'package:goscameracar/domain/plate_zoom.dart';
import 'package:goscameracar/camera/frame_crop.dart';

List<PlateTextLine> plateLines(
  RecognizedText result, [
  Offset origin = Offset.zero,
]) => result.blocks
    .expand((block) => block.lines)
    .map(
      (line) => PlateTextLine(
        line.text,
        left: line.boundingBox.left + origin.dx,
        top: line.boundingBox.top + origin.dy,
        width: line.boundingBox.width,
        height: line.boundingBox.height,
      ),
    )
    .toList();

// A portrait image encoded as a landscape NV21 sensor buffer, rotation 90.
Uint8List rotatedNv21(Uint8List rgba, int uprightWidth, int uprightHeight) {
  final width = uprightHeight, height = uprightWidth;
  final bytes = Uint8List(width * height * 3 ~/ 2);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final source = (x * uprightWidth + uprightWidth - 1 - y) * 4;
      bytes[y * width + x] =
          ((66 * rgba[source] +
                  129 * rgba[source + 1] +
                  25 * rgba[source + 2] +
                  128) >>
              8) +
          16;
    }
  }
  bytes.fillRange(width * height, bytes.length, 128);
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Native ML Kit reads an image of a plate', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Проверка распознавания'))),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1100, 300),
      Paint()..color = Colors.white,
    );
    final text = TextPainter(
      text: const TextSpan(
        text: 'A123BC77',
        style: TextStyle(
          fontFamily: 'sans-serif',
          fontSize: 160,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    text.layout();
    text.paint(canvas, const Offset(50, 40));
    final picture = recorder.endRecording();
    final image = await picture.toImage(1100, 300);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromBitmap(
          bitmap: bytes!.buffer.asUint8List(),
          width: 1100,
          height: 300,
        ),
      );
      expect(findPlateCandidates(plateLines(result)), contains('A123BC77'));
    } finally {
      await recognizer.close();
      image.dispose();
      picture.dispose();
      text.dispose();
    }
  });

  testWidgets('Off-centre plate survives a rotated NV21 crop in native ML Kit', (
    tester,
  ) async {
    const upright = Size(1080, 1920);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Offset.zero & upright, Paint()..color = Colors.grey);
    canvas.drawRect(
      const Rect.fromLTWH(15, 1190, 610, 150),
      Paint()..color = Colors.white,
    );
    final text = TextPainter(
      text: const TextSpan(
        text: 'A123BC77',
        style: TextStyle(
          fontFamily: 'sans-serif',
          fontSize: 86,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, const Offset(35, 1205));
    final picture = recorder.endRecording();
    final image = await picture.toImage(1080, 1920);
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = rotatedNv21(rgba!.buffer.asUint8List(), 1080, 1920);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final timer = Stopwatch()..start();
      final result = await recognizer.processImage(
        InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: const Size(1920, 1080),
            rotation: InputImageRotation.rotation90deg,
            format: InputImageFormat.nv21,
            bytesPerRow: 1920,
          ),
        ),
      );
      final fullTime = timer.elapsedMilliseconds;
      final analysis = analyzePlateText(plateLines(result));
      expect(analysis.candidates, {'A123BC77'});
      final bounds = analysis.zoomTarget!.bounds;
      expect(bounds.left, lessThan(100));
      expect(bounds.top, greaterThan(1200));
      final target = normalizePlateBounds(bounds, upright);
      final crop = cropCameraBytes(
        bytes: bytes,
        width: 1920,
        height: 1080,
        bytesPerRow: 1920,
        nv21: true,
        rotation: 90,
        uprightCrop: plateRecognitionCrop(target),
      )!;
      expect(crop.bytes.length, lessThan(bytes.length ~/ 3));
      timer.reset();
      final croppedResult = await recognizer.processImage(
        InputImage.fromBytes(
          bytes: crop.bytes,
          metadata: InputImageMetadata(
            size: Size(crop.width.toDouble(), crop.height.toDouble()),
            rotation: InputImageRotation.rotation90deg,
            format: InputImageFormat.nv21,
            bytesPerRow: crop.bytesPerRow,
          ),
        ),
      );
      final cropTime = timer.elapsedMilliseconds;
      final croppedAnalysis = analyzePlateText(
        plateLines(croppedResult, crop.uprightOrigin),
      );
      expect(croppedAnalysis.candidates, {'A123BC77'});
      final restored = croppedAnalysis.zoomTarget!.bounds;
      expect((restored.center - bounds.center).distance, lessThan(10));
      debugPrint(
        'Synthetic Full HD: full OCR ${fullTime}ms, cropped OCR ${cropTime}ms; '
        'crop ${(100 * crop.bytes.length / bytes.length).round()}% of buffer',
      );
    } finally {
      await recognizer.close();
      image.dispose();
      picture.dispose();
      text.dispose();
    }
  });

  testWidgets('Android camera stream supports zoom, focus and NV21 crops', (
    tester,
  ) async {
    final cameras = await availableCameras();
    expect(cameras, isNotEmpty);
    final controller = CameraController(
      cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      ),
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await controller.initialize();
    var frame = Completer<CameraImage>();
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CameraPreview(controller))),
      );
      await controller.startImageStream((image) {
        if (!frame.isCompleted) frame.complete(image);
      });
      final image = await frame.future.timeout(const Duration(seconds: 15));
      expect(image.format.group, ImageFormatGroup.nv21);
      expect(image.planes.length, 1);
      expect(image.planes.single.bytes, isNotEmpty);
      final minimum = await controller.getMinZoomLevel();
      final maximum = await controller.getMaxZoomLevel();
      final base = 1.0.clamp(minimum, maximum);
      final zoom = plateCameraZoom(
        const Rect.fromLTWH(.42, .45, .16, .04),
        base,
        minimum,
        maximum,
      );
      await controller.setFocusMode(FocusMode.auto);
      await controller.setZoomLevel(zoom);
      await controller.setFocusPoint(const Offset(.45, .6));
      frame = Completer<CameraImage>();
      final zoomed = await frame.future.timeout(const Duration(seconds: 15));
      final rotation = controller.description.sensorOrientation;
      final crop = cropCameraBytes(
        bytes: zoomed.planes.single.bytes,
        width: zoomed.width,
        height: zoomed.height,
        bytesPerRow: zoomed.planes.single.bytesPerRow,
        nv21: true,
        rotation: rotation,
        uprightCrop: const Rect.fromLTWH(.2, .3, .6, .4),
      );
      expect(crop, isNotNull);
      await recognizer.processImage(
        InputImage.fromBytes(
          bytes: crop!.bytes,
          metadata: InputImageMetadata(
            size: Size(crop.width.toDouble(), crop.height.toDouble()),
            rotation: InputImageRotationValue.fromRawValue(rotation)!,
            format: InputImageFormat.nv21,
            bytesPerRow: crop.bytesPerRow,
          ),
        ),
      );
      await controller.setZoomLevel(base);
      await controller.setFocusPoint(null);
      debugPrint(
        'Camera ${image.width}x${image.height}, zoom $minimum..$maximum: '
        '$base -> $zoom -> $base, focus and native NV21 crop accepted',
      );
      await controller.stopImageStream();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.dispose();
      await recognizer.close();
    }
  });
}
