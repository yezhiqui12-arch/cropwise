import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Internal Stage 1 binary FAW-damage screening output.
class MaizeClassificationResult {
  const MaizeClassificationResult({
    required this.topClass,
    required this.topConfidence,
    required this.probabilities,
    this.inferenceDurationMs = 0,
    this.modelName = 'Cropwise-YOLO11n-Cls-320-float32',
  });

  final String topClass;
  final double topConfidence;
  final Map<String, double> probabilities;
  final int inferenceDurationMs;
  final String modelName;

  double get fawDamageProbability =>
      (probabilities['faw_damage'] ?? 0.0).clamp(0.0, 1.0);

  bool get isFawSuspected => fawDamageProbability >= 0.50;

  bool get isHealthy =>
      topClass == 'no_faw_damage' &&
      (probabilities['no_faw_damage'] ?? 0.0) >= 0.50;

  String get binaryLabel => isFawSuspected ? 'FAW damage' : 'No FAW damage';

  Map<String, dynamic> toJson() => {
    'topClass': topClass,
    'topConfidence': topConfidence,
    'probabilities': probabilities,
    'inferenceDurationMs': inferenceDurationMs,
    'modelName': modelName,
  };
}

/// Runs the binary YOLO11n Stage 1 FAW-damage classifier.
class MaizeLeafClassifier {
  MaizeLeafClassifier({
    this.modelBytes,
    this.modelAssetPath =
        'assets/models/wormwise_faw_damage_classifier_320_float32.tflite',
    this.simulatedResult,
  });

  static const int inputSize = 320;
  static const List<String> classes = ['faw_damage', 'no_faw_damage'];

  final String modelAssetPath;
  final Uint8List? modelBytes;
  MaizeClassificationResult? simulatedResult;

  /// Request-scoped, already oriented image owned by the inference worker.
  img.Image? preparedImage;

  Interpreter? _interpreter;
  Future<void>? _initialization;
  List<int>? _inputShape;
  List<int>? _outputShape;
  Object? _loadError;

  bool get isModelLoaded => _interpreter != null || simulatedResult != null;
  Object? get loadError => _loadError;
  String get modelIdentifier => 'Cropwise-YOLO11n-Cls-320-float32';

  Future<void> initialize() {
    if (simulatedResult != null || _interpreter != null) {
      return Future<void>.value();
    }
    return _initialization ??= _loadInterpreter();
  }

  Future<void> _loadInterpreter() async {
    Interpreter? opened;
    try {
      final options = InterpreterOptions()..threads = 2;
      final interpreter = modelBytes == null
          ? await Interpreter.fromAsset(modelAssetPath, options: options)
          : Interpreter.fromBuffer(modelBytes!, options: options);
      opened = interpreter;
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);

      if (input.type != TensorType.float32 ||
          output.type != TensorType.float32) {
        throw StateError(
          'MaizeLeafClassifier requires float32 tensors, but received '
          '${input.type} input and ${output.type} output.',
        );
      }

      _inputShape = List<int>.unmodifiable(input.shape);
      _outputShape = List<int>.unmodifiable(output.shape);
      final inputShape = _inputShape!;
      final outputShape = _outputShape!;
      final isNchw =
          inputShape.length == 4 &&
          inputShape[0] == 1 &&
          inputShape[1] == 3 &&
          inputShape[2] == inputSize &&
          inputShape[3] == inputSize;
      final isNhwc =
          inputShape.length == 4 &&
          inputShape[0] == 1 &&
          inputShape[1] == inputSize &&
          inputShape[2] == inputSize &&
          inputShape[3] == 3;
      if ((!isNchw && !isNhwc) ||
          outputShape.isEmpty ||
          outputShape.last != classes.length) {
        throw StateError(
          'Unexpected Stage 1 tensor shapes: input $inputShape, '
          'output $outputShape.',
        );
      }
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

  Future<MaizeClassificationResult> classifyImage(File imageFile) async {
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
      throw StateError(
        'The MaizeLeafClassifier model could not be loaded: $_loadError',
      );
    }

    final decoded =
        preparedImage ?? img.decodeImage(await imageFile.readAsBytes());
    if (decoded == null) {
      throw const FormatException('The selected file is not a readable image.');
    }

    final oriented = preparedImage ?? img.bakeOrientation(decoded);
    final resized = img.copyResize(
      oriented,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    final inputBuffer = _createInputBuffer(resized, inputShape);
    interpreter.runInference([inputBuffer.buffer]);

    final outputBytes = interpreter.getOutputTensor(0).data;
    final outputBuffer = outputBytes.buffer.asFloat32List(
      outputBytes.offsetInBytes,
      outputBytes.lengthInBytes ~/ Float32List.bytesPerElement,
    );

    final probabilities = _computeProbabilities(outputBuffer);
    stopwatch.stop();

    var bestIndex = 0;
    var bestProb = -1.0;
    for (var i = 0; i < classes.length; i++) {
      final p = probabilities[classes[i]] ?? 0.0;
      if (p > bestProb) {
        bestProb = p;
        bestIndex = i;
      }
    }

    return MaizeClassificationResult(
      topClass: classes[bestIndex],
      topConfidence: bestProb,
      probabilities: probabilities,
      inferenceDurationMs: stopwatch.elapsedMilliseconds,
      modelName: modelIdentifier,
    );
  }

  Float32List _createInputBuffer(img.Image image, List<int> shape) {
    final isNchw = shape.length == 4 && shape[1] == 3;
    final buffer = Float32List(inputSize * inputSize * 3);

    if (isNchw) {
      final planeSize = inputSize * inputSize;
      for (var y = 0; y < inputSize; y++) {
        for (var x = 0; x < inputSize; x++) {
          final pixel = image.getPixel(x, y);
          final index = y * inputSize + x;
          buffer[index] = pixel.r / 255.0;
          buffer[planeSize + index] = pixel.g / 255.0;
          buffer[(2 * planeSize) + index] = pixel.b / 255.0;
        }
      }
    } else {
      var bufferIndex = 0;
      for (var y = 0; y < inputSize; y++) {
        for (var x = 0; x < inputSize; x++) {
          final pixel = image.getPixel(x, y);
          buffer[bufferIndex++] = pixel.r / 255.0;
          buffer[bufferIndex++] = pixel.g / 255.0;
          buffer[bufferIndex++] = pixel.b / 255.0;
        }
      }
    }

    return buffer;
  }

  Map<String, double> _computeProbabilities(Float32List rawOutputs) {
    if (rawOutputs.length < classes.length) {
      throw StateError(
        'Expected at least ${classes.length} output logits, but got ${rawOutputs.length}.',
      );
    }

    var sum = 0.0;
    var maxVal = -double.infinity;
    for (var i = 0; i < classes.length; i++) {
      final val = rawOutputs[i];
      sum += val;
      if (val > maxVal) maxVal = val;
    }

    final isAlreadyProbabilities = (sum >= 0.95 && sum <= 1.05);
    final probs = <String, double>{};

    if (isAlreadyProbabilities) {
      for (var i = 0; i < classes.length; i++) {
        probs[classes[i]] = rawOutputs[i].clamp(0.0, 1.0);
      }
    } else {
      var expSum = 0.0;
      final expVals = List<double>.filled(classes.length, 0.0);
      for (var i = 0; i < classes.length; i++) {
        final ev = math.exp(rawOutputs[i] - maxVal);
        expVals[i] = ev;
        expSum += ev;
      }
      for (var i = 0; i < classes.length; i++) {
        probs[classes[i]] = expSum > 0 ? expVals[i] / expSum : 0.0;
      }
    }

    return Map<String, double>.unmodifiable(probs);
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _initialization = null;
  }
}
