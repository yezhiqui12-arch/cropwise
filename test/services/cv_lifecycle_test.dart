import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/models/automatic_screening.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import 'package:wormwise/services/computer_vision/maize_leaf_classifier.dart';
import 'package:wormwise/services/computer_vision/tflite_faw_detector.dart';
import 'package:wormwise/services/computer_vision/two_stage_faw_cv_service.dart';

class _DelayedClassifier extends MaizeLeafClassifier {
  final started = Completer<void>();
  final finish = Completer<MaizeClassificationResult>();
  int closes = 0;
  @override
  Future<MaizeClassificationResult> classifyImage(File file) {
    started.complete();
    return finish.future;
  }

  @override
  void close() => closes++;
}

void main() {
  test(
    'close waits for active work and does not close injected models',
    () async {
      final classifier = _DelayedClassifier();
      final detector = TfliteFawDetector(simulatedResult: null);
      final pipeline = TwoStageFawCvService(
        classifier: classifier,
        detector: detector,
        loadPreferences: false,
      );
      final root = await Directory.systemTemp.createTemp('wormwise-lifecycle-');
      addTearDown(() => root.delete(recursive: true));
      final file = await File('${root.path}/photo').writeAsString('model stub');
      final operation = pipeline.analyzeImage(file);
      await classifier.started.future;
      await expectLater(pipeline.analyzeImage(file), throwsStateError);
      var closed = false;
      final closing = pipeline.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      await expectLater(pipeline.analyzeImage(file), throwsStateError);
      classifier.finish.complete(
        const MaizeClassificationResult(
          topClass: 'no_faw_damage',
          topConfidence: .9,
          probabilities: {'faw_damage': .1, 'no_faw_damage': .9},
        ),
      );
      expect(
        (await operation).suggestedPlantStatus,
        AutomaticScreening.negativeStatus,
      );
      await closing;
      await pipeline.close();
      expect(classifier.closes, 0);
      expect(pipeline.isModelLoaded, isFalse);
    },
  );

  test('missing detector input is an error, never a clean result', () async {
    await expectLater(
      TfliteFawDetector().analyzeImage(File('missing-photo')),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('unknown classifications cannot become available negative screens', () {
    // The domain must recognize the two supported binary labels explicitly.
    final screen = AutomaticScreening(
      const PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'unknown',
        confidenceScore: 0,
        classificationLabel: 'Unsupported',
      ),
    );
    expect(screen.available, isFalse);
    expect(screen.status, AutomaticScreening.unavailableStatus);
  });
}
