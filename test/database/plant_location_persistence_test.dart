import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/data/repositories/station1_workflow_repository.dart';
import 'package:wormwise/data/services/atomic_plant_save_service.dart';
import 'package:wormwise/services/evidence_capture_coordinator.dart';
import 'package:wormwise/services/evidence_storage_service.dart';

const _polygon =
    '{"type":"Polygon","coordinates":[[[121.0,17.0],[121.01,17.0],'
    '[121.01,17.01],[121.0,17.01],[121.0,17.0]]]}';

void main() {
  for (final withGps in [true, false]) {
    test(
      'photo GPS survives restart and attaches to plant: $withGps',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'wormwise-location-',
        );
        final dbFile = File('${root.path}/local.sqlite');
        var db = AppDatabase(NativeDatabase(dbFile));
        try {
          final fixture = await _createFixture(db);
          var repository = EvidenceCaptureRepository(db);
          final session = await repository.ensurePlantSession(
            assessmentId: fixture.assessment.id,
            stationId: fixture.station.id,
            plantPosition: 1,
            actorPersonId: fixture.evaluatorId,
          );
          final coordinator = EvidenceCaptureCoordinator(
            repository: repository,
            storage: EvidenceStorageService(rootDirectory: () async => root),
          );
          var bundle = await coordinator.stageCapture(
            session: session,
            viewType: DatabaseCodes.evidenceViewWhorlOverview,
            sourcePath: (await _writeTestJpeg(root, 'capture.jpg')).path,
            actorPersonId: fixture.evaluatorId,
          );
          final media = bundle.media.first;
          final captured = DateTime.utc(2026, 9, 26, 3, 4, 5);
          await (db.update(
            db.evidenceMedia,
          )..where((r) => r.id.equals(media.id))).write(
            EvidenceMediaCompanion(
              latitude: Value(withGps ? 17.123456 : null),
              longitude: Value(withGps ? 121.123456 : null),
              gpsAccuracyM: Value(withGps ? 7.5 : null),
              locationSource: Value(withGps ? 'phone_gps' : 'unavailable'),
              locationCapturedAt: Value(withGps ? captured : null),
            ),
          );
          bundle = await repository.loadBundle(session.id);
          await coordinator.accept(
            media: bundle.media.first,
            actorPersonId: fixture.evaluatorId,
          );
          await db.close();
          db = AppDatabase(NativeDatabase(dbFile));
          repository = EvidenceCaptureRepository(db);
          final saved =
              await AtomicPlantSaveService(
                db,
                evidenceRepository: repository,
              ).saveVegetativePlant(
                _plantInput(
                  stationId: fixture.station.id,
                  position: 1,
                  actorPersonId: fixture.evaluatorId,
                  evidenceSessionId: session.id,
                  requiredViews: {DatabaseCodes.evidenceViewWhorlOverview},
                ),
              );
          final plant = await (db.select(
            db.plantObservations,
          )..where((r) => r.id.equals(saved.plant.id))).getSingle();
          expect(plant.latitude, withGps ? 17.123456 : null);
          expect(plant.longitude, withGps ? 121.123456 : null);
          expect(plant.locationSource, withGps ? 'phone_gps' : 'unavailable');
          expect(plant.locationCapturedAt?.toUtc(), withGps ? captured : null);
          expect(plant.gpsAccuracyM, withGps ? 7.5 : null);
          final station = await (db.select(
            db.stations,
          )..where((r) => r.id.equals(fixture.station.id))).getSingle();
          expect(station.syncState, DatabaseCodes.queued);
        } finally {
          await db.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
  test(
    'v7 coordinates migrate as unverified and are queued for cloud refresh',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'wormwise-migrate-location-',
      );
      final file = File('${root.path}/migration.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      try {
        final fixture = await _createFixture(db);
        for (final table in [
          'stations',
          'plant_observations',
          'evidence_media',
        ]) {
          await db.customStatement(
            'ALTER TABLE $table DROP COLUMN location_source',
          );
          await db.customStatement(
            'ALTER TABLE $table DROP COLUMN location_captured_at',
          );
        }
        await db.customStatement('PRAGMA user_version = 7');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final station = await (db.select(
          db.stations,
        )..where((r) => r.id.equals(fixture.station.id))).getSingle();
        expect(station.locationSource, 'unverified');
        expect(station.locationCapturedAt, isNull);
        expect(station.syncState, DatabaseCodes.queued);
        expect(station.latitude, fixture.station.latitude);
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
}

class _Fixture {
  const _Fixture({
    required this.assessment,
    required this.station,
    required this.evaluatorId,
  });

  final AssessmentRecord assessment;
  final StationRecord station;
  final String evaluatorId;
}

Future<_Fixture> _createFixture(AppDatabase database) async {
  final evaluator = await PeopleRepository(
    database,
  ).findOrCreateEvaluator('Camera Phase A Evaluator');
  final field = await FieldRepository(database).createFieldWithBoundaryAndCycle(
    name: 'Camera Phase A Field',
    geometryGeojson: _polygon,
    areaHectares: 0.8,
    boundarySourceMethod: 'draw',
    boundaryConfirmationStatus: 'user_confirmed',
    ownerPersonId: evaluator.id,
    actorPersonId: evaluator.id,
  );
  final assessments = AssessmentRepository(database);
  var assessment = await assessments.createDraft(
    cropCycleId: field.cropCycle.id,
    boundaryVersionId: field.boundary.id,
    evaluatorPersonId: evaluator.id,
    assessmentMode: DatabaseCodes.modeV7V12,
    scoutingPattern: DatabaseCodes.patternW,
    growthStage: 'v7_v12',
    protocolVersion: 'camera-phase-a-test',
    formulaVersion: 'camera-phase-a-test',
  );
  await assessments.recordSafetyCheck(
    assessmentId: assessment.id,
    checkedByPersonId: evaluator.id,
    resultStatus: DatabaseCodes.noRecentTreatment,
  );
  await assessments.startAssessment(assessment.id);
  assessment = await assessments.assessmentById(assessment.id);
  final workflow = Station1WorkflowRepository(database);
  final prepared = await workflow.prepareBlockOne(assessment, field.boundary);
  final station = await workflow.saveStationLocation(
    prepared: prepared,
    actorPersonId: evaluator.id,
    notLocatedReason: DatabaseCodes.stationNoCurrentFix,
  );
  return _Fixture(
    assessment: assessment,
    station: station,
    evaluatorId: evaluator.id,
  );
}

VegetativePlantSave _plantInput({
  required String stationId,
  required int position,
  required String actorPersonId,
  required String evidenceSessionId,
  required Set<String> requiredViews,
  int pilotActiveDurationMs = 0,
}) {
  return VegetativePlantSave(
    stationId: stationId,
    plantPosition: position,
    plantStatus: DatabaseCodes.plantNegative,
    assessable: true,
    newestLeavesInspectedCount: 4,
    smallFreshWindowpanes: false,
    scraping: false,
    cuttingOrTearing: false,
    freshFrass: false,
    whorlFeedingSign: false,
    larvaVisible: false,
    larvalSize: 'none_seen',
    eggMassVisible: null,
    oldDamagePresent: false,
    possibleNonFawEvidence: false,
    uncertainEvidence: false,
    actorPersonId: actorPersonId,
    evidenceCaptureSessionId: evidenceSessionId,
    requiredEvidenceViewTypes: requiredViews,
    requireCameraPhaseAEvidence: true,
    pilotActiveDurationMs: pilotActiveDurationMs,
  );
}

Future<File> _writeTestJpeg(Directory root, String name) async {
  final image = image_lib.Image(width: 96, height: 72);
  for (final pixel in image) {
    pixel
      ..r = (pixel.x * 5 + pixel.y * 3) % 256
      ..g = (pixel.x * 2 + pixel.y * 7) % 256
      ..b = (pixel.x * 11 + pixel.y) % 256;
  }
  final file = File('${root.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(image_lib.encodeJpg(image, quality: 92), flush: true);
  return file;
}
