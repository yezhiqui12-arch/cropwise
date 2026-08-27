import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/data/services/atomic_plant_save_service.dart';

const _fieldPolygon =
    '{"type":"Polygon","coordinates":[[[121.0,17.0],[121.01,17.0],'
    '[121.01,17.01],[121.0,17.01],[121.0,17.0]]]}';

void main() {
  test(
    'schema v2 migrates through v7 without rewriting old observations',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (rawDatabase) {
            rawDatabase.execute(_v2PlantObservationsSql);
            rawDatabase.execute(_v2PlantingUnitObservationsSql);
            rawDatabase.execute(_v2VegetativeObservationsSql);
            rawDatabase.execute(_v2EvidenceMediaSql);
            rawDatabase.execute("""
            INSERT INTO plant_observations (
              id, station_id, sequence_number, plant_status,
              current_faw_evidence, old_damage_present,
              natural_enemy_quick_status
            ) VALUES (
              'legacy-plant', 'legacy-station', 1, 'uncertain',
              NULL, 1, 'none_seen'
            )
          """);
            rawDatabase.execute("""
            INSERT INTO vegetative_observations (
              plant_observation_id, newest_leaves_inspected_count,
              small_fresh_windowpanes, infested_whorl, scraping,
              cutting_or_tearing, fresh_frass, whorl_feeding_sign,
              larva_visible, larval_size
            ) VALUES (
              'legacy-plant', 4, 1, 1, 1, 0, 0, 0, 0, 'none_seen'
            )
          """);
            rawDatabase.userVersion = 2;
          },
        ),
      );

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      final plant = await (database.select(
        database.plantObservations,
      )..where((row) => row.id.equals('legacy-plant'))).getSingle();
      final vegetative =
          await (database.select(database.vegetativeObservations)
                ..where((row) => row.plantObservationId.equals('legacy-plant')))
              .getSingle();

      expect(version.read<int>('user_version'), 7);
      expect(plant.plantStatus, 'uncertain');
      expect(plant.currentFawEvidence, isNull);
      expect(plant.oldDamagePresent, isTrue);
      expect(plant.possibleNonFawEvidence, isNull);
      expect(plant.uncertainEvidence, isNull);
      expect(vegetative.smallFreshWindowpanes, isTrue);
      expect(vegetative.scraping, isTrue);
      expect(vegetative.eggMassVisible, isNull);

      await database.close();
    },
  );

  group('atomic vegetative plant save', () {
    late AppDatabase database;
    late AtomicPlantSaveService service;
    late _StationFixture fixture;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      fixture = await _createStationFixture(database);
      _activeFixture = fixture;
      service = AtomicPlantSaveService(database);
    });

    tearDown(() => database.close());

    test('validates plant position 1-10', () async {
      await expectLater(
        service.saveVegetativePlant(_input(plantPosition: 0)),
        throwsArgumentError,
      );
      await expectLater(
        service.saveVegetativePlant(_input(plantPosition: 11)),
        throwsArgumentError,
      );

      expect(await database.select(database.plantObservations).get(), isEmpty);
    });

    test(
      'accepts not_collected and rejects unknown natural-enemy codes',
      () async {
        final saved = await service.saveVegetativePlant(
          _input(plantPosition: 1),
        );
        expect(
          saved.plant.naturalEnemyQuickStatus,
          DatabaseCodes.naturalEnemyNotCollected,
        );

        await expectLater(
          service.saveVegetativePlant(
            _input(
              plantPosition: 2,
              naturalEnemyQuickStatus: 'not-a-real-code',
            ),
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'preserves nullable raw fields as yes, no, and not collected',
      () async {
        final values = <bool?>[null, false, true];
        for (var index = 0; index < values.length; index++) {
          await service.saveVegetativePlant(
            _input(
              plantPosition: index + 1,
              eggMassVisible: values[index],
              possibleNonFawEvidence: values[index],
              uncertainEvidence: values[index],
            ),
          );
        }

        final plants = await (database.select(
          database.plantObservations,
        )..orderBy([(row) => OrderingTerm.asc(row.sequenceNumber)])).get();
        final vegetative = await (database.select(
          database.vegetativeObservations,
        )..orderBy([(row) => OrderingTerm.asc(row.plantObservationId)])).get();
        final vegetativeByPlantId = {
          for (final row in vegetative) row.plantObservationId: row,
        };

        for (var index = 0; index < values.length; index++) {
          expect(plants[index].possibleNonFawEvidence, values[index]);
          expect(plants[index].uncertainEvidence, values[index]);
          expect(
            vegetativeByPlantId[plants[index].id]?.eggMassVisible,
            values[index],
          );
        }
      },
    );

    test(
      'derives SFW and each IW sign without claiming species confirmation',
      () async {
        final cases = [
          _input(plantPosition: 1, smallFreshWindowpanes: true),
          _input(plantPosition: 2, scraping: true),
          _input(plantPosition: 3, cuttingOrTearing: true),
          _input(plantPosition: 4, freshFrass: true),
          _input(plantPosition: 5, whorlFeedingSign: true),
        ];

        for (final input in cases) {
          final saved = await service.saveVegetativePlant(input);
          expect(saved.plant.currentFawEvidence, isTrue);
          expect(saved.vegetative.infestedWhorl, input.plantPosition != 1);
        }

        final larvaOnly = await service.saveVegetativePlant(
          _input(plantPosition: 6, larvaVisible: true, larvalSize: 'small'),
        );
        expect(larvaOnly.plant.currentFawEvidence, isFalse);
        expect(larvaOnly.vegetative.infestedWhorl, isFalse);
      },
    );

    test(
      'audits previous and replacement records from one atomic update',
      () async {
        final first = await service.saveVegetativePlant(
          _input(
            plantPosition: 1,
            scraping: true,
            eggMassVisible: null,
            oldDamagePresent: true,
            possibleNonFawEvidence: true,
            uncertainEvidence: true,
          ),
        );
        final second = await service.saveVegetativePlant(
          _input(
            plantPosition: 1,
            cuttingOrTearing: true,
            eggMassVisible: true,
            possibleNonFawEvidence: false,
            uncertainEvidence: false,
          ),
        );

        expect(second.plant.id, first.plant.id);
        final audit =
            await (database.select(database.auditLogs)..where(
                  (row) =>
                      row.entityId.equals(first.plant.id) &
                      row.action.equals('update'),
                ))
                .getSingle();
        final before = jsonDecode(audit.beforeJson!) as Map<String, dynamic>;
        final after = jsonDecode(audit.afterJson!) as Map<String, dynamic>;

        expect(before['scraping'], isTrue);
        expect(before['egg_mass_visible'], isNull);
        expect(before['old_damage_present'], isTrue);
        expect(before['possible_non_faw_evidence'], isTrue);
        expect(before['uncertain_evidence'], isTrue);
        expect(before['plant_status'], DatabaseCodes.plantUncertain);
        expect(after['scraping'], isFalse);
        expect(after['cutting_or_tearing'], isTrue);
        expect(after['egg_mass_visible'], isTrue);
        expect(after['possible_non_faw_evidence'], isFalse);
        expect(after['uncertain_evidence'], isFalse);
      },
    );

    test(
      'rolls back parent, child, audit, and outbox when create fails',
      () async {
        final auditCount =
            (await database.select(database.auditLogs).get()).length;
        final outboxCount =
            (await database.select(database.syncOutbox).get()).length;
        await database.customStatement("""
        CREATE TRIGGER fail_vegetative_insert
        BEFORE INSERT ON vegetative_observations
        BEGIN
          SELECT RAISE(ABORT, 'forced child insert failure');
        END
      """);

        await expectLater(
          service.saveVegetativePlant(_input(plantPosition: 1)),
          throwsA(anything),
        );

        expect(
          await database.select(database.plantObservations).get(),
          isEmpty,
        );
        expect(
          await database.select(database.vegetativeObservations).get(),
          isEmpty,
        );
        expect(
          (await database.select(database.auditLogs).get()).length,
          auditCount,
        );
        expect(
          (await database.select(database.syncOutbox).get()).length,
          outboxCount,
        );
      },
    );

    test(
      'rolls back an update and its audit when child replacement fails',
      () async {
        final original = await service.saveVegetativePlant(
          _input(plantPosition: 1, scraping: true, eggMassVisible: null),
        );
        final auditCount =
            (await database.select(database.auditLogs).get()).length;
        final outboxCount =
            (await database.select(database.syncOutbox).get()).length;
        await database.customStatement("""
        CREATE TRIGGER fail_vegetative_update
        BEFORE UPDATE ON vegetative_observations
        BEGIN
          SELECT RAISE(ABORT, 'forced child update failure');
        END
      """);

        await expectLater(
          service.saveVegetativePlant(
            _input(
              plantPosition: 1,
              cuttingOrTearing: true,
              eggMassVisible: true,
              possibleNonFawEvidence: true,
            ),
          ),
          throwsA(anything),
        );

        final plant = await (database.select(
          database.plantObservations,
        )..where((row) => row.id.equals(original.plant.id))).getSingle();
        final vegetative =
            await (database.select(database.vegetativeObservations)..where(
                  (row) => row.plantObservationId.equals(original.plant.id),
                ))
                .getSingle();
        expect(plant.possibleNonFawEvidence, isNull);
        expect(vegetative.scraping, isTrue);
        expect(vegetative.cuttingOrTearing, isFalse);
        expect(vegetative.eggMassVisible, isNull);
        expect(
          (await database.select(database.auditLogs).get()).length,
          auditCount,
        );
        expect(
          (await database.select(database.syncOutbox).get()).length,
          outboxCount,
        );
      },
    );
  });
}

class _StationFixture {
  const _StationFixture({required this.stationId});

  final String stationId;
}

Future<_StationFixture> _createStationFixture(AppDatabase database) async {
  final people = PeopleRepository(database);
  final fields = FieldRepository(database);
  final assessments = AssessmentRepository(database);
  final evaluator = await people.create(
    displayName: 'Phase 2 Evaluator',
    roleLabel: 'evaluator',
  );
  final field = await fields.createFieldWithBoundaryAndCycle(
    name: 'Phase 2 Field',
    geometryGeojson: _fieldPolygon,
    areaHectares: 1,
    boundarySourceMethod: 'draw',
    ownerPersonId: evaluator.id,
    actorPersonId: evaluator.id,
  );
  final block = await fields.addBlock(
    cropCycleId: field.cropCycle.id,
    boundaryVersionId: field.boundary.id,
    blockNumber: 1,
    geometryGeojson: _fieldPolygon,
    areaHectares: 1,
    actorPersonId: evaluator.id,
  );
  final assessment = await assessments.createDraft(
    cropCycleId: field.cropCycle.id,
    boundaryVersionId: field.boundary.id,
    evaluatorPersonId: evaluator.id,
    assessmentMode: DatabaseCodes.modeV7V12,
    scoutingPattern: DatabaseCodes.patternW,
    growthStage: 'v8',
    protocolVersion: 'phase-2-test',
    formulaVersion: 'phase-2-test',
  );
  final run = await assessments.addBlockRun(
    assessmentId: assessment.id,
    fieldBlockId: block.id,
    blockSequence: 1,
    scoutingPattern: DatabaseCodes.patternW,
  );
  final station = await assessments.addStation(
    assessmentBlockRunId: run.id,
    stationNumber: 1,
  );
  return _StationFixture(stationId: station.id);
}

VegetativePlantSave _input({
  required int plantPosition,
  bool smallFreshWindowpanes = false,
  bool scraping = false,
  bool cuttingOrTearing = false,
  bool freshFrass = false,
  bool whorlFeedingSign = false,
  bool larvaVisible = false,
  String larvalSize = 'none_seen',
  bool? eggMassVisible,
  bool oldDamagePresent = false,
  bool? possibleNonFawEvidence,
  bool? uncertainEvidence,
  String naturalEnemyQuickStatus = DatabaseCodes.naturalEnemyNotCollected,
}) {
  return VegetativePlantSave(
    stationId: _activeFixture.stationId,
    plantPosition: plantPosition,
    plantStatus: DatabaseCodes.plantUncertain,
    assessable: true,
    newestLeavesInspectedCount: 4,
    smallFreshWindowpanes: smallFreshWindowpanes,
    scraping: scraping,
    cuttingOrTearing: cuttingOrTearing,
    freshFrass: freshFrass,
    whorlFeedingSign: whorlFeedingSign,
    larvaVisible: larvaVisible,
    larvalSize: larvalSize,
    eggMassVisible: eggMassVisible,
    oldDamagePresent: oldDamagePresent,
    possibleNonFawEvidence: possibleNonFawEvidence,
    uncertainEvidence: uncertainEvidence,
    naturalEnemyQuickStatus: naturalEnemyQuickStatus,
  );
}

late _StationFixture _activeFixture;

const _v2PlantObservationsSql = """
  CREATE TABLE plant_observations (
    id TEXT PRIMARY KEY,
    station_id TEXT NOT NULL,
    sequence_number INTEGER NOT NULL,
    persistent_plant_identifier TEXT,
    assessable INTEGER NOT NULL DEFAULT 1,
    not_assessable_reason TEXT,
    plant_status TEXT NOT NULL,
    current_faw_evidence INTEGER,
    old_damage_present INTEGER NOT NULL DEFAULT 0,
    natural_enemy_quick_status TEXT NOT NULL,
    whole_plant_context_note TEXT,
    latitude REAL,
    longitude REAL,
    gps_accuracy_m REAL,
    captured_at INTEGER,
    evaluator_notes TEXT,
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    deleted_at INTEGER,
    device_id TEXT,
    sync_state TEXT NOT NULL DEFAULT 'local_only',
    server_version INTEGER NOT NULL DEFAULT 0,
    UNIQUE (station_id, sequence_number)
  )
""";

const _v2PlantingUnitObservationsSql = """
  CREATE TABLE planting_unit_observations (
    id TEXT PRIMARY KEY,
    station_id TEXT NOT NULL,
    sequence_number INTEGER NOT NULL,
    assessable INTEGER NOT NULL DEFAULT 1,
    not_assessable_reason TEXT,
    occupancy_status TEXT,
    observed_seedling_count INTEGER,
    intended_seedling_count INTEGER,
    visible_cutting INTEGER,
    visible_seedling_injury INTEGER,
    confirmed_faw_present INTEGER,
    injury_consistent_with_faw INTEGER,
    alternative_cause_code TEXT,
    notes TEXT,
    captured_at INTEGER,
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    deleted_at INTEGER,
    device_id TEXT,
    sync_state TEXT NOT NULL DEFAULT 'local_only',
    server_version INTEGER NOT NULL DEFAULT 0,
    UNIQUE (station_id, sequence_number)
  )
""";

const _v2VegetativeObservationsSql = """
  CREATE TABLE vegetative_observations (
    plant_observation_id TEXT PRIMARY KEY,
    newest_leaves_inspected_count INTEGER,
    small_fresh_windowpanes INTEGER NOT NULL DEFAULT 0,
    infested_whorl INTEGER NOT NULL DEFAULT 0,
    scraping INTEGER NOT NULL DEFAULT 0,
    cutting_or_tearing INTEGER NOT NULL DEFAULT 0,
    fresh_frass INTEGER NOT NULL DEFAULT 0,
    whorl_feeding_sign INTEGER NOT NULL DEFAULT 0,
    larva_visible INTEGER NOT NULL DEFAULT 0,
    larval_size TEXT NOT NULL DEFAULT 'none_seen',
    larva_count INTEGER,
    da_bafs_leaf_damage_score INTEGER,
    damage_score_uncertain INTEGER NOT NULL DEFAULT 0,
    damage_score_reason TEXT,
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at INTEGER NOT NULL DEFAULT (unixepoch())
  )
""";

const _v2EvidenceMediaSql = """
  CREATE TABLE evidence_media (
    id TEXT PRIMARY KEY,
    assessment_id TEXT NOT NULL,
    station_id TEXT,
    planting_unit_observation_id TEXT,
    plant_observation_id TEXT,
    ear_observation_id TEXT,
    intervention_id TEXT,
    safety_check_id TEXT,
    media_type TEXT NOT NULL,
    view_type TEXT,
    local_uri TEXT NOT NULL,
    remote_uri TEXT,
    thumbnail_local_uri TEXT,
    mime_type TEXT,
    byte_size INTEGER,
    sha256_checksum TEXT NOT NULL,
    captured_at INTEGER,
    latitude REAL,
    longitude REAL,
    gps_accuracy_m REAL,
    quality_status TEXT NOT NULL DEFAULT 'unchecked',
    upload_state TEXT NOT NULL DEFAULT 'local_only',
    is_original INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    deleted_at INTEGER,
    device_id TEXT,
    sync_state TEXT NOT NULL DEFAULT 'local_only',
    server_version INTEGER NOT NULL DEFAULT 0
  )
""";
