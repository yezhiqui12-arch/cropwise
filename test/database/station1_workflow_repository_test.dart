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
import 'package:wormwise/providers/station1_workflow_provider.dart';
import 'package:wormwise/services/evidence_capture_coordinator.dart';
import 'package:wormwise/services/evidence_storage_service.dart';

const _polygon =
    '{"type":"Polygon","coordinates":[[[121.0,17.0],[121.01,17.0],'
    '[121.01,17.01],[121.0,17.01],[121.0,17.0]]]}';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('Block 1 and Station 1 creation are idempotent', () async {
    final fixture = await _createFixture(database);
    final repository = Station1WorkflowRepository(database);

    final first = await repository.prepareBlockOne(
      fixture.assessment,
      fixture.boundary,
    );
    final second = await repository.prepareBlockOne(
      fixture.assessment,
      fixture.boundary,
    );

    expect(second.block.id, first.block.id);
    expect(second.run.id, first.run.id);
    expect((await database.select(database.fieldBlocks).get()).length, 1);
    expect(
      (await database.select(database.assessmentBlockRuns).get()).length,
      1,
    );

    final firstStation = await repository.saveStationLocation(
      prepared: first,
      actorPersonId: fixture.assessment.evaluatorPersonId,
      latitude: 17.01,
      longitude: 121.01,
      gpsAccuracyM: 245,
      capturedAt: DateTime.utc(2026, 8, 12),
    );
    final secondStation = await repository.saveStationLocation(
      prepared: first,
      actorPersonId: fixture.assessment.evaluatorPersonId,
      notLocatedReason: DatabaseCodes.stationNoCurrentFix,
    );

    expect(secondStation.id, firstStation.id);
    expect(secondStation.latitude, isNull);
    expect(secondStation.notLocatedReason, DatabaseCodes.stationNoCurrentFix);
    expect((await database.select(database.stations).get()).length, 1);
  });

  test(
    'field larger than one hectare cannot silently become one block',
    () async {
      final fixture = await _createFixture(database, areaHectares: 1.01);
      final repository = Station1WorkflowRepository(database);

      await expectLater(
        repository.prepareBlockOne(fixture.assessment, fixture.boundary),
        throwsA(isA<PilotBlockRequiredException>()),
      );
      expect(await database.select(database.fieldBlocks).get(), isEmpty);
      expect(
        await database.select(database.assessmentBlockRuns).get(),
        isEmpty,
      );
    },
  );

  test(
    'legacy later-stage records never enter the V3-V12 plant form',
    () async {
      for (final stage in ['vt_r2', 'r3_r6']) {
        final fixture = await _createFixture(
          database,
          growthStage: stage,
          startAssessment: false,
        );
        await (database.update(
          database.assessments,
        )..where((row) => row.id.equals(fixture.assessment.id))).write(
          AssessmentsCompanion(
            status: const Value(DatabaseCodes.inProgress),
            startedAt: Value(DateTime.now().toUtc()),
          ),
        );
        final provider = Station1WorkflowProvider(
          assessmentId: fixture.assessment.id,
          workflowRepository: Station1WorkflowRepository(database),
          assessmentRepository: AssessmentRepository(database),
          plantSaveService: AtomicPlantSaveService(database),
        );

        await provider.initialize();

        expect(
          provider.state,
          Station1ViewState.unsupportedStage,
          reason: stage,
        );
        expect(await database.select(database.fieldBlocks).get(), isEmpty);
        expect(
          await database.select(database.plantObservations).get(),
          isEmpty,
        );
      }
    },
  );

  test(
    'unconfirmed outline is defensively rejected without deleting draft',
    () async {
      final fixture = await _createFixture(
        database,
        confirmationStatus: 'draft',
      );
      final repository = Station1WorkflowRepository(database);

      await expectLater(
        repository.prepareBlockOne(fixture.assessment, fixture.boundary),
        throwsStateError,
      );
      expect(
        await (database.select(
          database.assessments,
        )..where((row) => row.id.equals(fixture.assessment.id))).getSingle(),
        isNotNull,
      );
    },
  );

  test(
    'restart resumes at smallest missing plant after condition check',
    () async {
      final fixture = await _createFixture(database);
      final repository = Station1WorkflowRepository(database);
      final assessmentRepository = AssessmentRepository(database);
      final saves = AtomicPlantSaveService(database);
      final first = Station1WorkflowProvider(
        assessmentId: fixture.assessment.id,
        workflowRepository: repository,
        assessmentRepository: assessmentRepository,
        plantSaveService: saves,
      );

      await first.initialize();
      expect(first.state, Station1ViewState.blockPreparation);
      await first.prepareBlockOne();
      await first.saveStationUnavailable(
        reason: DatabaseCodes.stationNoCurrentFix,
      );
      first.beginTenConsecutivePlants();
      await first.savePlant(
        _plantInput(
          stationId: first.snapshot!.station!.id,
          position: 1,
          status: DatabaseCodes.plantPossibleNonFaw,
          possibleNonFaw: true,
          uncertain: true,
        ),
      );
      expect(first.currentPlantPosition, 2);

      final resumed = Station1WorkflowProvider(
        assessmentId: fixture.assessment.id,
        workflowRepository: repository,
        assessmentRepository: assessmentRepository,
        plantSaveService: saves,
      );
      await resumed.initialize();
      expect(resumed.state, Station1ViewState.resumeCheck);
      await resumed.submitResumeCheck(
        condition: ResumeCondition.unchanged,
        safeToContinue: true,
      );

      expect(resumed.state, Station1ViewState.plantEntry);
      expect(resumed.currentPlantPosition, 2);
      final saved = (await database
          .select(database.plantObservations)
          .getSingle());
      expect(saved.plantStatus, DatabaseCodes.plantPossibleNonFaw);
      expect(saved.possibleNonFawEvidence, isTrue);
      expect(saved.uncertainEvidence, isTrue);
      expect(
        await (database.select(
          database.auditLogs,
        )..where((row) => row.action.equals('resume_check'))).get(),
        isNotEmpty,
      );
    },
  );

  test('restart recovers unfinished Plant 1 camera preview', () async {
    final fixture = await _createFixture(database);
    final repository = Station1WorkflowRepository(database);
    final evidenceRepository = EvidenceCaptureRepository(database);
    final root = await Directory.systemTemp.createTemp(
      'wormwise-resume-camera-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final evidence = EvidenceCaptureCoordinator(
      repository: evidenceRepository,
      storage: EvidenceStorageService(rootDirectory: () async => root),
    );
    Station1WorkflowProvider buildProvider() => Station1WorkflowProvider(
      assessmentId: fixture.assessment.id,
      workflowRepository: repository,
      assessmentRepository: AssessmentRepository(database),
      plantSaveService: AtomicPlantSaveService(
        database,
        evidenceRepository: evidenceRepository,
      ),
      evidenceCoordinator: evidence,
    );

    final first = buildProvider();
    await first.initialize();
    await first.prepareBlockOne();
    await first.saveStationUnavailable(
      reason: DatabaseCodes.stationNoCurrentFix,
    );
    expect(first.state, Station1ViewState.stationContextEvidence);
    await first.waiveEvidence(
      viewType: DatabaseCodes.evidenceViewStationContext,
      reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
    );
    await first.continueAfterStationContext();
    await first.beginTenConsecutivePlants();

    final source = File('${root.path}${Platform.pathSeparator}unfinished.jpg');
    final image = image_lib.Image(width: 64, height: 48);
    await source.writeAsBytes(image_lib.encodeJpg(image), flush: true);
    await first.stageEvidence(
      viewType: DatabaseCodes.evidenceViewWhorlOverview,
      sourcePath: source.path,
    );
    expect(
      first.currentEvidence!
          .mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!
          .storageState,
      DatabaseCodes.evidenceStorageStaged,
    );

    final resumed = buildProvider();
    await resumed.initialize();
    expect(resumed.state, Station1ViewState.resumeCheck);
    await resumed.submitResumeCheck(
      condition: ResumeCondition.unchanged,
      safeToContinue: true,
    );

    expect(resumed.state, Station1ViewState.plantCapture);
    expect(resumed.currentPlantPosition, 1);
    expect(
      resumed.currentEvidence!
          .mediaForView(DatabaseCodes.evidenceViewWhorlOverview)!
          .storageState,
      DatabaseCodes.evidenceStorageStaged,
    );
  });

  test(
    'capture-first completes all ten image sessions before manual confirmation',
    () async {
      final fixture = await _createFixture(database);
      final repository = Station1WorkflowRepository(database);
      final evidenceRepository = EvidenceCaptureRepository(database);
      final root = await Directory.systemTemp.createTemp(
        'wormwise-capture-first-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final evidence = EvidenceCaptureCoordinator(
        repository: evidenceRepository,
        storage: EvidenceStorageService(rootDirectory: () async => root),
      );
      final provider = Station1WorkflowProvider(
        assessmentId: fixture.assessment.id,
        workflowRepository: repository,
        assessmentRepository: AssessmentRepository(database),
        plantSaveService: AtomicPlantSaveService(
          database,
          evidenceRepository: evidenceRepository,
        ),
        evidenceCoordinator: evidence,
      );

      await provider.initialize();
      await provider.prepareBlockOne();
      await provider.saveStationUnavailable(
        reason: DatabaseCodes.stationNoCurrentFix,
      );
      await provider.waiveEvidence(
        viewType: DatabaseCodes.evidenceViewStationContext,
        reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
      );
      await provider.continueAfterStationContext();
      await provider.beginTenConsecutivePlants();
      expect(provider.state, Station1ViewState.plantCapture);

      for (var position = 1; position <= 10; position++) {
        expect(provider.currentPlantPosition, position);
        await provider.waiveEvidence(
          viewType: DatabaseCodes.evidenceViewWhorlOverview,
          reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
        );
        await provider.waiveEvidence(
          viewType: DatabaseCodes.evidenceViewCloseUp,
          reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
        );
        await provider.completeCurrentPlantCapture(
          const Duration(seconds: 20),
          3,
        );
      }

      expect(provider.state, Station1ViewState.stationReview);
      expect(provider.capturedPlantCount, 10);
      expect(provider.savedPlantCount, 0);
      expect(await database.select(database.plantObservations).get(), isEmpty);

      await provider.editPlant(1);
      expect(provider.state, Station1ViewState.plantEntry);
      await provider.savePlant(
        _plantInput(
          stationId: provider.snapshot!.station!.id,
          position: 1,
          status: DatabaseCodes.plantCurrentPositive,
          possibleNonFaw: false,
          uncertain: false,
          actorPersonId: fixture.assessment.evaluatorPersonId,
          evidenceSessionId: provider.currentEvidence!.session.id,
        ),
      );
      expect(provider.state, Station1ViewState.stationReview);
      expect(provider.savedPlantCount, 1);
    },
  );

  test(
    'treatment on resume safety-blocks without changing saved plants',
    () async {
      final fixture = await _createFixture(database);
      final repository = Station1WorkflowRepository(database);
      final prepared = await repository.prepareBlockOne(
        fixture.assessment,
        fixture.boundary,
      );
      final station = await repository.saveStationLocation(
        prepared: prepared,
        actorPersonId: fixture.assessment.evaluatorPersonId,
        notLocatedReason: DatabaseCodes.stationNoCurrentFix,
      );
      await AtomicPlantSaveService(database).saveVegetativePlant(
        _plantInput(
          stationId: station.id,
          position: 1,
          status: DatabaseCodes.plantNegative,
          possibleNonFaw: false,
          uncertain: false,
        ),
      );
      final provider = Station1WorkflowProvider(
        assessmentId: fixture.assessment.id,
        workflowRepository: repository,
        assessmentRepository: AssessmentRepository(database),
        plantSaveService: AtomicPlantSaveService(database),
      );
      await provider.initialize();

      await provider.submitResumeCheck(
        condition: ResumeCondition.treatmentOrFieldOperation,
        safeToContinue: false,
        note: 'Spray reported after Plant 1.',
      );

      expect(provider.state, Station1ViewState.safetyBlocked);
      expect(
        (await database.select(database.plantObservations).get()).length,
        1,
      );
      final assessment = await repository.assessmentById(fixture.assessment.id);
      expect(assessment.status, DatabaseCodes.safetyBlocked);
    },
  );

  test('editing a reviewed plant makes station review non-current', () async {
    final fixture = await _createFixture(database);
    final repository = Station1WorkflowRepository(database);
    final prepared = await repository.prepareBlockOne(
      fixture.assessment,
      fixture.boundary,
    );
    final station = await repository.saveStationLocation(
      prepared: prepared,
      actorPersonId: fixture.assessment.evaluatorPersonId,
      notLocatedReason: DatabaseCodes.stationUnsafeToWait,
    );
    final saves = AtomicPlantSaveService(database);
    for (var position = 1; position <= 10; position++) {
      await saves.saveVegetativePlant(
        _plantInput(
          stationId: station.id,
          position: position,
          status: DatabaseCodes.plantNegative,
          possibleNonFaw: false,
          uncertain: false,
        ),
      );
    }
    var snapshot = await repository.loadSnapshot(prepared);
    await repository.confirmStationReview(
      snapshot: snapshot,
      actorPersonId: fixture.assessment.evaluatorPersonId,
    );
    snapshot = await repository.loadSnapshot(prepared);
    expect(snapshot.reviewIsCurrent, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await saves.saveVegetativePlant(
      _plantInput(
        stationId: station.id,
        position: 4,
        status: DatabaseCodes.plantPossibleNonFaw,
        possibleNonFaw: true,
        uncertain: false,
      ),
    );

    snapshot = await repository.loadSnapshot(prepared);
    expect(snapshot.reviewIsCurrent, isFalse);
  });
}

class _Fixture {
  const _Fixture({required this.assessment, required this.boundary});

  final AssessmentRecord assessment;
  final BoundaryRecord boundary;
}

Future<_Fixture> _createFixture(
  AppDatabase database, {
  double areaHectares = 0.8,
  String confirmationStatus = 'user_confirmed',
  bool startAssessment = true,
  String growthStage = 'v3_v6',
}) async {
  final people = PeopleRepository(database);
  final evaluator = await people.findOrCreateEvaluator('Station 1 Evaluator');
  final field = await FieldRepository(database).createFieldWithBoundaryAndCycle(
    name: 'Station 1 Field',
    geometryGeojson: _polygon,
    areaHectares: areaHectares,
    boundarySourceMethod: 'draw',
    boundaryConfirmationStatus: confirmationStatus,
    ownerPersonId: evaluator.id,
    actorPersonId: evaluator.id,
  );
  final assessments = AssessmentRepository(database);
  var assessment = await assessments.createDraft(
    cropCycleId: field.cropCycle.id,
    boundaryVersionId: field.boundary.id,
    evaluatorPersonId: evaluator.id,
    assessmentMode: DatabaseCodes.modeVeV6,
    scoutingPattern: DatabaseCodes.patternW,
    growthStage: growthStage,
    protocolVersion: 'phase-3-test',
    formulaVersion: 'phase-3-test',
  );
  if (startAssessment) {
    await assessments.recordSafetyCheck(
      assessmentId: assessment.id,
      checkedByPersonId: evaluator.id,
      resultStatus: DatabaseCodes.noRecentTreatment,
    );
    await assessments.startAssessment(assessment.id);
    assessment = await assessments.assessmentById(assessment.id);
  }
  return _Fixture(assessment: assessment, boundary: field.boundary);
}

VegetativePlantSave _plantInput({
  required String stationId,
  required int position,
  required String status,
  required bool possibleNonFaw,
  required bool uncertain,
  String? actorPersonId,
  String? evidenceSessionId,
}) {
  return VegetativePlantSave(
    stationId: stationId,
    plantPosition: position,
    plantStatus: status,
    assessable: true,
    newestLeavesInspectedCount: 4,
    smallFreshWindowpanes: true,
    scraping: true,
    cuttingOrTearing: false,
    freshFrass: false,
    whorlFeedingSign: false,
    larvaVisible: false,
    larvalSize: 'none_seen',
    eggMassVisible: null,
    oldDamagePresent: true,
    possibleNonFawEvidence: possibleNonFaw,
    uncertainEvidence: uncertain,
    actorPersonId: actorPersonId,
    evidenceCaptureSessionId: evidenceSessionId,
    requiredEvidenceViewTypes: evidenceSessionId == null
        ? const {}
        : const {
            DatabaseCodes.evidenceViewWhorlOverview,
            DatabaseCodes.evidenceViewCloseUp,
          },
    requireCameraPhaseAEvidence: evidenceSessionId != null,
  );
}
