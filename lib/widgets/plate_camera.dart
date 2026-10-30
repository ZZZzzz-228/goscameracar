import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../app.dart';
import '../camera/frame_crop.dart';
import '../camera/frame_orientation.dart';
import '../camera/oriented_input.dart';
import '../camera/plate_text_engine.dart';
import '../domain/plate_number.dart';
import '../domain/plate_recognition.dart';
import '../domain/plate_zoom.dart';

class PlateCamera extends StatefulWidget {
  const PlateCamera({
    super.key,
    required this.onRecognized,
    required this.active,
    required this.scanRound,
    this.demoMode = false,
    this.onCandidate,
  });
  final ValueChanged<PlateNumber> onRecognized;
  final bool active;
  final int scanRound;
  final bool demoMode;
  final ValueChanged<String?>? onCandidate;

  @override
  State<PlateCamera> createState() => _PlateCameraState();
}

class _PlateCameraState extends State<PlateCamera> with WidgetsBindingObserver {
  final _tracker = PlatePassageTracker();
  final _orientationSearch = PlateOrientationSearch();
  DeviceOrientation? _frameOrientation;
  CameraController? _camera;
  Future<void> _cameraQueue = Future.value();
  Future<void> _cameraControls = Future.value();
  Future<void>? _pendingRecognition;
  DateTime _lastFullFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAdjustment = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastTargetSeen;
  DateTime? _zoomSettlesUntil;
  Rect? _targetBounds;
  Rect _previewCrop = fullCameraFrame;
  Offset? _focusPoint;
  double _minimumZoom = 1, _maximumZoom = 1, _zoom = 1, _baseZoom = 1;
  bool _adjusting = false;
  bool _changingZoom = false;
  int _zoomRevision = 0;
  int _targetRevision = 0;
  bool _disposed = false;
  bool _loading = true;
  bool _processing = false;
  bool _confirmingPlate = false;
  bool _flash = false;
  int _generation = 0;
  String? _error;

  bool get _supported =>
      !widget.demoMode &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_supported) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(plateTextEngine.warmUp());
      _scheduleCamera(true);
    }
  }

  @override
  void didUpdateWidget(covariant PlateCamera oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scanRound != oldWidget.scanRound ||
        widget.active != oldWidget.active) {
      _tracker.reset();
      _confirmingPlate = false;
    }
    if (widget.scanRound != oldWidget.scanRound) _resetTargeting();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleCamera(true);
    } else {
      _scheduleCamera(false);
    }
  }

  void _scheduleCamera(bool start) {
    final generation = ++_generation;
    _targetRevision++;
    _zoomRevision++;
    _tracker.reset();
    _confirmingPlate = false;
    _orientationSearch.reset();
    _frameOrientation = null;
    _targetBounds = null;
    _lastTargetSeen = null;
    _previewCrop = fullCameraFrame;
    _focusPoint = null;
    _lastFullFrame = DateTime.fromMillisecondsSinceEpoch(0);
    _lastAdjustment = DateTime.fromMillisecondsSinceEpoch(0);
    setState(() {
      _loading = true;
      _error = null;
      _flash = false;
    });
    _cameraQueue = _cameraQueue
        .then((_) async {
          await _releaseCamera();
          if (!start || _disposed || generation != _generation) return;
          final cameras = await availableCameras();
          if (_disposed || generation != _generation) return;
          if (cameras.isEmpty) {
            throw CameraException('NoCamera', 'No camera available');
          }
          final description = cameras.firstWhere(
            (item) => item.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );
          final controller = CameraController(
            description,
            ResolutionPreset.veryHigh,
            enableAudio: false,
            imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
                ? ImageFormatGroup.nv21
                : ImageFormatGroup.bgra8888,
          );
          _camera = controller;
          await controller.initialize();
          if (_disposed || generation != _generation) {
            await _releaseCamera();
            return;
          }
          try {
            _minimumZoom = await controller.getMinZoomLevel();
            _maximumZoom = await controller.getMaxZoomLevel();
            _baseZoom = 1.0.clamp(_minimumZoom, _maximumZoom);
            _zoom = _baseZoom;
            await controller.setZoomLevel(_baseZoom);
          } on CameraException {
            _minimumZoom = _maximumZoom = _baseZoom = _zoom = 1;
          }
          try {
            await controller.setFocusMode(FocusMode.auto);
          } on CameraException {
            /* Optional camera capability. */
          }
          if (_disposed || generation != _generation) {
            await _releaseCamera();
            return;
          }
          await controller.startImageStream(
            (image) => _onFrame(image, controller, generation),
          );
          if (!_disposed && generation == _generation) {
            setState(() => _loading = false);
          }
        })
        .catchError((Object error) async {
          await _releaseCamera();
          if (_disposed || generation != _generation) return;
          setState(() {
            _loading = false;
            _error =
                error is CameraException &&
                    error.code.startsWith('CameraAccess')
                ? 'Нет доступа к камере. Разрешите его в настройках приложения или введите номер вручную.'
                : 'Не удалось открыть камеру. Повторите попытку или введите номер вручную.';
          });
        });
  }

  Future<void> _releaseCamera() async {
    await _cameraControls;
    final controller = _camera;
    _camera = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException {
      /* The OS may have already closed the camera. */
    }
    await controller.dispose();
  }

  InputImage? _inputImage(CameraImage frame, CameraController controller) {
    final description = controller.description;
    var rotationDegrees = description.sensorOrientation;
    if (defaultTargetPlatform == TargetPlatform.android) {
      const orientations = {
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };
      final compensation = orientations[controller.value.deviceOrientation]!;
      rotationDegrees = description.lensDirection == CameraLensDirection.front
          ? (rotationDegrees + compensation) % 360
          : (rotationDegrees - compensation + 360) % 360;
    }
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    final format = InputImageFormatValue.fromRawValue(frame.format.raw);
    final expected = defaultTargetPlatform == TargetPlatform.android
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;
    if (rotation == null || format != expected || frame.planes.length != 1) {
      return null;
    }
    return InputImage.fromBytes(
      bytes: frame.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format!,
        bytesPerRow: frame.planes.first.bytesPerRow,
      ),
    );
  }

  void _onFrame(
    CameraImage frame,
    CameraController controller,
    int generation,
  ) {
    final now = DateTime.now();
    if (_disposed || generation != _generation) return;
    final orientation = controller.value.deviceOrientation;
    if (_frameOrientation != null && _frameOrientation != orientation) {
      setState(_resetTargeting);
    }
    _frameOrientation = orientation;
    if (_disposed ||
        generation != _generation ||
        !widget.active ||
        _processing ||
        _changingZoom ||
        _error != null ||
        (_zoomSettlesUntil != null && now.isBefore(_zoomSettlesUntil!))) {
      return;
    }
    var input = _inputImage(frame, controller);
    if (input == null) {
      setState(
        () =>
            _error = 'Формат камеры не поддерживается. Введите номер вручную.',
      );
      return;
    }
    _processing = true;
    final scanRound = widget.scanRound;
    final metadata = input.metadata!;
    final rotation = defaultTargetPlatform == TargetPlatform.android
        ? metadata.rotation.rawValue
        : 0;
    final swapped = rotation == 90 || rotation == 270;
    final fullSize = swapped
        ? Size(metadata.size.height, metadata.size.width)
        : metadata.size;
    var origin = Offset.zero;
    var cropped = false;
    // Revisit the full scene regularly. Cropped frames never count as an extra
    // confirmation of the same frame and never replace the wide search.
    if (_targetBounds != null &&
        (_confirmingPlate ||
            now.difference(_lastFullFrame).inMilliseconds < 500)) {
      final crop = cropCameraBytes(
        bytes: input.bytes!,
        width: frame.width,
        height: frame.height,
        bytesPerRow: metadata.bytesPerRow,
        nv21: metadata.format == InputImageFormat.nv21,
        rotation: rotation,
        uprightCrop: plateRecognitionCrop(_targetBounds!),
      );
      if (crop != null) {
        input = InputImage.fromBytes(
          bytes: crop.bytes,
          metadata: InputImageMetadata(
            size: Size(crop.width.toDouble(), crop.height.toDouble()),
            rotation: metadata.rotation,
            format: metadata.format,
            bytesPerRow: crop.bytesPerRow,
          ),
        );
        origin = crop.uprightOrigin;
        cropped = true;
      }
    }
    if (!cropped) _lastFullFrame = now;
    _pendingRecognition = _recognize(
      input,
      generation,
      scanRound,
      fullSize,
      origin,
      cropped,
      _zoomRevision,
      _orientationSearch.rotation,
      orientation,
    );
  }

  Future<void> _recognize(
    InputImage input,
    int generation,
    int scanRound,
    Size fullSize,
    Offset origin,
    bool cropped,
    int zoomRevision,
    int extraRotation,
    DeviceOrientation orientation,
  ) async {
    try {
      final prepared = await orientPlateInput(input, extraRotation);
      final result = await plateTextEngine.processImage(prepared);
      if (_disposed ||
          generation != _generation ||
          scanRound != widget.scanRound ||
          zoomRevision != _zoomRevision ||
          orientation != _camera?.value.deviceOrientation ||
          !widget.active) {
        return;
      }
      final lines = result.blocks
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
          .toList();
      final analysis = analyzePlateText(lines);
      widget.onCandidate?.call(
        analysis.candidates.length == 1
            ? PlateNumber.parse(analysis.candidates.single).body
            : null,
      );
      final now = DateTime.now();
      final target = analysis.zoomTarget;
      _orientationSearch.observe(
        complete: analysis.candidates.isNotEmpty,
        partial: target != null,
      );
      if (target != null) {
        final metadata = input.metadata!;
        final baseSize = rotatedFrameSize(
          metadata.size,
          metadata.format == InputImageFormat.nv21
              ? metadata.rotation.rawValue
              : 0,
        );
        final bounds = undoOcrRotation(
          target.bounds,
          baseSize,
          extraRotation,
        ).shift(origin);
        final normalized = normalizePlateBounds(bounds, fullSize);
        if (!normalized.isEmpty) {
          _lastTargetSeen = now;
          _targetBounds = normalized;
          setState(() => _previewCrop = platePreviewCrop(normalized));
        }
      } else {
        if (cropped) _lastFullFrame = DateTime.fromMillisecondsSinceEpoch(0);
        if (analysis.candidates.length > 1 ||
            (_lastTargetSeen != null &&
                now.difference(_lastTargetSeen!).inMilliseconds > 1100)) {
          setState(_resetTargeting);
        }
      }
      final plate = _tracker.observe(analysis.candidates, now);
      _confirmingPlate = _tracker.confirming;
      if (plate != null) {
        _tracker.reset();
        widget.onRecognized(plate);
      } else if (target != null && _targetBounds != null) {
        _adjustToTarget(
          _targetBounds!,
          generation,
          scanRound,
          allowZoom: analysis.candidates.isEmpty,
        );
      }
    } catch (_) {
      if (!_disposed &&
          generation == _generation &&
          scanRound == widget.scanRound &&
          zoomRevision == _zoomRevision &&
          orientation == _camera?.value.deviceOrientation &&
          widget.active) {
        setState(
          () => _error =
              'Не удалось распознать изображение. Повторите попытку или введите номер вручную.',
        );
      }
    } finally {
      _processing = false;
    }
  }

  void _resetTargeting() {
    _targetRevision++;
    _zoomRevision++;
    _tracker.reset();
    _confirmingPlate = false;
    _orientationSearch.reset();
    _targetBounds = null;
    _lastTargetSeen = null;
    _previewCrop = fullCameraFrame;
    _focusPoint = null;
    _lastFullFrame = DateTime.fromMillisecondsSinceEpoch(0);
    _lastAdjustment = DateTime.fromMillisecondsSinceEpoch(0);
    final controller = _camera;
    final generation = _generation;
    final revision = _targetRevision;
    if (controller == null) return;
    _cameraControls = _cameraControls
        .then((_) async {
          if (_disposed ||
              generation != _generation ||
              revision != _targetRevision ||
              controller != _camera) {
            return;
          }
          try {
            if ((_zoom - _baseZoom).abs() >= .08) {
              await _setCameraZoom(controller, _baseZoom);
            }
            await controller.setFocusPoint(null);
          } on CameraException {
            /* Keep manual entry available on limited hardware. */
          }
          if (mounted) setState(() {});
        })
        .catchError((Object _) {});
  }

  Future<void> _setCameraZoom(CameraController controller, double zoom) async {
    // Ignore frames captured during a lens change and results whose geometry
    // belongs to the previous zoom. Controls are serialized by _cameraControls.
    _changingZoom = true;
    _zoomRevision++;
    try {
      await controller.setZoomLevel(zoom);
      _zoom = zoom;
    } finally {
      _changingZoom = false;
      _lastFullFrame = DateTime.fromMillisecondsSinceEpoch(0);
      _zoomSettlesUntil = DateTime.now().add(const Duration(milliseconds: 140));
    }
  }

  void _adjustToTarget(
    Rect target,
    int generation,
    int scanRound, {
    required bool allowZoom,
  }) {
    final controller = _camera;
    final now = DateTime.now();
    if (controller == null ||
        _adjusting ||
        now.difference(_lastAdjustment).inMilliseconds < 650) {
      return;
    }
    // A readable plate gets an immediate second read from the next frame.
    // Hardware zoom is useful for incomplete reads, but delays a complete one.
    final zoom = allowZoom
        ? plateCameraZoom(target, _zoom, _minimumZoom, _maximumZoom)
        : _zoom;
    final moveFocus =
        _focusPoint == null || (_focusPoint! - target.center).distance > .1;
    if ((zoom - _zoom).abs() < .08 && !moveFocus) return;
    _adjusting = true;
    final revision = _targetRevision;
    _lastAdjustment = now;
    _cameraControls = _cameraControls
        .then((_) async {
          try {
            if (_disposed ||
                generation != _generation ||
                scanRound != widget.scanRound ||
                revision != _targetRevision ||
                controller != _camera ||
                !widget.active) {
              return;
            }
            var focusedTarget = target;
            if ((zoom - _zoom).abs() >= .08) {
              final factor = zoom / _zoom;
              try {
                await _setCameraZoom(controller, zoom);
                focusedTarget = Rect.fromLTRB(
                  (target.left - .5) * factor + .5,
                  (target.top - .5) * factor + .5,
                  (target.right - .5) * factor + .5,
                  (target.bottom - .5) * factor + .5,
                );
                if (!_disposed &&
                    generation == _generation &&
                    scanRound == widget.scanRound &&
                    revision == _targetRevision) {
                  setState(() {
                    _targetBounds = focusedTarget;
                    _previewCrop = platePreviewCrop(focusedTarget);
                  });
                }
              } on CameraException {
                /* Digital recentering still works without hardware zoom. */
              }
            }
            if (_disposed ||
                generation != _generation ||
                scanRound != widget.scanRound ||
                revision != _targetRevision ||
                !widget.active) {
              return;
            }
            if (moveFocus) {
              try {
                await controller.setFocusPoint(focusedTarget.center);
              } on CameraException {
                /* Not every lens supports focus points. */
              }
              _focusPoint = focusedTarget.center;
            }
          } finally {
            _adjusting = false;
          }
        })
        .catchError((Object _) {
          _adjusting = false;
        });
  }

  Future<void> _toggleFlash() async {
    final controller = _camera;
    if (controller == null) return;
    try {
      await controller.setFlashMode(_flash ? FlashMode.off : FlashMode.torch);
      if (mounted && controller == _camera) setState(() => _flash = !_flash);
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фонарик недоступен на этой камере.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _cameraQueue
          .then((_) async {
            await _releaseCamera();
            await _pendingRecognition;
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return _notice(
        widget.demoMode
            ? 'Демо-режим: введите номер вручную.'
            : 'Камера доступна в приложении на Android и iPhone. Здесь можно ввести номер вручную.',
      );
    }
    if (_error != null) return _notice(_error!, retry: true);
    if (_loading || _camera == null) {
      return _notice('Открываем камеру…', loading: true);
    }
    final controller = _camera!;
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final preview = value.previewSize!;
        final orientation =
            value.previewPauseOrientation ??
            value.lockedCaptureOrientation ??
            value.deviceOrientation;
        final landscape =
            orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight;
        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: landscape
                    ? preview.width / preview.height
                    : preview.height / preview.width,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRect(
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            TweenAnimationBuilder<Rect?>(
                              tween: RectTween(
                                begin: fullCameraFrame,
                                end: _previewCrop,
                              ),
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              child: CameraPreview(controller),
                              builder: (context, value, child) {
                                final crop = value ?? fullCameraFrame;
                                final scale = 1 / crop.width;
                                final transform =
                                    Matrix4.diagonal3Values(
                                      scale,
                                      scale,
                                      1,
                                    )..setTranslationRaw(
                                      -crop.left * constraints.maxWidth * scale,
                                      -crop.top * constraints.maxHeight * scale,
                                      0,
                                    );
                                return Transform(
                                  transform: transform,
                                  child: child,
                                );
                              },
                            ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton.filledTonal(
                        onPressed: _toggleFlash,
                        tooltip: 'Фонарик',
                        icon: Icon(
                          _flash ? Icons.flashlight_off : Icons.flashlight_on,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _notice(String message, {bool retry = false, bool loading = false}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            if (loading)
              const CircularProgressIndicator(color: accent)
            else
              const Icon(
                Icons.document_scanner_outlined,
                size: 42,
                color: accent,
              ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, height: 1.5),
            ),
            if (retry)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: accent),
                  onPressed: () => _scheduleCamera(true),
                  child: const Text('Повторить'),
                ),
              ),
          ],
        ),
      );
}
