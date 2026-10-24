import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/data/repositories/scouting_route_repository.dart';
import 'package:wormwise/data/repositories/scouting_workflow_repository.dart';
import 'package:wormwise/data/services/atomic_plant_save_service.dart';
import 'package:wormwise/data/services/scouting_completion_service.dart';
import 'package:wormwise/providers/scouting_workflow_provider.dart';
import 'package:wormwise/providers/scouting_workflow_state.dart';
import 'package:wormwise/services/scouting_route_generator.dart';

const _polygon =
    '{"type":"Polygon","coordinates":[[[121.0,17.0],[121.01,17.0],'
    '[121.01,17.01],[121.0,17.01],[121.0,17.0]]]}';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test(
    'draft, generated route, arrival, and adjustment recover after restart',
    () async {
      final fixture = await _fixture(database);
      final workflow = ScoutingWorkflowRepository(database);
      final prepared = (await workflow.prepareRequiredBlocks(
        fixture.assessment,
        fixture.boundary,
      )).single;
      final routes = ScoutingRouteRepository(database);
      var plan = await routes.loadOrCreateDraft(
        assessment: fixture.assessment,
        prepared: prepared,
      );
      plan = await routes.savePreparationDraft(
        plan,
        const RoutePreparationData(
          entrance: LatLng(17.0002, 121.0002),
          rowBearingDegrees: 0,
          obstaclesReviewed: true,
          wCrossingConfirmed: true,
        ),
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      plan = await routes.saveGeneratedPlan(
        ScoutingRouteGenerator.generate(
          draft: plan,
          boundary: ScoutingRouteGenerator.parsePolygon(
            prepared.block.geometryGeojson,
          ),
        ),
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      plan = await routes.beginTargetAdjustment(
        plan,
        stationNumber: 2,
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      plan = await routes.saveTargetAdjustmentDraft(
        plan,
        candidate: const LatLng(17.004, 121.004),
        reason: 'Unsafe ditch at generated point',
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );

      var restored = await ScoutingRouteRepository(
        database,
      ).loadPlan(prepared.run.id);
      expect(restored?.pendingAdjustment?.stationNumber, 2);
      expect(
        restored?.pendingAdjustment?.reason,
        'Unsafe ditch at generated point',
      );

      restored = await routes.applyTargetAdjustment(
        restored!,
        boundary: ScoutingRouteGenerator.parsePolygon(
          prepared.block.geometryGeojson,
        ),
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      expect(restored.targetFor(2).adjusted, isTrue);
      final adjustmentAudit = (await database.select(database.auditLogs).get())
          .singleWhere((audit) => audit.action == 'station_target_adjusted');
      expect(adjustmentAudit.reason, 'Unsafe ditch at generated point');

      await routes.confirmStationArrival(
        restored,
        stationNumber: 2,
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      final afterArrival = await ScoutingRouteRepository(
        database,
      ).loadPlan(prepared.run.id);
      expect(afterArrival?.arrivalConfirmedStation, 2);
    },
  );

  test(
    'provider restores preparation, travel, adjustment, and confirmed arrival',
    () async {
      final fixture = await _fixture(database);
      final first = _provider(database, fixture.assessment.id);
      await first.initialize();
      await first.prepareRequiredBlocks();
      expect(first.state, Station1ViewState.routePreparation);
      await first.saveRoutePreparation(
        const RoutePreparationData(
          entrance: LatLng(17.0002, 121.0002),
          rowBearingDegrees: 0,
          obstaclesReviewed: true,
          wCrossingConfirmed: true,
        ),
      );
      first.dispose();

      final preparationRestart = _provider(database, fixture.assessment.id);
      await preparationRestart.initialize();
      expect(preparationRestart.state, Station1ViewState.resumeCheck);
      await preparationRestart.submitResumeCheck(
        condition: ResumeCondition.unchanged,
        safeToContinue: true,
      );
      expect(preparationRestart.state, Station1ViewState.routePreparation);
      await preparationRestart.generateRoute();
      expect(preparationRestart.state, Station1ViewState.stationTravel);
      preparationRestart.dispose();

      final travelRestart = _provider(database, fixture.assessment.id);
      await travelRestart.initialize();
      await travelRestart.submitResumeCheck(
        condition: ResumeCondition.unchanged,
        safeToContinue: true,
      );
      expect(travelRestart.state, Station1ViewState.stationTravel);
      await travelRestart.beginTargetAdjustment();
      await travelRestart.saveTargetAdjustmentDraft(
        candidate: const LatLng(17.004, 121.004),
        reason: 'Flooded access',
      );
      travelRestart.dispose();

      final adjustmentRestart = _provider(database, fixture.assessment.id);
      await adjustmentRestart.initialize();
      await adjustmentRestart.submitResumeCheck(
        condition: ResumeCondition.unchanged,
        safeToContinue: true,
      );
      expect(adjustmentRestart.state, Station1ViewState.targetAdjustment);
      await adjustmentRestart.cancelTargetAdjustment();
      await adjustmentRestart.confirmReachedActiveStation();
      expect(adjustmentRestart.state, Station1ViewState.plantSelection);
      adjustmentRestart.dispose();

      final arrivalRestart = _provider(database, fixture.assessment.id);
      await arrivalRestart.initialize();
      await arrivalRestart.submitResumeCheck(
        condition: ResumeCondition.unchanged,
        safeToContinue: true,
      );
      expect(arrivalRestart.state, Station1ViewState.plantSelection);
      arrivalRestart.dispose();
    },
  );

  test(
    'completed station targets cannot be adjusted during recalculation',
    () async {
      final fixture = await _fixture(database);
      final workflow = ScoutingWorkflowRepository(database);
      final prepared = (await workflow.prepareRequiredBlocks(
        fixture.assessment,
        fixture.boundary,
      )).single;
      final routes = ScoutingRouteRepository(database);
      var plan = await routes.loadOrCreateDraft(
        assessment: fixture.assessment,
        prepared: prepared,
      );
      plan = plan.copyWith(
        preparation: const RoutePreparationData(
          entrance: LatLng(17.0002, 121.0002),
          rowBearingDegrees: 0,
          obstaclesReviewed: true,
          wCrossingConfirmed: true,
        ),
      );
      plan = ScoutingRouteGenerator.generate(
        draft: plan,
        boundary: ScoutingRouteGenerator.parsePolygon(
          prepared.block.geometryGeojson,
        ),
        completedStations: const {1: LatLng(17.002, 121.002)},
      );
      plan = await routes.saveGeneratedPlan(
        plan,
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );

      expect(
        () => routes.beginTargetAdjustment(
          plan,
          stationNumber: 1,
          actorPersonId: fixture.assessment.evaluatorPersonId,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'target adjustment requires a reason before changing the route',
    () async {
      final fixture = await _fixture(database);
      final workflow = ScoutingWorkflowRepository(database);
      final prepared = (await workflow.prepareRequiredBlocks(
        fixture.assessment,
        fixture.boundary,
      )).single;
      final routes = ScoutingRouteRepository(database);
      var plan = await routes.loadOrCreateDraft(
        assessment: fixture.assessment,
        prepared: prepared,
      );
      plan = ScoutingRouteGenerator.generate(
        draft: plan.copyWith(
          preparation: const RoutePreparationData(
            entrance: LatLng(17.0002, 121.0002),
            rowBearingDegrees: 0,
            obstaclesReviewed: true,
            wCrossingConfirmed: true,
          ),
        ),
        boundary: ScoutingRouteGenerator.parsePolygon(
          prepared.block.geometryGeojson,
        ),
      );
      plan = await routes.saveGeneratedPlan(
        plan,
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      plan = await routes.beginTargetAdjustment(
        plan,
        stationNumber: 3,
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      plan = await routes.saveTargetAdjustmentDraft(
        plan,
        candidate: const LatLng(17.006, 121.006),
        reason: '   ',
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );

      await expectLater(
        routes.applyTargetAdjustment(
          plan,
          boundary: ScoutingRouteGenerator.parsePolygon(
            prepared.block.geometryGeojson,
          ),
          actorPersonId: fixture.assessment.evaluatorPersonId,
        ),
        throwsStateError,
      );
      expect(
        (await routes.loadPlan(prepared.run.id))?.targetFor(3).adjusted,
        isFalse,
      );
    },
  );

  test('restart upgrades legacy manual ladder geometry exactly once', () async {
    final fixture = await _fixture(
      database,
      pattern: DatabaseCodes.patternLadder,
    );
    final workflow = ScoutingWorkflowRepository(database);
    final prepared = (await workflow.prepareRequiredBlocks(
      fixture.assessment,
      fixture.boundary,
    )).single;
    final routes = ScoutingRouteRepository(database);
    var plan = await routes.loadOrCreateDraft(
      assessment: fixture.assessment,
      prepared: prepared,
    );
    plan = ScoutingRouteGenerator.generate(
      draft: plan.copyWith(
        preparation: const RoutePreparationData(
          entrance: LatLng(17.0002, 121.0002),
          rowBearingDegrees: 0,
          obstaclesReviewed: true,
          accessiblePaths: [
            [LatLng(17.001, 121.005), LatLng(17.009, 121.005)],
          ],
        ),
      ),
      boundary: ScoutingRouteGenerator.parsePolygon(
        prepared.block.geometryGeojson,
      ),
    );
    await routes.saveGeneratedPlan(
      plan.copyWith(
        algorithmVersion: retiredRouteAlgorithmVersion,
        segments: const [
          ScoutingRouteSegment(
            points: [LatLng(17.001, 121.005), LatLng(17.009, 121.005)],
            kind: 'evaluator_confirmed_accessible_path',
            drawable: true,
          ),
        ],
      ),
      actorPersonId: fixture.assessment.evaluatorPersonId,
    );

    final provider = _provider(database, fixture.assessment.id);
    await provider.initialize();
    provider.dispose();
    final restored = await routes.loadPlan(prepared.run.id);

    expect(restored?.algorithmVersion, scoutingRouteAlgorithmVersion);
    expect(
      restored?.segments.any(
        (segment) => segment.kind == 'evaluator_confirmed_accessible_path',
      ),
      isFalse,
    );
    expect(
      restored?.segments.where(
        (segment) => segment.kind == 'ladder_branch_outbound',
      ),
      hasLength(5),
    );
    expect(
      (await database.select(database.auditLogs).get()).where(
        (audit) => audit.action == 'route_recalculated',
      ),
      hasLength(1),
    );
  });
}

class _Fixture {
  const _Fixture(this.assessment, this.boundary);
  final AssessmentRecord assessment;
  final BoundaryRecord boundary;
}

Future<_Fixture> _fixture(
  AppDatabase database, {
  String pattern = DatabaseCodes.patternW,
}) async {
  final evaluator = await PeopleRepository(
    database,
  ).findOrCreateEvaluator('Route Evaluator');
  final field = await FieldRepository(database).createFieldWithBoundaryAndCycle(
    name: 'Route Field',
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
    assessmentMode: DatabaseCodes.modeVeV6,
    scoutingPattern: pattern,
    growthStage: 'v3_v6',
    protocolVersion: 'increment-b-test',
    formulaVersion: 'increment-b-test',
  );
  await assessments.recordSafetyCheck(
    assessmentId: assessment.id,
    checkedByPersonId: evaluator.id,
    resultStatus: DatabaseCodes.noRecentTreatment,
  );
  await assessments.startAssessment(assessment.id);
  assessment = await assessments.assessmentById(assessment.id);
  return _Fixture(assessment, field.boundary);
}

ScoutingWorkflowProvider _provider(AppDatabase database, String assessmentId) =>
    ScoutingWorkflowProvider(
      assessmentId: assessmentId,
      workflowRepository: ScoutingWorkflowRepository(database),
      assessmentRepository: AssessmentRepository(database),
      plantSaveService: AtomicPlantSaveService(database),
      completionService: ScoutingCompletionService(database),
      routeRepository: ScoutingRouteRepository(database),
    );
