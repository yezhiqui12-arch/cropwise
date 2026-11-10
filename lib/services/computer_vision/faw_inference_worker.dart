import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import 'managed_inference_worker.dart';
import 'maize_leaf_classifier.dart';
import 'pest_species_detector.dart';
import 'tflite_faw_detector.dart';
import 'two_stage_faw_cv_service.dart';

ManagedInferenceWorker createFawInferenceWorker({
  required bool highlighting,
}) => ManagedInferenceWorker(
  entryPoint: fawInferenceWorkerMain,
  initialData: () async {
    // Asset loading stays on the root isolate; decoding and all native model
    // operations belong to the worker. Transfer buffers without another copy.
    final assets = await Future.wait([
      rootBundle.load(
        'assets/models/wormwise_faw_damage_classifier_320_float32.tflite',
      ),
      if (highlighting)
        rootBundle.load('assets/models/wormwise_yolo11n_960_float32.tflite'),
      if (highlighting)
        rootBundle.load(
          'assets/models/wormwise_pest_species_yolov8n_640_float32.tflite',
        ),
    ]);
    return [
      for (final asset in assets)
        TransferableTypedData.fromList([Uint8List.sublistView(asset)]),
    ];
  },
);

@pragma('vm:entry-point')
void fawInferenceWorkerMain(List<Object?> bootstrap) async {
  final replies = bootstrap[0] as SendPort;
  final models = bootstrap[1] as List;
  Uint8List? bytes(int index) => index < models.length
      ? (models[index] as TransferableTypedData).materialize().asUint8List()
      : null;
  final classifier = MaizeLeafClassifier(modelBytes: bytes(0));
  final detector = TfliteFawDetector(
    modelBytes: bytes(1),
    pestSpeciesDetector: PestSpeciesDetector(modelBytes: bytes(2)),
  );
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  Object? failure;
  try {
    await for (final dynamic message in commands) {
      if (message == null) break;
      try {
        final request = message as Map;
        final source = File(request['path'] as String);
        if (await source.exists()) {
          final decoded = img.decodeImage(await source.readAsBytes());
          if (decoded != null) {
            final oriented = img.bakeOrientation(decoded);
            classifier.preparedImage = oriented;
            detector.preparedImage = oriented;
          }
        }
        // The workers own the models; a per-request pipeline carries settings
        // without reading plugins/preferences from this background isolate.
        final pipeline = TwoStageFawCvService(
          classifier: classifier,
          detector: detector,
          loadPreferences: false,
          fawDamageThreshold: request['threshold'] as double,
        )..useAssessmentHighlighting(request['highlighting'] as bool);
        final result = await pipeline.analyzeImage(
          File(request['path'] as String),
        );
        classifier.preparedImage = null;
        detector.preparedImage = null;
        replies.send({'result': result.toJson()});
      } catch (error) {
        failure = error;
        break;
      }
    }
  } finally {
    classifier.preparedImage = null;
    detector.preparedImage = null;
    classifier.close();
    detector.close();
    commands.close();
    replies.send(
      failure == null ? {'result': null} : {'error': failure.toString()},
    );
  }
}
