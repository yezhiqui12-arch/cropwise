import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:wormwise/services/computer_vision/faw_inference_worker.dart';
import 'package:wormwise/services/computer_vision/managed_inference_worker.dart';
import 'package:wormwise/services/computer_vision/maize_leaf_classifier.dart';

void main() {
  test(
    'native worker classification matches the direct model',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'wormwise-native-worker-',
      );
      addTearDown(() => root.delete(recursive: true));
      final photo = File('${root.path}/photo.jpg');
      final fixture = image.Image(width: 64, height: 64);
      image.fill(fixture, color: image.ColorRgb8(30, 150, 40));
      await photo.writeAsBytes(image.encodeJpg(fixture));
      final bytes = await File(
        'assets/models/wormwise_faw_damage_classifier_320_float32.tflite',
      ).readAsBytes();
      final classifier = MaizeLeafClassifier(modelBytes: bytes);
      addTearDown(classifier.close);
      final direct = await classifier.classifyImage(photo);
      final worker = ManagedInferenceWorker(
        entryPoint: fawInferenceWorkerMain,
        initialData: () async => [
          TransferableTypedData.fromList([bytes]),
          TransferableTypedData.fromList([
            await File(
              'assets/models/wormwise_yolo11n_960_float32.tflite',
            ).readAsBytes(),
          ]),
          TransferableTypedData.fromList([
            await File(
              'assets/models/wormwise_pest_species_yolov8n_640_float32.tflite',
            ).readAsBytes(),
          ]),
        ],
      );
      addTearDown(worker.close);
      final result =
          await worker.run({
                'path': photo.path,
                'highlighting': false,
                'threshold': .5,
              })
              as Map;
      final probabilities = result['classificationProbabilities'] as Map;
      expect(
        probabilities['FAW damage'],
        closeTo(direct.fawDamageProbability, .00001),
      );
      expect(result['classificationLabel'], direct.binaryLabel);
      // Verify reuse, rather than testing only worker startup.
      final repeated =
          await worker.run({
                'path': photo.path,
                'highlighting': false,
                'threshold': .5,
              })
              as Map;
      expect(repeated['classificationLabel'], result['classificationLabel']);
    },
    skip: const bool.fromEnvironment('CROPWISE_NATIVE_MODEL_TEST')
        ? false
        : 'Opt-in native check: requires the platform TFLite runtime.',
  );
}
