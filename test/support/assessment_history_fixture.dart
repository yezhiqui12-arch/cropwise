import 'package:drift/drift.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';

const historyPolygon =
    '{"type":"Polygon","coordinates":[[[121,17],[121.001,17],[121.001,17.001],[121,17.001],[121,17]]]}';

Future<({CreatedFieldCycle field, AssessmentRecord assessment})> historyFixture(
  AppDatabase db, {
  String name = 'North Maize Field',
  String status = 'draft',
  String stage = 'v3_v6',
  int daysAgo = 0,
}) async {
  final fields = FieldRepository(db);
  final field = await fields.createFieldWithBoundaryAndCycle(
    name: name,
    geometryGeojson: historyPolygon,
    areaHectares: 0.8,
    boundarySourceMethod: 'draw',
  );
  final evaluator = await PeopleRepository(
    db,
  ).create(displayName: 'Maria Santos', roleLabel: 'evaluator');
  final assessment = await AssessmentRepository(db).createDraft(
    cropCycleId: field.cropCycle.id,
    boundaryVersionId: field.boundary!.id,
    evaluatorPersonId: evaluator.id,
    assessmentMode: stage == 'vt_r2' || stage == 'r3_r6' ? stage : 've_v6',
    scoutingPattern: 'w',
    growthStage: stage,
    protocolVersion: 'test-protocol',
    formulaVersion: 'test-formula',
  );
  final date = DateTime.now().toUtc().subtract(Duration(days: daysAgo));
  await (db.update(
    db.assessments,
  )..where((r) => r.id.equals(assessment.id))).write(
    AssessmentsCompanion(
      status: Value(status),
      createdAt: Value(date),
      safetySummaryStatus: const Value('no_recent_treatment'),
    ),
  );
  return (
    field: field,
    assessment: await AssessmentRepository(db).assessmentById(assessment.id),
  );
}

Future<StationRecord> historyStation(
  AppDatabase db,
  CreatedFieldCycle field,
  AssessmentRecord assessment,
) async {
  final block = await FieldRepository(db).addBlock(
    cropCycleId: field.cropCycle.id,
    boundaryVersionId: field.boundary!.id,
    blockNumber: 1,
    geometryGeojson: historyPolygon,
    areaHectares: 0.8,
  );
  final repo = AssessmentRepository(db);
  final run = await repo.addBlockRun(
    assessmentId: assessment.id,
    fieldBlockId: block.id,
    blockSequence: 1,
    scoutingPattern: 'w',
  );
  return repo.addStation(
    assessmentBlockRunId: run.id,
    stationNumber: 1,
    latitude: 17,
    longitude: 121,
  );
}
