import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import 'package:wormwise/services/computer_vision/tflite_faw_detector.dart';

void main() {
  group('Computer Vision Service & Models', () {
    test('cleanPlant default properties are correct', () {
      const clean = PlantDiagnosisResult.cleanPlant;
      expect(clean.isInfested, false);
      expect(clean.suggestedPlantStatus, DatabaseCodes.plantNegative);
      expect(clean.davisDamageGrade, 1);
      expect(clean.confidenceScore, 0.95);
      expect(clean.larvaVisible, false);
    });

    test(
      'fawInfested template creates positive diagnosis with correct signs',
      () {
        final faw = PlantDiagnosisResult.fawInfested(
          confidence: 0.94,
          davisGrade: 4,
          larvaSeen: true,
          larvaSize: 'medium',
          frassSeen: true,
          whorlSeen: true,
        );

        expect(faw.isInfested, true);
        expect(faw.suggestedPlantStatus, DatabaseCodes.plantCurrentPositive);
        expect(faw.davisDamageGrade, 4);
        expect(faw.confidenceScore, 0.94);
        expect(faw.larvaVisible, true);
        expect(faw.larvalSize, 'medium');
        expect(faw.frass, true);
        expect(faw.whorlFeeding, true);
        expect(faw.detectedSigns, contains('whorl_feeding'));
        expect(faw.detectedSigns, contains('fresh_frass'));
        expect(faw.detectedSigns, contains('larva'));
      },
    );

    test(
      'TfliteFawDetector returns clean fallback on non-existent file',
      () async {
        final detector = TfliteFawDetector();
        final result = await detector.analyzeImage(File('non_existent.jpg'));
        expect(result.isInfested, false);
        expect(result.suggestedPlantStatus, DatabaseCodes.plantNegative);
      },
    );

    test('TfliteFawDetector returns simulated result when provided', () async {
      final simulated = PlantDiagnosisResult.fawInfested(
        confidence: 0.98,
        davisGrade: 5,
      );
      final detector = TfliteFawDetector(simulatedResult: simulated);
      expect(detector.isModelLoaded, true);
      final result = await detector.analyzeImage(File('dummy.jpg'));
      expect(result.isInfested, true);
      expect(result.davisDamageGrade, 5);
      expect(result.confidenceScore, 0.98);
    });
  });
}
