import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/data/services/assessment_completion_validator.dart';
import 'package:wormwise/data/services/assessment_metrics_service.dart';

const _fieldPolygon =
    '{"type":"Polygon","coordinates":[[[121.0,17.0],[121.01,17.0],'
    '[121.01,17.01],[121.0,17.01],[121.0,17.0]]]}';

void main() {
  late AppDatabase database;
  late PeopleRepository people;
  late FieldRepository fields;
  late AssessmentRepository assessments;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    people = PeopleRepository(database);
    fields = FieldRepository(database);
    assessments = AssessmentRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'creates versioned field, boundary, crop cycle, and block offline',
    () async {
      final evaluator = await people.create(
        displayName: 'Test Evaluator',
        roleLabel: 'evaluator',
      );
      final created = await fields.createFieldWithBoundaryAndCycle(
        name: 'Test Cornfield',
        geometryGeojson: _fieldPolygon,
        areaHectares: 1,
        boundarySourceMethod: 'draw',
        ownerPersonId: evaluator.id,
        varietyName: 'Test variety',
        actorPersonId: evaluator.id,
      );
      final block = await fields.addBlock(
        cropCycleId: created.cropCycle.id,
        boundaryVersionId: created.boundary.id,
        blockNumber: 1,
        geometryGeojson: _fieldPolygon,
        areaHectares: 1,
        actorPersonId: evaluator.id,
      );
      final corrected = await fields.addBoundaryVersion(
        fieldId: created.field.id,
        geometryGeojson: _fieldPolygon,
        areaHectares: 0.98,
        sourceMethod: 'mark_corners',
        actorPersonId: evaluator.id,
      );

      expect(created.field.name, 'Test Cornfield');
      expect(created.boundary.versionNumber, 1);
      expect(corrected.versionNumber, 2);
      expect(block.blockNumber, 1);

      final refreshedField = await (database.select(
        database.fields,
      )..where((row) => row.id.equals(created.field.id))).getSingle();
      expect(refreshedField.activeBoundaryVersionId, corrected.id);
      expect(await database.select(database.syncOutbox).get(), isNotEmpty);
      expect(await database.select(database.auditLogs).get(), isNotEmpty);
    },
  );

  test('persists the selected field id in SQLite', () async {
    final created = await fields.createFieldWithBoundaryAndCycle(
      name: 'Preferred Cornfield',
      geometryGeojson: _fieldPolygon,
      areaHectares: 0.75,
      boundarySourceMethod: 'draw',
    );

    await fields.savePreferredFieldId(created.field.id);

    expect(await fields.readPreferredFieldId(), created.field.id);
  });

  test('stores an optional entrance GPS without claiming a boundary', () async {
    final created = await fields.createFieldWithBoundaryAndCycle(
      name: 'Reported Area Field',
      geometryGeojson: '{"type":"Polygon","coordinates":[]}',
      areaHectares: 0.75,
      boundarySourceMethod: 'entrance_gps',
      boundaryConfirmationStatus: 'location_only',
      centroidLatitude: 17.7901,
      centroidLongitude: 121.4782,
      averageAccuracyM: 6.2,
      worstAccuracyM: 9.4,
      confidenceCode: 'moderate_phone_gnss',
    );
    final workspace = FieldWorkspaceRecord(
      field: created.field,
      boundary: created.boundary,
      cropCycle: created.cropCycle,
    );

    expect(created.boundary.areaHectares, 0.75);
    expect(created.boundary.confirmationStatus, 'location_only');
    expect(created.boundary.centroidLatitude, 17.7901);
    expect(created.boundary.averageAccuracyM, 6.2);
    expect(created.boundary.confirmedAt, isNull);
    expect(workspace.spatialState, FieldSpatialState.entranceLocation);
    expect(workspace.hasApproximateOutline, isFalse);
  });

  test('replaces a draft outline with a confirmed boundary version', () async {
    final created = await fields.createFieldWithBoundaryAndCycle(
      name: 'Boundary Setup Field',
      geometryGeojson: '{"type":"Polygon","coordinates":[]}',
      areaHectares: 0.5,
      boundarySourceMethod: 'manual_pending',
      boundaryConfirmationStatus: 'draft',
    );

    final confirmed = await fields.addBoundaryVersion(
      fieldId: created.field.id,
      geometryGeojson: _fieldPolygon,
      areaHectares: 1.1,
      sourceMethod: 'draw',
      centroidLatitude: 17.005,
      centroidLongitude: 121.005,
      notes: 'User-confirmed scouting boundary.',
    );

    final refreshedField = await (database.select(
      database.fields,
    )..where((row) => row.id.equals(created.field.id))).getSingle();

    expect(created.boundary.confirmationStatus, 'draft');
    expect(confirmed.versionNumber, 2);
    expect(confirmed.confirmationStatus, 'user_confirmed');
    expect(confirmed.sourceMethod, 'draw');
    expect(confirmed.centroidLatitude, 17.005);
    expect(refreshedField.activeBoundaryVersionId, confirmed.id);
  });

  test('blocks assessment start until entry safety is confirmed', () async {
    final setup = await _createAssessmentFixture(
      people: people,
      fields: fields,
      assessments: assessments,
    );

    expect(
      () => assessments.startAssessment(setup.assessment.id),
      throwsA(isA<UnsafeFieldEntryException>()),
    );

    await assessments.recordSafetyCheck(
      assessmentId: setup.assessment.id,
      checkedByPersonId: setup.evaluator.id,
      resultStatus: DatabaseCodes.noRecentTreatment,
    );
    await assessments.startAssessment(setup.assessment.id);

    final started = await (database.select(
      database.assessments,
    )..where((row) => row.id.equals(setup.assessment.id))).getSingle();
    expect(started.status, DatabaseCodes.inProgress);
    expect(started.startedAt, isNotNull);
  });

  test('stores assessment route reason and local time-zone offset', () async {
    final setup = await _createAssessmentFixture(
      people: people,
      fields: fields,
      assessments: assessments,
    );
    final custom = await assessments.createDraft(
      cropCycleId: setup.assessment.cropCycleId,
      boundaryVersionId: setup.assessment.boundaryVersionId,
      evaluatorPersonId: setup.evaluator.id,
      assessmentMode: DatabaseCodes.modeVeV6,
      scoutingPattern: DatabaseCodes.patternLadder,
      patternReason: 'Standing water blocks the center route.',
      growthStage: 'v4',
      protocolVersion: 'test-protocol',
      formulaVersion: 'test-formula',
      localUtcOffsetMinutes: 480,
    );

    expect(custom.patternReason, 'Standing water blocks the center route.');
    expect(custom.localUtcOffsetMinutes, 480);
  });

  test(
    'validates 5x10 vegetative sample and calculates block metrics',
    () async {
      final setup = await _createAssessmentFixture(
        people: people,
        fields: fields,
        assessments: assessments,
      );
      await assessments.recordSafetyCheck(
        assessmentId: setup.assessment.id,
        checkedByPersonId: setup.evaluator.id,
        resultStatus: DatabaseCodes.noRecentTreatment,
      );
      await assessments.startAssessment(setup.assessment.id);

      final run = await assessments.addBlockRun(
        assessmentId: setup.assessment.id,
        fieldBlockId: setup.block.id,
        blockSequence: 1,
        scoutingPattern: DatabaseCodes.patternW,
      );

      var overallPlant = 0;
      for (var stationNumber = 1; stationNumber <= 5; stationNumber++) {
        final station = await assessments.addStation(
          assessmentBlockRunId: run.id,
          stationNumber: stationNumber,
        );
        for (var sequence = 1; sequence <= 10; sequence++) {
          overallPlant++;
          final currentPositive = overallPlant <= 8;
          final plant = await assessments.savePlant(
            stationId: station.id,
            sequenceNumber: sequence,
            plantStatus: currentPositive
                ? DatabaseCodes.plantCurrentPositive
                : DatabaseCodes.plantNegative,
            currentFawEvidence: currentPositive,
            naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
          );
          await assessments.saveVegetativeObservation(
            plantObservationId: plant.id,
            newestLeavesInspectedCount: 4,
            smallFreshWindowpanes: overallPlant <= 5,
            infestedWhorl: overallPlant <= 3,
            freshFrass: overallPlant <= 3,
            daBafsLeafDamageScore: currentPositive ? 2 : 0,
          );
        }
      }

      final validator = AssessmentCompletionValidator(database);
      final validation = await validator.validateBlock(run.id);
      expect(validation.issues, isEmpty);

      final metrics = await AssessmentMetricsService(
        database,
      ).recalculateBlock(run.id);
      final byCode = {for (final metric in metrics) metric.metricCode: metric};
      expect(
        byCode[DatabaseCodes.vegetativeCurrentInfestationPercent]?.value,
        16,
      );
      expect(byCode[DatabaseCodes.smallFreshWindowpanePercent]?.value, 10);
      expect(byCode[DatabaseCodes.infestedWhorlPercent]?.value, 6);

      await validator.completeAssessment(setup.assessment.id);
      final completed = await (database.select(
        database.assessments,
      )..where((row) => row.id.equals(setup.assessment.id))).getSingle();
      expect(completed.status, DatabaseCodes.completed);
    },
  );

  test(
    'VE-V2 requires a separate 10-position planting-unit sequence',
    () async {
      final setup = await _createAssessmentFixture(
        people: people,
        fields: fields,
        assessments: assessments,
        growthStage: 'v2',
      );
      await assessments.recordSafetyCheck(
        assessmentId: setup.assessment.id,
        checkedByPersonId: setup.evaluator.id,
        resultStatus: DatabaseCodes.noRecentTreatment,
      );
      await assessments.startAssessment(setup.assessment.id);
      final run = await assessments.addBlockRun(
        assessmentId: setup.assessment.id,
        fieldBlockId: setup.block.id,
        blockSequence: 1,
        scoutingPattern: DatabaseCodes.patternW,
      );
      final station = await assessments.addStation(
        assessmentBlockRunId: run.id,
        stationNumber: 1,
      );
      for (var sequence = 1; sequence <= 10; sequence++) {
        final plant = await assessments.savePlant(
          stationId: station.id,
          sequenceNumber: sequence,
          plantStatus: DatabaseCodes.plantNegative,
          currentFawEvidence: false,
          naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
        );
        await assessments.saveVegetativeObservation(
          plantObservationId: plant.id,
          daBafsLeafDamageScore: 0,
        );
      }

      final validator = AssessmentCompletionValidator(database);
      final before = await validator.validateBlock(run.id);
      expect(
        before.issues.map((issue) => issue.code),
        contains('planting_unit_count'),
      );

      for (var sequence = 1; sequence <= 10; sequence++) {
        await assessments.savePlantingUnit(
          stationId: station.id,
          sequenceNumber: sequence,
          assessable: true,
          occupancyStatus: 'occupied',
          observedSeedlingCount: 1,
        );
      }
      final after = await validator.validateBlock(run.id);
      expect(
        after.issues.map((issue) => issue.code),
        isNot(contains('planting_unit_count')),
      );
    },
  );
}

class _AssessmentFixture {
  const _AssessmentFixture({
    required this.evaluator,
    required this.block,
    required this.assessment,
  });

  final PersonRecord evaluator;
  final FieldBlockRecord block;
  final AssessmentRecord assessment;
}

Future<_AssessmentFixture> _createAssessmentFixture({
  required PeopleRepository people,
  required FieldRepository fields,
  required AssessmentRepository assessments,
  String growthStage = 'v3_v6',
}) async {
  final evaluator = await people.create(
    displayName: 'Assessment Evaluator',
    roleLabel: 'evaluator',
  );
  final created = await fields.createFieldWithBoundaryAndCycle(
    name: 'Assessment Field',
    geometryGeojson: _fieldPolygon,
    areaHectares: 1,
    boundarySourceMethod: 'draw',
    ownerPersonId: evaluator.id,
    actorPersonId: evaluator.id,
  );
  final block = await fields.addBlock(
    cropCycleId: created.cropCycle.id,
    boundaryVersionId: created.boundary.id,
    blockNumber: 1,
    geometryGeojson: _fieldPolygon,
    areaHectares: 1,
    actorPersonId: evaluator.id,
  );
  final assessment = await assessments.createDraft(
    cropCycleId: created.cropCycle.id,
    boundaryVersionId: created.boundary.id,
    evaluatorPersonId: evaluator.id,
    assessmentMode: DatabaseCodes.modeVeV6,
    scoutingPattern: DatabaseCodes.patternW,
    growthStage: growthStage,
    protocolVersion: 'draft-v1',
    formulaVersion: '1',
    interventionHistoryStatus: 'no',
  );
  return _AssessmentFixture(
    evaluator: evaluator,
    block: block,
    assessment: assessment,
  );
}
