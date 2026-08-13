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
  test(
    'schema v3 migrates evidence metadata to v4 without data loss',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (rawDatabase) {
            rawDatabase.execute(_v3EvidenceMediaSql);
            rawDatabase.execute("""
            INSERT INTO evidence_media (
              id, assessment_id, media_type, local_uri,
              sha256_checksum, quality_status, upload_state, is_original
            ) VALUES (
              'legacy-media', 'legacy-assessment', 'image',
              'legacy/photo.jpg', 'legacy-checksum', 'unchecked',
              'local_only', 1
            )
          """);
            rawDatabase.userVersion = 3;
          },
        ),
      );

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      final legacy = await (database.select(
        database.evidenceMedia,
      )..where((row) => row.id.equals('legacy-media'))).getSingle();

      expect(version.read<int>('user_version'), 4);
      expect(legacy.sha256Checksum, 'legacy-checksum');
      expect(legacy.captureSessionId, isNull);
      expect(legacy.captureSource, isNull);
      expect(legacy.widthPx, isNull);
      expect(legacy.heightPx, isNull);
      expect(legacy.qualityIssuesJson, isNull);
      expect(legacy.qualityCheckVersion, isNull);
      expect(legacy.storageState, DatabaseCodes.evidenceStorageReady);
      expect(
        await database.select(database.evidenceCaptureSessions).get(),
        isEmpty,
      );
      await database.close();
    },
  );

  group('Camera Phase A evidence persistence', () {
    late AppDatabase database;
    late Directory root;
    late _Fixture fixture;
    late EvidenceCaptureRepository evidenceRepository;
    late EvidenceStorageService storage;
    late EvidenceCaptureCoordinator coordinator;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      root = await Directory.systemTemp.createTemp('wormwise-evidence-test-');
      fixture = await _createFixture(database);
      evidenceRepository = EvidenceCaptureRepository(database);
      storage = EvidenceStorageService(rootDirectory: () async => root);
      coordinator = EvidenceCaptureCoordinator(
        repository: evidenceRepository,
        storage: storage,
      );
    });

    tearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'capture sessions are idempotent and evidence attaches to Plant 1',
      () async {
        final first = await evidenceRepository.ensurePlantSession(
          assessmentId: fixture.assessment.id,
          stationId: fixture.station.id,
          plantPosition: 1,
          actorPersonId: fixture.evaluatorId,
        );
        final second = await evidenceRepository.ensurePlantSession(
          assessmentId: fixture.assessment.id,
          stationId: fixture.station.id,
          plantPosition: 1,
          actorPersonId: fixture.evaluatorId,
        );
        expect(second.id, first.id);

        final source = await _writeTestJpeg(root, 'capture-source.jpg');
        var bundle = await coordinator.stageCapture(
          session: first,
          viewType: DatabaseCodes.evidenceViewWhorlOverview,
          sourcePath: source.path,
          actorPersonId: fixture.evaluatorId,
        );
        expect(
          bundle
              .mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!
              .storageState,
          DatabaseCodes.evidenceStorageStaged,
        );
        bundle = await coordinator.accept(
          media: bundle.mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!,
          actorPersonId: fixture.evaluatorId,
        );

        final saved =
            await AtomicPlantSaveService(
              database,
              evidenceRepository: evidenceRepository,
            ).saveVegetativePlant(
              _plantInput(
                stationId: fixture.station.id,
                position: 1,
                actorPersonId: fixture.evaluatorId,
                evidenceSessionId: first.id,
                requiredViews: {DatabaseCodes.evidenceViewWhorlOverview},
                pilotActiveDurationMs: 73210,
              ),
            );
        final attached =
            await (database.select(database.evidenceMedia)..where(
                  (row) => row.id.equals(
                    bundle
                        .mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!
                        .id,
                  ),
                ))
                .getSingle();
        final attachedSession = await (database.select(
          database.evidenceCaptureSessions,
        )..where((row) => row.id.equals(first.id))).getSingle();

        expect(attached.assessmentId, fixture.assessment.id);
        expect(attached.stationId, fixture.station.id);
        expect(attached.plantObservationId, saved.plant.id);
        expect(attachedSession.plantPosition, 1);
        expect(attachedSession.plantObservationId, saved.plant.id);
        expect(
          attachedSession.collectionStatus,
          DatabaseCodes.evidenceSessionComplete,
        );
        final metrics = await coordinator.loadPilotWorkloadMetrics(
          fixture.station.id,
        );
        expect(
          metrics.activeTimeByPlant[1],
          const Duration(milliseconds: 73210),
        );
        expect(metrics.acceptedImageCount, 1);
        expect(metrics.retakeCount, 0);
        expect(metrics.storageBytes, greaterThan(0));

        await (database.update(
          database.evidenceCaptureSessions,
        )..where((row) => row.id.equals(first.id))).write(
          const EvidenceCaptureSessionsCompanion(
            requirementsVersion: Value('camera_phase_a_v1'),
          ),
        );
        final upgraded = await evidenceRepository.ensurePlantSession(
          assessmentId: fixture.assessment.id,
          stationId: fixture.station.id,
          plantPosition: 1,
          actorPersonId: fixture.evaluatorId,
        );
        final upgradedBundle = await coordinator.stageCapture(
          session: upgraded,
          viewType: DatabaseCodes.evidenceViewCloseUp,
          sourcePath: (await _writeTestJpeg(root, 'upgraded-close.jpg')).path,
          actorPersonId: fixture.evaluatorId,
        );
        expect(
          upgradedBundle
              .mediaForView(DatabaseCodes.evidenceViewCloseUp)!
              .plantObservationId,
          saved.plant.id,
        );
      },
    );

    test(
      'capture-first completion requires two views and preserves conditional detail association',
      () async {
        final session = await evidenceRepository.ensurePlantSession(
          assessmentId: fixture.assessment.id,
          stationId: fixture.station.id,
          plantPosition: 1,
          actorPersonId: fixture.evaluatorId,
        );
        expect(session.requirementsVersion, 'capture_first_station1_v1');

        await coordinator.recordPlantCaptureInspection(
          session: session,
          actorPersonId: fixture.evaluatorId,
          newestLeavesInspectedCount: 3,
        );
        await coordinator.recordPlantCaptureInspection(
          session: session,
          actorPersonId: fixture.evaluatorId,
          newestLeavesInspectedCount: 4,
        );
        final restartedRepository = EvidenceCaptureRepository(database);
        final recoveredInspection = await restartedRepository
            .loadPilotWorkloadAuditSummary(fixture.station.id);
        expect(recoveredInspection.inspectedLeavesByPlant[1], 4);

        var bundle = await coordinator.stageCapture(
          session: session,
          viewType: DatabaseCodes.evidenceViewWhorlOverview,
          sourcePath: (await _writeTestJpeg(root, 'overview.jpg')).path,
          actorPersonId: fixture.evaluatorId,
        );
        bundle = await coordinator.accept(
          media: bundle.mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!,
          actorPersonId: fixture.evaluatorId,
        );
        await expectLater(
          coordinator.completePlantCapture(
            session: bundle.session,
            actorPersonId: fixture.evaluatorId,
            activeDuration: const Duration(seconds: 12),
            newestLeavesInspectedCount: 3,
          ),
          throwsStateError,
        );

        bundle = await coordinator.stageCapture(
          session: bundle.session,
          viewType: DatabaseCodes.evidenceViewCloseUp,
          sourcePath: (await _writeTestJpeg(root, 'whorl-detail.jpg')).path,
          actorPersonId: fixture.evaluatorId,
        );
        bundle = await coordinator.accept(
          media: bundle.mediaForView(DatabaseCodes.evidenceViewCloseUp)!,
          actorPersonId: fixture.evaluatorId,
        );
        bundle = await coordinator.stageCapture(
          session: bundle.session,
          viewType: DatabaseCodes.evidenceViewDiagnosticDetail,
          sourcePath: (await _writeTestJpeg(root, 'extra-detail.jpg')).path,
          actorPersonId: fixture.evaluatorId,
        );
        bundle = await coordinator.accept(
          media: bundle.mediaForView(
            DatabaseCodes.evidenceViewDiagnosticDetail,
          )!,
          actorPersonId: fixture.evaluatorId,
        );

        await coordinator.completePlantCapture(
          session: bundle.session,
          actorPersonId: fixture.evaluatorId,
          activeDuration: const Duration(seconds: 31),
          newestLeavesInspectedCount: 3,
        );
        final captured = await evidenceRepository.loadBundle(session.id);
        expect(
          captured.session.collectionStatus,
          DatabaseCodes.evidenceSessionComplete,
        );
        expect(captured.session.plantObservationId, isNull);

        final saved =
            await AtomicPlantSaveService(
              database,
              evidenceRepository: evidenceRepository,
            ).saveVegetativePlant(
              _plantInput(
                stationId: fixture.station.id,
                position: 1,
                actorPersonId: fixture.evaluatorId,
                evidenceSessionId: session.id,
                requiredViews: const {
                  DatabaseCodes.evidenceViewWhorlOverview,
                  DatabaseCodes.evidenceViewCloseUp,
                },
                pilotActiveDurationMs: 9000,
              ),
            );
        final attached = await evidenceRepository.loadBundle(session.id);
        expect(attached.media, hasLength(3));
        for (final media in attached.media) {
          expect(media.plantObservationId, saved.plant.id);
          expect(media.isCanonicalEvidence, isTrue);
        }
        final metrics = await coordinator.loadPilotWorkloadMetrics(
          fixture.station.id,
        );
        expect(metrics.acceptedImageCount, 3);
        expect(metrics.manualFormUseCount, 1);
        expect(metrics.guidedTapCount, 12);
        expect(metrics.activeTimeByPlant[1], const Duration(seconds: 40));
      },
    );

    test(
      'wrong plant association rolls back plant, session, and media updates',
      () async {
        final session = await evidenceRepository.ensurePlantSession(
          assessmentId: fixture.assessment.id,
          stationId: fixture.station.id,
          plantPosition: 1,
          actorPersonId: fixture.evaluatorId,
        );
        var bundle = await coordinator.stageCapture(
          session: session,
          viewType: DatabaseCodes.evidenceViewWhorlOverview,
          sourcePath: (await _writeTestJpeg(root, 'wrong-plant.jpg')).path,
          actorPersonId: fixture.evaluatorId,
        );
        bundle = await coordinator.accept(
          media: bundle.mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!,
          actorPersonId: fixture.evaluatorId,
        );
        final mediaId = bundle
            .mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!
            .id;

        await expectLater(
          AtomicPlantSaveService(
            database,
            evidenceRepository: evidenceRepository,
          ).saveVegetativePlant(
            _plantInput(
              stationId: fixture.station.id,
              position: 2,
              actorPersonId: fixture.evaluatorId,
              evidenceSessionId: session.id,
              requiredViews: {DatabaseCodes.evidenceViewWhorlOverview},
            ),
          ),
          throwsStateError,
        );

        expect(
          await database.select(database.plantObservations).get(),
          isEmpty,
        );
        expect(
          (await (database.select(
                database.evidenceMedia,
              )..where((row) => row.id.equals(mediaId))).getSingle())
              .plantObservationId,
          isNull,
        );
        expect(
          (await (database.select(
                database.evidenceCaptureSessions,
              )..where((row) => row.id.equals(session.id))).getSingle())
              .plantObservationId,
          isNull,
        );
      },
    );

    test('manual fallback permits a valid physical plant assessment', () async {
      final session = await evidenceRepository.ensurePlantSession(
        assessmentId: fixture.assessment.id,
        stationId: fixture.station.id,
        plantPosition: 1,
        actorPersonId: fixture.evaluatorId,
      );
      await coordinator.waive(
        session: session,
        viewType: DatabaseCodes.evidenceViewWhorlOverview,
        reasonCode: DatabaseCodes.evidenceFallbackPermissionDenied,
        actorPersonId: fixture.evaluatorId,
        note: 'Permission unavailable in the field.',
      );

      final saved =
          await AtomicPlantSaveService(
            database,
            evidenceRepository: evidenceRepository,
          ).saveVegetativePlant(
            _plantInput(
              stationId: fixture.station.id,
              position: 1,
              actorPersonId: fixture.evaluatorId,
              evidenceSessionId: session.id,
              requiredViews: {DatabaseCodes.evidenceViewWhorlOverview},
            ),
          );
      final completed = await evidenceRepository.loadBundle(session.id);

      expect(saved.plant.assessable, isTrue);
      expect(completed.media, isEmpty);
      expect(completed.session.plantObservationId, saved.plant.id);
      expect(
        completed.session.collectionStatus,
        DatabaseCodes.evidenceSessionManualFallback,
      );
      expect(
        completed.waivedViewTypes,
        contains(DatabaseCodes.evidenceViewWhorlOverview),
      );
      expect(
        (await coordinator.loadPilotWorkloadMetrics(
          fixture.station.id,
        )).manualFallbackCount,
        1,
      );
    });

    test('retakes are counted without retaining the deleted image', () async {
      final session = await evidenceRepository.ensurePlantSession(
        assessmentId: fixture.assessment.id,
        stationId: fixture.station.id,
        plantPosition: 1,
        actorPersonId: fixture.evaluatorId,
      );
      var bundle = await coordinator.stageCapture(
        session: session,
        viewType: DatabaseCodes.evidenceViewWhorlOverview,
        sourcePath: (await _writeTestJpeg(root, 'retake.jpg')).path,
        actorPersonId: fixture.evaluatorId,
      );
      bundle = await coordinator.accept(
        media: bundle.mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!,
        actorPersonId: fixture.evaluatorId,
      );
      final media = bundle.mediaForView(
        DatabaseCodes.evidenceViewWhorlOverview,
      )!;
      final original = await storage.resolve(media.localUri);
      await coordinator.remove(
        media: media,
        actorPersonId: fixture.evaluatorId,
        retake: true,
      );

      final metrics = await coordinator.loadPilotWorkloadMetrics(
        fixture.station.id,
      );
      expect(metrics.retakeCount, 1);
      expect(metrics.acceptedImageCount, 0);
      expect(metrics.storageBytes, 0);
      expect(await original.exists(), isFalse);
    });

    test(
      'promoted file is reconciled after a database update failure window',
      () async {
        final session = await evidenceRepository.ensurePlantSession(
          assessmentId: fixture.assessment.id,
          stationId: fixture.station.id,
          plantPosition: 1,
          actorPersonId: fixture.evaluatorId,
        );
        final staged = await coordinator.stageCapture(
          session: session,
          viewType: DatabaseCodes.evidenceViewWhorlOverview,
          sourcePath: (await _writeTestJpeg(root, 'recovery.jpg')).path,
          actorPersonId: fixture.evaluatorId,
        );
        final media = staged.mediaForView(
          DatabaseCodes.evidenceViewWhorlOverview,
        )!;
        await storage.promote(
          localUri: media.localUri,
          thumbnailLocalUri: media.thumbnailLocalUri!,
        );

        await coordinator.reconcileAssessment(
          assessmentId: fixture.assessment.id,
          actorPersonId: fixture.evaluatorId,
        );

        final recovered = await evidenceRepository.loadBundle(session.id);
        expect(
          recovered
              .mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!
              .storageState,
          DatabaseCodes.evidenceStorageReady,
        );
        expect(
          await storage.exists(
            recovered
                .mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!
                .localUri,
          ),
          isTrue,
        );
      },
    );

    test(
      'restart keeps an unfinished preview and reports a missing accepted file',
      () async {
        final session = await evidenceRepository.ensurePlantSession(
          assessmentId: fixture.assessment.id,
          stationId: fixture.station.id,
          plantPosition: 1,
          actorPersonId: fixture.evaluatorId,
        );
        var bundle = await coordinator.stageCapture(
          session: session,
          viewType: DatabaseCodes.evidenceViewWhorlOverview,
          sourcePath: (await _writeTestJpeg(root, 'unfinished.jpg')).path,
          actorPersonId: fixture.evaluatorId,
        );
        final stagedBeforeRestart = bundle.mediaForView(
          DatabaseCodes.evidenceViewWhorlOverview,
        )!;
        final stagedBytesBeforeRestart = await (await storage.resolve(
          stagedBeforeRestart.localUri,
        )).readAsBytes();
        await coordinator.reconcileAssessment(
          assessmentId: fixture.assessment.id,
          actorPersonId: fixture.evaluatorId,
        );
        bundle = await evidenceRepository.loadBundle(session.id);
        expect(
          bundle
              .mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!
              .storageState,
          DatabaseCodes.evidenceStorageStaged,
        );
        final stagedAfterRestart = bundle.mediaForView(
          DatabaseCodes.evidenceViewWhorlOverview,
        )!;
        expect(stagedAfterRestart.localUri, stagedBeforeRestart.localUri);
        expect(
          stagedAfterRestart.sha256Checksum,
          stagedBeforeRestart.sha256Checksum,
        );
        expect(
          await (await storage.resolve(
            stagedAfterRestart.localUri,
          )).readAsBytes(),
          stagedBytesBeforeRestart,
        );

        bundle = await coordinator.accept(
          media: bundle.mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!,
          actorPersonId: fixture.evaluatorId,
        );
        final accepted = bundle.mediaForView(
          DatabaseCodes.evidenceViewWhorlOverview,
        )!;
        await (await storage.resolve(accepted.localUri)).delete();
        await coordinator.reconcileAssessment(
          assessmentId: fixture.assessment.id,
          actorPersonId: fixture.evaluatorId,
        );
        bundle = await evidenceRepository.loadBundle(session.id);
        expect(
          bundle
              .mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!
              .storageState,
          DatabaseCodes.evidenceStorageMissing,
        );
      },
    );

    test(
      'accepted deletion removes files and retains an audited checksum tombstone',
      () async {
        final session = await evidenceRepository.ensurePlantSession(
          assessmentId: fixture.assessment.id,
          stationId: fixture.station.id,
          plantPosition: 1,
          actorPersonId: fixture.evaluatorId,
        );
        var bundle = await coordinator.stageCapture(
          session: session,
          viewType: DatabaseCodes.evidenceViewWhorlOverview,
          sourcePath: (await _writeTestJpeg(root, 'delete.jpg')).path,
          actorPersonId: fixture.evaluatorId,
        );
        bundle = await coordinator.accept(
          media: bundle.mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!,
          actorPersonId: fixture.evaluatorId,
        );
        final media = bundle.mediaForView(
          DatabaseCodes.evidenceViewWhorlOverview,
        )!;
        final main = await storage.resolve(media.localUri);
        final thumbnail = await storage.resolve(media.thumbnailLocalUri!);
        expect(await main.exists(), isTrue);
        expect(await thumbnail.exists(), isTrue);

        await coordinator.remove(
          media: media,
          actorPersonId: fixture.evaluatorId,
        );

        expect(await main.exists(), isFalse);
        expect(await thumbnail.exists(), isFalse);
        final tombstone = await (database.select(
          database.evidenceMedia,
        )..where((row) => row.id.equals(media.id))).getSingle();
        expect(tombstone.deletedAt, isNotNull);
        expect(tombstone.sha256Checksum, media.sha256Checksum);
        expect(tombstone.storageState, DatabaseCodes.evidenceStorageDeleted);
        final audit =
            await (database.select(database.auditLogs)..where(
                  (row) =>
                      row.entityId.equals(media.id) &
                      row.action.equals('deleted'),
                ))
                .getSingle();
        expect(audit.afterJson, contains('"file_retained":false'));
        expect(
          await (database.select(
            database.syncOutbox,
          )..where((row) => row.entityType.equals('evidence_media'))).get(),
          isEmpty,
        );
      },
    );
  });
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

const _v3EvidenceMediaSql = """
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
