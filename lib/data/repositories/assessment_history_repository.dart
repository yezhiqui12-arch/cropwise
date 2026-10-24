import '../../models/automatic_screening.dart';
import 'advisor_model_results_reader.dart';
import 'da_monitoring_repository.dart';
import '../services/scouting_completion_service.dart';
import 'package:drift/drift.dart';

import '../../models/assessment_history_models.dart';
import '../../services/scouting_sampling_protocol.dart';
import '../local/app_database.dart';
import '../local/database_codes.dart';
import 'field_repository.dart';
import 'scouting_workflow_repository.dart';

class FieldInfestationSample {
  const FieldInfestationSample({
    required this.assessmentId,
    required this.completedAt,
    required this.growthStage,
    required this.metricCode,
    required this.positive,
    required this.assessable,
    this.cropCycleId = '',
  });

  final String assessmentId;
  final DateTime completedAt;
  final String growthStage;
  final String metricCode;
  final int positive;
  final int assessable;
  final String cropCycleId;
}

/// Read-only history. Never repairs evidence, runs inference, or writes reviews.
class AssessmentHistoryRepository {
  const AssessmentHistoryRepository(this.database);
  final AppDatabase database;

  /// Statuses across accessible history, independent of filters and pagination.
  Stream<Set<String>> watchRecordedStatuses() => database
      .customSelect(
        '''SELECT DISTINCT a.status FROM assessments a
       JOIN crop_cycles c ON c.id = a.crop_cycle_id
       JOIN fields f ON f.id = c.field_id
       WHERE a.deleted_at IS NULL AND c.deleted_at IS NULL
         AND f.deleted_at IS NULL AND f.is_archived = 0''',
        readsFrom: {database.assessments, database.cropCycles, database.fields},
      )
      .watch()
      .map((rows) => rows.map((row) => row.read<String>('status')).toSet());

  Stream<List<FieldInfestationSample>> watchFieldInfestationSamples(
    String fieldId,
  ) => database
      .customSelect(
        '''
        SELECT a.id AS assessment_id, a.crop_cycle_id, a.completed_at, a.growth_stage,
               m.metric_code, m.numerator, m.denominator
        FROM assessments a
        JOIN crop_cycles c ON c.id = a.crop_cycle_id
        JOIN metric_results m ON m.assessment_id = a.id
        WHERE c.field_id = ? AND a.deleted_at IS NULL AND c.deleted_at IS NULL
          AND m.deleted_at IS NULL AND m.formula_version = a.formula_version
          AND m.scope_id IN (SELECT id FROM assessment_block_runs
                            WHERE assessment_id = a.id AND deleted_at IS NULL)
          AND a.status = 'completed' AND a.completed_at IS NOT NULL
          AND m.metric_code IN ('vegetative_current_infestation_percent',
                                'vt_r2_ip_percent', 'active_ear_infestation_percent')
          AND m.scope_type = 'block' AND m.denominator > 0
        ORDER BY a.completed_at DESC
        ''',
        variables: [Variable(fieldId)],
        readsFrom: {
          database.assessments,
          database.cropCycles,
          database.metricResults,
          database.assessmentBlockRuns,
        },
      )
      .watch()
      .map(
        (rows) => List.unmodifiable(
          rows.map(
            (row) => FieldInfestationSample(
              assessmentId: row.read('assessment_id'),
              cropCycleId: row.read('crop_cycle_id'),
              completedAt: row.read<DateTime>('completed_at'),
              growthStage: row.read('growth_stage'),
              metricCode: row.read('metric_code'),
              positive: row.read('numerator'),
              assessable: row.read('denominator'),
            ),
          ),
        ),
      );

  Stream<List<FieldRecord>> watchFields() =>
      (database.select(database.fields)
            ..where((f) => f.deletedAt.isNull() & f.isArchived.equals(false))
            ..orderBy([(f) => OrderingTerm.asc(f.name)]))
          .watch();

  Stream<List<AssessmentHistoryEntry>> watchPage({
    String? fieldId,
    String? status,
    int limit = 30,
  }) {
    final filters = <String>[
      'a.deleted_at IS NULL',
      'c.deleted_at IS NULL',
      'f.deleted_at IS NULL',
      'f.is_archived = 0',
    ];
    final variables = <Variable>[];
    if (fieldId != null) {
      filters.add('f.id = ?');
      variables.add(Variable(fieldId));
    }
    if (status != null) {
      filters.add('a.status = ?');
      variables.add(Variable(status));
    }
    variables.add(Variable(limit < 1 ? 1 : limit));
    return database
        .customSelect(
          '''
      WITH block_counts AS (
        SELECT assessment_id, COUNT(*) AS blocks
        FROM assessment_block_runs WHERE deleted_at IS NULL
        GROUP BY assessment_id
      ), station_counts AS (
        SELECT b.assessment_id, COUNT(*) AS stations
        FROM stations s
        JOIN assessment_block_runs b ON b.id=s.assessment_block_run_id
        WHERE b.deleted_at IS NULL AND s.deleted_at IS NULL
        GROUP BY b.assessment_id
      ), plant_counts AS (
        SELECT b.assessment_id, COUNT(*) AS plants
        FROM plant_observations p
        JOIN stations s ON s.id=p.station_id
        JOIN assessment_block_runs b ON b.id=s.assessment_block_run_id
        WHERE b.deleted_at IS NULL AND s.deleted_at IS NULL
          AND p.deleted_at IS NULL
        GROUP BY b.assessment_id
      ), position_counts AS (
        SELECT b.assessment_id, COUNT(*) AS positions
        FROM planting_unit_observations p
        JOIN stations s ON s.id=p.station_id
        JOIN assessment_block_runs b ON b.id=s.assessment_block_run_id
        WHERE b.deleted_at IS NULL AND s.deleted_at IS NULL
          AND p.deleted_at IS NULL
        GROUP BY b.assessment_id
      ), photo_counts AS (
        SELECT assessment_id, COUNT(*) AS photos
        FROM evidence_media
        WHERE deleted_at IS NULL AND storage_state='ready'
        GROUP BY assessment_id
      )
      SELECT a.id, f.id AS field_id, f.name AS field_name, a.status,
        a.growth_stage, a.scouting_pattern, a.created_at, a.started_at,
        COALESCE(bc.blocks, 0) AS blocks,
        COALESCE(sc.stations, 0) AS stations,
        COALESCE(pc.plants, 0) AS plants,
        COALESCE(uc.positions, 0) AS positions,
        COALESCE(mc.photos, 0) AS photos,
        (
          SELECT COALESCE(em.thumbnail_local_uri, em.local_uri)
          FROM evidence_media em
          WHERE em.assessment_id = a.id
            AND em.deleted_at IS NULL
            AND em.storage_state = 'ready'
            AND em.media_type = 'image'
          ORDER BY RANDOM()
          LIMIT 1
        ) AS evidence_thumbnail_uri
      FROM assessments a JOIN crop_cycles c ON c.id=a.crop_cycle_id
      JOIN fields f ON f.id=c.field_id
      LEFT JOIN block_counts bc ON bc.assessment_id=a.id
      LEFT JOIN station_counts sc ON sc.assessment_id=a.id
      LEFT JOIN plant_counts pc ON pc.assessment_id=a.id
      LEFT JOIN position_counts uc ON uc.assessment_id=a.id
      LEFT JOIN photo_counts mc ON mc.assessment_id=a.id
      WHERE ${filters.join(' AND ')}
      ORDER BY COALESCE(a.started_at,a.created_at) DESC, a.id DESC LIMIT ?
    ''',
          variables: variables,
          readsFrom: {
            database.assessments,
            database.fields,
            database.cropCycles,
            database.assessmentBlockRuns,
            database.stations,
            database.plantObservations,
            database.plantingUnitObservations,
            database.evidenceMedia,
          },
        )
        .watch()
        .map(
          (rows) => List.unmodifiable(
            rows.map(
              (r) => AssessmentHistoryEntry(
                id: r.read('id'),
                fieldId: r.read('field_id'),
                fieldName: r.read('field_name'),
                status: r.read('status'),
                growthStage: r.read('growth_stage'),
                pattern: r.read('scouting_pattern'),
                createdAt: r.read<DateTime>('created_at'),
                startedAt: r.readNullable<DateTime>('started_at'),
                blocks: r.read('blocks'),
                stations: r.read('stations'),
                plants: r.read('plants'),
                positions: r.read('positions'),
                photos: r.read('photos'),
                evidenceThumbnailUri: r.readNullable<String>(
                  'evidence_thumbnail_uri',
                ),
              ),
            ),
          ),
        );
  }

  Stream<AssessmentHistoryDetail?> watchDetail(String id) => database
      .customSelect(
        'SELECT id FROM assessments WHERE id = ?',
        variables: [Variable(id)],
        readsFrom: {
          database.people,
          database.fields,
          database.fieldBoundaryVersions,
          database.cropCycles,
          database.fieldBlocks,
          database.assessments,
          database.safetyChecks,
          database.assessmentBlockRuns,
          database.stations,
          database.plantingUnitObservations,
          database.plantObservations,
          database.veV2StationInspections,
          database.vegetativeObservations,
          database.reproductiveObservations,
          database.lateSeasonAssessmentSetups,
          database.earOpeningSelections,
          database.earObservations,
          database.evidenceCaptureSessions,
          database.evidenceMedia,
          database.metricResults,
          database.auditLogs,
          database.appPreferences,
        },
      )
      .watch()
      .asyncMap((_) => loadDetail(id));

  Future<AssessmentHistoryDetail?> loadDetail(String id) async {
    final a = await (database.select(
      database.assessments,
    )..where((r) => r.id.equals(id) & r.deletedAt.isNull())).getSingleOrNull();
    if (a == null) return null;
    final cycle =
        await (database.select(database.cropCycles)
              ..where((r) => r.id.equals(a.cropCycleId) & r.deletedAt.isNull()))
            .getSingleOrNull();
    if (cycle == null) return null;
    final field =
        await (database.select(database.fields)
              ..where((r) => r.id.equals(cycle.fieldId) & r.deletedAt.isNull()))
            .getSingleOrNull();
    if (field == null) return null;
    // Historical context always uses the assessment's boundary version.
    final boundary = await (database.select(
      database.fieldBoundaryVersions,
    )..where((r) => r.id.equals(a.boundaryVersionId))).getSingleOrNull();
    final person = await (database.select(
      database.people,
    )..where((r) => r.id.equals(a.evaluatorPersonId))).getSingleOrNull();
    final runs =
        await (database.select(database.assessmentBlockRuns)
              ..where((r) => r.assessmentId.equals(id) & r.deletedAt.isNull())
              ..orderBy([(r) => OrderingTerm.asc(r.blockSequence)]))
            .get();
    final snapshots = <StationSnapshot>[];
    var missingBlocks = 0;
    final workflow = ScoutingWorkflowRepository(database);
    final blocks = runs.isEmpty
        ? <FieldBlockRecord>[]
        : await (database.select(database.fieldBlocks)..where(
                (row) =>
                    row.id.isIn(runs.map((run) => run.fieldBlockId)) &
                    row.deletedAt.isNull(),
              ))
              .get();
    final blockById = {for (final block in blocks) block.id: block};
    for (final run in runs) {
      final block = blockById[run.fieldBlockId];
      if (block == null) {
        missingBlocks++;
        continue;
      }
      final prepared = PreparedScoutingRun(block: block, run: run);
      snapshots.addAll(
        await Future.wait([
          for (
            var number = 1;
            number <= ScoutingSamplingProtocol.locationCount(a.protocolVersion);
            number++
          )
            workflow.loadStationSnapshot(prepared, stationNumber: number),
        ]),
      );
    }
    final stationIds = snapshots
        .map((s) => s.station?.id)
        .whereType<String>()
        .toList();
    final units = stationIds.isEmpty
        ? <PlantingUnitObservationRecord>[]
        : await (database.select(database.plantingUnitObservations)
                ..where(
                  (r) => r.stationId.isIn(stationIds) & r.deletedAt.isNull(),
                )
                ..orderBy([(r) => OrderingTerm.asc(r.sequenceNumber)]))
              .get();
    final sessions = await (database.select(
      database.evidenceCaptureSessions,
    )..where((r) => r.assessmentId.equals(id))).get();
    final media =
        await (database.select(database.evidenceMedia)
              ..where(
                (r) =>
                    r.assessmentId.equals(id) &
                    r.deletedAt.isNull() &
                    r.storageState.isIn(['ready', 'missing']),
              )
              ..orderBy([
                (r) => OrderingTerm.asc(r.capturedAt),
                (r) => OrderingTerm.asc(r.id),
              ]))
            .get();
    final stationLabels = {
      for (final s in snapshots)
        if (s.station != null)
          s.station!.id:
              'Block ${s.prepared.run.blockSequence} · ${s.requiredPlantCount == 1 ? 'Plant' : 'Station'} ${s.stationNumber}',
    };
    final plantPositions = {
      for (final s in snapshots)
        for (final p in s.plants) p.plant.id: p.plant.sequenceNumber,
    };
    final unitPositions = {for (final u in units) u.id: u.sequenceNumber};
    final sessionById = {for (final s in sessions) s.id: s};
    final evidence = media.map((m) {
      final session = sessionById[m.captureSessionId];
      final plantObservationId =
          m.plantObservationId ?? session?.plantObservationId;
      final scopeType =
          session?.scopeType ??
          (plantObservationId != null
              ? DatabaseCodes.evidenceScopePlant
              : m.plantingUnitObservationId != null
              ? DatabaseCodes.evidenceScopePlantingUnit
              : DatabaseCodes.evidenceScopeStationContext);
      final station =
          stationLabels[m.stationId ?? session?.stationId] ??
          'Assessment evidence';
      final unit = unitPositions[m.plantingUnitObservationId];
      final position =
          plantPositions[plantObservationId] ?? session?.plantPosition;
      final subject =
          scopeType == DatabaseCodes.evidenceScopePlant && position != null
          ? '${const {'ve', 'v1', 'v2'}.contains(a.growthStage) ? 'Seedling' : 'Plant'} $position'
          : unit != null
          ? 'Planting position $unit'
          : 'Station context';
      return AssessmentEvidenceEntry(
        m,
        ScoutingSamplingProtocol.isDa(a.protocolVersion)
            ? station
            : '$station · $subject',
        stationId: m.stationId ?? session?.stationId,
        plantObservationId: plantObservationId,
        plantPosition: position,
        scopeType: scopeType,
      );
    }).toList();
    evidence.sort((a, b) => a.scope.compareTo(b.scope));
    final safety =
        await (database.select(database.safetyChecks)
              ..where((r) => r.assessmentId.equals(id) & r.deletedAt.isNull())
              ..orderBy([(r) => OrderingTerm.desc(r.checkedAt)])
              ..limit(1))
            .getSingleOrNull();
    final metrics =
        await (database.select(database.metricResults)
              ..where(
                (r) =>
                    r.assessmentId.equals(id) &
                    r.deletedAt.isNull() &
                    r.formulaVersion.equals(a.formulaVersion) &
                    r.scopeType.equals('block') &
                    r.scopeId.isIn(runs.map((run) => run.id)),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.metricCode)]))
            .get();
    final readiness = await ScoutingCompletionService(
      database,
    ).validateAssessment(id);
    final models = await AdvisorModelResultsReader(database).load(
      assessmentId: id,
      stations: snapshots
          .map((s) => s.station)
          .whereType<StationRecord>()
          .toList(),
      plants: [
        for (final s in snapshots)
          for (final p in s.plants) p.plant,
      ],
    );
    return AssessmentHistoryDetail(
      daMonitoringData: (await DaMonitoringRepository(database).load(id)).data,
      modelScreenings: {
        for (final sample in models.samples)
          '${sample.stationId}:${sample.position}': sample.result == null
              ? null
              : AutomaticScreening(
                  sample.result!,
                  evidenceSignature: sample.images.isEmpty
                      ? null
                      : (sample.images.map((m) => m.sha256Checksum).toList()
                              ..sort())
                            .join(':'),
                ),
      },
      assessment: a,
      metrics: List.unmodifiable(metrics),
      workspace: FieldWorkspaceRecord(
        field: field,
        boundary: boundary,
        cropCycle: cycle,
      ),
      evaluator: person?.displayName ?? 'Evaluator unavailable',
      stations: List.unmodifiable(snapshots),
      units: List.unmodifiable(units),
      evidence: List.unmodifiable(evidence),
      safety: safety,
      missingBlocks: missingBlocks,
      readiness: readiness,
      resultSummary: AssessmentResultSummary.fromRecords(
        growthStage: a.growthStage,
        formulaVersion: a.formulaVersion,
        stations: snapshots,
        blockMetrics: metrics,
        readiness: readiness,
      ),
    );
  }
}
