import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/data/repositories/assessment_history_repository.dart';
import 'package:wormwise/data/repositories/assessment_repository.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/data/repositories/people_repository.dart';
import 'package:wormwise/providers/assessment_workspace_provider.dart';
import 'package:wormwise/models/assessment_history_models.dart';
import '../support/assessment_history_fixture.dart';

void main() {
  late AppDatabase db;
  late AssessmentHistoryRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = AssessmentHistoryRepository(db);
  });
  tearDown(() => db.close());

  test(
    'historical completion is assessed without rewriting its status',
    () async {
      final fixture = await historyFixture(db, status: 'completed');
      final station = await historyStation(
        db,
        fixture.field,
        fixture.assessment,
      );
      final before =
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      final detail = (await repo.loadDetail(fixture.assessment.id))!;
      expect(detail.readiness.isValid, isFalse);
      expect(
        detail.readiness.issues.any((i) => i.stationId == station.id),
        isTrue,
      );
      expect(
        detail.readiness.issues.any(
          (i) => i.stationNumber == 2 && i.blockRunId != null,
        ),
        isTrue,
      );
      expect(detail.assessment.status, 'completed');
      expect(detail.canResume, isFalse);
      final after =
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      expect(after, before);
    },
  );

  test(
    'filters statuses and fields, orders by date, excludes deleted fields',
    () async {
      final older = await historyFixture(db, status: 'completed', daysAgo: 2);
      final newer = await historyFixture(db, name: 'South Field');
      expect((await repo.watchPage().first).map((r) => r.id), [
        newer.assessment.id,
        older.assessment.id,
      ]);
      expect(
        (await repo.watchPage(status: 'completed').first).single.id,
        older.assessment.id,
      );
      expect(
        (await repo.watchPage(fieldId: newer.field.field.id).first).single.id,
        newer.assessment.id,
      );
      expect(
        await repo
            .watchPage(fieldId: newer.field.field.id, status: 'completed')
            .first,
        isEmpty,
      );
      expect(await repo.watchPage(limit: 1).first, hasLength(1));
      await FieldRepository(
        db,
      ).setFieldArchived(fieldId: newer.field.field.id, archived: true);
      expect((await repo.watchPage().first).single.id, older.assessment.id);
      expect((await repo.loadDetail(newer.assessment.id))!.canResume, isFalse);
    },
  );

  test(
    'detail preserves historical boundary, separates seedling positions, and never writes',
    () async {
      final fixture = await historyFixture(db, stage: 've');
      final station = await historyStation(
        db,
        fixture.field,
        fixture.assessment,
      );
      await db
          .into(db.plantingUnitObservations)
          .insert(
            PlantingUnitObservationsCompanion.insert(
              id: 'unit',
              stationId: station.id,
              sequenceNumber: 1,
              primaryCondition: const Value('empty_unexplained'),
            ),
          );
      await FieldRepository(db).addBoundaryVersion(
        fieldId: fixture.field.field.id,
        geometryGeojson: historyPolygon,
        areaHectares: 0.9,
        sourceMethod: 'draw',
      );
      final before =
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      final detail = (await repo.loadDetail(fixture.assessment.id))!;
      final row = (await repo.watchPage().first).single;
      final after =
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      expect(after, before);
      expect(detail.workspace.boundary!.id, fixture.field.boundary.id);
      expect(detail.stations, hasLength(5));
      expect(detail.stations.where((s) => s.reviewIsCurrent), isEmpty);
      expect(row.positions, 1);
      expect(row.plants, 0);
      expect(row.stations, 1);
    },
  );

  test(
    'accepted and missing media are scoped; staged and deleted media excluded',
    () async {
      final fixture = await historyFixture(db);
      final station = await historyStation(
        db,
        fixture.field,
        fixture.assessment,
      );
      for (final state in ['ready', 'missing', 'staged', 'deleted']) {
        await db
            .into(db.evidenceMedia)
            .insert(
              EvidenceMediaCompanion.insert(
                id: state,
                assessmentId: fixture.assessment.id,
                stationId: Value(station.id),
                mediaType: 'image',
                localUri: 'absent/$state.jpg',
                sha256Checksum: 'test',
                storageState: Value(state),
                deletedAt: state == 'deleted'
                    ? Value(DateTime.now())
                    : const Value.absent(),
              ),
            );
      }
      final detail = (await repo.loadDetail(fixture.assessment.id))!;
      expect(detail.evidence, hasLength(2));
      expect(detail.evidence.first.scope, contains('Block 1 · Station 1'));
      expect(
        detail.evidence.every((entry) => entry.stationId == station.id),
        isTrue,
      );
      expect(
        detail.evidence.every(
          (entry) =>
              entry.scopeType == DatabaseCodes.evidenceScopeStationContext,
        ),
        isTrue,
      );
      expect((await repo.watchPage().first).single.photos, 1);
    },
  );

  test(
    'plant-scoped seedling media is not relabeled as unit evidence',
    () async {
      final fixture = await historyFixture(db, stage: 'v2');
      final station = await historyStation(
        db,
        fixture.field,
        fixture.assessment,
      );
      await db
          .into(db.plantingUnitObservations)
          .insert(
            PlantingUnitObservationsCompanion.insert(
              id: 'source-unit',
              stationId: station.id,
              sequenceNumber: 1,
              primaryCondition: const Value(DatabaseCodes.veUnitHealthy),
            ),
          );
      await db
          .into(db.evidenceCaptureSessions)
          .insert(
            EvidenceCaptureSessionsCompanion.insert(
              id: 'seedling-session',
              assessmentId: fixture.assessment.id,
              stationId: station.id,
              scopeType: DatabaseCodes.evidenceScopePlant,
              scopeKey: 'plant_01',
              plantPosition: const Value(1),
              sourcePlantingUnitObservationId: const Value('source-unit'),
            ),
          );
      await db
          .into(db.evidenceMedia)
          .insert(
            EvidenceMediaCompanion.insert(
              id: 'seedling-photo',
              assessmentId: fixture.assessment.id,
              stationId: Value(station.id),
              plantingUnitObservationId: const Value('source-unit'),
              captureSessionId: const Value('seedling-session'),
              mediaType: 'image',
              localUri: 'absent/seedling.jpg',
              sha256Checksum: 'seedling-test',
              storageState: const Value(DatabaseCodes.evidenceStorageReady),
            ),
          );

      final evidence = (await repo.loadDetail(
        fixture.assessment.id,
      ))!.evidence.single;
      expect(evidence.scopeType, DatabaseCodes.evidenceScopePlant);
      expect(evidence.scope, endsWith('Seedling 1'));
      expect(evidence.plantPosition, 1);
    },
  );

  test('history reacts when the saved assessment status changes', () async {
    final fixture = await historyFixture(db);
    final values = <List<AssessmentHistoryEntry>>[];
    final subscription = repo.watchPage().listen(values.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await (db.update(db.assessments)
          ..where((r) => r.id.equals(fixture.assessment.id)))
        .write(const AssessmentsCompanion(status: Value('completed')));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await subscription.cancel();
    expect(values.first.single.status, 'draft');
    expect(values.last.single.status, 'completed');
  });

  test(
    'resume provider watches exact assessment despite a newer open assessment',
    () async {
      final fixture = await historyFixture(db);
      final repository = AssessmentRepository(db);
      await repository.createDraft(
        cropCycleId: fixture.field.cropCycle.id,
        boundaryVersionId: fixture.field.boundary.id,
        evaluatorPersonId: fixture.assessment.evaluatorPersonId,
        assessmentMode: 've_v6',
        scoutingPattern: 'w',
        growthStage: 'v3_v6',
        protocolVersion: 'test',
        formulaVersion: 'test',
      );
      final detail = (await repo.loadDetail(fixture.assessment.id))!;
      final provider = AssessmentWorkspaceProvider.forAssessment(
        repository,
        PeopleRepository(db),
        detail.workspace,
        detail.assessment,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(provider.currentAssessment!.id, fixture.assessment.id);
      expect(
        provider.fieldWorkspace!.cropCycle!.id,
        fixture.field.cropCycle.id,
      );
      provider.dispose();
      for (final status in [
        'completed',
        'incomplete',
        'invalid',
        'cancelled',
      ]) {
        expect(assessmentResumeLabel(status), isNull);
      }
    },
  );
}
