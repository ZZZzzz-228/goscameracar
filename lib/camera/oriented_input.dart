import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'frame_orientation.dart';

typedef _BgraJob = ({
  Uint8List bytes,
  int width,
  int height,
  int stride,
  int rotation,
});

Uint8List _turnBgra(_BgraJob job) => rotateBgra(
  bytes: job.bytes,
  width: job.width,
  height: job.height,
  bytesPerRow: job.stride,
  rotation: job.rotation,
);

Future<InputImage> orientPlateInput(InputImage input, int extraRotation) async {
  if (extraRotation == 0) return input;
  final meta = input.metadata!;
  if (meta.format == InputImageFormat.nv21) {
    // Camera bytes stay in place; Android ML Kit applies this rotation natively.
    return InputImage.fromBytes(
      bytes: input.bytes!,
      metadata: InputImageMetadata(
        size: meta.size,
        rotation: InputImageRotationValue.fromRawValue(
          normalizedRotation(meta.rotation.rawValue + extraRotation),
        )!,
        format: meta.format,
        bytesPerRow: meta.bytesPerRow,
      ),
    );
  }
  final bytes = await compute(_turnBgra, (
    bytes: input.bytes!,
    width: meta.size.width.toInt(),
    height: meta.size.height.toInt(),
    stride: meta.bytesPerRow,
    rotation: extraRotation,
  ));
  final size = rotatedFrameSize(meta.size, extraRotation);
  return InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: size,
      rotation: InputImageRotation.rotation0deg,
      format: meta.format,
      bytesPerRow: size.width.toInt() * 4,
    ),
  );
}
