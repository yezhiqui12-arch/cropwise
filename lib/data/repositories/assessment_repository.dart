import '../../services/computer_vision/detection_preferences.dart';
import '../../services/scouting_sampling_protocol.dart';
import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';
import 'local_mutation_recorder.dart';

class UnsafeFieldEntryException implements Exception {
  const UnsafeFieldEntryException(this.safetyStatus);

  final String safetyStatus;

  @override
  String toString() =>
      'Field entry is blocked because safety status is $safetyStatus.';
}

class AssessmentRepository {
  AssessmentRepository(this.database)
    : _mutations = LocalMutationRecorder(database);

  final AppDatabase database;
  final LocalMutationRecorder _mutations;

  Future<AssessmentRecord> createDraft({
    required String cropCycleId,
    required String boundaryVersionId,
    required String evaluatorPersonId,
    required String assessmentMode,
    required String scoutingPattern,
    required String growthStage,
    required String protocolVersion,
    required String formulaVersion,
    String? patternReason,
    String assessmentType = DatabaseCodes.formal,
    String interventionHistoryStatus = 'unknown',
    String preferredLanguage = 'en',
    bool growthStageUncertain = false,
    String? growthStageBestEstimate,
    String? previousAssessmentId,
    String? weatherContext,
    int? localUtcOffsetMinutes,
    String? deviceId,
  }) async {
    final id = LocalId.generate();
    await database.transaction(() async {
      await database
          .into(database.assessments)
          .insert(
            AssessmentsCompanion.insert(
              id: id,
              cropCycleId: cropCycleId,
              boundaryVersionId: boundaryVersionId,
              evaluatorPersonId: evaluatorPersonId,
              assessmentType: Value(assessmentType),
              assessmentMode: assessmentMode,
              scoutingPattern: scoutingPattern,
              patternReason: Value(patternReason),
              growthStage: growthStage,
              protocolVersion: protocolVersion,
              formulaVersion: formulaVersion,
              interventionHistoryStatus: Value(interventionHistoryStatus),
              preferredLanguage: Value(preferredLanguage),
              growthStageUncertain: Value(growthStageUncertain),
              growthStageBestEstimate: Value(growthStageBestEstimate),
              previousAssessmentId: Value(previousAssessmentId),
              weatherContext: Value(weatherContext),
              localUtcOffsetMinutes: Value(localUtcOffsetMinutes),
              deviceId: Value(deviceId),
            ),
          );
      await DetectionPreferences.forAssessment(database, id);
      await _mutations.record(
        entityType: 'assessments',
        entityId: id,
        action: 'create',
        actorPersonId: evaluatorPersonId,
        deviceId: deviceId,
        after: {
          'crop_cycle_id': cropCycleId,
          'assessment_mode': assessmentMode,
          'growth_stage': growthStage,
          'status': DatabaseCodes.draft,
        },
      );
    });
    return _assessmentById(id);
  }

  Stream<AssessmentRecord?> watchOpenAssessmentForCropCycle(
    String cropCycleId,
  ) {
    final query = database.select(database.assessments)
      ..where(
        (row) =>
            row.cropCycleId.equals(cropCycleId) &
            row.deletedAt.isNull() &
            row.protocolVersion
                .equals(ScoutingSamplingProtocol.retiredFiveStationVersion)
                .not() &
            row.scoutingPattern.isIn(['w', 'ladder']).not() &
            row.status.isIn([
              DatabaseCodes.draft,
              DatabaseCodes.safetyBlocked,
              DatabaseCodes.inProgress,
              DatabaseCodes.incomplete,
            ]),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..limit(1);
    return query.watchSingleOrNull();
  }

  Stream<AssessmentRecord?> watchAssessmentById(String id) =>
      (database.select(database.assessments)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .watchSingleOrNull();
  Future<AssessmentRecord> assessmentById(String id) => _assessmentById(id);

  Future<void> updateWeatherContext({
    required String assessmentId,
    required String weatherContext,
  }) async {
    await database.transaction(() async {
      final assessment = await _assessmentById(assessmentId);
      if (assessment.weatherContext == weatherContext) return;
      final now = DateTime.now().toUtc();
      await (database.update(
        database.assessments,
      )..where((row) => row.id.equals(assessmentId))).write(
        AssessmentsCompanion(
          weatherContext: Value(weatherContext),
          updatedAt: Value(now),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
      await _mutations.record(
        entityType: 'assessments',
        entityId: assessmentId,
        action: 'weather_context_updated',
        actorPersonId: assessment.evaluatorPersonId,
        before: {'weather_context': assessment.weatherContext},
        after: {'weather_context': weatherContext},
      );
    });
  }

  Future<AssessmentRecord> correctGrowthStageBeforeObservations({
    required String assessmentId,
    required String growthStage,
    required String assessmentMode,
    required String scoutingPattern,
  }) async {
    await database.transaction(() async {
      final assessment = await _assessmentById(assessmentId);
      final existingRuns = await (database.select(
        database.assessmentBlockRuns,
      )..where((row) => row.assessmentId.equals(assessmentId))).get();
      if (existingRuns.isNotEmpty) {
        throw StateError(
          'Growth stage cannot be changed after field observations have started.',
        );
      }
      final now = DateTime.now().toUtc();
      final supported = DatabaseCodes.isGrowthStageImplemented(growthStage);
      await (database.update(
        database.assessments,
      )..where((row) => row.id.equals(assessmentId))).write(
        AssessmentsCompanion(
          growthStage: Value(growthStage),
          growthStageBestEstimate: const Value(null),
          growthStageUncertain: const Value(false),
          assessmentMode: Value(assessmentMode),
          scoutingPattern: Value(scoutingPattern),
          status: Value(
            supported ? DatabaseCodes.inProgress : DatabaseCodes.draft,
          ),
          updatedAt: Value(now),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
      await _mutations.record(
        entityType: 'assessments',
        entityId: assessmentId,
        action: 'growth_stage_corrected',
        actorPersonId: assessment.evaluatorPersonId,
        before: {
          'growth_stage': assessment.growthStage,
          'growth_stage_uncertain': assessment.growthStageUncertain,
          'assessment_mode': assessment.assessmentMode,
          'scouting_pattern': assessment.scoutingPattern,
        },
        after: {
          'growth_stage': growthStage,
          'growth_stage_uncertain': false,
          'assessment_mode': assessmentMode,
          'scouting_pattern': scoutingPattern,
          'status': supported ? DatabaseCodes.inProgress : DatabaseCodes.draft,
        },
      );
    });
    return _assessmentById(assessmentId);
  }

  Future<SafetyCheckRecord> recordSafetyCheck({
    required String assessmentId,
    required String checkedByPersonId,
    required String resultStatus,
    String? interventionId,
    DateTime? applicationEndAtUsed,
    String? reiTextUsed,
    String? reiSource,
    String? phiTextUsed,
    String? phiSource,
    DateTime? calculatedSafeEntryAt,
    bool calculationInputsVerified = false,
    String? notes,
    String? deviceId,
  }) async {
    final id = LocalId.generate();
    final isBlocked =
        resultStatus == DatabaseCodes.blockedReiActive ||
        resultStatus == DatabaseCodes.cannotConfirmSafety;

    await database.transaction(() async {
      await database
          .into(database.safetyChecks)
          .insert(
            SafetyChecksCompanion.insert(
              id: id,
              assessmentId: assessmentId,
              interventionId: Value(interventionId),
              checkedByPersonId: checkedByPersonId,
              checkedAt: DateTime.now().toUtc(),
              applicationEndAtUsed: Value(applicationEndAtUsed?.toUtc()),
              reiTextUsed: Value(reiTextUsed),
              reiSource: Value(reiSource),
              phiTextUsed: Value(phiTextUsed),
              phiSource: Value(phiSource),
              resultStatus: resultStatus,
              calculatedSafeEntryAt: Value(calculatedSafeEntryAt?.toUtc()),
              calculationInputsVerified: Value(calculationInputsVerified),
              notes: Value(notes),
              deviceId: Value(deviceId),
            ),
          );
      await (database.update(
        database.assessments,
      )..where((row) => row.id.equals(assessmentId))).write(
        AssessmentsCompanion(
          safetySummaryStatus: Value(resultStatus),
          status: Value(
            isBlocked ? DatabaseCodes.safetyBlocked : DatabaseCodes.draft,
          ),
          updatedAt: Value(DateTime.now().toUtc()),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
      await _mutations.record(
        entityType: 'safety_checks',
        entityId: id,
        action: 'create',
        actorPersonId: checkedByPersonId,
        deviceId: deviceId,
        after: {
          'assessment_id': assessmentId,
          'intervention_id': interventionId,
          'result_status': resultStatus,
        },
      );
    });

    return (database.select(
      database.safetyChecks,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<void> startAssessment(String assessmentId) async {
    final assessment = await _assessmentById(assessmentId);
    final allowed =
        assessment.safetySummaryStatus == DatabaseCodes.noRecentTreatment ||
        assessment.safetySummaryStatus == DatabaseCodes.safeIntervalCompleted;
    if (!allowed) {
      throw UnsafeFieldEntryException(assessment.safetySummaryStatus);
    }
    if (!DatabaseCodes.isGrowthStageImplemented(assessment.growthStage)) {
      throw StateError(
        'The ${assessment.growthStage} assessment workflow is not yet available. The setup draft remains saved.',
      );
    }

    await database.transaction(() async {
      await (database.update(
        database.assessments,
      )..where((row) => row.id.equals(assessmentId))).write(
        AssessmentsCompanion(
          status: const Value(DatabaseCodes.inProgress),
          startedAt: Value(DateTime.now().toUtc()),
          updatedAt: Value(DateTime.now().toUtc()),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
      await _mutations.record(
        entityType: 'assessments',
        entityId: assessmentId,
        action: 'update',
        actorPersonId: assessment.evaluatorPersonId,
        after: {'status': DatabaseCodes.inProgress},
      );
    });
  }

  Future<AssessmentBlockRunRecord> addBlockRun({
    required String assessmentId,
    required String fieldBlockId,
    required int blockSequence,
    required String scoutingPattern,
    String? patternReason,
    String? routeGeojson,
    String? deviceId,
  }) async {
    final id = LocalId.generate();
    await database
        .into(database.assessmentBlockRuns)
        .insert(
          AssessmentBlockRunsCompanion.insert(
            id: id,
            assessmentId: assessmentId,
            fieldBlockId: fieldBlockId,
            blockSequence: blockSequence,
            scoutingPattern: scoutingPattern,
            patternReason: Value(patternReason),
            routeGeojson: Value(routeGeojson),
            status: const Value(DatabaseCodes.inProgress),
            startedAt: Value(DateTime.now().toUtc()),
            deviceId: Value(deviceId),
          ),
        );
    return (database.select(
      database.assessmentBlockRuns,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<StationRecord> addStation({
    required String assessmentBlockRunId,
    required int stationNumber,
    double? latitude,
    double? longitude,
    double? gpsAccuracyM,
    String? accessibilityNotes,
    String? deviceId,
  }) async {
    if (stationNumber < 1 || stationNumber > 5) {
      throw ArgumentError.value(stationNumber, 'stationNumber', 'Must be 1-5');
    }
    final id = LocalId.generate();
    await database
        .into(database.stations)
        .insert(
          StationsCompanion.insert(
            id: id,
            assessmentBlockRunId: assessmentBlockRunId,
            stationNumber: stationNumber,
            latitude: Value(latitude),
            longitude: Value(longitude),
            gpsAccuracyM: Value(gpsAccuracyM),
            capturedAt: Value(DateTime.now().toUtc()),
            accessibilityNotes: Value(accessibilityNotes),
            deviceId: Value(deviceId),
          ),
        );
    return (database.select(
      database.stations,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<PlantObservationRecord> savePlant({
    required String stationId,
    required int sequenceNumber,
    required String plantStatus,
    required String naturalEnemyQuickStatus,
    bool assessable = true,
    bool? currentFawEvidence,
    bool? possibleNonFawEvidence,
    bool? uncertainEvidence,
    bool oldDamagePresent = false,
    String? notAssessableReason,
    String? persistentPlantIdentifier,
    String? evaluatorNotes,
    String? deviceId,
  }) async {
    if (sequenceNumber < 1 || sequenceNumber > 10) {
      throw ArgumentError.value(
        sequenceNumber,
        'sequenceNumber',
        'Must be 1-10',
      );
    }
    if (!DatabaseCodes.plantStatuses.contains(plantStatus)) {
      throw ArgumentError.value(
        plantStatus,
        'plantStatus',
        'Unsupported plant status',
      );
    }
    if (!DatabaseCodes.naturalEnemyQuickStatuses.contains(
      naturalEnemyQuickStatus,
    )) {
      throw ArgumentError.value(
        naturalEnemyQuickStatus,
        'naturalEnemyQuickStatus',
        'Unsupported natural-enemy quick status',
      );
    }
    if (!assessable && plantStatus != DatabaseCodes.plantNotAssessable) {
      throw ArgumentError(
        'A non-assessable plant must use plant_not_assessable status.',
      );
    }

    final existing =
        await (database.select(database.plantObservations)..where(
              (row) =>
                  row.stationId.equals(stationId) &
                  row.sequenceNumber.equals(sequenceNumber),
            ))
            .getSingleOrNull();
    final id = existing?.id ?? LocalId.generate();

    await database
        .into(database.plantObservations)
        .insertOnConflictUpdate(
          PlantObservationsCompanion.insert(
            id: id,
            stationId: stationId,
            sequenceNumber: sequenceNumber,
            persistentPlantIdentifier: Value(persistentPlantIdentifier),
            assessable: Value(assessable),
            notAssessableReason: Value(notAssessableReason),
            plantStatus: plantStatus,
            currentFawEvidence: Value(currentFawEvidence),
            possibleNonFawEvidence: Value(possibleNonFawEvidence),
            uncertainEvidence: Value(uncertainEvidence),
            oldDamagePresent: Value(oldDamagePresent),
            naturalEnemyQuickStatus: naturalEnemyQuickStatus,
            capturedAt: Value(DateTime.now().toUtc()),
            evaluatorNotes: Value(evaluatorNotes),
            updatedAt: Value(DateTime.now().toUtc()),
            deviceId: Value(deviceId),
            syncState: const Value(DatabaseCodes.queued),
          ),
        );
    return (database.select(
      database.plantObservations,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<PlantingUnitObservationRecord> savePlantingUnit({
    required String stationId,
    required int sequenceNumber,
    required bool assessable,
    String? notAssessableReason,
    String? occupancyStatus,
    int? observedSeedlingCount,
    int? intendedSeedlingCount,
    bool? visibleCutting,
    bool? visibleSeedlingInjury,
    bool? confirmedFawPresent,
    bool? injuryConsistentWithFaw,
    String? alternativeCauseCode,
    String? notes,
    String? deviceId,
  }) async {
    if (sequenceNumber < 1 || sequenceNumber > 10) {
      throw ArgumentError.value(
        sequenceNumber,
        'sequenceNumber',
        'Must be 1-10',
      );
    }
    if (!assessable &&
        (notAssessableReason == null || notAssessableReason.trim().isEmpty)) {
      throw ArgumentError('A non-assessable planting unit requires a reason.');
    }

    final existing =
        await (database.select(database.plantingUnitObservations)..where(
              (row) =>
                  row.stationId.equals(stationId) &
                  row.sequenceNumber.equals(sequenceNumber),
            ))
            .getSingleOrNull();
    final id = existing?.id ?? LocalId.generate();
    await database
        .into(database.plantingUnitObservations)
        .insertOnConflictUpdate(
          PlantingUnitObservationsCompanion.insert(
            id: id,
            stationId: stationId,
            sequenceNumber: sequenceNumber,
            assessable: Value(assessable),
            notAssessableReason: Value(notAssessableReason),
            occupancyStatus: Value(occupancyStatus),
            observedSeedlingCount: Value(observedSeedlingCount),
            intendedSeedlingCount: Value(intendedSeedlingCount),
            visibleCutting: Value(visibleCutting),
            visibleSeedlingInjury: Value(visibleSeedlingInjury),
            confirmedFawPresent: Value(confirmedFawPresent),
            injuryConsistentWithFaw: Value(injuryConsistentWithFaw),
            alternativeCauseCode: Value(alternativeCauseCode),
            notes: Value(notes),
            capturedAt: Value(DateTime.now().toUtc()),
            updatedAt: Value(DateTime.now().toUtc()),
            deviceId: Value(deviceId),
            syncState: const Value(DatabaseCodes.queued),
          ),
        );
    return (database.select(
      database.plantingUnitObservations,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<void> saveVegetativeObservation({
    required String plantObservationId,
    int? newestLeavesInspectedCount,
    bool smallFreshWindowpanes = false,
    bool infestedWhorl = false,
    bool scraping = false,
    bool cuttingOrTearing = false,
    bool freshFrass = false,
    bool whorlFeedingSign = false,
    bool larvaVisible = false,
    String larvalSize = 'none_seen',
    bool? eggMassVisible,
    int? larvaCount,
    int? daBafsLeafDamageScore,
    bool damageScoreUncertain = false,
  }) async {
    if (daBafsLeafDamageScore != null &&
        (daBafsLeafDamageScore < 0 || daBafsLeafDamageScore > 9)) {
      throw ArgumentError.value(
        daBafsLeafDamageScore,
        'daBafsLeafDamageScore',
        'Must be 0-9',
      );
    }
    if (!DatabaseCodes.larvalSizes.contains(larvalSize)) {
      throw ArgumentError.value(
        larvalSize,
        'larvalSize',
        'Unsupported larval-size group',
      );
    }
    await database
        .into(database.vegetativeObservations)
        .insertOnConflictUpdate(
          VegetativeObservationsCompanion.insert(
            plantObservationId: plantObservationId,
            newestLeavesInspectedCount: Value(newestLeavesInspectedCount),
            smallFreshWindowpanes: Value(smallFreshWindowpanes),
            infestedWhorl: Value(infestedWhorl),
            scraping: Value(scraping),
            cuttingOrTearing: Value(cuttingOrTearing),
            freshFrass: Value(freshFrass),
            whorlFeedingSign: Value(whorlFeedingSign),
            larvaVisible: Value(larvaVisible),
            larvalSize: Value(larvalSize),
            eggMassVisible: Value(eggMassVisible),
            larvaCount: Value(larvaCount),
            daBafsLeafDamageScore: Value(daBafsLeafDamageScore),
            damageScoreUncertain: Value(damageScoreUncertain),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<void> saveReproductiveObservation({
    required String plantObservationId,
    bool tasselExamined = false,
    bool earBaseExamined = false,
    bool upperAxilExamined = false,
    bool lowerAxilExamined = false,
    bool freshFeedingPresent = false,
    bool larvaPresent = false,
    int? larvaCount,
    required bool percentInfestedPositive,
  }) async {
    await database
        .into(database.reproductiveObservations)
        .insertOnConflictUpdate(
          ReproductiveObservationsCompanion.insert(
            plantObservationId: plantObservationId,
            tasselExamined: Value(tasselExamined),
            earBaseExamined: Value(earBaseExamined),
            upperAxilExamined: Value(upperAxilExamined),
            lowerAxilExamined: Value(lowerAxilExamined),
            freshFeedingPresent: Value(freshFeedingPresent),
            larvaPresent: Value(larvaPresent),
            larvaCount: Value(larvaCount),
            percentInfestedPositive: Value(percentInfestedPositive),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<AssessmentRecord> _assessmentById(String id) {
    return (database.select(
      database.assessments,
    )..where((row) => row.id.equals(id))).getSingle();
  }
}
