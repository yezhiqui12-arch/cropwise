import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:wormwise/data/services/atomic_plant_save_service.dart';
import 'package:wormwise/data/services/atomic_ve_v2_save_service.dart';

const _polygon =
    '{"type":"Polygon","coordinates":[[[121.0,17.0],[121.01,17.0],'
    '[121.01,17.01],[121.0,17.01],[121.0,17.0]]]}';

void main() {
  test(
    'schema v4 migrates VE-V2 fields through v7 without rewriting records',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute(_v4PlantingUnitsSql);
            raw.execute(_v4PlantsSql);
            raw.execute(_v4EvidenceCaptureSessionsSql);
            raw.execute("""
            INSERT INTO planting_unit_observations (
              id, station_id, sequence_number, occupancy_status,
              observed_seedling_count
            ) VALUES ('legacy-unit', 'legacy-station', 1, 'occupied', 2)
          """);
            raw.execute("""
            INSERT INTO evidence_capture_sessions (
              id, assessment_id, station_id, scope_type, scope_key,
              requirements_version, collection_mode, collection_status
            ) VALUES (
              'legacy-session', 'legacy-assessment', 'legacy-station',
              'plant', 'plant_01', 'camera_phase_a_v1', 'camera', 'complete'
            )
          """);
            raw.execute("""
            INSERT INTO plant_observations (
              id, station_id, sequence_number, plant_status,
              natural_enemy_quick_status
            ) VALUES ('legacy-plant', 'legacy-station', 1, 'negative', 'none_seen')
          """);
            raw.userVersion = 4;
          },
        ),
      );

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      final unit = await database
          .select(database.plantingUnitObservations)
          .getSingle();
      final plant = await database
          .select(database.plantObservations)
          .getSingle();

      expect(version.read<int>('user_version'), 7);
      expect(unit.observedSeedlingCount, 2);
      expect(unit.primaryCondition, isNull);
      expect(unit.alternativeCauseCodesJson, isNull);
      expect(plant.sourcePlantingUnitObservationId, isNull);
      final legacySession = await (database.select(
        database.evidenceCaptureSessions,
      )..where((row) => row.id.equals('legacy-session'))).getSingle();
      expect(legacySession.sourcePlantingUnitObservationId, isNull);
      expect(
        await database.select(database.veV2StationInspections).get(),
        isEmpty,
      );
      await database.close();
    },
  );

  group('VE-V2 atomic persistence', () {
    late AppDatabase database;
    late _Fixture fixture;
    late AtomicVeV2SaveService units;
    late AtomicPlantSaveService plants;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      fixture = await _fixture(database);
      units = AtomicVeV2SaveService(database);
      plants = AtomicPlantSaveService(database);
    });

    tearDown(() => database.close());

    test(
      'keeps planting-unit and living-plant denominators separate with an explicit link',
      () async {
        await units.saveStationSetup(
          VeV2StationSetupInput(
            stationId: fixture.station.id,
            growthStage: 've',
            rowDirectionCode: 'forward_from_station',
            plantingUnitSequenceAssessable: true,
            stationContextMeetsRowPurpose: true,
            emergenceContinuing: true,
            actorPersonId: fixture.actorId,
          ),
        );
        final unit = await units.savePlantingUnit(
          _healthyUnit(fixture, 1, seedlings: 2),
        );
        final plant = await plants.saveVegetativePlant(
          _livingPlant(fixture, 1, unit.id),
        );

        expect(
          await database.select(database.plantingUnitObservations).get(),
          hasLength(1),
        );
        expect(
          await database.select(database.plantObservations).get(),
          hasLength(1),
        );
        expect(plant.plant.sourcePlantingUnitObservationId, unit.id);
        expect(unit.observedSeedlingCount, 2);
      },
    );

    test(
      'rolls back raw unit and audit when required evidence association fails',
      () async {
        await expectLater(
          units.savePlantingUnit(
            VeV2PlantingUnitSave(
              stationId: fixture.station.id,
              sequenceNumber: 1,
              assessable: true,
              primaryCondition: DatabaseCodes.veUnitCutSevered,
              observedSeedlingCount: 0,
              recognizableRemnantPresent: true,
              visibleCutting: true,
              visibleSevering: true,
              visibleSeedlingInjury: true,
              injuryLocation: 'at_soil',
              injuryFreshness: 'fresh',
              larvaVisible: false,
              larvalSize: null,
              freshFrass: false,
              rotPresent: false,
              tunnelingPresent: false,
              discolorationPresent: false,
              otherNonFawEvidence: false,
              evaluatorPrimaryInterpretation:
                  DatabaseCodes.veInterpretationOtherPest,
              evaluatorConfidence: 'moderate',
              alternativeCauseCodes: const {'common_cutworm'},
              inspectionDurationMs: 1200,
              actorPersonId: fixture.actorId,
              evidenceCaptureSessionId: 'missing-session',
              requiredEvidenceViewTypes: const {
                DatabaseCodes.evidenceViewWholeSeedling,
                DatabaseCodes.evidenceViewStemBase,
                DatabaseCodes.evidenceViewCloseUp,
              },
            ),
          ),
          throwsA(anything),
        );
        expect(
          await database.select(database.plantingUnitObservations).get(),
          isEmpty,
        );
        expect(
          await (database.select(database.auditLogs)..where(
                (row) => row.entityType.equals('planting_unit_observations'),
              ))
              .get(),
          isEmpty,
        );
      },
    );

    test('rejects cross-station physical-seedling links atomically', () async {
      final unit = await units.savePlantingUnit(_healthyUnit(fixture, 1));
      final second = await ScoutingWorkflowRepository(database)
          .saveStationLocation(
            prepared: fixture.prepared,
            stationNumber: 2,
            actorPersonId: fixture.actorId,
            notLocatedReason: DatabaseCodes.stationNoCurrentFix,
          );
      await expectLater(
        plants.saveVegetativePlant(
          _livingPlant(
            _Fixture(second, fixture.prepared, fixture.actorId),
            1,
            unit.id,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        await (database.select(
          database.plantObservations,
        )..where((row) => row.stationId.equals(second.id))).get(),
        isEmpty,
      );
    });

    test('accepts VE-V2 view-specific documented fallbacks', () async {
      final evidence = EvidenceCaptureRepository(database);
      final unitSession = await evidence.ensurePlantingUnitSession(
        assessmentId: fixture.prepared.run.assessmentId,
        stationId: fixture.station.id,
        sequenceNumber: 1,
        actorPersonId: fixture.actorId,
      );
      await evidence.waiveRequiredView(
        session: unitSession,
        viewType: DatabaseCodes.evidenceViewWholeSeedling,
        reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
        actorPersonId: fixture.actorId,
      );
      final rowSession = await evidence.ensureVeRowContextSession(
        assessmentId: fixture.prepared.run.assessmentId,
        stationId: fixture.station.id,
        actorPersonId: fixture.actorId,
      );
      await evidence.waiveRequiredView(
        session: rowSession,
        viewType: DatabaseCodes.evidenceViewVeRowContext,
        reasonCode: DatabaseCodes.evidenceFallbackUnsafe,
        actorPersonId: fixture.actorId,
      );

      expect(
        (await evidence.loadBundle(
          unitSession.id,
        )).isViewSatisfied(DatabaseCodes.evidenceViewWholeSeedling),
        isTrue,
      );
      expect(
        (await evidence.loadBundle(
          rowSession.id,
        )).isViewSatisfied(DatabaseCodes.evidenceViewVeRowContext),
        isTrue,
      );
    });

    test(
      'occupied routing avoids duplicate photos and living evidence keeps its physical-unit link',
      () async {
        final evidence = EvidenceCaptureRepository(database);
        final unitSession = await evidence.ensurePlantingUnitSession(
          assessmentId: fixture.prepared.run.assessmentId,
          stationId: fixture.station.id,
          sequenceNumber: 1,
          actorPersonId: fixture.actorId,
        );
        final unit = await units.saveCaptureRouting(
          VeV2CaptureRoutingSave(
            stationId: fixture.station.id,
            sequenceNumber: 1,
            occupancyStatus: DatabaseCodes.veOccupancySeedling,
            observedSeedlingCount: 1,
            inspectionDurationMs: 900,
            evidenceCaptureSessionId: unitSession.id,
            requiredEvidenceViewTypes: const {},
            actorPersonId: fixture.actorId,
          ),
        );
        expect(unit.primaryCondition, isNull);
        expect(unit.evaluatorPrimaryInterpretation, isNull);

        final livingSession = await evidence.ensurePlantSession(
          assessmentId: fixture.prepared.run.assessmentId,
          stationId: fixture.station.id,
          plantPosition: 1,
          actorPersonId: fixture.actorId,
          requirementsVersion:
              DatabaseCodes.evidencePolicyVeV2ModelReadyCaptureV1,
          sourcePlantingUnitObservationId: unit.id,
        );
        await evidence.waiveRequiredView(
          session: livingSession,
          viewType: DatabaseCodes.evidenceViewWholeSeedling,
          reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
          actorPersonId: fixture.actorId,
        );
        await evidence.completePlantCapture(
          session: livingSession,
          actorPersonId: fixture.actorId,
          pilotActiveDurationMs: 500,
          newestLeavesInspectedCount: 3,
          requiredViewTypes: const {DatabaseCodes.evidenceViewWholeSeedling},
        );

        final recovered = await evidence.loadBundle(livingSession.id);
        expect(recovered.session.completedAt, isNotNull);
        expect(recovered.session.sourcePlantingUnitObservationId, unit.id);
        expect(recovered.session.plantObservationId, isNull);
      },
    );
  });
}

VeV2PlantingUnitSave _healthyUnit(
  _Fixture fixture,
  int position, {
  int seedlings = 1,
}) => VeV2PlantingUnitSave(
  stationId: fixture.station.id,
  sequenceNumber: position,
  assessable: true,
  primaryCondition: DatabaseCodes.veUnitHealthy,
  observedSeedlingCount: seedlings,
  recognizableRemnantPresent: true,
  visibleCutting: false,
  visibleSevering: false,
  visibleSeedlingInjury: false,
  injuryLocation: null,
  injuryFreshness: null,
  larvaVisible: null,
  larvalSize: null,
  freshFrass: null,
  rotPresent: null,
  tunnelingPresent: null,
  discolorationPresent: null,
  otherNonFawEvidence: null,
  evaluatorPrimaryInterpretation: DatabaseCodes.veInterpretationNone,
  evaluatorConfidence: 'high',
  alternativeCauseCodes: const {},
  inspectionDurationMs: 500,
  actorPersonId: fixture.actorId,
);

VegetativePlantSave _livingPlant(
  _Fixture fixture,
  int position,
  String unitId,
) => VegetativePlantSave(
  stationId: fixture.station.id,
  plantPosition: position,
  plantStatus: DatabaseCodes.plantNegative,
  assessable: true,
  newestLeavesInspectedCount: 3,
  smallFreshWindowpanes: false,
  scraping: false,
  cuttingOrTearing: false,
  freshFrass: false,
  whorlFeedingSign: false,
  larvaVisible: false,
  larvalSize: 'none_seen',
  eggMassVisible: false,
  oldDamagePresent: false,
  possibleNonFawEvidence: false,
  uncertainEvidence: false,
  naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
  sourcePlantingUnitObservationId: unitId,
  actorPersonId: fixture.actorId,
);

Future<_Fixture> _fixture(AppDatabase database) async {
  final field = await FieldRepository(database).createFieldWithBoundaryAndCycle(
    name: 'VE-V2 Field',
    geometryGeojson: _polygon,
    areaHectares: 0.8,
    boundarySourceMethod: 'draw',
    boundaryConfirmationStatus: 'user_confirmed',
  );
  final person = await PeopleRepository(
    database,
  ).findOrCreateEvaluator('VE Evaluator');
  final assessments = AssessmentRepository(database);
  var assessment = await assessments.createDraft(
    cropCycleId: field.cropCycle.id,
    boundaryVersionId: field.boundary.id,
    evaluatorPersonId: person.id,
    assessmentMode: DatabaseCodes.modeVeV6,
    scoutingPattern: DatabaseCodes.patternW,
    growthStage: 've',
    protocolVersion: 'test',
    formulaVersion: 'test',
    interventionHistoryStatus: 'no',
  );
  await assessments.recordSafetyCheck(
    assessmentId: assessment.id,
    checkedByPersonId: person.id,
    resultStatus: DatabaseCodes.noRecentTreatment,
  );
  await assessments.startAssessment(assessment.id);
  assessment = await assessments.assessmentById(assessment.id);
  final workflow = ScoutingWorkflowRepository(database);
  final prepared = (await workflow.prepareRequiredBlocks(
    assessment,
    field.boundary,
  )).single;
  final station = await workflow.saveStationLocation(
    prepared: prepared,
    stationNumber: 1,
    actorPersonId: person.id,
    notLocatedReason: DatabaseCodes.stationNoCurrentFix,
  );
  return _Fixture(station, prepared, person.id);
}

class _Fixture {
  const _Fixture(this.station, this.prepared, this.actorId);
  final StationRecord station;
  final PreparedScoutingRun prepared;
  final String actorId;
}

const _v4PlantingUnitsSql = """
CREATE TABLE planting_unit_observations (
 id TEXT PRIMARY KEY, station_id TEXT NOT NULL, sequence_number INTEGER NOT NULL,
 assessable INTEGER NOT NULL DEFAULT 1, not_assessable_reason TEXT,
 occupancy_status TEXT, observed_seedling_count INTEGER, intended_seedling_count INTEGER,
 visible_cutting INTEGER, visible_seedling_injury INTEGER, confirmed_faw_present INTEGER,
 injury_consistent_with_faw INTEGER, alternative_cause_code TEXT, notes TEXT, captured_at INTEGER,
 created_at INTEGER NOT NULL DEFAULT (unixepoch()), updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
 deleted_at INTEGER, device_id TEXT, sync_state TEXT NOT NULL DEFAULT 'local_only',
 server_version INTEGER NOT NULL DEFAULT 0, UNIQUE(station_id, sequence_number))
""";

const _v4PlantsSql = """
CREATE TABLE plant_observations (
 id TEXT PRIMARY KEY, station_id TEXT NOT NULL, sequence_number INTEGER NOT NULL,
 persistent_plant_identifier TEXT, assessable INTEGER NOT NULL DEFAULT 1,
 not_assessable_reason TEXT, plant_status TEXT NOT NULL, current_faw_evidence INTEGER,
 possible_non_faw_evidence INTEGER, uncertain_evidence INTEGER,
 old_damage_present INTEGER NOT NULL DEFAULT 0, natural_enemy_quick_status TEXT NOT NULL,
 whole_plant_context_note TEXT, latitude REAL, longitude REAL, gps_accuracy_m REAL,
 captured_at INTEGER, evaluator_notes TEXT, created_at INTEGER NOT NULL DEFAULT (unixepoch()),
 updated_at INTEGER NOT NULL DEFAULT (unixepoch()), deleted_at INTEGER, device_id TEXT,
 sync_state TEXT NOT NULL DEFAULT 'local_only', server_version INTEGER NOT NULL DEFAULT 0,
 UNIQUE(station_id, sequence_number))
""";

const _v4EvidenceCaptureSessionsSql = """
CREATE TABLE evidence_capture_sessions (
 id TEXT PRIMARY KEY, created_at INTEGER NOT NULL DEFAULT (unixepoch()),
 updated_at INTEGER NOT NULL DEFAULT (unixepoch()), deleted_at INTEGER,
 device_id TEXT, sync_state TEXT NOT NULL DEFAULT 'local_only',
 server_version INTEGER NOT NULL DEFAULT 0, assessment_id TEXT NOT NULL,
 station_id TEXT NOT NULL, scope_type TEXT NOT NULL, scope_key TEXT NOT NULL,
 plant_position INTEGER, plant_observation_id TEXT,
 requirements_version TEXT NOT NULL DEFAULT 'camera_phase_a_v1',
 collection_mode TEXT NOT NULL DEFAULT 'camera',
 collection_status TEXT NOT NULL DEFAULT 'in_progress',
 waived_view_types_json TEXT, fallback_reason_code TEXT, fallback_note TEXT,
 started_at INTEGER NOT NULL DEFAULT (unixepoch()), completed_at INTEGER,
 UNIQUE(station_id, scope_key))
""";
