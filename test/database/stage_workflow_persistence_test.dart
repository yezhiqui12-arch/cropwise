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
import 'package:wormwise/data/services/stage_plant_save_service.dart';

const _polygon =
    '{"type":"Polygon","coordinates":[[[121.0,17.0],[121.01,17.0],'
    '[121.01,17.01],[121.0,17.01],[121.0,17.0]]]}';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('V7-V12 persists DA-BAFS score, attribution, and freshness', () async {
    final fixture = await _createFixture(
      database,
      growthStage: 'v7_v12',
      assessmentMode: DatabaseCodes.modeV7V12,
      scoutingPattern: DatabaseCodes.patternW,
    );
    final station = await _createStation(database, fixture);

    final saved = await AtomicPlantSaveService(database).saveVegetativePlant(
      VegetativePlantSave(
        stationId: station.id,
        plantPosition: 1,
        plantStatus: DatabaseCodes.plantCurrentPositive,
        assessable: true,
        newestLeavesInspectedCount: 4,
        smallFreshWindowpanes: true,
        scraping: false,
        cuttingOrTearing: false,
        freshFrass: true,
        whorlFeedingSign: true,
        larvaVisible: false,
        larvalSize: 'none_seen',
        eggMassVisible: false,
        oldDamagePresent: true,
        possibleNonFawEvidence: false,
        uncertainEvidence: false,
        naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyObserved,
        daBafsLeafDamageScore: 6,
        damageAttribution: DatabaseCodes.damageAttributionFawConsistent,
        damageFreshness: DatabaseCodes.evidenceMixed,
      ),
    );

    expect(saved.vegetative.daBafsLeafDamageScore, 6);
    expect(
      saved.vegetative.damageAttribution,
      DatabaseCodes.damageAttributionFawConsistent,
    );
    expect(saved.vegetative.damageFreshness, DatabaseCodes.evidenceMixed);
    expect(
      saved.plant.naturalEnemyQuickStatus,
      DatabaseCodes.naturalEnemyObserved,
    );
  });

  test(
    'VT-R2 requires all target zones and derives current infestation',
    () async {
      final fixture = await _createFixture(
        database,
        growthStage: 'vt_r2',
        assessmentMode: DatabaseCodes.modeVtR2,
        scoutingPattern: DatabaseCodes.patternLadder,
      );
      final station = await _createStation(database, fixture);
      final service = StagePlantSaveService(database);
      final valid = _reproductiveSave(station.id);

      await expectLater(
        service.saveReproductivePlant(
          _reproductiveSave(station.id, lowerAxilExamined: false),
        ),
        throwsArgumentError,
      );
      await service.saveReproductivePlant(valid);

      final plant = await database
          .select(database.plantObservations)
          .getSingle();
      final observation = await database
          .select(database.reproductiveObservations)
          .getSingle();
      expect(plant.plantStatus, DatabaseCodes.plantCurrentPositive);
      expect(plant.currentFawEvidence, isTrue);
      expect(observation.percentInfestedPositive, isTrue);
      expect(observation.classification, DatabaseCodes.reproductiveInfested);
      expect(observation.tasselExamined, isTrue);
      expect(observation.lowerAxilExamined, isTrue);
    },
  );

  test(
    'R3-R6 records authorization, deterministic selections, replacement, and external ear',
    () async {
      final fixture = await _createFixture(
        database,
        growthStage: 'r3_r6',
        assessmentMode: DatabaseCodes.modeR3R6,
        scoutingPattern: DatabaseCodes.patternLadder,
      );
      final workflow = ScoutingWorkflowRepository(database);
      final prepared = (await workflow.prepareRequiredBlocks(
        fixture.assessment,
        fixture.boundary,
      )).single;
      final station = await workflow.saveStationLocation(
        prepared: prepared,
        stationNumber: 1,
        actorPersonId: fixture.assessment.evaluatorPersonId,
        notLocatedReason: DatabaseCodes.stationNoCurrentFix,
      );
      final service = StagePlantSaveService(database);

      await service.saveLateSeasonSetup(
        LateSeasonSetupInput(
          assessmentId: fixture.assessment.id,
          cropUse: 'grain',
          commercialHarvestStarted: false,
          selectedEarsPartOfHarvest: true,
          openingPermission: DatabaseCodes.openingPermissionGranted,
          maximumEarsPermitted: 10,
          openingReason: 'Protocol validation',
          permissionGrantedBy: 'Field owner',
          evaluatorPersonId: fixture.assessment.evaluatorPersonId,
          permissionRecordedAt: DateTime.utc(2026, 8, 27),
          earDesignationRule: 'Primary uppermost marketable ear',
          blockRunIds: [prepared.run.id],
        ),
      );

      final plan = await service.loadOpeningPlan(
        blockRunId: prepared.run.id,
        stationNumber: 1,
      );
      expect(plan, hasLength(10));
      expect(plan.map((row) => row.plantPosition).toSet(), hasLength(10));
      expect(plan.where((row) => row.initiallySelected), hasLength(2));
      final first = plan.firstWhere((row) => row.initiallySelected);
      final replacement = await service.markOpeningSelectionFailed(
        selectionId: first.id,
        reason: 'Ear absent at opening',
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );
      expect(replacement, isNotNull);
      expect(replacement!.selectionStatus, 'replacement_selected');
      expect(replacement.replacesPlantPosition, first.plantPosition);

      final evidence = EvidenceCaptureRepository(database);
      final evidenceSession = await evidence.ensurePlantSession(
        assessmentId: fixture.assessment.id,
        stationId: station.id,
        plantPosition: replacement.plantPosition,
        actorPersonId: fixture.assessment.evaluatorPersonId,
        requirementsVersion: 'r3_r6_ear_evidence_v1',
      );
      await evidence.waiveRequiredView(
        session: evidenceSession,
        viewType: DatabaseCodes.evidenceViewEarRegionOverview,
        reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
        actorPersonId: fixture.assessment.evaluatorPersonId,
      );

      await service.saveExternalEar(
        EarExternalPlantSave(
          stationId: station.id,
          plantPosition: replacement.plantPosition,
          earPresent: true,
          externallyAssessable: true,
          designatedEarIdentity: 'Primary uppermost marketable ear',
          exteriorEarTipExamined: true,
          baseShankSilkAxilsExamined: true,
          externalDamagePresent: true,
          activeInfestationPresent: true,
          silkDamagePresent: false,
          huskDamagePresent: true,
          entryHolePresent: true,
          frassPresent: true,
          frassFreshness: DatabaseCodes.evidenceFresh,
          larvaPresent: true,
          larvalSize: 'medium',
          feedingFreshness: DatabaseCodes.evidenceFresh,
          moldRotLikeSymptoms: false,
          externalClassification: DatabaseCodes.earExternalActive,
          naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
          actorPersonId: fixture.assessment.evaluatorPersonId,
          evidenceCaptureSessionId: evidenceSession.id,
          requiredEvidenceViewTypes: const {
            DatabaseCodes.evidenceViewEarRegionOverview,
          },
        ),
      );

      var ear = await database.select(database.earObservations).getSingle();
      expect(ear.externalClassification, DatabaseCodes.earExternalActive);
      expect(ear.openingPermission, DatabaseCodes.openingPermissionGranted);
      expect(ear.entryHolePresent, isTrue);
      expect(ear.opened, isFalse);

      for (final view in const {
        DatabaseCodes.evidenceViewWholeEarBeforeOpening,
        DatabaseCodes.evidenceViewOpenedEarSideA,
        DatabaseCodes.evidenceViewOpenedEarSideB,
      }) {
        await evidence.waiveRequiredView(
          session: evidenceSession,
          viewType: view,
          reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
          actorPersonId: fixture.assessment.evaluatorPersonId,
        );
      }
      await service.saveOpenedEar(
        OpenedEarSave(
          earObservationId: ear.id,
          selectionId: replacement.id,
          huskIntactBeforeOpening: true,
          internalDamagePresent: true,
          totalKernelsCounted: 200,
          damagedKernelsCounted: 20,
          kernelCountMethod: 'manual_full_count',
          earTipDamageLengthMm: 14,
          cobDamagePresent: true,
          brokenMissingUnderdevelopedKernels: false,
          earRotPresent: false,
          internalClassification: DatabaseCodes.earInternalConfirmedFaw,
          evidenceCaptureSessionId: evidenceSession.id,
          actorPersonId: fixture.assessment.evaluatorPersonId,
        ),
      );

      ear = await database.select(database.earObservations).getSingle();
      final completedSelection = await (database.select(
        database.earOpeningSelections,
      )..where((row) => row.id.equals(replacement.id))).getSingle();
      expect(ear.opened, isTrue);
      expect(ear.totalKernelsCounted, 200);
      expect(ear.damagedKernelsCounted, 20);
      expect(completedSelection.selectionStatus, 'opened');
    },
  );
}

ReproductivePlantSave _reproductiveSave(
  String stationId, {
  bool lowerAxilExamined = true,
}) => ReproductivePlantSave(
  stationId: stationId,
  plantPosition: 1,
  assessable: true,
  classification: DatabaseCodes.reproductiveInfested,
  tasselExamined: true,
  earBaseExamined: true,
  upperAxilExamined: true,
  lowerAxilExamined: lowerAxilExamined,
  freshFeedingPresent: true,
  frassPresent: true,
  earHuskPenetrationVisible: false,
  larvaPresent: false,
  larvalSize: 'none_seen',
  possibleNonFawEvidence: false,
  uncertainEvidence: false,
  naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
);

class _Fixture {
  const _Fixture({required this.assessment, required this.boundary});

  final AssessmentRecord assessment;
  final BoundaryRecord boundary;
}

Future<_Fixture> _createFixture(
  AppDatabase database, {
  required String growthStage,
  required String assessmentMode,
  required String scoutingPattern,
}) async {
  final evaluator = await PeopleRepository(
    database,
  ).findOrCreateEvaluator('Stage Workflow Evaluator');
  final field = await FieldRepository(database).createFieldWithBoundaryAndCycle(
    name: 'Stage Workflow Field',
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
    assessmentMode: assessmentMode,
    scoutingPattern: scoutingPattern,
    growthStage: growthStage,
    protocolVersion: 'stage-workflow-test',
    formulaVersion: 'stage-workflow-test',
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

Future<StationRecord> _createStation(
  AppDatabase database,
  _Fixture fixture,
) async {
  final workflow = ScoutingWorkflowRepository(database);
  final prepared = (await workflow.prepareRequiredBlocks(
    fixture.assessment,
    fixture.boundary,
  )).single;
  return workflow.saveStationLocation(
    prepared: prepared,
    stationNumber: 1,
    actorPersonId: fixture.assessment.evaluatorPersonId,
    notLocatedReason: DatabaseCodes.stationNoCurrentFix,
  );
}
