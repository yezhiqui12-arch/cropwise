import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/assessment_history_repository.dart';
import 'package:wormwise/data/repositories/evidence_capture_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:wormwise/data/services/automatic_screening_save_service.dart';
import 'package:wormwise/data/services/scouting_completion_service.dart';
import 'package:wormwise/models/assessment_history_models.dart';
import 'package:wormwise/models/automatic_screening.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';
import 'package:wormwise/services/scouting_sampling_protocol.dart';

Future<AssessmentHistoryDetail> daResultsFixture(
  AppDatabase db, {
  int recorded = 20,
  int positives = 4,
  int unavailable = 0,
  bool infestationDetections = false,
}) async {
  final actor = await PeopleRepository(
    db,
  ).findOrCreateEvaluator('Test evaluator');
  final field = await FieldRepository(db).createFieldWithBoundaryAndCycle(
    name: 'Corn plot',
    geometryGeojson:
        '{"type":"Polygon","coordinates":[[[121,17],[121.001,17],[121.001,17.001],[121,17.001],[121,17]]]}',
    areaHectares: 1,
    boundarySourceMethod: 'draw',
    boundaryConfirmationStatus: 'user_confirmed',
    ownerPersonId: actor.id,
    actorPersonId: actor.id,
  );
  final assessments = AssessmentRepository(db);
  final draft = await assessments.createDraft(
    cropCycleId: field.cropCycle.id,
    boundaryVersionId: field.boundary!.id,
    evaluatorPersonId: actor.id,
    assessmentMode: 've_v6',
    scoutingPattern: ScoutingSamplingProtocol.daPattern,
    growthStage: 'v3_v6',
    protocolVersion: ScoutingSamplingProtocol.daVersion,
    formulaVersion: '1.0-draft',
  );
  await assessments.recordSafetyCheck(
    assessmentId: draft.id,
    checkedByPersonId: actor.id,
    resultStatus: DatabaseCodes.noRecentTreatment,
  );
  await assessments.startAssessment(draft.id);
  final assessment = await assessments.assessmentById(draft.id);
  final workflow = ScoutingWorkflowRepository(db);
  final run = (await workflow.prepareRequiredBlocks(
    assessment,
    field.boundary!,
  )).single;
  final evidence = EvidenceCaptureRepository(db);
  for (var number = 1; number <= recorded; number++) {
    final station = await workflow.saveStationLocation(
      prepared: run,
      actorPersonId: actor.id,
      stationNumber: number,
      notLocatedReason: DatabaseCodes.stationNoCurrentFix,
    );
    final session = await evidence.ensurePlantSession(
      assessmentId: assessment.id,
      stationId: station.id,
      plantPosition: 1,
      actorPersonId: actor.id,
      requirementsVersion:
          DatabaseCodes.evidencePolicyCameraFirstOverviewConditionalV1,
    );
    await evidence.waiveRequiredView(
      session: session,
      viewType: DatabaseCodes.evidenceViewWhorlOverview,
      reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
      actorPersonId: actor.id,
    );
    await evidence.completePlantCapture(
      session: session,
      actorPersonId: actor.id,
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
          isInfested: number <= positives,
          pestLabel: 'screen',
          classifierStage:
              infestationDetections && number <= recorded - unavailable
              ? 'overlay_complete'
              : null,
          detectionBoxes:
              infestationDetections &&
                  number <= positives &&
                  number <= recorded - unavailable
              ? [
                  const ModelDetectionBox(
                    sourcePath: 'fixture.jpg',
                    classId: 2,
                    label: 'Larvae',
                    confidence: .9,
                    left: 0,
                    top: 0,
                    right: 10,
                    bottom: 10,
                    imageWidth: 20,
                    imageHeight: 20,
                  ),
                ]
              : const [],
          confidenceScore: .9,
          suggestedPlantStatus: DatabaseCodes.plantNegative,
          classificationLabel: number > recorded - unavailable
              ? null
              : number <= positives
              ? 'FAW damage'
              : 'No FAW damage',
        ),
      ),
      actorId: actor.id,
      sessionId: session.id,
      primaryView: DatabaseCodes.evidenceViewWhorlOverview,
    );
    await workflow.confirmStationReview(
      snapshot: await workflow.loadStationSnapshot(run, stationNumber: number),
      actorPersonId: actor.id,
      manualConfirmationDeferred: true,
    );
  }
  if (recorded == 20)
    await ScoutingCompletionService(db).completeBlock(run.run.id);
  return (await AssessmentHistoryRepository(db).loadDetail(assessment.id))!;
}
