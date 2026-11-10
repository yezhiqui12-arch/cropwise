import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../data/local/database_codes.dart';
import 'faw_computer_vision_service.dart';
import 'pest_species_detector.dart';

/// Runs the verified WormWise YOLO11n detector fully on-device.
class TfliteFawDetector implements FawComputerVisionService {
  TfliteFawDetector({
    this.modelBytes,
    this.modelAssetPath = 'assets/models/wormwise_yolo11n_960_float32.tflite',
    // Matches the best field-photo configuration verified in Kaggle:
    // imgsz=960, conf=0.10, iou=0.45.
    this.confidenceThreshold = 0.10,
    this.iouThreshold = 0.45,
    PestSpeciesDetector? pestSpeciesDetector,
    this.simulatedResult,
  }) : _pestSpeciesDetector = pestSpeciesDetector ?? PestSpeciesDetector();

  static const int _inputSize = 960;
  static const int _classCount = 4;

  final String modelAssetPath;
  final Uint8List? modelBytes;
  final double confidenceThreshold;
  final double iouThreshold;
  final PestSpeciesDetector _pestSpeciesDetector;
  PlantDiagnosisResult? simulatedResult;

  /// Request-scoped, already oriented image owned by the inference worker.
  img.Image? preparedImage;

  Interpreter? _interpreter;
  Future<void>? _initialization;
  List<int>? _inputShape;
  List<int>? _outputShape;
  Object? _loadError;

  @override
  bool get isModelLoaded => _interpreter != null || simulatedResult != null;

  Object? get loadError => _loadError;

  @override
  String get modelIdentifier =>
      'Cropwise-YOLO11n-Champion-960-float32+PestSpecies-YOLOv8n-640-float32';

  /// Loads the bundled LiteRT/TFLite asset once. Calls are safe to repeat.
  Future<void> initialize() {
    if (simulatedResult != null || _interpreter != null) {
      return Future<void>.value();
    }
    return _initialization ??= _loadInterpreter();
  }

  Future<void> _loadInterpreter() async {
    Interpreter? opened;
    try {
      final options = InterpreterOptions()..threads = 4;
      final interpreter = modelBytes == null
          ? await Interpreter.fromAsset(modelAssetPath, options: options)
          : Interpreter.fromBuffer(modelBytes!, options: options);
      opened = interpreter;
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);

      if (input.type != TensorType.float32 ||
          output.type != TensorType.float32) {
        throw StateError(
          'Cropwise requires float32 tensors, but received '
          '${input.type} input and ${output.type} output.',
        );
      }
      if (!_isSupportedInputShape(input.shape)) {
        throw StateError('Unsupported model input shape: ${input.shape}');
      }
      if (!_isSupportedOutputShape(output.shape)) {
        throw StateError('Unsupported model output shape: ${output.shape}');
      }

      _inputShape = List<int>.unmodifiable(input.shape);
      _outputShape = List<int>.unmodifiable(output.shape);
      _interpreter = interpreter;
      opened = null;
      _loadError = null;
    } catch (error) {
      opened?.close();
      _interpreter = null;
      _inputShape = null;
      _outputShape = null;
      _loadError = error;
      _initialization = null;
      rethrow;
    }
  }

  bool _isSupportedInputShape(List<int> shape) {
    return shape.length == 4 &&
        shape.first == 1 &&
        ((shape[1] == _inputSize && shape[2] == _inputSize && shape[3] == 3) ||
            (shape[1] == 3 &&
                shape[2] == _inputSize &&
                shape[3] == _inputSize));
  }

  bool _isSupportedOutputShape(List<int> shape) {
    if (shape.length != 3 || shape.first != 1) return false;
    final attributes = 4 + _classCount;
    return shape[1] == attributes || shape[2] == attributes;
  }

  @override
  Future<PlantDiagnosisResult> analyzeImage(File imageFile) async {
    final stopwatch = Stopwatch()..start();
    final simulation = simulatedResult;
    if (simulation != null) return simulation;
    if (!await imageFile.exists()) {
      throw const FileSystemException('The screening image is unavailable.');
    }

    await initialize();
    final interpreter = _interpreter;
    final inputShape = _inputShape;
    final outputShape = _outputShape;
    if (interpreter == null || inputShape == null || outputShape == null) {
      throw StateError('The Cropwise model could not be loaded: $_loadError');
    }

    final decoded =
        preparedImage ?? img.decodeImage(await imageFile.readAsBytes());
    if (decoded == null) {
      throw const FormatException('The selected file is not a readable image.');
    }

    final oriented = preparedImage ?? img.bakeOrientation(decoded);
    final prepared = _letterbox(oriented);
    final inputBuffer = _createInputBuffer(prepared.image, inputShape);
    // Transfer exact float32 bytes in and read exact native output bytes back.
    // This avoids List.reshape() copies and the nested-list output type errors
    // that previously prevented usable results on Android.
    interpreter.runInference([inputBuffer.buffer]);
    final outputBytes = interpreter.getOutputTensor(0).data;
    final outputBuffer = outputBytes.buffer.asFloat32List(
      outputBytes.offsetInBytes,
      outputBytes.lengthInBytes ~/ Float32List.bytesPerElement,
    );

    final detections = _classAwareNms(
      _decodeOutput(
        outputBuffer,
        outputShape,
        prepared.scale,
        prepared.padX,
        prepared.padY,
        prepared.originalWidth,
        prepared.originalHeight,
      ),
    );
    final speciesBoxes = <ModelDetectionBox>[];
    // Species identification is triggered only by a Model 2 larva box.
    for (final larva in detections.where(
      (detection) => detection.classId == 2,
    )) {
      try {
        final species = await _pestSpeciesDetector.identify(
          oriented,
          left: larva.box.left,
          top: larva.box.top,
          right: larva.box.right,
          bottom: larva.box.bottom,
          sourcePath: imageFile.absolute.path,
        );
        if (species != null) speciesBoxes.add(species);
      } catch (error) {
        debugPrint(
          '[TfliteFawDetector] Pest identification unavailable: $error',
        );
      }
    }
    stopwatch.stop();
    return _toDiagnosis(
      detections,
      stopwatch.elapsedMilliseconds,
      imageFile.absolute.path,
      prepared.originalWidth,
      prepared.originalHeight,
      speciesBoxes,
    );
  }

  _PreparedImage _letterbox(img.Image source) {
    final scale = math.min(
      _inputSize / source.width,
      _inputSize / source.height,
    );
    final resizedWidth = math.max(1, (source.width * scale).round());
    final resizedHeight = math.max(1, (source.height * scale).round());
    final resized = img.copyResize(
      source,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: img.Interpolation.linear,
    );
    final padX = (_inputSize - resizedWidth) ~/ 2;
    final padY = (_inputSize - resizedHeight) ~/ 2;
    final canvas = img.Image(
      width: _inputSize,
      height: _inputSize,
      numChannels: 3,
    );
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);
    return _PreparedImage(
      image: canvas,
      scale: scale,
      padX: padX,
      padY: padY,
      originalWidth: source.width,
      originalHeight: source.height,
    );
  }

  Float32List _createInputBuffer(img.Image image, List<int> shape) {
    final buffer = Float32List(_inputSize * _inputSize * 3);
    final isChannelsFirst = shape[1] == 3;
    final planeSize = _inputSize * _inputSize;
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final pixel = image.getPixel(x, y);
        final position = y * _inputSize + x;
        final red = pixel.r.toDouble() / 255.0;
        final green = pixel.g.toDouble() / 255.0;
        final blue = pixel.b.toDouble() / 255.0;
        if (isChannelsFirst) {
          buffer[position] = red;
          buffer[planeSize + position] = green;
          buffer[(2 * planeSize) + position] = blue;
        } else {
          final offset = position * 3;
          buffer[offset] = red;
          buffer[offset + 1] = green;
          buffer[offset + 2] = blue;
        }
      }
    }
    return buffer;
  }

  List<_Detection> _decodeOutput(
    Float32List output,
    List<int> shape,
    double scale,
    int padX,
    int padY,
    int originalWidth,
    int originalHeight,
  ) {
    final attributes = 4 + _classCount;
    final channelsFirst = shape[1] == attributes;
    final candidateCount = channelsFirst ? shape[2] : shape[1];
    final detections = <_Detection>[];

    double valueAt(int candidate, int attribute) => channelsFirst
        ? output[(attribute * candidateCount) + candidate]
        : output[(candidate * attributes) + attribute];

    for (var candidate = 0; candidate < candidateCount; candidate++) {
      var classId = 0;
      var confidence = valueAt(candidate, 4);
      for (var id = 1; id < _classCount; id++) {
        final score = valueAt(candidate, 4 + id);
        if (score > confidence) {
          confidence = score;
          classId = id;
        }
      }
      if (!confidence.isFinite || confidence < confidenceThreshold) continue;

      // This Ultralytics TFLite export returns normalized xywh coordinates.
      // Convert them back to the 960x960 letterboxed input before removing
      // padding. Treating these 0..1 values as pixels collapses every box to
      // zero area after padding is removed, which made valid detections appear
      // as an exact 0% result in the app.
      final centerX = valueAt(candidate, 0) * _inputSize;
      final centerY = valueAt(candidate, 1) * _inputSize;
      final width = valueAt(candidate, 2) * _inputSize;
      final height = valueAt(candidate, 3) * _inputSize;
      if (![centerX, centerY, width, height].every((v) => v.isFinite) ||
          width <= 0 ||
          height <= 0) {
        continue;
      }

      final box = _Box(
        left: (((centerX - width / 2) - padX) / scale).clamp(
          0.0,
          originalWidth.toDouble(),
        ),
        top: (((centerY - height / 2) - padY) / scale).clamp(
          0.0,
          originalHeight.toDouble(),
        ),
        right: (((centerX + width / 2) - padX) / scale).clamp(
          0.0,
          originalWidth.toDouble(),
        ),
        bottom: (((centerY + height / 2) - padY) / scale).clamp(
          0.0,
          originalHeight.toDouble(),
        ),
      );
      if (box.area <= 0) continue;
      detections.add(
        _Detection(classId: classId, confidence: confidence, box: box),
      );
    }
    return detections;
  }

  List<_Detection> _classAwareNms(List<_Detection> detections) {
    final sorted = [...detections]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <_Detection>[];
    for (final candidate in sorted) {
      final suppressed = kept.any(
        (existing) =>
            existing.classId == candidate.classId &&
            _iou(existing.box, candidate.box) > iouThreshold,
      );
      if (!suppressed) kept.add(candidate);
    }
    return kept;
  }

  double _iou(_Box a, _Box b) {
    final overlapWidth = math.max(
      0.0,
      math.min(a.right, b.right) - math.max(a.left, b.left),
    );
    final overlapHeight = math.max(
      0.0,
      math.min(a.bottom, b.bottom) - math.max(a.top, b.top),
    );
    final intersection = overlapWidth * overlapHeight;
    final union = a.area + b.area - intersection;
    return union <= 0 ? 0 : intersection / union;
  }

  PlantDiagnosisResult _toDiagnosis(
    List<_Detection> detections,
    int durationMs,
    String sourcePath,
    int imageWidth,
    int imageHeight,
    List<ModelDetectionBox> speciesBoxes,
  ) {
    if (detections.isEmpty) {
      return PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'No FAW Evidence Detected',
        confidenceScore: 0,
        suggestedPlantStatus: DatabaseCodes.plantNegative,
        inferenceDurationMs: durationMs,
        modelName: modelIdentifier,
      );
    }

    final classIds = detections.map((d) => d.classId).toSet();
    final maxConfidence = detections.map((d) => d.confidence).reduce(math.max);
    final hasDamage = classIds.contains(0);
    final hasFrass = classIds.contains(1);
    final hasLarva = classIds.contains(2);
    final hasEgg = classIds.contains(3);
    final signs = <String>[
      if (hasDamage) 'larval_damage',
      if (hasFrass) 'fresh_frass',
      if (hasLarva) 'larva',
      if (hasEgg) 'egg_mass',
    ];

    return PlantDiagnosisResult(
      isInfested: true,
      pestLabel: speciesBoxes.isEmpty
          ? signs.map((s) => s.replaceAll('_', ' ')).join(', ')
          : speciesBoxes.map((box) => box.label).toSet().join(', '),
      confidenceScore: speciesBoxes.isEmpty
          ? maxConfidence
          : speciesBoxes.map((box) => box.confidence).reduce(math.max),
      suggestedPlantStatus: DatabaseCodes.plantCurrentPositive,
      detectedSigns: signs,
      larvaVisible: hasLarva,
      larvalSize: hasLarva ? 'uncertain' : 'none_seen',
      windowpanes: hasDamage,
      scraping: hasDamage,
      cutting: false,
      frass: hasFrass,
      whorlFeeding: false,
      inferenceDurationMs: durationMs,
      modelName: modelIdentifier,
      detectionBoxes: [
        ...detections.map(
          (detection) => ModelDetectionBox(
            sourcePath: sourcePath,
            classId: detection.classId,
            label: const [
              'Larval damage',
              'Frass',
              'Larva',
              'Egg',
            ][detection.classId],
            confidence: detection.confidence,
            left: detection.box.left / imageWidth,
            top: detection.box.top / imageHeight,
            right: detection.box.right / imageWidth,
            bottom: detection.box.bottom / imageHeight,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          ),
        ),
        ...speciesBoxes,
      ],
    );
  }

  void close() {
    _interpreter?.close();
    _pestSpeciesDetector.close();
    _interpreter = null;
    _inputShape = null;
    _outputShape = null;
    _initialization = null;
  }
}

class _PreparedImage {
  const _PreparedImage({
    required this.image,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.originalWidth,
    required this.originalHeight,
  });

  final img.Image image;
  final double scale;
  final int padX;
  final int padY;
  final int originalWidth;
  final int originalHeight;
}

class _Detection {
  const _Detection({
    required this.classId,
    required this.confidence,
    required this.box,
  });

  final int classId;
  final double confidence;
  final _Box box;
}

class _Box {
  const _Box({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get area => math.max(0.0, right - left) * math.max(0.0, bottom - top);
}
