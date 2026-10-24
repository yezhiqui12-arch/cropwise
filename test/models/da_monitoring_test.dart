import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/da_monitoring_repository.dart';
import 'package:wormwise/models/da_monitoring.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';

PlantDiagnosisResult daTestModel({
  String? stage = 'overlay_complete',
  String? label = 'FAW damage',
  List<int> boxes = const [2, 3],
}) => PlantDiagnosisResult(
  isInfested: false,
  pestLabel: 'Test model',
  confidenceScore: .92,
  classificationLabel: label,
  classifierStage: stage,
  detectionBoxes: [
    for (final id in boxes)
      ModelDetectionBox(
        sourcePath: 'sample.jpg',
        classId: id,
        label: 'Test',
        confidence: .9,
        left: 0,
        top: 0,
        right: 1,
        bottom: 1,
        imageWidth: 10,
        imageHeight: 10,
      ),
  ],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('egg and larva boxes check one presence flag; pupa is not inferred', () {
    final finding = DaPlantFinding.fromModel(daTestModel(boxes: [2, 2, 3, 3]));
    expect(finding.values, {
      'egg': true,
      'larva': true,
      'pupa': null,
      'damage': true,
    });
    expect(
      DaPlantFinding.fromModel(daTestModel(boxes: [])).values['egg'],
      false,
    );
  });
  test(
    'skipped, failed and missing detection never becomes no eggs/larvae',
    () {
      for (final stage in [
        'overlay_off',
        'overlay_unavailable',
        'Stage 1 (No FAW damage — Stage 2 not run)',
      ]) {
        final finding = DaPlantFinding.fromModel(
          daTestModel(stage: stage, label: 'No FAW damage', boxes: []),
        );
        expect(finding.values['damage'], false);
        expect(finding.values['egg'], null);
        expect(finding.values['larva'], null);
      }
      expect(
        DaPlantFinding.fromModel(null).values.values.every((v) => v == null),
        true,
      );
    },
  );
  test('rain uses the saved 48-hour interval and the actual yes/no fallback', () {
    final rain = DaReportRain.fromContext(
      'open_meteo_precipitation_last_48h_mm=4.25;weather_period_end_utc=2026-10-07T00:00:00Z',
    );
    expect(rain.rained, true);
    expect(rain.millimeters, 4.25);
    expect(rain.periodEnd, DateTime.utc(2026, 10, 7));
    expect(
      DaReportRain.fromContext('open_meteo_precipitation_last_48h_mm=0').rained,
      false,
    );
    expect(
      DaReportRain.fromContext('rain_wet_field_last_48h=yes').rained,
      true,
    );
    expect(
      DaReportRain.fromContext('rain_wet_field_last_48h=no').rained,
      false,
    );
    expect(
      DaReportRain.fromContext('rain_wet_field_last_48h=not_sure').rained,
      null,
    );
    expect(DaReportRain.fromContext(null).rained, null);
    expect(
      DaReportRain.fromContext(
        'open_meteo_precipitation_last_48h_mm=-1',
      ).rained,
      null,
    );
  });
  test(
    'corrections persist per block, reset and ignore changed photo evidence',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DaMonitoringRepository(db);
      await repository.saveCorrection('a', 'block1', 7, 'photos1', {
        'damage': false,
        'egg': false,
      });
      await repository.saveCorrection('a', 'block2', 7, 'photos2', {
        'damage': true,
        'larva': false,
      });
      final saved = await repository.load('a');
      final original = DaPlantFinding.fromModel(daTestModel());
      expect(
        original
            .withCorrections(saved.plant('block1', 7), 'photos1')
            .values['damage'],
        false,
      );
      expect(
        original
            .withCorrections(saved.plant('block2', 7), 'photos2')
            .values['damage'],
        true,
      );
      expect(
        original
            .withCorrections(saved.plant('block1', 7), 'different-photo')
            .corrected,
        isEmpty,
      );
      expect(original.values['damage'], true);
      await repository.saveCorrection('a', 'block1', 7, 'photos1', {});
      expect((await repository.load('a')).plant('block1', 7), null);
      expect((await repository.load('a')).plant('block2', 7), isNotNull);
      expect(
        await repository
            .load('another-assessment')
            .then((r) => r.plant('block2', 7)),
        null,
      );
    },
  );
  test(
    'natural enemies are persisted once per block without contradictory choices',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DaMonitoringRepository(db);
      await repository.saveEnemies('a', 'block1', ['predators', 'parasitoids']);
      await repository.saveEnemies('a', 'block2', ['not_recorded']);
      final loaded = await repository.load('a');
      expect(loaded.enemies('block1'), ['predators', 'parasitoids']);
      expect(loaded.enemies('block2'), ['not_recorded']);
      expect(
        () => repository.saveEnemies('a', 'block1', ['none', 'predators']),
        throwsArgumentError,
      );
      await repository.saveProfile('cycle1', {
        'farmer': 'Farmer',
        'week': 3,
        'remarks': 'This visit',
        'collector': 'Collector',
      });
      expect(await repository.loadProfile('cycle1'), {'farmer': 'Farmer'});
    },
  );
}
