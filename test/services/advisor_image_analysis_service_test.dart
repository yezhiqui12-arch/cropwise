import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/services/advisor/advisor_image_analysis_service.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';

void main() {
  test(
    'turns on-device detections into a guarded sourced explanation',
    () async {
      final service = AdvisorImageAnalysisService(_FakeImageModel());

      final result = await service.analyze(File('test-maize.jpg'));
      final answer = result.answer;

      expect(answer.topicId, 'on_device_image_analysis');
      expect(answer.summary, contains('visual suggestion'));
      expect(answer.summary, contains('not a confirmed diagnosis'));
      expect(answer.source.label, contains('on-device'));
      expect(answer.details.join(' '), contains('No field observation'));
      expect(result.imagePath, 'test-maize.jpg');
      expect(result.detectionBoxes, hasLength(1));
    },
  );
}

class _FakeImageModel implements FawComputerVisionService {
  @override
  bool get isModelLoaded => true;

  @override
  String get modelIdentifier => 'fake-model-v1';

  @override
  Future<PlantDiagnosisResult> analyzeImage(File imageFile) async {
    return const PlantDiagnosisResult(
      isInfested: true,
      pestLabel: 'FAW-like visual evidence',
      confidenceScore: 0.82,
      suggestedPlantStatus: DatabaseCodes.plantCurrentPositive,
      detectedSigns: ['larval_damage'],
      modelName: 'fake-model-v1',
      detectionBoxes: [
        ModelDetectionBox(
          sourcePath: 'test-maize.jpg',
          classId: 0,
          label: 'damage',
          confidence: 0.82,
          left: 0,
          top: 0,
          right: 10,
          bottom: 10,
          imageWidth: 100,
          imageHeight: 100,
        ),
      ],
    );
  }
}
