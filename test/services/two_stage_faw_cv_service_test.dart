import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import 'package:wormwise/services/computer_vision/maize_leaf_classifier.dart';
import 'package:wormwise/services/computer_vision/tflite_faw_detector.dart';
import 'package:wormwise/services/computer_vision/two_stage_faw_cv_service.dart';

void main() {
  group('FAW-only two-stage pipeline', () {
    test('non-existent file returns clean fallback', () async {
      final result = await TwoStageFawCvService().analyzeImage(
        File('non_existent.jpg'),
      );
      expect(result.isInfested, false);
      expect(result.suggestedPlantStatus, DatabaseCodes.plantNegative);
    });

    test('Stage 1 no-FAW result stops before Model 2', () async {
      final classifier = MaizeLeafClassifier(
        simulatedResult: const MaizeClassificationResult(
          topClass: 'no_faw_damage',
          topConfidence: .88,
          probabilities: {'faw_damage': .12, 'no_faw_damage': .88},
        ),
      );
      final detector = TfliteFawDetector(
        simulatedResult: PlantDiagnosisResult.fawInfested(confidence: .99),
      );

      final result = await TwoStageFawCvService(
        classifier: classifier,
        detector: detector,
      ).analyzeImage(File('dummy.jpg'));

      expect(result.isInfested, false);
      expect(result.classificationLabel, 'No FAW damage');
      expect(result.classificationProbabilities.keys, {
        'FAW damage',
        'No FAW damage',
      });
      expect(result.classifierStage, contains('Stage 2 not run'));
    });

    test('binary negative output is treated as no-FAW damage', () async {
      final classifier = MaizeLeafClassifier(
        simulatedResult: const MaizeClassificationResult(
          topClass: 'no_faw_damage',
          topConfidence: .91,
          probabilities: {'faw_damage': .09, 'no_faw_damage': .91},
        ),
      );

      final result = await TwoStageFawCvService(
        classifier: classifier,
      ).analyzeImage(File('dummy.jpg'));

      expect(result.pestLabel, 'No FAW damage detected');
      expect(result.classificationLabel, 'No FAW damage');
      expect(result.toJson().toString(), isNot(contains('Blight')));
      expect(result.toJson().toString(), isNot(contains('MLB')));
    });

    test('Stage 1 FAW damage calls Model 2 and confirms evidence', () async {
      final classifier = MaizeLeafClassifier(
        simulatedResult: const MaizeClassificationResult(
          topClass: 'faw_damage',
          topConfidence: .87,
          probabilities: {'faw_damage': .87, 'no_faw_damage': .13},
        ),
      );
      final detector = TfliteFawDetector(
        simulatedResult: PlantDiagnosisResult(
          isInfested: true,
          pestLabel: 'Fall Armyworm',
          confidenceScore: .94,
          suggestedPlantStatus: DatabaseCodes.plantCurrentPositive,
          detectedSigns: const ['larva', 'fresh_frass'],
          larvaVisible: true,
          frass: true,
          detectionBoxes: const [
            ModelDetectionBox(
              sourcePath: 'dummy.jpg',
              classId: 2,
              label: 'fall-armyworm-larva',
              confidence: .94,
              left: .2,
              top: .3,
              right: .4,
              bottom: .5,
              imageWidth: 960,
              imageHeight: 960,
            ),
          ],
        ),
      );

      final result = await TwoStageFawCvService(
        classifier: classifier,
        detector: detector,
      ).analyzeImage(File('dummy.jpg'));

      expect(result.isInfested, true);
      expect(result.classificationLabel, 'FAW damage');
      expect(result.detectionBoxes, hasLength(1));
      expect(result.classifierStage, contains('Stage 2 evidence confirmed'));
    });

    test(
      'Stage 2 non-confirmation stays uncertain, not confirmed FAW',
      () async {
        final classifier = MaizeLeafClassifier(
          simulatedResult: const MaizeClassificationResult(
            topClass: 'faw_damage',
            topConfidence: .82,
            probabilities: {'faw_damage': .82, 'no_faw_damage': .18},
          ),
        );
        final detector = TfliteFawDetector(
          simulatedResult: PlantDiagnosisResult.cleanPlant,
        );

        final result = await TwoStageFawCvService(
          classifier: classifier,
          detector: detector,
        ).analyzeImage(File('dummy.jpg'));

        expect(result.isInfested, false);
        expect(result.suggestedPlantStatus, DatabaseCodes.plantOldDamageOnly);
        expect(result.pestLabel, 'FAW-like damage not confirmed');
      },
    );

    test('Stage 1 failure does not bypass the gate to Model 2', () async {
      final detector = TfliteFawDetector(
        simulatedResult: PlantDiagnosisResult.fawInfested(confidence: .99),
      );
      final result = await TwoStageFawCvService(
        classifier: _ThrowingClassifier(),
        detector: detector,
      ).analyzeImage(File('dummy.jpg'));

      expect(result.isInfested, false);
      expect(result.suggestedPlantStatus, DatabaseCodes.plantUncertain);
      expect(result.classifierStage, contains('Stage 2 not run'));
    });
  });
}

class _ThrowingClassifier extends MaizeLeafClassifier {
  @override
  Future<MaizeClassificationResult> classifyImage(File imageFile) async {
    throw StateError('screen unavailable');
  }
}
