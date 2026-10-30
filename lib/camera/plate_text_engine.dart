import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Keep the native model ready across cars and camera screen reopenings.
/// The operating system releases this app-lifetime resource on process exit.
final plateTextEngine = PlateTextEngine();

class PlateTextEngine {
  TextRecognizer? _recognizer;
  Future<void> _queue = Future.value();
  Future<void>? _warmup;

  Future<RecognizedText> processImage(InputImage input) {
    final result = _queue.then((_) {
      final recognizer = _recognizer ??= TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      return recognizer.processImage(input);
    });
    // A failed frame must not poison subsequent scans.
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> warmUp() => _warmup ??= processImage(
    InputImage.fromBitmap(
      bitmap: Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 255),
      width: 64,
      height: 64,
    ),
  ).then<void>((_) {}, onError: (Object _, StackTrace _) {});
}
