import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/advisor_model_results_reader.dart';
import 'package:wormwise/models/da_assessment_results.dart';
import 'package:wormwise/models/sampled_infestation.dart';
import 'package:wormwise/services/cloud/expert_review_service.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import '../support/da_results_fixture.dart';

ModelDetectionBox box(int id) => ModelDetectionBox(
  sourcePath: 'test.jpg',
  classId: id,
  label: 'test',
  confidence: .9,
  left: 0,
  top: 0,
  right: 10,
  bottom: 10,
  imageWidth: 20,
  imageHeight: 20,
);
PlantDiagnosisResult model(
  List<int> ids, {
  String? stage = 'overlay_complete',
}) => PlantDiagnosisResult(
  isInfested: false,
  pestLabel: 'screen',
  confidenceScore: .9,
  classificationLabel: 'FAW damage',
  classifierStage: stage,
  detectionBoxes: ids.map(box).toList(),
);
ExpertPlantRating rating(int number, int score, String? freshness) =>
    ExpertPlantRating(
      stationNumber: number,
      plantNumber: 1,
      outcome: 'scored',
      davisScore: score,
      damageFreshness: freshness,
      note: '',
      photos: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'only detector frass or larvae count, never damage/eggs/species labels',
    () {
      for (final id in [1, 2]) {
        expect(modelSampledInfestation(model([id])), isTrue);
      }
      for (final id in [0, 3, 4, 5, 6]) {
        expect(modelSampledInfestation(model([id])), isFalse);
      }
      expect(modelSampledInfestation(model([], stage: 'overlay_off')), isNull);
      expect(modelSampledInfestation(null), isNull);
    },
  );
  test('immutable expert current damage determines infestation', () {
    expect(expertSampledInfestation(rating(1, 3, 'fresh')), isTrue);
    expect(expertSampledInfestation(rating(1, 3, 'old_only')), isFalse);
    expect(expertSampledInfestation(rating(1, 0, null)), isFalse);
    expect(expertSampledInfestation(rating(1, 3, 'uncertain')), isNull);
    expect(expertSampledInfestation(rating(1, 3, null)), isNull);
    expect(expertSampledInfestation(null), isNull);
  });
  test(
    'cloud summary deduplicates plants and excludes stale/skipped detectors',
    () {
      AdvisorModelSample sample(
        String station,
        PlantDiagnosisResult result, {
        String availability = 'available',
      }) => AdvisorModelSample(
        stationId: station,
        position: 1,
        images: const [],
        availability: availability,
        result: result,
      );
      final summary = AdvisorModelResults([
        sample('one', model([1, 2, 2])),
        sample('one', model([1, 2, 2])),
        sample('two', model([0, 3])),
        sample('three', model([2]), availability: 'stale'),
        sample('four', model([], stage: 'overlay_off')),
      ]).sampledInfestationSummary;
      expect(summary['sample_count'], 4);
      expect(summary['infested_count'], 1);
      expect(summary['not_infested_count'], 1);
      expect(summary['eligible_count'], 2);
      expect(summary['unavailable_count'], 2);
      expect(summary['percent'], 50);
      expect(
        AdvisorModelResults([
          sample('same', model([2])),
          sample('same', model([])),
        ]).sampledInfestationSummary['eligible_count'],
        0,
      );
    },
  );
  test(
    '20 sampled plants use detector counts and finalized findings supersede them',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final sample = DaSampleResults.fromDetail(
        await daResultsFixture(db, infestationDetections: true),
      );
      final provisional = DaSampledInfestation(sample);
      expect(provisional.infested, 4);
      expect(provisional.notInfested, 16);
      expect(provisional.percent, 20);
      expect(provisional.caseLabel, 'Infested');
      final rows = [
        for (var i = 1; i <= 20; i++)
          rating(i, i <= 4 ? 3 : 0, i <= 4 ? 'old_only' : null),
      ];
      final expert = DaExpertResults.fromRatings(
        sample: sample,
        summary: ExpertSeveritySummary(
          reviewedPlants: 20,
          scoredPlants: 20,
          insufficientPlants: 0,
          medianDavisScore: 0,
          finalizedAt: DateTime.utc(2026, 10, 7),
        ),
        ratings: rows,
      );
      final finalized = DaSampledInfestation(
        sample,
        finalized: true,
        expert: expert,
      );
      expect(finalized.infested, 0);
      expect(finalized.notInfested, 20);
      expect(finalized.caseLabel, 'Not infested');
      expect(finalized.source, 'Expert findings');
      final missing = DaSampledInfestation(sample, finalized: true);
      expect(missing.infested, 0);
      expect(missing.percent, isNull);
      expect(missing.unavailable, 20);
    },
  );
  test(
    'historical damage-only scores cannot establish sampled infestation',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final sample = DaSampleResults.fromDetail(await daResultsFixture(db));
      expect(sample.screeningPercent, 20);
      final infestation = DaSampledInfestation(sample);
      expect(infestation.percent, isNull);
      expect(infestation.caseLabel, 'Unavailable');
    },
  );
}
