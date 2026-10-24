import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/advisor_context_repository.dart';
import 'package:wormwise/models/automatic_screening.dart';
import 'package:wormwise/data/services/automatic_screening_save_service.dart';
import 'package:wormwise/providers/advisor_controller.dart';
import 'package:wormwise/services/advisor/advisor_open_chat_service.dart';
import 'package:wormwise/services/advisor/advisor_knowledge_service.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await _insertCompletedAssessment(database);
  });

  tearDown(() => database.close());

  test(
    'loads field progress and evidence while excluding legacy findings and metrics',
    () async {
      final snapshot = await AdvisorContextRepository(database).load(
        fieldId: 'field-1',
        cropCycleId: 'cycle-1',
        preferredAssessmentId: 'assessment-1',
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.fieldName, 'North Maize Field');
      expect(snapshot.areaHectares, 0.8);
      expect(snapshot.hasConfirmedOutline, isTrue);
      expect(snapshot.varietyName, 'Hybrid 123');
      expect(snapshot.hasSeparateModelFindingProvenance, isFalse);

      final assessment = snapshot.assessment!;
      expect(assessment.isCompleted, isTrue);
      expect(assessment.totalBlocks, 1);
      expect(assessment.completedBlocks, 1);
      expect(assessment.stationRecords, 1);
      expect(assessment.plantRecords, 3);
      expect(assessment.assessablePlants, 2);
      expect(
        assessment.findingSummary.containsKey('manual_current_infestation'),
        isFalse,
      );
      expect(
        (assessment.findingSummary['automatic_damage_screen']
            as Map)['missing_result_count'],
        3,
      );
      expect(assessment.evidencePhotoCount, 1);
      expect(assessment.metrics, isEmpty);
    },
  );

  test('returns no field context when no field is selected', () async {
    final snapshot = await AdvisorContextRepository(
      database,
    ).load(fieldId: null, cropCycleId: null);

    expect(snapshot, isNull);
  });

  test(
    'read tools exclude legacy metrics and reject cross-field assessment access',
    () async {
      final tools = AdvisorContextRepository(database);
      final catalog = await tools.read('list_fields', {});
      expect((catalog['fields'] as List).single['id'], 'field-1');
      final history = await tools.read('list_assessments', {
        'field_id': 'field-1',
      });
      expect((history['assessments'] as List).single['id'], 'assessment-1');
      final result = await tools.read('get_assessment', {
        'field_id': 'field-1',
      });
      expect(result['assessment_id'], 'assessment-1');
      expect(result.containsKey('metrics'), isFalse);
      expect(result.containsKey('observations'), isFalse);
      expect((result['evidence'] as Map)['evidence_photos'], 1);
      await database
          .into(database.fields)
          .insert(
            FieldsCompanion.insert(id: 'other-field', name: 'Other Field'),
          );
      final denied = await tools.read('get_assessment', {
        'field_id': 'other-field',
        'assessment_id': 'assessment-1',
      });
      expect(denied['assessment'], isNull);
    },
  );

  test(
    'overview and station details recover actual cached Model 1 results',
    () async {
      await _cache(database, position: 1, checksum: 'test-checksum');
      await (database.update(
        database.plantObservations,
      )..where((p) => p.id.equals('plant-2'))).write(
        PlantObservationsCompanion(
          wholePlantContextNote: Value(
            AutomaticScreening(_result(false)).encode(),
          ),
        ),
      );
      final tools = AdvisorContextRepository(database);
      final assessment = await tools.read('get_assessment', {
        'field_id': 'field-1',
      });
      final screen =
          (assessment['finding_summary'] as Map)['automatic_damage_screen']
              as Map;
      expect(screen['positive_count'], 1);
      expect(screen['eligible_count'], 2);
      expect(screen['percent'], 50);
      final samples = await tools.read('get_assessment_samples', {
        'field_id': 'field-1',
      });
      final station = (samples['stations'] as List).single as Map;
      expect((station['damage_screen'] as Map)['eligible_count'], 2);
      expect(station.containsKey('current_positive_rate'), isFalse);
      final plant = (samples['plants'] as List).first as Map;
      expect(plant['model_result_source'], 'evidence_matched_model_cache');
      expect(
        (plant['model_result'] as Map)['classificationLabel'],
        'FAW damage',
      );
      for (final key in [
        'old_damage',
        'possible_non_faw',
        'uncertain',
        'vegetative',
        'reproductive',
        'ears',
        'current_faw_evidence',
      ]) {
        expect(plant.containsKey(key), isFalse);
      }
    },
  );

  test(
    'stale cache is not counted and missing output is not a zero rate',
    () async {
      await _cache(database, position: 1, checksum: 'replaced-photo');
      final tools = AdvisorContextRepository(database);
      final assessment = await tools.read('get_assessment', {
        'field_id': 'field-1',
      });
      final screen =
          (assessment['finding_summary'] as Map)['automatic_damage_screen']
              as Map;
      expect(screen['eligible_count'], 0);
      expect(screen['stale_result_count'], 1);
      expect(screen['percent'], isNull);
      expect(screen['availability'], 'results_unavailable');
    },
  );

  test(
    'ongoing sample with only captured evidence and a cache is included',
    () async {
      await database
          .into(database.evidenceCaptureSessions)
          .insert(
            EvidenceCaptureSessionsCompanion.insert(
              id: 'capture-4',
              assessmentId: 'assessment-1',
              stationId: 'station-1',
              scopeType: 'plant',
              scopeKey: 'plant_4',
              plantPosition: const Value(4),
            ),
          );
      await database
          .into(database.evidenceMedia)
          .insert(
            EvidenceMediaCompanion.insert(
              id: 'media-4',
              assessmentId: 'assessment-1',
              stationId: const Value('station-1'),
              captureSessionId: const Value('capture-4'),
              mediaType: 'image',
              localUri: 'evidence/4.jpg',
              sha256Checksum: 'checksum-4',
              storageState: const Value(DatabaseCodes.evidenceStorageReady),
            ),
          );
      await _cache(database, position: 4, checksum: 'checksum-4');
      final samples = await AdvisorContextRepository(
        database,
      ).read('get_assessment_samples', {'field_id': 'field-1'});
      final plant = (samples['plants'] as List).last as Map;
      expect(plant['sequence'], 4);
      expect(plant['plant_observation_id'], isNull);
      expect(
        (plant['model_result'] as Map)['classificationLabel'],
        'FAW damage',
      );
      expect(
        ((samples['finding_summary'] as Map)['automatic_damage_screen']
            as Map)['eligible_count'],
        1,
      );
    },
  );

  test('rerunning a model persists output onto a legacy observation', () async {
    await AutomaticScreeningSaveService(database).save(
      stationId: 'station-1',
      position: 1,
      growthStage: 'v3_v6',
      screening: AutomaticScreening(
        _result(true),
        evidenceSignature: 'test-checksum',
      ),
      actorId: 'person-1',
      primaryView: 'leaf',
    );
    final plant = await (database.select(
      database.plantObservations,
    )..where((p) => p.id.equals('plant-1'))).getSingle();
    expect(
      AutomaticScreening.parse(plant.wholePlantContextNote)?.evidenceSignature,
      'test-checksum',
    );
    final assessment = await AdvisorContextRepository(
      database,
    ).read('get_assessment', {'field_id': 'field-1'});
    expect(
      ((assessment['finding_summary'] as Map)['automatic_damage_screen']
          as Map)['positive_count'],
      1,
    );
    await AutomaticScreeningSaveService(database).save(
      stationId: 'station-1',
      position: 1,
      growthStage: 'v3_v6',
      screening: AutomaticScreening(
        _result(false),
        evidenceSignature: 'test-checksum',
      ),
      actorId: 'person-1',
      primaryView: 'leaf',
    );
    final updated = await (database.select(
      database.plantObservations,
    )..where((p) => p.id.equals('plant-1'))).getSingle();
    expect(updated.plantStatus, plant.plantStatus);
    expect(updated.capturedAt, plant.capturedAt);
    expect(
      AutomaticScreening.parse(updated.wholePlantContextNote)?.positive,
      isFalse,
    );
  });

  test(
    'each question refreshes cached field context after new model output',
    () async {
      final tools = AdvisorContextRepository(database);
      final service = _CaptureChat();
      final controller = AdvisorController(
        openChatService: service,
        contextRepository: tools,
      );
      addTearDown(controller.dispose);
      await controller.loadContext(
        fieldId: 'field-1',
        cropCycleId: 'cycle-1',
        preferredAssessmentId: 'assessment-1',
      );
      await _cache(database, position: 1, checksum: 'test-checksum');
      await controller.ask('Explain my latest assessment results');
      final records = service.request!.fieldContext!.records!;
      final screen =
          ((records['assessment'] as Map)['finding_summary']
                  as Map)['automatic_damage_screen']
              as Map;
      expect(screen['eligible_count'], 1);
      expect(screen['positive_count'], 1);
      expect(
        (records['assessment'] as Map).containsKey('current_positive'),
        isFalse,
      );
    },
  );
}

PlantDiagnosisResult _result(bool positive) => PlantDiagnosisResult(
  isInfested: false,
  pestLabel: 'Damage screening',
  confidenceScore: .9,
  modelName:
      'WormWise-AutoScreen-v1:WormWise-YOLO11n-Cls-320-float32:overlay=false',
  classificationLabel: positive ? 'FAW damage' : 'No FAW damage',
  classificationProbabilities: {
    'FAW damage': positive ? .9 : .1,
    'No FAW damage': positive ? .1 : .9,
  },
);

Future<void> _cache(
  AppDatabase database, {
  required int position,
  required String checksum,
}) async {
  final result = _result(true);
  await database
      .into(database.appPreferences)
      .insertOnConflictUpdate(
        AppPreferencesCompanion.insert(
          preferenceKey: 'plant_model_station-1_$position',
          preferenceValue: jsonEncode({
            'signature': checksum,
            'pipelineVersion': result.modelName,
            'result': result.toJson(),
          }),
        ),
      );
}

class _CaptureChat implements AdvisorOpenChatService {
  AdvisorOpenChatRequest? request;
  @override
  Future<AdvisorAnswer> answer(AdvisorOpenChatRequest request) async {
    this.request = request;
    return const AdvisorAnswer(
      topicId: 'gemini_open_chat',
      title: '',
      summary: 'Recorded findings',
      details: [],
      source: AdvisorKnowledgeSource(
        label: 'Local fixture',
        reference: 'Fixture',
        version: '1',
      ),
    );
  }
}

Future<void> _insertCompletedAssessment(AppDatabase database) async {
  final now = DateTime.utc(2026, 9, 3, 8);
  await database
      .into(database.fields)
      .insert(
        FieldsCompanion.insert(
          id: 'field-1',
          name: 'North Maize Field',
          barangay: const Value('Aquib'),
          activeBoundaryVersionId: const Value('boundary-1'),
        ),
      );
  await database
      .into(database.fieldBoundaryVersions)
      .insert(
        FieldBoundaryVersionsCompanion.insert(
          id: 'boundary-1',
          fieldId: 'field-1',
          versionNumber: 1,
          geometryGeojson:
              '{"type":"Polygon","coordinates":[[[121,17],[121.01,17],[121,17.01],[121,17]]]}',
          sourceMethod: 'map_drawn',
          areaHectares: 0.8,
          confirmationStatus: const Value('user_confirmed'),
        ),
      );
  await database
      .into(database.cropCycles)
      .insert(
        CropCyclesCompanion.insert(
          id: 'cycle-1',
          fieldId: 'field-1',
          varietyName: const Value('Hybrid 123'),
          plantingDate: Value(DateTime.utc(2026, 8, 1)),
        ),
      );
  await database
      .into(database.people)
      .insert(PeopleCompanion.insert(id: 'person-1', displayName: 'Evaluator'));
  await database
      .into(database.assessments)
      .insert(
        AssessmentsCompanion.insert(
          id: 'assessment-1',
          cropCycleId: 'cycle-1',
          boundaryVersionId: 'boundary-1',
          evaluatorPersonId: 'person-1',
          assessmentMode: DatabaseCodes.modeVeV6,
          scoutingPattern: 'w_pattern',
          growthStage: 'v3_v6',
          protocolVersion: 'protocol-test-v1',
          formulaVersion: 'formula-test-v1',
          status: const Value(DatabaseCodes.completed),
          startedAt: Value(now),
          completedAt: Value(now.add(const Duration(hours: 1))),
          weatherContext: const Value('No recent heavy rain reported.'),
        ),
      );
  await database
      .into(database.fieldBlocks)
      .insert(
        FieldBlocksCompanion.insert(
          id: 'block-1',
          cropCycleId: 'cycle-1',
          boundaryVersionId: 'boundary-1',
          blockNumber: 1,
          geometryGeojson:
              '{"type":"Polygon","coordinates":[[[121,17],[121.01,17],[121,17.01],[121,17]]]}',
          areaHectares: 0.8,
        ),
      );
  await database
      .into(database.assessmentBlockRuns)
      .insert(
        AssessmentBlockRunsCompanion.insert(
          id: 'run-1',
          assessmentId: 'assessment-1',
          fieldBlockId: 'block-1',
          blockSequence: 1,
          scoutingPattern: 'w_pattern',
          status: const Value(DatabaseCodes.completed),
        ),
      );
  await database
      .into(database.stations)
      .insert(
        StationsCompanion.insert(
          id: 'station-1',
          assessmentBlockRunId: 'run-1',
          stationNumber: 1,
        ),
      );
  await database
      .into(database.plantObservations)
      .insert(
        PlantObservationsCompanion.insert(
          id: 'plant-1',
          stationId: 'station-1',
          sequenceNumber: 1,
          plantStatus: DatabaseCodes.plantCurrentPositive,
          naturalEnemyQuickStatus: 'none_seen',
        ),
      );
  await database
      .into(database.plantObservations)
      .insert(
        PlantObservationsCompanion.insert(
          id: 'plant-2',
          stationId: 'station-1',
          sequenceNumber: 2,
          plantStatus: DatabaseCodes.plantOldDamageOnly,
          oldDamagePresent: const Value(true),
          uncertainEvidence: const Value(true),
          naturalEnemyQuickStatus: 'none_seen',
        ),
      );
  await database
      .into(database.plantObservations)
      .insert(
        PlantObservationsCompanion.insert(
          id: 'plant-3',
          stationId: 'station-1',
          sequenceNumber: 3,
          assessable: const Value(false),
          plantStatus: DatabaseCodes.plantNegative,
          naturalEnemyQuickStatus: 'none_seen',
        ),
      );
  await database
      .into(database.evidenceMedia)
      .insert(
        EvidenceMediaCompanion.insert(
          id: 'media-1',
          assessmentId: 'assessment-1',
          stationId: const Value('station-1'),
          plantObservationId: const Value('plant-1'),
          mediaType: 'image',
          localUri: 'evidence/photo.jpg',
          sha256Checksum: 'test-checksum',
          storageState: const Value(DatabaseCodes.evidenceStorageReady),
        ),
      );
  await database
      .into(database.evidenceMedia)
      .insert(
        EvidenceMediaCompanion.insert(
          id: 'media-staged',
          assessmentId: 'assessment-1',
          stationId: const Value('station-1'),
          plantObservationId: const Value('plant-1'),
          mediaType: 'image',
          localUri: 'staging/incomplete-photo.jpg',
          sha256Checksum: 'staged-test-checksum',
          storageState: const Value(DatabaseCodes.evidenceStorageStaged),
        ),
      );
  await database
      .into(database.metricResults)
      .insert(
        MetricResultsCompanion.insert(
          id: 'metric-1',
          assessmentId: 'assessment-1',
          scopeType: 'block',
          scopeId: const Value('run-1'),
          metricCode: DatabaseCodes.vegetativeCurrentInfestationPercent,
          numerator: const Value(1),
          denominator: const Value(2),
          value: const Value(50),
          unit: 'percent',
          formulaVersion: 'formula-test-v1',
          validationStatus: const Value('provisional'),
          calculatedAt: now.add(const Duration(hours: 1)),
        ),
      );
}
