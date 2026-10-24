import 'package:drift/native.dart';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/assessment_history_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/services/automatic_screening_save_service.dart';
import 'package:wormwise/data/services/scouting_completion_service.dart';
import 'package:wormwise/data/services/assessment_validation_types.dart';
import 'package:wormwise/models/automatic_screening.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import 'package:wormwise/services/scouting_sampling_protocol.dart';
import 'package:wormwise/services/assessment_protocol_selector.dart';
import 'package:wormwise/data/repositories/scouting_route_repository.dart';
import 'package:wormwise/data/services/atomic_plant_save_service.dart';
import 'package:wormwise/data/services/atomic_ve_v2_save_service.dart';
import 'package:wormwise/providers/scouting_workflow_provider.dart';
import 'package:wormwise/providers/scouting_workflow_state.dart';
import 'package:wormwise/services/evidence_capture_coordinator.dart';
import 'package:wormwise/services/evidence_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  Future<({AssessmentRecord assessment, BoundaryRecord boundary})> fixture(
    String version, {
    String stage = 'v3_v6',
  }) async {
    final person = await PeopleRepository(
      db,
    ).findOrCreateEvaluator('DA test evaluator');
    final field = await FieldRepository(db).createFieldWithBoundaryAndCycle(
      name: 'DA field',
      geometryGeojson:
          '{"type":"Polygon","coordinates":[[[121,17],[121.001,17],[121.001,17.001],[121,17.001],[121,17]]]}',
      areaHectares: .8,
      boundarySourceMethod: 'draw',
      boundaryConfirmationStatus: 'user_confirmed',
      ownerPersonId: person.id,
      actorPersonId: person.id,
    );
    final repo = AssessmentRepository(db);
    final draft = await repo.createDraft(
      cropCycleId: field.cropCycle.id,
      boundaryVersionId: field.boundary!.id,
      evaluatorPersonId: person.id,
      assessmentMode: AssessmentProtocolSelector.assessmentModeFor(stage),
      scoutingPattern: version == ScoutingSamplingProtocol.daVersion
          ? ScoutingSamplingProtocol.daPattern
          : 'w',
      growthStage: stage,
      protocolVersion: version,
      formulaVersion: '1.0-draft',
    );
    await repo.recordSafetyCheck(
      assessmentId: draft.id,
      checkedByPersonId: person.id,
      resultStatus: DatabaseCodes.noRecentTreatment,
    );
    await repo.startAssessment(draft.id);
    return (
      assessment: await repo.assessmentById(draft.id),
      boundary: field.boundary!,
    );
  }

  test(
    'DA completes exactly twenty individual plants and preserves pending expert confirmation',
    () async {
      final f = await fixture(ScoutingSamplingProtocol.daVersion);
      final repo = ScoutingWorkflowRepository(db),
          evidence = EvidenceCaptureRepository(db);
      final prepared = (await repo.prepareRequiredBlocks(
        f.assessment,
        f.boundary,
      )).single;
      expect((await repo.loadBlockSnapshot(prepared)).stations, hasLength(20));
      final actor = f.assessment.evaluatorPersonId;
      for (var number = 1; number <= 20; number++) {
        final station = await repo.saveStationLocation(
          prepared: prepared,
          actorPersonId: actor,
          stationNumber: number,
          notLocatedReason: DatabaseCodes.stationNoCurrentFix,
        );
        final session = await evidence.ensurePlantSession(
          assessmentId: f.assessment.id,
          stationId: station.id,
          plantPosition: 1,
          actorPersonId: actor,
          requirementsVersion:
              DatabaseCodes.evidencePolicyCameraFirstOverviewConditionalV1,
        );
        await evidence.waiveRequiredView(
          session: session,
          viewType: DatabaseCodes.evidenceViewWhorlOverview,
          reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
          actorPersonId: actor,
        );
        await evidence.completePlantCapture(
          session: session,
          actorPersonId: actor,
          pilotActiveDurationMs: 0,
          newestLeavesInspectedCount: 3,
          requiredViewTypes: {DatabaseCodes.evidenceViewWhorlOverview},
        );
        await AutomaticScreeningSaveService(db).save(
          stationId: station.id,
          position: 1,
          growthStage: 'v3_v6',
          screening: AutomaticScreening(
            PlantDiagnosisResult(
              isInfested: number <= 4,
              pestLabel: 'screen',
              confidenceScore: .9,
              suggestedPlantStatus: DatabaseCodes.plantNegative,
              classificationLabel: number <= 4 ? 'FAW damage' : 'No FAW damage',
            ),
          ),
          actorId: actor,
          sessionId: session.id,
          primaryView: DatabaseCodes.evidenceViewWhorlOverview,
        );
        final snapshot = await repo.loadStationSnapshot(
          prepared,
          stationNumber: number,
        );
        expect(snapshot.requiredPlantCount, 1);
        await repo.confirmStationReview(
          snapshot: snapshot,
          actorPersonId: actor,
          manualConfirmationDeferred: true,
        );
        if (number == 19)
          expect(
            (await ScoutingCompletionService(
              db,
            ).validateBlock(prepared.run.id)).isValid,
            isFalse,
          );
      }
      final validation = await ScoutingCompletionService(
        db,
      ).validateBlock(prepared.run.id);
      expect(validation.issues, isEmpty);
      final plants = await db.select(db.plantObservations).get();
      expect(plants, hasLength(20));
      expect(
        plants.where(
          (p) => AutomaticScreening.parse(p.wholePlantContextNote)!.positive,
        ),
        hasLength(4),
      );
      expect(plants.every((p) => p.sequenceNumber == 1), isTrue);
      await ScoutingCompletionService(db).completeBlock(prepared.run.id);
      expect(
        (await repo.assessmentById(f.assessment.id)).status,
        DatabaseCodes.completed,
      );
      final history = await AssessmentHistoryRepository(
        db,
      ).loadDetail(f.assessment.id);
      expect(history, isNotNull);
      expect(history!.stations, hasLength(20));
      expect(history.stations.last.stationNumber, 20);
      expect(history.stations.expand((s) => s.plants), hasLength(20));
    },
  );
  test('retired patterns cannot prepare a new sampling run', () async {
    final f = await fixture('legacy-test');
    final repo = ScoutingWorkflowRepository(db);
    await expectLater(
      repo.prepareRequiredBlocks(f.assessment, f.boundary),
      throwsStateError,
    );
    expect(await db.select(db.assessmentBlockRuns).get(), isEmpty);
    expect(
      await AssessmentRepository(db).assessmentById(f.assessment.id),
      isNotNull,
    );
    await expectLater(
      ScoutingCompletionService(db).completeAssessment(f.assessment.id),
      throwsA(isA<AssessmentValidationException>()),
    );
  });
  for (final stage in ['v3_v6', 've', 'vt_r2', 'r3_r6']) {
    test(
      'guided $stage resumes a saved photo, saves one plant, and travels to Plant 2',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'da_walk_flow_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final source = File('${directory.path}/source.jpg');
        await source.writeAsBytes(
          img.encodeJpg(img.Image(width: 96, height: 96)),
        );
        final f = await fixture(
          ScoutingSamplingProtocol.daVersion,
          stage: stage,
        );
        final evidence = EvidenceCaptureRepository(db),
            workflow = ScoutingWorkflowRepository(db);
        ScoutingWorkflowProvider provider() => ScoutingWorkflowProvider(
          assessmentId: f.assessment.id,
          workflowRepository: workflow,
          assessmentRepository: AssessmentRepository(db),
          plantSaveService: AtomicPlantSaveService(
            db,
            evidenceRepository: evidence,
          ),
          completionService: ScoutingCompletionService(db),
          veV2SaveService: AtomicVeV2SaveService(db),
          routeRepository: ScoutingRouteRepository(db),
          evidenceCoordinator: EvidenceCaptureCoordinator(
            repository: evidence,
            storage: EvidenceStorageService(
              rootDirectory: () async => directory,
            ),
          ),
          computerVisionService: _ScreeningService(),
        );
        final first = provider();
        await first.initialize();
        await first.prepareRequiredBlocks();
        expect(first.state, Station1ViewState.stationTravel);
        expect(first.routePlan!.targets, hasLength(20));
        await first.confirmReachedActiveStation();
        await first.selectCapturePlant(1, analyzePrevious: false);
        final media = await first.stageEvidence(
          viewType: first.primaryEvidenceViewType,
          sourcePath: source.path,
          deleteSourceAfterCopy: false,
          fromCamera: true,
        );
        await first.acceptEvidence(media);
        final oldPlan = first.routePlan!.copyWith(
          algorithmVersion: 'da_manual_scattered_points_v1',
          targets: [
            first.routePlan!.targets.first,
            for (var i = 1; i < 20; i++)
              first.routePlan!.targets[20 - i].copyWith(stationNumber: i + 1),
          ],
        );
        await ScoutingRouteRepository(db).saveGeneratedPlan(
          oldPlan,
          actorPersonId: f.assessment.evaluatorPersonId,
        );
        first.dispose();
        final resumed = provider();
        await resumed.initialize();
        expect(
          resumed.routePlan!.algorithmVersion,
          ScoutingSamplingProtocol.daAlgorithm,
        );
        expect(
          resumed.routePlan!.targetFor(1).location,
          oldPlan.targetFor(1).location,
        );
        expect(
          resumed.routePlan!.targets.map((t) => t.location),
          unorderedEquals(oldPlan.targets.map((t) => t.location)),
        );
        expect(
          (await ScoutingRouteRepository(db).loadOrCreateDraft(
            assessment: f.assessment,
            prepared: resumed.prepared!,
          )).algorithmVersion,
          ScoutingSamplingProtocol.daAlgorithm,
        );
        expect(resumed.bundleForPlant(1)!.media, hasLength(1));
        await resumed.submitResumeCheck(
          condition: ResumeCondition.unchanged,
          safeToContinue: true,
        );
        await resumed.selectCapturePlant(1, analyzePrevious: false);
        await resumed.analyzeDaActivePlantForPreview();
        final preview = await resumed.loadDaPlantDetails(1);
        expect(preview.samplingStatus, 'In progress');
        expect(preview.diagnosis?.classificationLabel, 'No FAW damage');
        expect(resumed.stationNumber, 1);
        expect(resumed.completedDaPlantCount, 0);
        final beforeNotes =
            (await db.select(db.plantObservations).get()).single;
        await resumed.saveDaPlantNotesAndReturn('Predators seen: 2.');
        final afterNotes = (await db.select(db.plantObservations).get()).single;
        expect(afterNotes.evaluatorNotes, 'Predators seen: 2.');
        expect(
          afterNotes.wholePlantContextNote,
          beforeNotes.wholePlantContextNote,
        );
        expect(afterNotes.plantStatus, beforeNotes.plantStatus);
        await resumed.finishDaPlantAndContinue();
        expect(
          (await EvidenceCaptureRepository(db).loadPilotWorkloadAuditSummary(
            afterNotes.stationId,
          )).inspectedLeavesByPlant,
          isEmpty,
        );
        expect(resumed.stationNumber, 2);
        expect(resumed.state, Station1ViewState.stationTravel);
        expect(resumed.completedDaPlantCount, 1);
        final activeNumber = resumed.stationNumber;
        final state = resumed.state;
        final sampled = await resumed.loadDaPlantDetails(1);
        expect(sampled.samplingStatus, 'Sampled');
        expect(sampled.photos.single.id, media.id);
        expect(sampled.diagnosis?.classificationLabel, 'No FAW damage');
        expect(sampled.plant?.evaluatorNotes, 'Predators seen: 2.');
        final pending = await resumed.loadDaPlantDetails(12);
        expect(pending.samplingStatus, 'Not sampled');
        expect(pending.photos, isEmpty);
        expect(pending.diagnosis, isNull);
        expect(resumed.stationNumber, activeNumber);
        expect(resumed.state, state);
        expect(await db.select(db.plantObservations).get(), hasLength(1));
        expect(
          (await db.select(db.plantObservations).get()).single.evaluatorNotes,
          'Predators seen: 2.',
        );
        resumed.dispose();
      },
    );
  }
}

class _ScreeningService implements FawComputerVisionService {
  @override
  bool get isModelLoaded => true;
  @override
  String get modelIdentifier => 'WormWise-AutoScreen-v1:test';
  @override
  Future<PlantDiagnosisResult> analyzeImage(File imageFile) async =>
      const PlantDiagnosisResult(
        isInfested: false,
        pestLabel: 'screen',
        confidenceScore: .9,
        suggestedPlantStatus: DatabaseCodes.plantNegative,
        classificationLabel: 'No FAW damage',
        modelName: 'WormWise-AutoScreen-v1:test',
      );
}
