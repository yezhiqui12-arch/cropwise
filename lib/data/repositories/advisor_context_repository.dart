import 'advisor_model_results_reader.dart';
import 'da_monitoring_repository.dart';
import '../../services/advisor/advisor_assessment_contract.dart';
import '../../services/scouting_sampling_protocol.dart';
import '../../models/da_monitoring.dart';
import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../../services/advisor/advisor_open_chat_service.dart';

class AdvisorMetricSnapshot {
  const AdvisorMetricSnapshot({
    required this.code,
    required this.label,
    required this.unit,
    required this.value,
    required this.numerator,
    required this.denominator,
    required this.formulaVersion,
    required this.validationStatus,
    required this.calculatedAt,
    this.scopeType = 'unknown',
    this.scopeId,
    this.blockSequence,
    this.warningCode,
  });

  final String code;
  final String label;
  final String unit;
  final double? value;
  final double? numerator;
  final double? denominator;
  final String formulaVersion;
  final String validationStatus;
  final DateTime calculatedAt;
  final String scopeType;
  final String? scopeId;
  final int? blockSequence;
  final String? warningCode;
}

class AdvisorAssessmentSnapshot {
  const AdvisorAssessmentSnapshot({
    required this.id,
    required this.status,
    required this.growthStage,
    required this.growthStageUncertain,
    required this.scoutingPattern,
    required this.protocolVersion,
    required this.formulaVersion,
    required this.totalBlocks,
    required this.completedBlocks,
    required this.stationRecords,
    required this.plantRecords,
    required this.assessablePlants,
    required this.evidencePhotoCount,
    required this.metrics,
    this.blockCoverage = const [],
    this.findingSummary = const {},
    this.weatherContext,
    this.startedAt,
    this.completedAt,
    this.expertReview = const {},
  });

  final String id;
  final String status;
  final String growthStage;
  final bool growthStageUncertain;
  final String scoutingPattern;
  final String protocolVersion;
  final String formulaVersion;
  final int totalBlocks;
  final int completedBlocks;
  final int stationRecords;
  final int plantRecords;
  final int assessablePlants;
  final int evidencePhotoCount;
  final List<AdvisorMetricSnapshot> metrics;
  final List<Map<String, dynamic>> blockCoverage;
  final Map<String, dynamic> findingSummary;
  final String? weatherContext;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final Map<String, dynamic> expertReview;
  Map<String, dynamic> get sampling =>
      AdvisorAssessmentContract.sampling(protocolVersion, totalBlocks);
  Map<String, dynamic> get sampledInfestation =>
      AdvisorAssessmentContract.infestation(
        model: Map<String, dynamic>.from(
          findingSummary['sampled_infestation'] as Map? ?? const {},
        ),
        review: expertReview,
        plannedPlants: sampling['planned_plants'] as int?,
      );

  bool get isCompleted => status == DatabaseCodes.completed;
  bool get isSafetyBlocked => status == DatabaseCodes.safetyBlocked;
}

class AdvisorFieldContextSnapshot {
  const AdvisorFieldContextSnapshot({
    required this.fieldId,
    required this.fieldName,
    required this.hasConfirmedOutline,
    required this.hasSeparateModelFindingProvenance,
    this.barangay,
    this.areaHectares,
    this.boundaryGeoJson,
    this.centroidLatitude,
    this.centroidLongitude,
    this.varietyName,
    this.plantingDate,
    this.assessment,
  });

  final String fieldId;
  final String fieldName;
  final String? barangay;
  final double? areaHectares;
  final String? boundaryGeoJson;
  final double? centroidLatitude;
  final double? centroidLongitude;
  final bool hasConfirmedOutline;
  final String? varietyName;
  final DateTime? plantingDate;
  final AdvisorAssessmentSnapshot? assessment;

  /// True when independently saved plant/cache model output was found.
  final bool hasSeparateModelFindingProvenance;
}

/// Read-only projection of local field and assessment records for the Guide.
class AdvisorContextRepository implements AdvisorDataTools {
  const AdvisorContextRepository(this.database, {this.readExpertReview});

  final AppDatabase database;
  final Map<String, dynamic> Function(String assessmentId)? readExpertReview;

  @override
  Future<Map<String, dynamic>> read(
    String tool,
    Map<String, dynamic> arguments,
  ) async {
    if (tool == 'get_assessment_catalog') return _assessmentCatalog(arguments);
    if (tool == 'list_fields') {
      final rows =
          await (database.select(database.fields)
                ..where((r) => r.deletedAt.isNull())
                ..orderBy([(r) => OrderingTerm.asc(r.name)]))
              .get();
      return {
        'fields': [
          for (final r in rows)
            {'id': r.id, 'name': r.name, 'archived': r.isArchived},
        ],
        'truncated': false,
      };
    }
    final fieldId = arguments['field_id'];
    if (fieldId is! String) {
      return {'error': 'A field_id from list_fields is required.'};
    }
    final field =
        await (database.select(database.fields)
              ..where((r) => r.id.equals(fieldId) & r.deletedAt.isNull()))
            .getSingleOrNull();
    if (field == null) return {'error': 'Field is unavailable.'};
    final cycles =
        await (database.select(database.cropCycles)
              ..where((r) => r.fieldId.equals(fieldId) & r.deletedAt.isNull())
              ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
            .get();
    if (tool == 'get_field') {
      final boundary = field.activeBoundaryVersionId == null
          ? null
          : await (database.select(database.fieldBoundaryVersions)
                  ..where((b) => b.id.equals(field.activeBoundaryVersionId!)))
                .getSingleOrNull();
      return {
        'id': field.id,
        'name': field.name,
        'archived': field.isArchived,
        'area_hectares': boundary?.areaHectares,
        'crop_cycles': [
          for (final c in cycles)
            {
              'id': c.id,
              'status': c.status,
              'variety': c.varietyName,
              'planting_date': c.plantingDate?.toIso8601String(),
            },
        ],
        'truncated': false,
      };
    }
    final cycleIds = cycles.map((c) => c.id).toList();
    final assessments =
        await (database.select(database.assessments)
              ..where(
                (r) => r.cropCycleId.isIn(cycleIds) & r.deletedAt.isNull(),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
            .get();
    if (tool == 'list_assessments') {
      return {
        'field_name': field.name,
        'assessments': [
          for (final a in assessments)
            {
              'id': a.id,
              'crop_cycle_id': a.cropCycleId,
              'status': a.status,
              'growth_stage': a.growthStage,
              'created_at': a.createdAt.toIso8601String(),
              'completed_at': a.completedAt?.toIso8601String(),
            },
        ],
        'truncated': false,
      };
    }
    final assessmentId = arguments['assessment_id'];
    final assessment = assessmentId == null
        ? (assessments.isEmpty ? null : assessments.first)
        : await (database.select(database.assessments)..where(
                (r) =>
                    r.id.equals(assessmentId.toString()) &
                    r.cropCycleId.isIn(cycleIds) &
                    r.deletedAt.isNull(),
              ))
              .getSingleOrNull();
    if (assessment == null) {
      return {'field_name': field.name, 'assessment': null};
    }
    if (tool == 'get_assessment_samples') {
      return _samples(field, assessment, arguments);
    }
    if (tool != 'get_assessment') return {'error': 'Unknown read tool.'};
    final a = await _assessmentSnapshot(assessment);
    return {
      'field_name': field.name,
      'field_id': field.id,
      'assessment_id': a.id,
      'created_at': assessment.createdAt.toIso8601String(),
      'completed_at': a.completedAt?.toIso8601String(),
      'status': a.status,
      'growth_stage': a.growthStage,
      'growth_stage_uncertain': a.growthStageUncertain,
      'sampling': a.sampling,
      'sampled_infestation': a.sampledInfestation,
      'finalized_expert_findings': AdvisorAssessmentContract.finalized(
        a.expertReview,
      ),
      'blocks': {'completed': a.completedBlocks, 'total': a.totalBlocks},
      'stations': a.stationRecords,
      'block_coverage': a.blockCoverage,
      'finding_summary': a.findingSummary,
      'plant_records': a.plantRecords,
      'evidence': {'evidence_photos': a.evidencePhotoCount},
      'weather': a.weatherContext,
      'field_entry_safety': assessment.safetySummaryStatus,
      'supporting_metrics_available': false,
      'metric_interpretation':
          'Stored supporting block metrics are excluded. Use saved sample counts and CV results, with their eligible counts. Do not reconstruct the removed supporting percentages or treat historical chat claims as current evidence.',
      'expert_review': a.expertReview,
      'sample_details_tool': 'get_assessment_samples',
      'model_provenance':
          'Model 1 counts use saved classifications from plant records or evidence-matched model caches. Per-plant results and optional detector findings are available through get_assessment_samples. No manual observation results are supplied.',
    };
  }

  /// Every non-deleted assessment in this account's local database, across
  /// all crop cycles and fields (including archived fields). No active filter.
  Future<Map<String, dynamic>> _assessmentCatalog(
    Map<String, dynamic> arguments,
  ) async {
    final fields =
        await (database.select(database.fields)
              ..where((f) => f.deletedAt.isNull())
              ..orderBy([(f) => OrderingTerm.asc(f.name)]))
            .get();
    final cycles =
        await (database.select(database.cropCycles)..where(
              (c) =>
                  c.fieldId.isIn(fields.map((f) => f.id)) &
                  c.deletedAt.isNull(),
            ))
            .get();
    final records =
        await (database.select(database.assessments)
              ..where(
                (a) =>
                    a.cropCycleId.isIn(cycles.map((c) => c.id)) &
                    a.deletedAt.isNull(),
              )
              ..orderBy([
                (a) => OrderingTerm.desc(a.createdAt),
                (a) => OrderingTerm.asc(a.id),
              ]))
            .get();
    final fieldById = {for (final f in fields) f.id: f};
    final cycleById = {for (final c in cycles) c.id: c};
    final totals = <String, int>{};
    for (final a in records) {
      totals[a.status] = (totals[a.status] ?? 0) + 1;
    }
    final offset =
        (arguments['offset'] is num ? (arguments['offset'] as num).toInt() : 0)
            .clamp(0, records.length);
    final limit =
        (arguments['limit'] is num ? (arguments['limit'] as num).toInt() : 40)
            .clamp(1, 100);
    final page = records.skip(offset).take(limit).toList();
    final rows = <Map<String, dynamic>>[];
    // Bounded concurrency prevents one query burst per plant/assessment.
    for (var start = 0; start < page.length; start += 4) {
      rows.addAll(
        await Future.wait(
          page.skip(start).take(4).map((record) async {
            final cycle = cycleById[record.cropCycleId]!;
            final field = fieldById[cycle.fieldId]!;
            final snapshot = await _assessmentSnapshot(record);
            final expert = AdvisorAssessmentContract.finalized(
              snapshot.expertReview,
            );
            return <String, dynamic>{
              'id': record.id,
              'field_id': field.id,
              'field_name': field.name,
              'crop_cycle_id': cycle.id,
              'crop_cycle_status': cycle.status,
              'field_archived': field.isArchived,
              'variety': cycle.varietyName,
              'planting_date': cycle.plantingDate?.toIso8601String(),
              'status': record.status,
              'growth_stage': record.growthStage,
              'created_at': record.createdAt.toIso8601String(),
              'started_at': record.startedAt?.toIso8601String(),
              'completed_at': record.completedAt?.toIso8601String(),
              'field_entry_safety': record.safetySummaryStatus,
              'recorded_weather': record.weatherContext,
              'sampling': snapshot.sampling,
              'recorded_plants': snapshot.plantRecords,
              'evidence_photos': snapshot.evidencePhotoCount,
              'damage_screen':
                  snapshot.findingSummary['automatic_damage_screen'],
              'sampled_infestation': snapshot.sampledInfestation,
              'expert_findings': expert == null
                  ? null
                  : {
                      for (final key in const [
                        'mean_davis_score',
                        'scored_plants',
                        'reviewed_plants',
                        'insufficient_plants',
                        'score_distribution',
                        'finalized_at',
                      ])
                        key: expert[key],
                    },
              'details_available': ['get_assessment', 'get_assessment_samples'],
              'expert_review_availability':
                  snapshot.expertReview['availability'],
            };
          }),
        ),
      );
    }
    final next = offset + page.length;
    return {
      'scope': 'all_saved_fields_and_crop_cycles',
      'total_assessments': records.length,
      'total_fields': fields.length,
      'status_counts': totals,
      'fields': [
        for (final f in fields)
          {'id': f.id, 'name': f.name, 'archived': f.isArchived},
      ],
      'assessments': rows,
      'offset': offset,
      'next_offset': next < records.length ? next : null,
      'truncated': next < records.length,
      'meaning':
          'Includes completed, draft, in-progress and other saved statuses across all non-deleted crop cycles. The selected assessment is not the full inventory. Archived fields are read-only history. Local records only; unsynchronized records from another device may be unavailable.',
    };
  }

  Future<Map<String, dynamic>> _samples(
    FieldRecord field,
    AssessmentRecord assessment,
    Map<String, dynamic> arguments,
  ) async {
    final runs =
        await (database.select(database.assessmentBlockRuns)
              ..where(
                (r) =>
                    r.assessmentId.equals(assessment.id) & r.deletedAt.isNull(),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.blockSequence)]))
            .get();
    final stations =
        await (database.select(database.stations)
              ..where(
                (s) =>
                    s.assessmentBlockRunId.isIn(runs.map((r) => r.id)) &
                    s.deletedAt.isNull(),
              )
              ..orderBy([(s) => OrderingTerm.asc(s.stationNumber)]))
            .get();
    final plants =
        await (database.select(database.plantObservations)..where(
              (p) =>
                  p.stationId.isIn(stations.map((s) => s.id)) &
                  p.deletedAt.isNull(),
            ))
            .get();
    final models = await AdvisorModelResultsReader(
      database,
    ).load(assessmentId: assessment.id, stations: stations, plants: plants);
    final selected = models.samples
        .where(
          (s) =>
              arguments['station_id'] == null ||
              s.stationId == arguments['station_id'],
        )
        .toList();
    final offset =
        (arguments['offset'] is num ? (arguments['offset'] as num).toInt() : 0)
            .clamp(0, selected.length);
    List<Map<String, dynamic>> streaks(List<AdvisorModelSample> samples) {
      final found = <Map<String, dynamic>>[];
      var current = <int>[];
      void flush() {
        if (current.length >= 2) {
          found.add({
            'from': current.first,
            'to': current.last,
            'count': current.length,
          });
        }
        current = [];
      }

      for (final sample in samples) {
        if (!sample.positive) {
          flush();
          continue;
        }
        if (current.isNotEmpty && sample.position != current.last + 1) flush();
        current.add(sample.position);
      }
      flush();
      return found;
    }

    return {
      'field_id': field.id,
      'field_name': field.name,
      'assessment_id': assessment.id,
      'status': assessment.status,
      'growth_stage': assessment.growthStage,
      'sampling': AdvisorAssessmentContract.sampling(
        assessment.protocolVersion,
        runs.length,
      ),
      'finding_summary': models.summary,
      'stations': [
        for (final station in stations)
          {
            'id': station.id,
            'station_number': station.stationNumber,
            if (ScoutingSamplingProtocol.isDa(assessment.protocolVersion))
              'display_label': 'Plant ${station.stationNumber}',
            'block_run_id': station.assessmentBlockRunId,
            'block': runs
                .firstWhere((r) => r.id == station.assessmentBlockRunId)
                .blockSequence,
            'sample_count': models.samples
                .where((s) => s.stationId == station.id)
                .length,
            'damage_screen': (AdvisorModelResults(
              models.samples.where((s) => s.stationId == station.id).toList(),
            ).summary['automatic_damage_screen']),
            'consecutive_damage_screen_positive': streaks(
              models.samples.where((s) => s.stationId == station.id).toList(),
            ),
          },
      ],
      'plants': [
        for (final sample in selected.skip(offset).take(20))
          {
            'plant_observation_id': sample.plant?.id,
            'station_id': sample.stationId,
            'sequence': sample.position,
            'block_run_id': stations
                .firstWhere((s) => s.id == sample.stationId)
                .assessmentBlockRunId,
            'block_sequence': runs
                .firstWhere(
                  (r) =>
                      r.id ==
                      stations
                          .firstWhere((s) => s.id == sample.stationId)
                          .assessmentBlockRunId,
                )
                .blockSequence,
            if (ScoutingSamplingProtocol.isDa(assessment.protocolVersion))
              'plant_number': stations
                  .firstWhere((s) => s.id == sample.stationId)
                  .stationNumber,
            'model_result_availability': sample.availability,
            'model_result_source': sample.source,
            'model_result': sample.eligible ? sample.modelJson : null,
            'images': [
              for (final media in sample.images)
                {
                  'id': media.id,
                  'view': media.viewType,
                  'quality': media.qualityStatus,
                  'storage_state': media.storageState,
                  'captured_at': media.capturedAt?.toIso8601String(),
                },
            ],
          },
      ],
      'total_matching_plants': selected.length,
      'offset': offset,
      'next_offset': offset + 20 < selected.length ? offset + 20 : null,
      'model_result_scope':
          'Saved plant-level Model 1 classification and optional detector findings. '
          'Photo checkpoints and merged plant results are saved; cached results must match current evidence checksums. '
          'Missing saved output does not establish that the model was never run.',
      'interpretation':
          'Only CV findings are supplied. Manual infestation and old manual observation categories '
          'are excluded. Consecutive sample positions are not proof of physical adjacency or spread. '
          'Damage-screen positives do not confirm active infestation. Images are metadata; do not claim to inspect raw photos.',
    };
  }

  Future<AdvisorFieldContextSnapshot?> load({
    required String? fieldId,
    required String? cropCycleId,
    String? preferredAssessmentId,
  }) async {
    if (fieldId == null) return null;

    final field =
        await (database.select(database.fields)
              ..where((row) => row.id.equals(fieldId) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (field == null) return null;

    final boundary = field.activeBoundaryVersionId == null
        ? null
        : await (database.select(database.fieldBoundaryVersions)..where(
                (row) =>
                    row.id.equals(field.activeBoundaryVersionId!) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
    final cycle = cropCycleId == null
        ? null
        : await (database.select(database.cropCycles)..where(
                (row) => row.id.equals(cropCycleId) & row.deletedAt.isNull(),
              ))
              .getSingleOrNull();

    final assessment = cycle == null
        ? null
        : await _latestAssessment(
            cropCycleId: cycle.id,
            preferredAssessmentId: preferredAssessmentId,
          );

    final savedAssessment = assessment == null
        ? null
        : await _assessmentSnapshot(assessment);
    return AdvisorFieldContextSnapshot(
      fieldId: field.id,
      fieldName: field.name,
      barangay: field.barangay,
      areaHectares: boundary?.areaHectares,
      boundaryGeoJson: boundary?.geometryGeojson,
      centroidLatitude: boundary?.centroidLatitude,
      centroidLongitude: boundary?.centroidLongitude,
      hasConfirmedOutline: boundary?.confirmationStatus == 'user_confirmed',
      varietyName: cycle?.varietyName,
      plantingDate: cycle?.plantingDate,
      assessment: savedAssessment,
      hasSeparateModelFindingProvenance:
          ((savedAssessment?.findingSummary['automatic_damage_screen']
                      as Map?)?['eligible_count']
                  as int? ??
              0) >
          0,
    );
  }

  Future<AssessmentRecord?> _latestAssessment({
    required String cropCycleId,
    String? preferredAssessmentId,
  }) async {
    if (preferredAssessmentId != null) {
      final preferred =
          await (database.select(database.assessments)..where(
                (row) =>
                    row.id.equals(preferredAssessmentId) &
                    row.cropCycleId.equals(cropCycleId) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (preferred != null) return preferred;
    }

    final query = database.select(database.assessments)
      ..where(
        (row) => row.cropCycleId.equals(cropCycleId) & row.deletedAt.isNull(),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<AdvisorAssessmentSnapshot> _assessmentSnapshot(
    AssessmentRecord assessment,
  ) async {
    final runs =
        await (database.select(database.assessmentBlockRuns)
              ..where(
                (row) =>
                    row.assessmentId.equals(assessment.id) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.blockSequence)]))
            .get();
    final runIds = runs.map((run) => run.id).toList(growable: false);
    final stations = runIds.isEmpty
        ? const <StationRecord>[]
        : await (database.select(database.stations)..where(
                (row) =>
                    row.assessmentBlockRunId.isIn(runIds) &
                    row.deletedAt.isNull(),
              ))
              .get();
    final stationIds = stations.map((station) => station.id).toList();
    final plants = stationIds.isEmpty
        ? const <PlantObservationRecord>[]
        : await (database.select(database.plantObservations)..where(
                (row) =>
                    row.stationId.isIn(stationIds) & row.deletedAt.isNull(),
              ))
              .get();
    final evidence =
        await (database.select(database.evidenceMedia)..where(
              (row) =>
                  row.assessmentId.equals(assessment.id) &
                  row.deletedAt.isNull() &
                  row.isCanonicalEvidence.equals(true) &
                  row.storageState.equals(DatabaseCodes.evidenceStorageReady),
            ))
            .get();
    final modelResults = await AdvisorModelResultsReader(
      database,
    ).load(assessmentId: assessment.id, stations: stations, plants: plants);
    final monitoring = await DaMonitoringRepository(
      database,
    ).load(assessment.id);
    return AdvisorAssessmentSnapshot(
      id: assessment.id,
      status: assessment.status,
      growthStage: assessment.growthStage,
      growthStageUncertain: assessment.growthStageUncertain,
      scoutingPattern: assessment.scoutingPattern,
      protocolVersion: assessment.protocolVersion,
      formulaVersion: assessment.formulaVersion,
      totalBlocks: runs.length,
      completedBlocks: runs
          .where((run) => run.status == DatabaseCodes.completed)
          .length,
      stationRecords: stations.length,
      plantRecords: plants.length,
      assessablePlants: plants.where((plant) => plant.assessable).length,
      evidencePhotoCount: evidence.length,
      metrics: const [],
      blockCoverage: [
        for (final run in runs)
          {
            'block_run_id': run.id,
            'block_sequence': run.blockSequence,
            'status': run.status,
            if (ScoutingSamplingProtocol.isDa(assessment.protocolVersion))
              'planned_plants': ScoutingSamplingProtocol.plantsPerBlock,
            'model_results': AdvisorModelResults(
              modelResults.samples
                  .where(
                    (sample) => stations.any(
                      (station) =>
                          station.id == sample.stationId &&
                          station.assessmentBlockRunId == run.id,
                    ),
                  )
                  .toList(),
            ).summary,
            'station_records': stations
                .where((station) => station.assessmentBlockRunId == run.id)
                .length,
            'sampled_station_count': stations
                .where(
                  (station) =>
                      station.assessmentBlockRunId == run.id &&
                      plants.any((plant) => plant.stationId == station.id),
                )
                .length,
            'plant_records': plants
                .where(
                  (plant) => stations.any(
                    (station) =>
                        station.id == plant.stationId &&
                        station.assessmentBlockRunId == run.id,
                  ),
                )
                .length,
          },
      ],
      findingSummary: {
        ...modelResults.summary,
        if (ScoutingSamplingProtocol.isDa(assessment.protocolVersion))
          'da_monitoring_observations': {
            'natural_enemies': [
              for (final run in runs)
                {
                  'block_run_id': run.id,
                  'block_sequence': run.blockSequence,
                  'observations': monitoring.enemies(run.id),
                },
            ],
            'plant_presence': [
              for (final sample in modelResults.samples)
                {
                  'station_id': sample.stationId,
                  'plant_number': stations
                      .firstWhere((s) => s.id == sample.stationId)
                      .stationNumber,
                  'block_run_id': stations
                      .firstWhere((s) => s.id == sample.stationId)
                      .assessmentBlockRunId,
                  'presence':
                      DaPlantFinding.fromModel(
                            sample.eligible ? sample.result : null,
                          )
                          .withCorrections(
                            monitoring.plant(
                              stations
                                  .firstWhere((s) => s.id == sample.stationId)
                                  .assessmentBlockRunId,
                              stations
                                  .firstWhere((s) => s.id == sample.stationId)
                                  .stationNumber,
                            ),
                            daPhotoSignature(sample.images),
                          )
                          .values,
                },
            ],
            'meaning':
                'DA report presence observations; optional farmer corrections do not change CV predictions or expert scores',
          },
      },
      expertReview:
          readExpertReview?.call(assessment.id) ??
          const {'availability': 'unavailable'},
      weatherContext: assessment.weatherContext,
      startedAt: assessment.startedAt,
      completedAt: assessment.completedAt,
    );
  }
}
