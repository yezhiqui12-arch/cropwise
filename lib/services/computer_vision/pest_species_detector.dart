import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'faw_computer_vision_service.dart';

/// Identifies a Model 2 larva crop with the exported three-pest YOLOv8 model.
/// This is an optional visual suggestion, never an evaluator-confirmed fact.
class PestSpeciesDetector {
  PestSpeciesDetector({
    this.modelAssetPath =
        'assets/models/wormwise_pest_species_yolov8n_640_float32.tflite',
    this.confidenceThreshold = 0.25,
  });

  static const int inputSize = 640;
  static const labels = ['Corn earworm', 'Cutworm', 'Fall armyworm'];
  final String modelAssetPath;
  final double confidenceThreshold;
  Interpreter? _interpreter;
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final interpreter = await Interpreter.fromAsset(
        modelAssetPath,
        options: InterpreterOptions()..threads = 2,
      );
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);
      final inputShape = input.shape;
      final outputShape = output.shape;
      if (input.type != TensorType.float32 ||
          output.type != TensorType.float32 ||
          inputShape.length != 4 ||
          inputShape[0] != 1 ||
          !((inputShape[1] == inputSize &&
                  inputShape[2] == inputSize &&
                  inputShape[3] == 3) ||
              (inputShape[1] == 3 &&
                  inputShape[2] == inputSize &&
                  inputShape[3] == inputSize)) ||
          outputShape.length != 3 ||
          outputShape[0] != 1 ||
          !(outputShape[1] == 7 || outputShape[2] == 7)) {
        interpreter.close();
        throw StateError(
          'Unexpected pest detector tensors: $inputShape -> $outputShape',
        );
      }
      _interpreter = interpreter;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<ModelDetectionBox?> identify(
    img.Image source, {
    required double left,
    required double top,
    required double right,
    required double bottom,
    required String sourcePath,
  }) async {
    await initialize();
    final interpreter = _interpreter!;
    // Keep context around the Model 2 larva box without running on the full
    // photograph or on unrelated damage/frass/egg boxes.
    final centerX = (left + right) / 2;
    final centerY = (top + bottom) / 2;
    final side = math.max(right - left, bottom - top) * 1.6;
    final x1 = (centerX - side / 2).floor().clamp(0, source.width);
    final y1 = (centerY - side / 2).floor().clamp(0, source.height);
    final x2 = (centerX + side / 2).ceil().clamp(0, source.width);
    final y2 = (centerY + side / 2).ceil().clamp(0, source.height);
    if (x2 <= x1 || y2 <= y1) return null;
    final crop = img.copyCrop(
      source,
      x: x1,
      y: y1,
      width: x2 - x1,
      height: y2 - y1,
    );
    final scale = math.min(inputSize / crop.width, inputSize / crop.height);
    final resized = img.copyResize(
      crop,
      width: math.max(1, (crop.width * scale).round()),
      height: math.max(1, (crop.height * scale).round()),
      interpolation: img.Interpolation.linear,
    );
    final padX = (inputSize - resized.width) ~/ 2;
    final padY = (inputSize - resized.height) ~/ 2;
    final canvas = img.Image(
      width: inputSize,
      height: inputSize,
      numChannels: 3,
    );
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    final shape = interpreter.getInputTensor(0).shape;
    final channelsFirst = shape[1] == 3;
    final pixels = Float32List(inputSize * inputSize * 3);
    final plane = inputSize * inputSize;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = canvas.getPixel(x, y);
        final offset = y * inputSize + x;
        if (channelsFirst) {
          pixels[offset] = pixel.r / 255;
          pixels[plane + offset] = pixel.g / 255;
          pixels[2 * plane + offset] = pixel.b / 255;
        } else {
          pixels[3 * offset] = pixel.r / 255;
          pixels[3 * offset + 1] = pixel.g / 255;
          pixels[3 * offset + 2] = pixel.b / 255;
        }
      }
    }
    interpreter.runInference([pixels.buffer]);
    final tensor = interpreter.getOutputTensor(0);
    final bytes = tensor.data;
    final output = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ Float32List.bytesPerElement,
    );
    final outputShape = tensor.shape;
    final attributesFirst = outputShape[1] == 7;
    final candidates = attributesFirst ? outputShape[2] : outputShape[1];
    double at(int candidate, int attribute) => attributesFirst
        ? output[attribute * candidates + candidate]
        : output[candidate * 7 + attribute];

    ModelDetectionBox? best;
    for (var candidate = 0; candidate < candidates; candidate++) {
      var classId = 0;
      var confidence = at(candidate, 4);
      for (var id = 1; id < labels.length; id++) {
        final score = at(candidate, 4 + id);
        if (score > confidence) {
          classId = id;
          confidence = score;
        }
      }
      if (!confidence.isFinite ||
          confidence < confidenceThreshold ||
          (best != null && confidence <= best.confidence)) {
        continue;
      }
      final cx = at(candidate, 0);
      final cy = at(candidate, 1);
      final w = at(candidate, 2);
      final h = at(candidate, 3);
      if (![cx, cy, w, h].every((value) => value.isFinite) ||
          w <= 0 ||
          h <= 0) {
        continue;
      }
      // Ultralytics TFLite exports may report normalized or input-pixel xywh.
      final units = math.max(math.max(cx.abs(), cy.abs()), math.max(w, h)) <= 2
          ? inputSize.toDouble()
          : 1.0;
      final boxLeft = (x1 + ((cx - w / 2) * units - padX) / scale).clamp(
        0.0,
        source.width.toDouble(),
      );
      final boxTop = (y1 + ((cy - h / 2) * units - padY) / scale).clamp(
        0.0,
        source.height.toDouble(),
      );
      final boxRight = (x1 + ((cx + w / 2) * units - padX) / scale).clamp(
        0.0,
        source.width.toDouble(),
      );
      final boxBottom = (y1 + ((cy + h / 2) * units - padY) / scale).clamp(
        0.0,
        source.height.toDouble(),
      );
      if (boxRight <= boxLeft || boxBottom <= boxTop) continue;
      final marginX = (right - left) * 0.2;
      final marginY = (bottom - top) * 0.2;
      final detectedCenterX = (boxLeft + boxRight) / 2;
      final detectedCenterY = (boxTop + boxBottom) / 2;
      if (detectedCenterX < left - marginX ||
          detectedCenterX > right + marginX ||
          detectedCenterY < top - marginY ||
          detectedCenterY > bottom + marginY) {
        continue;
      }
      best = ModelDetectionBox(
        sourcePath: sourcePath,
        classId: 4 + classId,
        label: labels[classId],
        confidence: confidence,
        left: boxLeft / source.width,
        top: boxTop / source.height,
        right: boxRight / source.width,
        bottom: boxBottom / source.height,
        imageWidth: source.width,
        imageHeight: source.height,
      );
    }
    return best;
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _initialization = null;
  }
}
