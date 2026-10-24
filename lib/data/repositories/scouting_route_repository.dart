import 'package:drift/drift.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../services/scouting_route_generator.dart';
import '../../services/scouting_sampling_protocol.dart';
import '../local/app_database.dart';
import '../local/database_codes.dart';
import 'local_mutation_recorder.dart';
import 'scouting_workflow_repository.dart';

class ScoutingRouteRepository {
  ScoutingRouteRepository(this.database)
    : _mutations = LocalMutationRecorder(database);

  final AppDatabase database;
  final LocalMutationRecorder _mutations;

  Future<ScoutingRoutePlan?> loadPlan(String blockRunId) async {
    final run = await (database.select(
      database.assessmentBlockRuns,
    )..where((row) => row.id.equals(blockRunId))).getSingle();
    final value = run.routeGeojson;
    if (value == null || value.trim().isEmpty) return null;
    try {
      final plan = ScoutingRoutePlan.fromGeoJson(value);
      if (plan.blockRunId != blockRunId) {
        throw const FormatException('Route document belongs to another block.');
      }
      return plan;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Saved route guidance is unreadable and was not overwritten.',
      );
    }
  }

  Future<ScoutingRoutePlan> loadOrCreateDraft({
    required AssessmentRecord assessment,
    required PreparedScoutingRun prepared,
  }) async {
    final existing = await loadPlan(prepared.run.id);
    if (existing != null) return existing;
    final draft = ScoutingRoutePlan(
      assessmentId: assessment.id,
      blockRunId: prepared.run.id,
      blockId: prepared.block.id,
      boundaryVersionId: prepared.block.boundaryVersionId,
      pattern: prepared.run.scoutingPattern,
      status: ScoutingRouteStatus.draft,
      preparation: const RoutePreparationData(),
      updatedAt: DateTime.now().toUtc(),
    );
    return savePlan(
      draft,
      actorPersonId: assessment.evaluatorPersonId,
      action: 'route_preparation_started',
    );
  }

  Future<ScoutingRoutePlan> savePreparationDraft(
    ScoutingRoutePlan plan,
    RoutePreparationData preparation, {
    required String actorPersonId,
  }) {
    return savePlan(
      plan.copyWith(
        status: ScoutingRouteStatus.draft,
        preparation: preparation,
        pendingAdjustment: null,
        arrivalConfirmedStation: null,
        updatedAt: DateTime.now().toUtc(),
      ),
      actorPersonId: actorPersonId,
      action: 'route_preparation_saved',
      queueForSync: false,
    );
  }

  Future<ScoutingRoutePlan> saveGeneratedPlan(
    ScoutingRoutePlan plan, {
    required String actorPersonId,
    bool recalculated = false,
  }) {
    if (!plan.isReady) {
      throw StateError(
        'Generated plan does not contain all required sampling targets.',
      );
    }
    return savePlan(
      plan,
      actorPersonId: actorPersonId,
      action: recalculated ? 'route_recalculated' : 'route_plan_generated',
    );
  }

  Future<ScoutingRoutePlan> beginTargetAdjustment(
    ScoutingRoutePlan plan, {
    required int stationNumber,
    required String actorPersonId,
  }) {
    final target = plan.targetFor(stationNumber);
    if (target.lockedCompleted) {
      throw StateError('A completed station target cannot be moved.');
    }
    return savePlan(
      plan.copyWith(
        pendingAdjustment: PendingTargetAdjustment(
          stationNumber: stationNumber,
        ),
        arrivalConfirmedStation: null,
        updatedAt: DateTime.now().toUtc(),
      ),
      actorPersonId: actorPersonId,
      action: 'station_target_adjustment_started',
      queueForSync: false,
    );
  }

  Future<ScoutingRoutePlan> saveTargetAdjustmentDraft(
    ScoutingRoutePlan plan, {
    required LatLng? candidate,
    required String reason,
    required String actorPersonId,
  }) {
    final pending = plan.pendingAdjustment;
    if (pending == null) {
      throw StateError('No station target adjustment is active.');
    }
    return savePlan(
      plan.copyWith(
        pendingAdjustment: PendingTargetAdjustment(
          stationNumber: pending.stationNumber,
          candidate: candidate,
          reason: reason,
        ),
        updatedAt: DateTime.now().toUtc(),
      ),
      actorPersonId: actorPersonId,
      action: 'station_target_adjustment_draft_saved',
      queueForSync: false,
    );
  }

  Future<ScoutingRoutePlan> applyTargetAdjustment(
    ScoutingRoutePlan plan, {
    required List<LatLng> boundary,
    required String actorPersonId,
  }) async {
    final pending = plan.pendingAdjustment;
    if (pending == null || pending.candidate == null) {
      throw StateError('Tap a new target position on the map.');
    }
    final reason = pending.reason.trim();
    if (reason.isEmpty) {
      throw StateError('Record why this target is inaccessible or unsafe.');
    }
    if (!ScoutingRouteGenerator.validTarget(
      pending.candidate!,
      boundary,
      plan.preparation.obstacles,
    )) {
      throw StateError(
        'The adjusted target must remain inside the assessment block and outside marked obstacles.',
      );
    }
    if (plan.pattern == ScoutingSamplingProtocol.daPattern &&
        !ScoutingRouteGenerator.validDaTarget(
          pending.candidate!,
          boundary,
          plan.preparation.obstacles,
        )) {
      throw StateError(
        'Select a plant location at least 3 m from the field edge.',
      );
    }
    if (plan.pattern == ScoutingSamplingProtocol.daPattern &&
        plan.targets.any(
          (t) =>
              t.stationNumber != pending.stationNumber &&
              ScoutingRouteGenerator.distanceMeters(
                    t.location,
                    pending.candidate!,
                  ) <
                  2,
        )) {
      throw StateError(
        'Choose a separate location from the other sampled plants.',
      );
    }
    final before = plan.targetFor(pending.stationNumber);
    if (before.lockedCompleted) {
      throw StateError('A completed station target cannot be moved.');
    }
    final targets = [
      for (final target in plan.targets)
        if (target.stationNumber == pending.stationNumber)
          target.copyWith(
            location: pending.candidate,
            source: 'evaluator_adjusted',
            adjusted: true,
            adjustmentReason: reason,
          )
        else
          target,
    ];
    final updated = plan.copyWith(
      targets: targets,
      pendingAdjustment: null,
      arrivalConfirmedStation: null,
      updatedAt: DateTime.now().toUtc(),
    );
    return savePlan(
      updated,
      actorPersonId: actorPersonId,
      action: 'station_target_adjusted',
      reason: reason,
      before: {
        'station_number': before.stationNumber,
        'latitude': before.location.latitude,
        'longitude': before.location.longitude,
      },
      after: {
        'station_number': pending.stationNumber,
        'latitude': pending.candidate!.latitude,
        'longitude': pending.candidate!.longitude,
      },
    );
  }

  Future<ScoutingRoutePlan> cancelTargetAdjustment(
    ScoutingRoutePlan plan, {
    required String actorPersonId,
  }) {
    return savePlan(
      plan.copyWith(pendingAdjustment: null, updatedAt: DateTime.now().toUtc()),
      actorPersonId: actorPersonId,
      action: 'station_target_adjustment_cancelled',
      queueForSync: false,
    );
  }

  Future<ScoutingRoutePlan> confirmStationArrival(
    ScoutingRoutePlan plan, {
    required int stationNumber,
    required String actorPersonId,
  }) {
    plan.targetFor(stationNumber);
    return savePlan(
      plan.copyWith(
        arrivalConfirmedStation: stationNumber,
        updatedAt: DateTime.now().toUtc(),
      ),
      actorPersonId: actorPersonId,
      action: 'station_arrival_confirmed_by_evaluator',
      after: {'station_number': stationNumber},
    );
  }

  Future<ScoutingRoutePlan> clearStationArrival(
    ScoutingRoutePlan plan, {
    required String actorPersonId,
  }) {
    if (plan.arrivalConfirmedStation == null) return Future.value(plan);
    return savePlan(
      plan.copyWith(
        arrivalConfirmedStation: null,
        updatedAt: DateTime.now().toUtc(),
      ),
      actorPersonId: actorPersonId,
      action: 'station_arrival_consumed',
      queueForSync: false,
    );
  }

  Future<ScoutingRoutePlan> savePlan(
    ScoutingRoutePlan plan, {
    required String actorPersonId,
    required String action,
    String? reason,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    bool queueForSync = true,
  }) async {
    await database.transaction(() async {
      final run = await (database.select(
        database.assessmentBlockRuns,
      )..where((row) => row.id.equals(plan.blockRunId))).getSingle();
      if (run.assessmentId != plan.assessmentId ||
          run.fieldBlockId != plan.blockId) {
        throw StateError('Route plan does not match the assessment block run.');
      }
      await (database.update(
        database.assessmentBlockRuns,
      )..where((row) => row.id.equals(run.id))).write(
        AssessmentBlockRunsCompanion(
          routeGeojson: Value(plan.toGeoJson()),
          updatedAt: Value(plan.updatedAt.toUtc()),
          syncState: Value(queueForSync ? DatabaseCodes.queued : run.syncState),
        ),
      );
      await _mutations.record(
        entityType: 'assessment_block_runs',
        entityId: run.id,
        action: action,
        actorPersonId: actorPersonId,
        before: before ?? _summary(run.routeGeojson),
        after: after ?? _summary(plan.toGeoJson()),
        reason: reason,
        queueForSync: queueForSync,
      );
    });
    return plan;
  }

  Map<String, Object?> _summary(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const {'route_status': 'not_started'};
    }
    try {
      final plan = ScoutingRoutePlan.fromGeoJson(value);
      return {
        'document_version': scoutingRouteDocumentVersion,
        'route_status': plan.status.name,
        'pattern': plan.pattern,
        'target_count': plan.targets.length,
        'pending_adjustment_station': plan.pendingAdjustment?.stationNumber,
        'arrival_confirmed_station': plan.arrivalConfirmedStation,
      };
    } catch (_) {
      return const {'route_status': 'legacy_or_unreadable'};
    }
  }
}
