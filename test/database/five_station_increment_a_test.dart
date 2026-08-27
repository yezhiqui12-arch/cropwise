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
import 'package:wormwise/data/services/assessment_completion_validator.dart';
import 'package:wormwise/data/services/five_station_completion_service.dart';
import 'package:wormwise/providers/five_station_workflow_provider.dart';
import 'package:wormwise/providers/station1_workflow_provider.dart';
import 'package:wormwise/services/evidence_capture_coordinator.dart';
import 'package:wormwise/services/evidence_storage_service.dart';
import 'package:wormwise/services/station_evidence_policy.dart';

const _polygon =
    '{"type":"Polygon","coordinates":[[[121.0,17.0],[121.01,17.0],'
    '[121.01,17.01],[121.0,17.01],[121.0,17.0]]]}';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test(
    'Stations 1-5 and ten positions remain idempotently associated',
    () async {
      final fixture = await _createFixture(database);
      final workflow = ScoutingWorkflowRepository(database);
      final prepared = (await workflow.prepareRequiredBlocks(
        fixture.assessment,
        fixture.boundary,
      )).single;
      final evidence = EvidenceCaptureRepository(database);
      final saves = AtomicPlantSaveService(
        database,
        evidenceRepository: evidence,
      );

      for (var stationNumber = 1; stationNumber <= 5; stationNumber++) {
        final first = await workflow.saveStationLocation(
          prepared: prepared,
          stationNumber: stationNumber,
          actorPersonId: fixture.assessment.evaluatorPersonId,
          notLocatedReason: DatabaseCodes.stationNoCurrentFix,
        );
        final second = await workflow.saveStationLocation(
          prepared: prepared,
          stationNumber: stationNumber,
          actorPersonId: fixture.assessment.evaluatorPersonId,
          notLocatedReason: DatabaseCodes.stationNoCurrentFix,
        );
        expect(second.id, first.id);

        for (var position = 1; position <= 10; position++) {
          await saves.saveVegetativePlant(
            _plantInput(stationId: first.id, position: position),
          );
          await saves.saveVegetativePlant(
            _plantInput(stationId: first.id, position: position),
          );
        }
      }

      final stations = await database.select(database.stations).get();
      final plants = await database.select(database.plantObservations).get();
      expect(stations.length, 5);
      expect(plants.length, 50);
      for (final station in stations) {
        final stationPlants = plants
            .where((plant) => plant.stationId == station.id)
            .toList();
        expect(stationPlants.length, 10);
        expect(
          stationPlants.map((plant) => plant.sequenceNumber).toSet(),
          Set<int>.from(List<int>.generate(10, (index) => index + 1)),
        );
      }
    },
  );

  test(
    'camera-first policy is versioned and save rolls back when required evidence is absent',
    () async {
      final fixture = await _createFixture(database);
      final workflow = ScoutingWorkflowRepository(database);
      final prepared = (await workflow.prepareRequiredBlocks(
        fixture.assessment,
        fixture.boundary,
      )).single;
      final station = await workflow.saveStationLocation(
        prepared: prepared,
        stationNumber: 2,
        actorPersonId: fixture.assessment.evaluatorPersonId,
        notLocatedReason: DatabaseCodes.stationNoCurrentFix,
      );
      final evidence = EvidenceCaptureRepository(database);
      final session = await evidence.ensurePlantSession(
        assessmentId: fixture.assessment.id,
        stationId: station.id,
        plantPosition: 1,
        actorPersonId: fixture.assessment.evaluatorPersonId,
        requirementsVersion: StationEvidencePolicy
            .cameraFirstOverviewConditional
            .requirementsVersion,
      );
      expect(
        session.requirementsVersion,
        DatabaseCodes.evidencePolicyCameraFirstOverviewConditionalV1,
      );
      final saves = AtomicPlantSaveService(
        database,
        evidenceRepository: evidence,
      );
      final positive = _plantInput(
        stationId: station.id,
        position: 1,
        actorPersonId: fixture.assessment.evaluatorPersonId,
        evidenceSessionId: session.id,
        currentEvidence: true,
      );

      await expectLater(saves.saveVegetativePlant(positive), throwsStateError);
      expect(await database.select(database.plantObservations).get(), isEmpty);
      expect(
        await database.select(database.vegetativeObservations).get(),
        isEmpty,
      );

      await evidence.waiveRequiredView(
        session: session,
        viewType: DatabaseCodes.evidenceViewWhorlOverview,
        reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      final saved = await saves.saveVegetativePlant(positive);
      expect(saved.plant.stationId, station.id);
      expect(saved.plant.sequenceNumber, 1);
      expect(saved.plant.currentFawEvidence, isTrue);
      final bundle = await evidence.loadBundle(session.id);
      expect(bundle.session.plantObservationId, saved.plant.id);
    },
  );

  test(
    'restart resumes at Station 3 after two current station reviews',
    () async {
      final fixture = await _createFixture(database);
      final workflow = ScoutingWorkflowRepository(database);
      final prepared = (await workflow.prepareRequiredBlocks(
        fixture.assessment,
        fixture.boundary,
      )).single;
      final evidence = EvidenceCaptureRepository(database);
      final saves = AtomicPlantSaveService(
        database,
        evidenceRepository: evidence,
      );
      for (var stationNumber = 1; stationNumber <= 2; stationNumber++) {
        await _completeStation(
          database: database,
          workflow: workflow,
          evidence: evidence,
          saves: saves,
          fixture: fixture,
          prepared: prepared,
          stationNumber: stationNumber,
        );
      }

      final coordinator = EvidenceCaptureCoordinator(
        repository: evidence,
        storage: EvidenceStorageService(),
      );
      final provider = FiveStationWorkflowProvider(
        assessmentId: fixture.assessment.id,
        workflowRepository: workflow,
        assessmentRepository: AssessmentRepository(database),
        plantSaveService: saves,
        completionService: FiveStationCompletionService(database),
        evidenceCoordinator: coordinator,
      );
      await provider.initialize();

      expect(provider.stationNumber, 3);
      expect(provider.state, Station1ViewState.resumeCheck);
      await provider.submitResumeCheck(
        condition: ResumeCondition.unchanged,
        safeToContinue: true,
      );
      expect(provider.state, Station1ViewState.stationLocation);
      expect(provider.stationNumber, 3);

      await provider.saveStationUnavailable(
        reason: DatabaseCodes.stationNoCurrentFix,
      );
      expect(provider.state, Station1ViewState.stationContextEvidence);
      await provider.waiveEvidence(
        viewType: DatabaseCodes.evidenceViewStationContext,
        reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
      );
      await provider.continueAfterStationContext();
      expect(provider.state, Station1ViewState.plantCapture);

      for (var position = 1; position <= 10; position++) {
        expect(provider.currentPlantPosition, position);
        await provider.waiveEvidence(
          viewType: DatabaseCodes.evidenceViewWhorlOverview,
          reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
        );
        await provider.completeCurrentPlantCapture(Duration.zero, 3);
      }
      expect(provider.state, Station1ViewState.stationReview);
      expect(provider.snapshot!.plants, isEmpty);

      for (var position = 1; position <= 10; position++) {
        await provider.editPlant(position);
        await provider.saveReviewedPlant(
          _plantInput(
            stationId: provider.snapshot!.station!.id,
            position: position,
            actorPersonId: fixture.assessment.evaluatorPersonId,
            evidenceSessionId: provider.currentEvidence!.session.id,
            requiredViews: const {DatabaseCodes.evidenceViewWhorlOverview},
          ),
          DatabaseCodes.evidenceReviewSufficient,
        );
        expect(provider.state, Station1ViewState.stationReview);
      }
      expect(provider.state, Station1ViewState.stationReview);
      await provider.confirmStationReview();
      expect(provider.state, Station1ViewState.betweenStations);
      await provider.continueToNextStation();
      expect(provider.stationNumber, 4);
      expect(provider.state, Station1ViewState.stationLocation);
    },
  );

  test(
    'block completion validates all 50 associated plants and every current review',
    () async {
      final fixture = await _createFixture(database);
      final workflow = ScoutingWorkflowRepository(database);
      final prepared = (await workflow.prepareRequiredBlocks(
        fixture.assessment,
        fixture.boundary,
      )).single;
      final evidence = EvidenceCaptureRepository(database);
      final saves = AtomicPlantSaveService(
        database,
        evidenceRepository: evidence,
      );
      final completion = FiveStationCompletionService(database);

      for (var stationNumber = 1; stationNumber <= 4; stationNumber++) {
        await _completeStation(
          database: database,
          workflow: workflow,
          evidence: evidence,
          saves: saves,
          fixture: fixture,
          prepared: prepared,
          stationNumber: stationNumber,
        );
      }
      final incomplete = await completion.validateBlock(prepared.run.id);
      expect(incomplete.isValid, isFalse);
      expect(
        incomplete.issues.map((issue) => issue.code),
        contains('station_count'),
      );
      await expectLater(
        completion.completeBlock(prepared.run.id),
        throwsA(isA<AssessmentValidationException>()),
      );

      await _completeStation(
        database: database,
        workflow: workflow,
        evidence: evidence,
        saves: saves,
        fixture: fixture,
        prepared: prepared,
        stationNumber: 5,
      );
      final complete = await completion.validateBlock(prepared.run.id);
      expect(complete.issues, isEmpty);
      final provider = FiveStationWorkflowProvider(
        assessmentId: fixture.assessment.id,
        workflowRepository: workflow,
        assessmentRepository: AssessmentRepository(database),
        plantSaveService: saves,
        completionService: completion,
        evidenceCoordinator: EvidenceCaptureCoordinator(
          repository: evidence,
          storage: EvidenceStorageService(),
        ),
      );
      await provider.initialize();
      expect(provider.state, Station1ViewState.resumeCheck);
      await provider.submitResumeCheck(
        condition: ResumeCondition.unchanged,
        safeToContinue: true,
      );
      expect(provider.state, Station1ViewState.blockReview);
      await provider.openStationFromBlockReview(3);
      expect(provider.state, Station1ViewState.stationReview);
      await provider.confirmStationReview();
      expect(provider.state, Station1ViewState.blockReview);

      await completion.completeBlock(prepared.run.id);

      final run = await (database.select(
        database.assessmentBlockRuns,
      )..where((row) => row.id.equals(prepared.run.id))).getSingle();
      final assessment = await workflow.assessmentById(fixture.assessment.id);
      expect(run.status, DatabaseCodes.completed);
      expect(assessment.status, DatabaseCodes.completed);
      final metrics = await database.select(database.metricResults).get();
      expect(metrics.map((row) => row.metricCode).toSet(), {
        DatabaseCodes.vegetativeCurrentInfestationPercent,
        DatabaseCodes.smallFreshWindowpanePercent,
        DatabaseCodes.infestedWhorlPercent,
      });
      expect(metrics.every((row) => row.denominator == 50), isTrue);
    },
  );

  test(
    'one completed block cannot complete an assessment with another required block',
    () async {
      final fixture = await _createFixture(database, areaHectares: 1.6);
      final fields = FieldRepository(database);
      await fields.addBlock(
        cropCycleId: fixture.assessment.cropCycleId,
        boundaryVersionId: fixture.boundary.id,
        blockNumber: 1,
        geometryGeojson: _polygon,
        areaHectares: 0.8,
        separationReason: 'existing_confirmed_management_block',
        isProvisional: false,
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      await fields.addBlock(
        cropCycleId: fixture.assessment.cropCycleId,
        boundaryVersionId: fixture.boundary.id,
        blockNumber: 2,
        geometryGeojson: _polygon,
        areaHectares: 0.8,
        separationReason: 'existing_confirmed_management_block',
        isProvisional: false,
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      final workflow = ScoutingWorkflowRepository(database);
      final prepared = await workflow.prepareRequiredBlocks(
        fixture.assessment,
        fixture.boundary,
      );
      expect(prepared.length, 2);
      final evidence = EvidenceCaptureRepository(database);
      final saves = AtomicPlantSaveService(
        database,
        evidenceRepository: evidence,
      );
      for (var stationNumber = 1; stationNumber <= 5; stationNumber++) {
        await _completeStation(
          database: database,
          workflow: workflow,
          evidence: evidence,
          saves: saves,
          fixture: fixture,
          prepared: prepared.first,
          stationNumber: stationNumber,
        );
      }

      await FiveStationCompletionService(
        database,
      ).completeBlock(prepared.first.run.id);
      final assessment = await workflow.assessmentById(fixture.assessment.id);
      final secondRun = await (database.select(
        database.assessmentBlockRuns,
      )..where((row) => row.id.equals(prepared.last.run.id))).getSingle();
      expect(assessment.status, DatabaseCodes.inProgress);
      expect(secondRun.status, DatabaseCodes.inProgress);
    },
  );

  test(
    'debug shortcut fills only missing positions with clearly synthetic isolated records',
    () async {
      final fixture = await _createFixture(database);
      final workflow = ScoutingWorkflowRepository(database);
      final evidence = EvidenceCaptureRepository(database);
      final provider = FiveStationWorkflowProvider(
        assessmentId: fixture.assessment.id,
        workflowRepository: workflow,
        assessmentRepository: AssessmentRepository(database),
        plantSaveService: AtomicPlantSaveService(
          database,
          evidenceRepository: evidence,
        ),
        completionService: FiveStationCompletionService(database),
        evidenceCoordinator: EvidenceCaptureCoordinator(
          repository: evidence,
          storage: EvidenceStorageService(),
        ),
        testMode: true,
        debugFeaturesEnabled: true,
      );
      await provider.initialize();
      expect(provider.state, Station1ViewState.blockPreparation);
      await provider.prepareRequiredBlocks();

      await provider.fillRemainingTestPlants();

      expect(provider.state, Station1ViewState.stationReview);
      expect(provider.snapshot!.plants, hasLength(10));
      expect(
        provider.snapshot!.plants.every(
          (item) =>
              item.plant.evaluatorNotes?.startsWith('[TEST DATA]') == true,
        ),
        isTrue,
      );
      final plantBundles = provider.stationEvidenceBundles
          .where(
            (bundle) =>
                bundle.session.scopeType == DatabaseCodes.evidenceScopePlant,
          )
          .toList();
      expect(plantBundles, hasLength(10));
      expect(
        plantBundles.every(
          (bundle) =>
              bundle.session.requirementsVersion ==
              DatabaseCodes.evidencePolicyCameraFirstOverviewConditionalV1,
        ),
        isTrue,
      );
      expect(
        plantBundles
            .where(
              (bundle) => bundle.isViewSatisfied(
                DatabaseCodes.evidenceViewWhorlOverview,
              ),
            )
            .length,
        8,
      );
      expect(provider.plantEvidenceReviews, hasLength(8));
      expect(
        provider.plantEvidenceReviews.values.every(
          (review) =>
              review.isCurrent &&
              review.status == DatabaseCodes.evidenceReviewSufficient,
        ),
        isTrue,
      );
      expect(await database.select(database.metricResults).get(), isEmpty);

      await provider.completeTestStation();
      expect(provider.state, Station1ViewState.betweenStations);
      expect(provider.completedStationNumbers, contains(1));
      expect(provider.completedStationLocations, isNot(contains(1)));
      provider.dispose();
    },
  );

  test(
    'debug all-station shortcut bypasses camera and forms for Stations 1-5',
    () async {
      final fixture = await _createFixture(database);
      final workflow = ScoutingWorkflowRepository(database);
      final evidence = EvidenceCaptureRepository(database);
      final provider = FiveStationWorkflowProvider(
        assessmentId: fixture.assessment.id,
        workflowRepository: workflow,
        assessmentRepository: AssessmentRepository(database),
        plantSaveService: AtomicPlantSaveService(
          database,
          evidenceRepository: evidence,
        ),
        completionService: FiveStationCompletionService(database),
        evidenceCoordinator: EvidenceCaptureCoordinator(
          repository: evidence,
          storage: EvidenceStorageService(),
        ),
        testMode: true,
        debugFeaturesEnabled: true,
      );
      await provider.initialize();
      expect(provider.state, Station1ViewState.blockPreparation);

      await provider.completeAllRemainingTestStations();

      expect(provider.stationNumber, 5);
      expect(provider.state, Station1ViewState.blockReview);
      expect(provider.blockSnapshot!.allStationsReviewed, isTrue);
      expect(await database.select(database.stations).get(), hasLength(5));
      expect(
        await database.select(database.plantObservations).get(),
        hasLength(50),
      );
      expect(
        await database.select(database.vegetativeObservations).get(),
        hasLength(50),
      );
      expect(
        await database.select(database.evidenceCaptureSessions).get(),
        hasLength(55),
      );
      expect(await database.select(database.evidenceMedia).get(), isEmpty);
      final stationReviews = (await database.select(database.auditLogs).get())
          .where((audit) => audit.action == 'review_confirmed')
          .toList();
      expect(stationReviews, hasLength(5));
      expect(await database.select(database.metricResults).get(), isEmpty);
      provider.dispose();
    },
  );

  test(
    'VE-V2 progresses through five isolated stations and completes the block',
    () async {
      final fixture = await _createFixture(database, growthStage: 've');
      final workflow = ScoutingWorkflowRepository(database);
      final evidence = EvidenceCaptureRepository(database);
      final completion = FiveStationCompletionService(database);
      FiveStationWorkflowProvider buildProvider() =>
          FiveStationWorkflowProvider(
            assessmentId: fixture.assessment.id,
            workflowRepository: workflow,
            assessmentRepository: AssessmentRepository(database),
            plantSaveService: AtomicPlantSaveService(
              database,
              evidenceRepository: evidence,
            ),
            completionService: completion,
            veV2SaveService: AtomicVeV2SaveService(database),
            evidenceCoordinator: EvidenceCaptureCoordinator(
              repository: evidence,
              storage: EvidenceStorageService(),
            ),
            testMode: true,
            debugFeaturesEnabled: true,
          );
      var provider = buildProvider();
      await provider.initialize();
      expect(provider.state, Station1ViewState.blockPreparation);

      await provider.completeTestStation();
      expect(provider.state, Station1ViewState.betweenStations);
      expect(provider.stationNumber, 1);
      await provider.navigateBackWithinWorkflow();
      expect(provider.state, Station1ViewState.veV2StationReview);
      await provider.continueToNextStation();
      expect(provider.stationNumber, 2);
      provider.dispose();

      provider = buildProvider();
      await provider.initialize();
      expect(provider.state, Station1ViewState.resumeCheck);
      await provider.submitResumeCheck(
        condition: ResumeCondition.unchanged,
        safeToContinue: true,
      );
      expect(provider.stationNumber, 2);
      expect(provider.state, Station1ViewState.stationLocation);

      await provider.completeAllRemainingTestStations();

      expect(provider.stationNumber, 5);
      expect(provider.state, Station1ViewState.blockReview);
      expect(provider.blockSnapshot!.allStationsReviewed, isTrue);
      expect(await database.select(database.stations).get(), hasLength(5));
      expect(
        await database.select(database.veV2StationInspections).get(),
        hasLength(5),
      );
      expect(
        await database.select(database.plantingUnitObservations).get(),
        hasLength(50),
      );
      expect(
        await database.select(database.plantObservations).get(),
        hasLength(50),
      );
      expect(
        (await completion.validateBlock(provider.prepared!.run.id)).issues,
        isEmpty,
      );

      await provider.openStationFromBlockReview(3);
      expect(provider.state, Station1ViewState.veV2StationReview);
      await provider.navigateBackWithinWorkflow();
      expect(provider.state, Station1ViewState.blockReview);

      await provider.completeCurrentBlock();
      expect(provider.state, Station1ViewState.samplingComplete);
      expect(
        (await workflow.assessmentById(fixture.assessment.id)).status,
        DatabaseCodes.completed,
      );
      provider.dispose();
    },
  );

  test(
    'Back moves through station views without changing persisted records',
    () async {
      final fixture = await _createFixture(database);
      final workflow = ScoutingWorkflowRepository(database);
      final evidence = EvidenceCaptureRepository(database);
      final provider = FiveStationWorkflowProvider(
        assessmentId: fixture.assessment.id,
        workflowRepository: workflow,
        assessmentRepository: AssessmentRepository(database),
        plantSaveService: AtomicPlantSaveService(
          database,
          evidenceRepository: evidence,
        ),
        completionService: FiveStationCompletionService(database),
        evidenceCoordinator: EvidenceCaptureCoordinator(
          repository: evidence,
          storage: EvidenceStorageService(),
        ),
        testMode: true,
        debugFeaturesEnabled: true,
      );
      await provider.initialize();
      await provider.completeTestStation();
      expect(provider.state, Station1ViewState.betweenStations);

      final plantIds = (await database.select(database.plantObservations).get())
          .map((plant) => plant.id)
          .toSet();
      final mediaCount =
          (await database.select(database.evidenceMedia).get()).length;

      await provider.navigateBackWithinWorkflow();
      expect(provider.state, Station1ViewState.stationReview);
      await provider.editPlant(4);
      expect(provider.state, Station1ViewState.plantEntry);
      await provider.navigateBackWithinWorkflow();
      expect(provider.state, Station1ViewState.stationReview);

      await provider.navigateBackWithinWorkflow();
      expect(provider.state, Station1ViewState.plantCapture);
      expect(provider.currentPlantPosition, 10);
      await provider.navigateBackWithinWorkflow();
      expect(provider.state, Station1ViewState.plantCapture);
      expect(provider.currentPlantPosition, 9);

      expect(
        (await database.select(database.plantObservations).get())
            .map((plant) => plant.id)
            .toSet(),
        plantIds,
      );
      expect(
        (await database.select(database.evidenceMedia).get()).length,
        mediaCount,
      );
      provider.dispose();
    },
  );

  test('production provider rejects debug shortcuts', () async {
    final evidence = EvidenceCaptureRepository(database);
    final provider = FiveStationWorkflowProvider(
      assessmentId: 'production-assessment',
      workflowRepository: ScoutingWorkflowRepository(database),
      assessmentRepository: AssessmentRepository(database),
      plantSaveService: AtomicPlantSaveService(
        database,
        evidenceRepository: evidence,
      ),
      completionService: FiveStationCompletionService(database),
      evidenceCoordinator: EvidenceCaptureCoordinator(
        repository: evidence,
        storage: EvidenceStorageService(),
      ),
      testMode: false,
      debugFeaturesEnabled: true,
    );

    await expectLater(provider.fillRemainingTestPlants(), throwsStateError);
    await expectLater(provider.completeTestStation(), throwsStateError);
    await expectLater(
      provider.completeAllRemainingTestStations(),
      throwsStateError,
    );
    provider.dispose();
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
  String growthStage = 'v3_v6',
}) async {
  final evaluator = await PeopleRepository(
    database,
  ).findOrCreateEvaluator('Five Station Evaluator');
  final field = await FieldRepository(database).createFieldWithBoundaryAndCycle(
    name: 'Five Station Field',
    geometryGeojson: _polygon,
    areaHectares: areaHectares,
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
    assessmentMode: DatabaseCodes.modeVeV6,
    scoutingPattern: DatabaseCodes.patternW,
    growthStage: growthStage,
    protocolVersion: 'increment-a-test',
    formulaVersion: 'increment-a-test',
  );
  await assessments.recordSafetyCheck(
    assessmentId: assessment.id,
    checkedByPersonId: evaluator.id,
    resultStatus: DatabaseCodes.noRecentTreatment,
  );
  await assessments.startAssessment(assessment.id);
  assessment = await assessments.assessmentById(assessment.id);
  return _Fixture(assessment: assessment, boundary: field.boundary);
}

Future<void> _completeStation({
  required AppDatabase database,
  required ScoutingWorkflowRepository workflow,
  required EvidenceCaptureRepository evidence,
  required AtomicPlantSaveService saves,
  required _Fixture fixture,
  required PreparedScoutingRun prepared,
  required int stationNumber,
}) async {
  final actorId = fixture.assessment.evaluatorPersonId;
  final station = await workflow.saveStationLocation(
    prepared: prepared,
    stationNumber: stationNumber,
    actorPersonId: actorId,
    notLocatedReason: DatabaseCodes.stationNoCurrentFix,
  );
  final context = await evidence.ensureStationContextSession(
    assessmentId: fixture.assessment.id,
    stationId: station.id,
    actorPersonId: actorId,
  );
  await evidence.waiveRequiredView(
    session: context,
    viewType: DatabaseCodes.evidenceViewStationContext,
    reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
    actorPersonId: actorId,
  );
  await evidence.completeStationContext(
    session: context,
    actorPersonId: actorId,
  );

  final policy = StationEvidencePolicy.forStation(stationNumber);
  for (var position = 1; position <= 10; position++) {
    final session = await evidence.ensurePlantSession(
      assessmentId: fixture.assessment.id,
      stationId: station.id,
      plantPosition: position,
      actorPersonId: actorId,
      requirementsVersion: policy.requirementsVersion,
    );
    final requiredViews = const {DatabaseCodes.evidenceViewWhorlOverview};
    for (final view in requiredViews) {
      await evidence.waiveRequiredView(
        session: session,
        viewType: view,
        reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
        actorPersonId: actorId,
      );
    }
    final saved = await saves.saveVegetativePlant(
      _plantInput(
        stationId: station.id,
        position: position,
        actorPersonId: actorId,
        evidenceSessionId: session.id,
        requiredViews: requiredViews,
      ),
    );
    final attached = await evidence.loadBundle(session.id);
    expect(attached.session.plantObservationId, saved.plant.id);
    await evidence.recordPlantEvidenceReview(
      bundle: attached,
      status: DatabaseCodes.evidenceReviewSufficient,
      actorPersonId: actorId,
    );
  }
  final snapshot = await workflow.loadStationSnapshot(
    prepared,
    stationNumber: stationNumber,
  );
  await workflow.confirmStationReview(
    snapshot: snapshot,
    actorPersonId: actorId,
  );
}

VegetativePlantSave _plantInput({
  required String stationId,
  required int position,
  String? actorPersonId,
  String? evidenceSessionId,
  Set<String> requiredViews = const {},
  bool currentEvidence = false,
}) {
  return VegetativePlantSave(
    stationId: stationId,
    plantPosition: position,
    plantStatus: currentEvidence
        ? DatabaseCodes.plantCurrentPositive
        : DatabaseCodes.plantNegative,
    assessable: true,
    newestLeavesInspectedCount: 3,
    smallFreshWindowpanes: currentEvidence,
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
    actorPersonId: actorPersonId,
    evidenceCaptureSessionId: evidenceSessionId,
    requiredEvidenceViewTypes: currentEvidence
        ? const {DatabaseCodes.evidenceViewWhorlOverview}
        : requiredViews,
    requireCameraPhaseAEvidence: evidenceSessionId != null,
  );
}
