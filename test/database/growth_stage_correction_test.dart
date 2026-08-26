import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';

void main() {
  test('legacy uncertain stage can be corrected before observations', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final fields = FieldRepository(database);
    final created = await fields.createFieldWithBoundaryAndCycle(
      name: 'Stage Test',
      geometryGeojson: '{"type":"Polygon","coordinates":[]}',
      areaHectares: 0.8,
      boundarySourceMethod: 'draw',
      boundaryConfirmationStatus: 'user_confirmed',
    );
    final evaluator = await PeopleRepository(
      database,
    ).findOrCreateEvaluator('Tester');
    final repository = AssessmentRepository(database);
    final assessment = await repository.createDraft(
      cropCycleId: created.cropCycle.id,
      boundaryVersionId: created.boundary.id,
      evaluatorPersonId: evaluator.id,
      assessmentMode: DatabaseCodes.modeVeV6,
      scoutingPattern: DatabaseCodes.patternW,
      growthStage: 'v3_v6',
      growthStageUncertain: true,
      protocolVersion: 'test',
      formulaVersion: 'test',
    );

    final corrected = await repository.correctGrowthStageBeforeObservations(
      assessmentId: assessment.id,
      growthStage: 'vt_r2',
      assessmentMode: DatabaseCodes.modeVtR2,
      scoutingPattern: DatabaseCodes.patternLadder,
    );

    expect(corrected.growthStage, 'vt_r2');
    expect(corrected.growthStageUncertain, isFalse);
    expect(corrected.status, DatabaseCodes.draft);
    expect(await database.select(database.assessmentBlockRuns).get(), isEmpty);
  });
}
