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
      expect(clean.confidenceScore, 0.95);
      expect(clean.larvaVisible, false);
    });

    test(
      'fawInfested template creates positive diagnosis with correct signs',
      () {
        final faw = PlantDiagnosisResult.fawInfested(
          confidence: 0.94,
          larvaSeen: true,
          larvaSize: 'medium',
          frassSeen: true,
          whorlSeen: true,
        );

        expect(faw.isInfested, true);
        expect(faw.suggestedPlantStatus, DatabaseCodes.plantCurrentPositive);
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
      );
      final detector = TfliteFawDetector(simulatedResult: simulated);
      expect(detector.isModelLoaded, true);
      final result = await detector.analyzeImage(File('dummy.jpg'));
      expect(result.isInfested, true);
      expect(result.confidenceScore, 0.98);
    });

    test('PlantDiagnosisResult.merge fuses multi-image results correctly', () {
      final overview = PlantDiagnosisResult.cleanPlant;
      final closeUp = PlantDiagnosisResult.fawInfested(
        confidence: 0.93,
        larvaSeen: true,
        larvaSize: 'large',
        frassSeen: true,
        whorlSeen: true,
      );
      final detail = PlantDiagnosisResult.fawInfested(
        confidence: 0.96,
        larvaSeen: false,
        frassSeen: true,
      );

      final merged = PlantDiagnosisResult.merge([overview, closeUp, detail]);
      expect(merged.isInfested, true);
      expect(merged.confidenceScore, 0.96);
      expect(merged.larvaVisible, true);
      expect(merged.larvalSize, 'large');
      expect(merged.frass, true);
      expect(merged.whorlFeeding, true);
      expect(merged.suggestedPlantStatus, DatabaseCodes.plantCurrentPositive);
    });

    test('PlantDiagnosisResult.merge returns clean when all views clean', () {
      const img1 = PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'No Pest',
        confidenceScore: 0.92,
      );
      const img2 = PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'No Pest',
        confidenceScore: 0.97,
      );

      final merged = PlantDiagnosisResult.merge([img1, img2]);
      expect(merged.isInfested, false);
      expect(merged.confidenceScore, 0.97);
      expect(merged.suggestedPlantStatus, DatabaseCodes.plantNegative);
    });

    test('oldDamagePlant and nonFawPlant templates are correct', () {
      final oldDamage = PlantDiagnosisResult.oldDamagePlant();
      expect(oldDamage.isInfested, false);
      expect(oldDamage.suggestedPlantStatus, DatabaseCodes.plantOldDamageOnly);
      expect(oldDamage.detectedSigns, contains('old_feeding_scars'));

      final nonFaw = PlantDiagnosisResult.nonFawPlant();
      expect(nonFaw.isInfested, false);
      expect(nonFaw.suggestedPlantStatus, DatabaseCodes.plantPossibleNonFaw);
      expect(nonFaw.detectedSigns, contains('non_faw_damage'));
    });
  });
}
