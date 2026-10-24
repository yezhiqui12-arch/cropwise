import '../../models/automatic_screening.dart';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';
import '../repositories/local_mutation_recorder.dart';
import '../repositories/evidence_capture_repository.dart';

class VeV2StationSetupInput {
  const VeV2StationSetupInput({
    required this.stationId,
    required this.growthStage,
    required this.rowDirectionCode,
    required this.plantingUnitSequenceAssessable,
    required this.stationContextMeetsRowPurpose,
    this.emergenceContinuing,
    this.delayedEmergencePlausible,
    this.sequenceNotAssessableReason,
    this.actorPersonId,
  });

  final String stationId;
  final String growthStage;
  final String rowDirectionCode;
  final bool plantingUnitSequenceAssessable;
  final bool stationContextMeetsRowPurpose;
  final bool? emergenceContinuing;
  final bool? delayedEmergencePlausible;
  final String? sequenceNotAssessableReason;
  final String? actorPersonId;
}

class VeV2PlantingUnitSave {
  const VeV2PlantingUnitSave({
    required this.stationId,
    required this.sequenceNumber,
    required this.assessable,
    required this.primaryCondition,
    required this.observedSeedlingCount,
    required this.recognizableRemnantPresent,
    required this.visibleCutting,
    required this.visibleSevering,
    required this.visibleSeedlingInjury,
    required this.injuryLocation,
    required this.injuryFreshness,
    required this.larvaVisible,
    required this.larvalSize,
    required this.freshFrass,
    required this.rotPresent,
    required this.tunnelingPresent,
    required this.discolorationPresent,
    required this.otherNonFawEvidence,
    required this.evaluatorPrimaryInterpretation,
    required this.evaluatorConfidence,
    required this.alternativeCauseCodes,
    required this.inspectionDurationMs,
    this.notAssessableReason,
    this.intendedSeedlingCount,
    this.notes,
    this.actorPersonId,
    this.evidenceCaptureSessionId,
    this.requiredEvidenceViewTypes = const {},
    this.repeatedPhysicalCheck = false,
  });

  final String stationId;
  final int sequenceNumber;
  final bool assessable;
  final String? notAssessableReason;
  final String primaryCondition;
  final int? observedSeedlingCount;
  final int? intendedSeedlingCount;
  final bool? recognizableRemnantPresent;
  final bool? visibleCutting;
  final bool? visibleSevering;
  final bool? visibleSeedlingInjury;
  final String? injuryLocation;
  final String? injuryFreshness;
  final bool? larvaVisible;
  final String? larvalSize;
  final bool? freshFrass;
  final bool? rotPresent;
  final bool? tunnelingPresent;
  final bool? discolorationPresent;
  final bool? otherNonFawEvidence;
  final String? evaluatorPrimaryInterpretation;
  final String? evaluatorConfidence;
  final Set<String> alternativeCauseCodes;
  final int inspectionDurationMs;
  final String? notes;
  final String? actorPersonId;
  final String? evidenceCaptureSessionId;
  final Set<String> requiredEvidenceViewTypes;
  final bool repeatedPhysicalCheck;
}

/// Minimal physical routing facts saved during continuous camera capture.
/// Detailed injury and pest interpretation remain null until Station Review.
class VeV2CaptureRoutingSave {
  const VeV2CaptureRoutingSave({
    required this.stationId,
    required this.sequenceNumber,
    required this.occupancyStatus,
    required this.observedSeedlingCount,
    required this.inspectionDurationMs,
    required this.evidenceCaptureSessionId,
    required this.requiredEvidenceViewTypes,
    required this.actorPersonId,
    this.notAssessableReason,
  });

  final String stationId;
  final int sequenceNumber;
  final String occupancyStatus;
  final int observedSeedlingCount;
  final int inspectionDurationMs;
  final String evidenceCaptureSessionId;
  final Set<String> requiredEvidenceViewTypes;
  final String actorPersonId;
  final String? notAssessableReason;
}

class AtomicVeV2SaveService {
  AtomicVeV2SaveService(
    this.database, {
    EvidenceCaptureRepository? evidenceRepository,
  }) : _mutations = LocalMutationRecorder(database),
       _evidence = evidenceRepository ?? EvidenceCaptureRepository(database);

  final AppDatabase database;
  final LocalMutationRecorder _mutations;
  final EvidenceCaptureRepository _evidence;

  Future<VeV2StationInspectionRecord?> loadStationInspection(
    String stationId,
  ) => (database.select(
    database.veV2StationInspections,
  )..where((row) => row.stationId.equals(stationId))).getSingleOrNull();

  Future<List<PlantingUnitObservationRecord>> loadPlantingUnits(
    String stationId,
  ) =>
      (database.select(database.plantingUnitObservations)
            ..where((row) => row.stationId.equals(stationId))
            ..orderBy([(row) => OrderingTerm.asc(row.sequenceNumber)]))
          .get();

  Future<PlantingUnitObservationRecord> saveCaptureRouting(
    VeV2CaptureRoutingSave input,
  ) async {
    _validateCaptureRouting(input);
    return database.transaction(() async {
      final previous =
          await (database.select(database.plantingUnitObservations)..where(
                (row) =>
                    row.stationId.equals(input.stationId) &
                    row.sequenceNumber.equals(input.sequenceNumber),
              ))
              .getSingleOrNull();
      final id = previous?.id ?? LocalId.generate();
      final now = DateTime.now().toUtc();
      final assessable =
          input.occupancyStatus != DatabaseCodes.veOccupancyNotAssessable;
      if (previous == null) {
        await database
            .into(database.plantingUnitObservations)
            .insert(
              PlantingUnitObservationsCompanion.insert(
                id: id,
                stationId: input.stationId,
                sequenceNumber: input.sequenceNumber,
                assessable: Value(assessable),
                notAssessableReason: Value(input.notAssessableReason),
                occupancyStatus: Value(input.occupancyStatus),
                observedSeedlingCount: Value(input.observedSeedlingCount),
                recognizableRemnantPresent: Value(
                  input.occupancyStatus == DatabaseCodes.veOccupancyRemnant,
                ),
                inspectionDurationMs: Value(input.inspectionDurationMs),
                capturedAt: Value(now),
                updatedAt: Value(now),
                syncState: const Value(DatabaseCodes.queued),
              ),
            );
      } else {
        await (database.update(
          database.plantingUnitObservations,
        )..where((row) => row.id.equals(id))).write(
          PlantingUnitObservationsCompanion(
            assessable: Value(assessable),
            notAssessableReason: Value(input.notAssessableReason),
            occupancyStatus: Value(input.occupancyStatus),
            observedSeedlingCount: Value(input.observedSeedlingCount),
            recognizableRemnantPresent: Value(
              input.occupancyStatus == DatabaseCodes.veOccupancyRemnant,
            ),
            inspectionDurationMs: Value(input.inspectionDurationMs),
            capturedAt: Value(now),
            updatedAt: Value(now),
            syncState: const Value(DatabaseCodes.queued),
          ),
        );
      }
      final bundle = await _evidence.loadBundle(input.evidenceCaptureSessionId);
      if (bundle.session.scopeType == DatabaseCodes.evidenceScopePlantingUnit) {
        await _evidence.attachPlantingUnitEvidenceInCurrentTransaction(
          sessionId: input.evidenceCaptureSessionId,
          stationId: input.stationId,
          sequenceNumber: input.sequenceNumber,
          plantingUnitObservationId: id,
          requiredViewTypes: input.requiredEvidenceViewTypes,
          actorPersonId: input.actorPersonId,
        );
      } else if (bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
          bundle.session.stationId == input.stationId &&
          bundle.session.plantPosition == input.sequenceNumber) {
        if (bundle.session.sourcePlantingUnitObservationId != null &&
            bundle.session.sourcePlantingUnitObservationId != id) {
          throw StateError(
            'Evidence is linked to a different seedling position.',
          );
        }
        await (database.update(
          database.evidenceCaptureSessions,
        )..where((row) => row.id.equals(bundle.session.id))).write(
          EvidenceCaptureSessionsCompanion(
            sourcePlantingUnitObservationId: Value(id),
            updatedAt: Value(now),
          ),
        );
      } else {
        throw StateError('Evidence does not match this seedling position.');
      }
      final saved = await (database.select(
        database.plantingUnitObservations,
      )..where((row) => row.id.equals(id))).getSingle();
      await _mutations.record(
        entityType: 'planting_unit_observations',
        entityId: id,
        action: 'capture_routed',
        actorPersonId: input.actorPersonId,
        before: previous == null ? null : _unitSnapshot(previous),
        after: _unitSnapshot(saved),
        queueForSync: false,
      );
      return saved;
    });
  }

  Future<VeV2StationInspectionRecord> saveStationSetup(
    VeV2StationSetupInput input,
  ) async {
    _validateStationSetup(input);
    return database.transaction(() async {
      final previous =
          await (database.select(database.veV2StationInspections)
                ..where((row) => row.stationId.equals(input.stationId)))
              .getSingleOrNull();
      final now = DateTime.now().toUtc();
      final id = previous?.id ?? LocalId.generate();
      await database
          .into(database.veV2StationInspections)
          .insertOnConflictUpdate(
            VeV2StationInspectionsCompanion.insert(
              id: id,
              stationId: input.stationId,
              emergenceContinuing: Value(input.emergenceContinuing),
              delayedEmergencePlausible: Value(input.delayedEmergencePlausible),
              plantingUnitSequenceAssessable: Value(
                input.plantingUnitSequenceAssessable,
              ),
              sequenceNotAssessableReason: Value(
                input.sequenceNotAssessableReason,
              ),
              rowDirectionCode: Value(input.rowDirectionCode),
              stationContextMeetsRowPurpose: Value(
                input.stationContextMeetsRowPurpose,
              ),
              startedAt: Value(previous?.startedAt ?? now),
              updatedAt: Value(now),
              syncState: const Value(DatabaseCodes.queued),
            ),
          );
      final saved = await (database.select(
        database.veV2StationInspections,
      )..where((row) => row.id.equals(id))).getSingle();
      await _mutations.record(
        entityType: 've_v2_station_inspections',
        entityId: id,
        action: previous == null ? 'create' : 'update',
        actorPersonId: input.actorPersonId,
        before: previous == null ? null : _stationSnapshot(previous),
        after: _stationSnapshot(saved),
      );
      return saved;
    });
  }

  Future<PlantingUnitObservationRecord> savePlantingUnit(
    VeV2PlantingUnitSave input,
  ) async {
    _validatePlantingUnit(input);
    return database.transaction(() async {
      final previous =
          await (database.select(database.plantingUnitObservations)..where(
                (row) =>
                    row.stationId.equals(input.stationId) &
                    row.sequenceNumber.equals(input.sequenceNumber),
              ))
              .getSingleOrNull();
      final now = DateTime.now().toUtc();
      final id = previous?.id ?? LocalId.generate();
      final correctionCount = previous == null
          ? 0
          : previous.correctionCount + 1;
      await database
          .into(database.plantingUnitObservations)
          .insertOnConflictUpdate(
            PlantingUnitObservationsCompanion.insert(
              id: id,
              stationId: input.stationId,
              sequenceNumber: input.sequenceNumber,
              assessable: Value(input.assessable),
              notAssessableReason: Value(input.notAssessableReason),
              occupancyStatus: Value(
                _rawOccupancyFor(previous, input.primaryCondition),
              ),
              primaryCondition: Value(input.primaryCondition),
              observedSeedlingCount: Value(input.observedSeedlingCount),
              intendedSeedlingCount: Value(input.intendedSeedlingCount),
              recognizableRemnantPresent: Value(
                input.recognizableRemnantPresent,
              ),
              visibleCutting: Value(input.visibleCutting),
              visibleSevering: Value(input.visibleSevering),
              visibleSeedlingInjury: Value(input.visibleSeedlingInjury),
              injuryLocation: Value(input.injuryLocation),
              injuryFreshness: Value(input.injuryFreshness),
              larvaVisible: Value(input.larvaVisible),
              larvalSize: Value(input.larvalSize),
              freshFrass: Value(input.freshFrass),
              rotPresent: Value(input.rotPresent),
              tunnelingPresent: Value(input.tunnelingPresent),
              discolorationPresent: Value(input.discolorationPresent),
              otherNonFawEvidence: Value(input.otherNonFawEvidence),
              confirmedFawPresent: Value(
                input.evaluatorPrimaryInterpretation ==
                    DatabaseCodes.veInterpretationConfirmedFaw,
              ),
              injuryConsistentWithFaw: Value(
                input.evaluatorPrimaryInterpretation ==
                    DatabaseCodes.veInterpretationFawConsistent,
              ),
              alternativeCauseCode: Value(
                input.alternativeCauseCodes.length == 1
                    ? input.alternativeCauseCodes.single
                    : null,
              ),
              alternativeCauseCodesJson: Value(
                jsonEncode(input.alternativeCauseCodes.toList()..sort()),
              ),
              evaluatorPrimaryInterpretation: Value(
                input.evaluatorPrimaryInterpretation,
              ),
              evaluatorConfidence: Value(input.evaluatorConfidence),
              inspectionDurationMs: Value(input.inspectionDurationMs),
              correctionCount: Value(correctionCount),
              notes: Value(input.notes),
              capturedAt: Value(now),
              updatedAt: Value(now),
              syncState: const Value(DatabaseCodes.queued),
            ),
          );
      final saved = await (database.select(
        database.plantingUnitObservations,
      )..where((row) => row.id.equals(id))).getSingle();
      if (input.evidenceCaptureSessionId != null) {
        await _evidence.attachPlantingUnitEvidenceInCurrentTransaction(
          sessionId: input.evidenceCaptureSessionId!,
          stationId: input.stationId,
          sequenceNumber: input.sequenceNumber,
          plantingUnitObservationId: id,
          requiredViewTypes: input.requiredEvidenceViewTypes,
          actorPersonId: input.actorPersonId ?? '',
        );
      }
      await _mutations.record(
        entityType: 'planting_unit_observations',
        entityId: id,
        action: previous == null ? 'create' : 'update',
        actorPersonId: input.actorPersonId,
        before: previous == null ? null : _unitSnapshot(previous),
        after: _unitSnapshot(saved),
      );
      if (previous != null) {
        await _incrementStationCounter(
          stationId: input.stationId,
          correction: true,
        );
      }
      if (input.repeatedPhysicalCheck) {
        await _incrementStationCounter(
          stationId: input.stationId,
          repeatedPhysicalCheck: true,
        );
      }
      return saved;
    });
  }

  Future<void> addEntryDuration({
    required String stationId,
    required Duration duration,
    required bool plantingUnit,
  }) async {
    if (duration.isNegative) {
      throw ArgumentError('Duration cannot be negative.');
    }
    await database.transaction(() async {
      final row = await (database.select(
        database.veV2StationInspections,
      )..where((item) => item.stationId.equals(stationId))).getSingle();
      final companion = plantingUnit
          ? VeV2StationInspectionsCompanion(
              plantingUnitEntryDurationMs: Value(
                row.plantingUnitEntryDurationMs + duration.inMilliseconds,
              ),
              updatedAt: Value(DateTime.now().toUtc()),
            )
          : VeV2StationInspectionsCompanion(
              livingSeedlingEntryDurationMs: Value(
                row.livingSeedlingEntryDurationMs + duration.inMilliseconds,
              ),
              updatedAt: Value(DateTime.now().toUtc()),
            );
      await (database.update(
        database.veV2StationInspections,
      )..where((item) => item.id.equals(row.id))).write(companion);
    });
  }

  Future<void> recordLivingPlantCorrection({
    required String stationId,
    required bool repeatedPhysicalCheck,
  }) => _incrementStationCounter(
    stationId: stationId,
    correction: true,
    repeatedPhysicalCheck: repeatedPhysicalCheck,
  );

  Future<void> recordRepeatedPhysicalCheck(String stationId) =>
      _incrementStationCounter(
        stationId: stationId,
        repeatedPhysicalCheck: true,
      );

  Future<void> _incrementStationCounter({
    required String stationId,
    bool correction = false,
    bool repeatedPhysicalCheck = false,
  }) async {
    final row = await loadStationInspection(stationId);
    if (row == null) return;
    await (database.update(
      database.veV2StationInspections,
    )..where((item) => item.id.equals(row.id))).write(
      VeV2StationInspectionsCompanion(
        correctionCount: correction
            ? Value(row.correctionCount + 1)
            : const Value.absent(),
        repeatedPhysicalCheckCount: repeatedPhysicalCheck
            ? Value(row.repeatedPhysicalCheckCount + 1)
            : const Value.absent(),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<VeV2StationInspectionRecord> completePilotStation({
    required String stationId,
    required String actorPersonId,
  }) async {
    return database.transaction(() async {
      final inspection = await loadStationInspection(stationId);
      if (inspection == null) {
        throw StateError('VE-V2 station setup is missing.');
      }
      final units = await loadPlantingUnits(stationId);
      if (inspection.plantingUnitSequenceAssessable && units.length != 10) {
        throw StateError('Ten planting units are required.');
      }
      final plants = await (database.select(
        database.plantObservations,
      )..where((row) => row.stationId.equals(stationId))).get();
      if (plants.length != 10) {
        throw StateError('Ten living-seedling confirmations are required.');
      }
      final bundles = await _evidence.loadStationBundles(stationId);
      if (inspection.stationContextMeetsRowPurpose != true) {
        final rowContext = bundles.where(
          (bundle) => bundle.session.scopeKey == 've_v2_row_context',
        );
        if (rowContext.isEmpty ||
            !rowContext.single.isViewSatisfied(
              DatabaseCodes.evidenceViewVeRowContext,
            )) {
          throw StateError(
            'Row context requires a photograph or documented fallback.',
          );
        }
      }
      for (final plant in plants) {
        if (const {
              DatabaseCodes.naturalEnemyNotAssessable,
              DatabaseCodes.naturalEnemyNotCollected,
            }.contains(plant.naturalEnemyQuickStatus) &&
            !(plant.evaluatorNotes ?? '').contains('Natural-enemy reason:') &&
            AutomaticScreening.parse(plant.wholePlantContextNote) == null) {
          throw StateError(
            'Natural-enemy exceptions require a documented reason.',
          );
        }
        final vegetative = await (database.select(
          database.vegetativeObservations,
        )..where((row) => row.plantObservationId.equals(plant.id))).getSingle();
        final requiresSeedlingEvidence =
            plant.plantStatus == DatabaseCodes.plantCurrentPositive ||
            plant.possibleNonFawEvidence == true ||
            plant.uncertainEvidence == true ||
            vegetative.smallFreshWindowpanes ||
            vegetative.scraping ||
            vegetative.cuttingOrTearing ||
            vegetative.freshFrass ||
            vegetative.whorlFeedingSign ||
            vegetative.larvaVisible ||
            vegetative.eggMassVisible == true;
        if (!requiresSeedlingEvidence) continue;
        final plantEvidence = bundles.where(
          (bundle) => bundle.session.plantObservationId == plant.id,
        );
        if (plantEvidence.isEmpty ||
            !plantEvidence.single.isViewSatisfied(
              DatabaseCodes.evidenceViewWholeSeedling,
            ) ||
            !plantEvidence.single.isViewSatisfied(
              DatabaseCodes.evidenceViewCloseUp,
            )) {
          throw StateError(
            'Positive or uncertain living-seedling evidence requires whole-seedling and close-up photographs or documented fallback.',
          );
        }
      }
      final now = DateTime.now().toUtc();
      await (database.update(
        database.veV2StationInspections,
      )..where((row) => row.id.equals(inspection.id))).write(
        VeV2StationInspectionsCompanion(
          evaluatorWorkloadRating: const Value(null),
          completedAt: Value(now),
          updatedAt: Value(now),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
      final saved = await loadStationInspection(stationId);
      await _mutations.record(
        entityType: 've_v2_station_inspections',
        entityId: inspection.id,
        action: 'pilot_station_completed',
        actorPersonId: actorPersonId,
        after: {
          'station_id': stationId,
          'planting_unit_count': units.length,
          'living_seedling_count': plants.length,
          'linked_seedling_count': plants
              .where((plant) => plant.sourcePlantingUnitObservationId != null)
              .length,
          'additional_seedling_count': plants
              .where((plant) => plant.sourcePlantingUnitObservationId == null)
              .length,
        },
      );
      return saved!;
    });
  }

  void _validateStationSetup(VeV2StationSetupInput input) {
    if (!const {'ve', 'v1', 'v2'}.contains(input.growthStage)) {
      throw ArgumentError('VE-V2 station setup requires VE, V1, or V2.');
    }
    if (input.growthStage == 've' && input.emergenceContinuing == null) {
      throw ArgumentError('VE requires the emergence-continuing answer.');
    }
    if (input.growthStage != 've' && input.delayedEmergencePlausible == null) {
      throw ArgumentError('V1-V2 requires the delayed-emergence answer.');
    }
    if (input.rowDirectionCode.trim().isEmpty) {
      throw ArgumentError('The row direction is required.');
    }
    if (!input.plantingUnitSequenceAssessable &&
        (input.sequenceNotAssessableReason == null ||
            input.sequenceNotAssessableReason!.trim().isEmpty)) {
      throw ArgumentError('An unassessable sequence requires a reason.');
    }
  }

  void _validatePlantingUnit(VeV2PlantingUnitSave input) {
    if (input.sequenceNumber < 1 || input.sequenceNumber > 10) {
      throw ArgumentError.value(
        input.sequenceNumber,
        'sequenceNumber',
        'Must be 1-10',
      );
    }
    if (input.inspectionDurationMs < 0) {
      throw ArgumentError('Inspection duration cannot be negative.');
    }
    if (!DatabaseCodes.veUnitConditions.contains(input.primaryCondition)) {
      throw ArgumentError('Unsupported VE-V2 planting-unit condition.');
    }
    if (!input.assessable) {
      if (input.primaryCondition != DatabaseCodes.veUnitNotAssessable ||
          input.notAssessableReason == null ||
          input.notAssessableReason!.trim().isEmpty) {
        throw ArgumentError(
          'A non-assessable position requires its condition and reason.',
        );
      }
      return;
    }
    if (input.primaryCondition == DatabaseCodes.veUnitNotAssessable) {
      throw ArgumentError('An assessable position cannot be not assessable.');
    }
    final occupied = const {
      DatabaseCodes.veUnitHealthy,
      DatabaseCodes.veUnitFeedingInjury,
    }.contains(input.primaryCondition);
    if (occupied &&
        (input.observedSeedlingCount == null ||
            input.observedSeedlingCount! < 1)) {
      throw ArgumentError(
        'An occupied unit requires at least one living seedling.',
      );
    }
    if (!occupied && (input.observedSeedlingCount ?? 0) != 0) {
      throw ArgumentError(
        'This planting-unit condition cannot contain a living seedling count.',
      );
    }
    final needsInterpretation =
        input.primaryCondition != DatabaseCodes.veUnitHealthy;
    if (needsInterpretation &&
        !DatabaseCodes.veInterpretations.contains(
          input.evaluatorPrimaryInterpretation,
        )) {
      throw ArgumentError(
        'Injured, empty, uncertain, or dead units require evaluator interpretation.',
      );
    }
    if (input.evaluatorPrimaryInterpretation ==
            DatabaseCodes.veInterpretationConfirmedFaw &&
        input.larvaVisible != true) {
      throw ArgumentError(
        'Confirmed FAW requires a visible larva; diagnostic evidence is validated separately.',
      );
    }
    final requiredViews = <String>{};
    if (const {
          DatabaseCodes.veUnitFeedingInjury,
          DatabaseCodes.veUnitCutSevered,
          DatabaseCodes.veUnitWiltedDead,
          DatabaseCodes.veUnitPositionUncertain,
        }.contains(input.primaryCondition) ||
        input.evaluatorPrimaryInterpretation ==
            DatabaseCodes.veInterpretationUncertain) {
      requiredViews.add(DatabaseCodes.evidenceViewWholeSeedling);
    }
    if (input.primaryCondition == DatabaseCodes.veUnitCutSevered) {
      requiredViews
        ..add(DatabaseCodes.evidenceViewStemBase)
        ..add(DatabaseCodes.evidenceViewCloseUp);
    }
    if (input.rotPresent == true ||
        input.tunnelingPresent == true ||
        input.discolorationPresent == true ||
        input.freshFrass == true ||
        input.otherNonFawEvidence == true) {
      requiredViews.add(DatabaseCodes.evidenceViewCloseUp);
    }
    if (input.evaluatorPrimaryInterpretation ==
        DatabaseCodes.veInterpretationConfirmedFaw) {
      requiredViews
        ..add(DatabaseCodes.evidenceViewLarvaDorsal)
        ..add(DatabaseCodes.evidenceViewLarvaHead);
    }
    if (requiredViews.isNotEmpty) {
      if (input.evidenceCaptureSessionId == null ||
          input.actorPersonId == null ||
          input.actorPersonId!.isEmpty) {
        throw ArgumentError(
          'Positive or uncertain VE-V2 evidence requires photographs or documented fallback.',
        );
      }
      if (!input.requiredEvidenceViewTypes.containsAll(requiredViews)) {
        throw ArgumentError('Required VE-V2 evidence views are incomplete.');
      }
    }
  }

  void _validateCaptureRouting(VeV2CaptureRoutingSave input) {
    if (input.sequenceNumber < 1 || input.sequenceNumber > 10) {
      throw ArgumentError.value(input.sequenceNumber, 'sequenceNumber');
    }
    if (!DatabaseCodes.veOccupancyStatuses.contains(input.occupancyStatus)) {
      throw ArgumentError('Unsupported VE-V2 occupancy routing fact.');
    }
    if (input.inspectionDurationMs < 0) {
      throw ArgumentError('Capture duration cannot be negative.');
    }
    final occupied = input.occupancyStatus == DatabaseCodes.veOccupancySeedling;
    if (occupied && input.observedSeedlingCount < 1) {
      throw ArgumentError(
        'A seedling position requires at least one seedling.',
      );
    }
    if (!occupied && input.observedSeedlingCount != 0) {
      throw ArgumentError('Only a seedling position can add living seedlings.');
    }
    if (input.occupancyStatus == DatabaseCodes.veOccupancyNotAssessable &&
        (input.notAssessableReason == null ||
            input.notAssessableReason!.trim().isEmpty)) {
      throw ArgumentError('A non-assessable position requires a reason.');
    }
    // A living seedling is photographed once in its linked plant session.
    // Requiring whole-seedling and stem-base images on the planting-unit
    // session first would duplicate the field workload and block the camera
    // transition. A recognizable remnant remains stage-specific evidence and
    // therefore requires its stem-base view here.
    final coreViews = <String>{
      if (input.occupancyStatus == DatabaseCodes.veOccupancyRemnant)
        DatabaseCodes.evidenceViewStemBase,
    };
    if (!input.requiredEvidenceViewTypes.containsAll(coreViews)) {
      throw ArgumentError('The capture-stage VE-V2 views are incomplete.');
    }
  }

  String _rawOccupancyFor(
    PlantingUnitObservationRecord? previous,
    String primaryCondition,
  ) {
    final raw = previous?.occupancyStatus;
    if (raw != null && DatabaseCodes.veOccupancyStatuses.contains(raw)) {
      return raw;
    }
    return switch (primaryCondition) {
      DatabaseCodes.veUnitHealthy ||
      DatabaseCodes.veUnitFeedingInjury => DatabaseCodes.veOccupancySeedling,
      DatabaseCodes.veUnitEmptyUnexplained => DatabaseCodes.veOccupancyEmpty,
      DatabaseCodes.veUnitCutSevered ||
      DatabaseCodes.veUnitWiltedDead => DatabaseCodes.veOccupancyRemnant,
      DatabaseCodes.veUnitNotAssessable =>
        DatabaseCodes.veOccupancyNotAssessable,
      _ => DatabaseCodes.veOccupancyUncertain,
    };
  }

  Map<String, Object?> _stationSnapshot(VeV2StationInspectionRecord row) => {
    'station_id': row.stationId,
    'emergence_continuing': row.emergenceContinuing,
    'delayed_emergence_plausible': row.delayedEmergencePlausible,
    'sequence_assessable': row.plantingUnitSequenceAssessable,
    'row_direction_code': row.rowDirectionCode,
    'station_context_meets_row_purpose': row.stationContextMeetsRowPurpose,
  };

  Map<String, Object?> _unitSnapshot(PlantingUnitObservationRecord row) => {
    'station_id': row.stationId,
    'sequence_number': row.sequenceNumber,
    'primary_condition': row.primaryCondition,
    'observed_seedling_count': row.observedSeedlingCount,
    'visible_cutting': row.visibleCutting,
    'visible_severing': row.visibleSevering,
    'injury_location': row.injuryLocation,
    'injury_freshness': row.injuryFreshness,
    'larva_visible': row.larvaVisible,
    'fresh_frass': row.freshFrass,
    'alternative_cause_codes_json': row.alternativeCauseCodesJson,
    'evaluator_primary_interpretation': row.evaluatorPrimaryInterpretation,
  };
}
