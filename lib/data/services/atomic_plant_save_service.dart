import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';
import '../repositories/local_mutation_recorder.dart';
import '../repositories/evidence_capture_repository.dart';

class VegetativePlantSave {
  const VegetativePlantSave({
    required this.stationId,
    required this.plantPosition,
    required this.plantStatus,
    required this.assessable,
    required this.newestLeavesInspectedCount,
    required this.smallFreshWindowpanes,
    required this.scraping,
    required this.cuttingOrTearing,
    required this.freshFrass,
    required this.whorlFeedingSign,
    required this.larvaVisible,
    required this.larvalSize,
    required this.eggMassVisible,
    required this.oldDamagePresent,
    required this.possibleNonFawEvidence,
    required this.uncertainEvidence,
    this.notAssessableReason,
    this.naturalEnemyQuickStatus = DatabaseCodes.naturalEnemyNotCollected,
    this.persistentPlantIdentifier,
    this.sourcePlantingUnitObservationId,
    this.evaluatorNotes,
    this.actorPersonId,
    this.deviceId,
    this.evidenceCaptureSessionId,
    this.requiredEvidenceViewTypes = const {},
    this.requireCameraPhaseAEvidence = false,
    this.pilotActiveDurationMs = 0,
    this.manualFormUsed = true,
    this.daBafsLeafDamageScore,
    this.damageScoreUncertain = false,
    this.damageScoreReason,
    this.damageAttribution,
    this.damageFreshness,
  });

  final String stationId;
  final int plantPosition;
  final String plantStatus;
  final bool assessable;
  final String? notAssessableReason;
  final int? newestLeavesInspectedCount;
  final bool smallFreshWindowpanes;
  final bool scraping;
  final bool cuttingOrTearing;
  final bool freshFrass;
  final bool whorlFeedingSign;
  final bool larvaVisible;
  final String larvalSize;
  final bool? eggMassVisible;
  final bool oldDamagePresent;
  final bool? possibleNonFawEvidence;
  final bool? uncertainEvidence;
  final String naturalEnemyQuickStatus;
  final String? persistentPlantIdentifier;

  /// Optional explicit link to the planting unit containing this same
  /// physical seedling. It never copies or derives biological answers.
  final String? sourcePlantingUnitObservationId;
  final String? evaluatorNotes;
  final String? actorPersonId;
  final String? deviceId;
  final String? evidenceCaptureSessionId;
  final Set<String> requiredEvidenceViewTypes;
  final bool requireCameraPhaseAEvidence;
  final int pilotActiveDurationMs;
  final bool manualFormUsed;
  final int? daBafsLeafDamageScore;
  final bool damageScoreUncertain;
  final String? damageScoreReason;
  final String? damageAttribution;
  final String? damageFreshness;
}

class SavedVegetativePlant {
  const SavedVegetativePlant({required this.plant, required this.vegetative});

  final PlantObservationRecord plant;
  final VegetativeObservationRecord vegetative;
}

/// Protocol-derived SFW/IW indicators.
///
/// These indicate current FAW-consistent feeding evidence for the vegetative
/// calculation. They do not confirm that the pest species is FAW.
abstract final class VegetativeEvidenceDerivation {
  static bool infestedWhorl({
    required bool scraping,
    required bool cuttingOrTearing,
    required bool freshFrass,
    required bool whorlFeedingSign,
  }) {
    return scraping || cuttingOrTearing || freshFrass || whorlFeedingSign;
  }

  static bool currentFawConsistentEvidence({
    required bool smallFreshWindowpanes,
    required bool infestedWhorl,
  }) {
    return smallFreshWindowpanes || infestedWhorl;
  }
}

class AtomicPlantSaveService {
  AtomicPlantSaveService(
    this.database, {
    EvidenceCaptureRepository? evidenceRepository,
  }) : _mutations = LocalMutationRecorder(database),
       _evidence = evidenceRepository ?? EvidenceCaptureRepository(database);

  final AppDatabase database;
  final LocalMutationRecorder _mutations;
  final EvidenceCaptureRepository _evidence;

  Future<SavedVegetativePlant> saveVegetativePlant(
    VegetativePlantSave input,
  ) async {
    _validate(input);

    return database.transaction(() async {
      // Both previous records are intentionally loaded inside this transaction
      // so the audit snapshot and replacement values describe one atomic save.
      final previousPlant =
          await (database.select(database.plantObservations)..where(
                (row) =>
                    row.stationId.equals(input.stationId) &
                    row.sequenceNumber.equals(input.plantPosition),
              ))
              .getSingleOrNull();
      final plantId = previousPlant?.id ?? LocalId.generate();
      final previousVegetative = previousPlant == null
          ? null
          : await (database.select(database.vegetativeObservations)..where(
                  (row) => row.plantObservationId.equals(previousPlant.id),
                ))
                .getSingleOrNull();

      final infestedWhorl = VegetativeEvidenceDerivation.infestedWhorl(
        scraping: input.scraping,
        cuttingOrTearing: input.cuttingOrTearing,
        freshFrass: input.freshFrass,
        whorlFeedingSign: input.whorlFeedingSign,
      );
      final currentFawEvidence =
          VegetativeEvidenceDerivation.currentFawConsistentEvidence(
            smallFreshWindowpanes: input.smallFreshWindowpanes,
            infestedWhorl: infestedWhorl,
          );
      final now = DateTime.now().toUtc();

      if (input.sourcePlantingUnitObservationId != null) {
        final linkedUnit =
            await (database.select(database.plantingUnitObservations)..where(
                  (row) =>
                      row.id.equals(input.sourcePlantingUnitObservationId!),
                ))
                .getSingleOrNull();
        if (linkedUnit == null || linkedUnit.stationId != input.stationId) {
          throw ArgumentError(
            'A linked planting unit must exist in the same station.',
          );
        }
        final alreadyLinked =
            await (database.selectOnly(database.plantObservations)
                  ..addColumns([database.plantObservations.id.count()])
                  ..where(
                    database.plantObservations.sourcePlantingUnitObservationId
                            .equals(linkedUnit.id) &
                        (previousPlant == null
                            ? const Constant(true)
                            : database.plantObservations.id
                                  .equals(previousPlant.id)
                                  .not()),
                  ))
                .map(
                  (row) => row.read(database.plantObservations.id.count()) ?? 0,
                )
                .getSingle();
        if (alreadyLinked >= (linkedUnit.observedSeedlingCount ?? 0)) {
          throw StateError(
            'All living seedlings recorded for this planting unit are already linked.',
          );
        }
      }

      if (previousPlant == null) {
        await database
            .into(database.plantObservations)
            .insert(
              PlantObservationsCompanion.insert(
                id: plantId,
                stationId: input.stationId,
                sequenceNumber: input.plantPosition,
                sourcePlantingUnitObservationId: Value(
                  input.sourcePlantingUnitObservationId,
                ),
                persistentPlantIdentifier: Value(
                  input.persistentPlantIdentifier,
                ),
                assessable: Value(input.assessable),
                notAssessableReason: Value(input.notAssessableReason),
                plantStatus: input.plantStatus,
                currentFawEvidence: Value(currentFawEvidence),
                possibleNonFawEvidence: Value(input.possibleNonFawEvidence),
                uncertainEvidence: Value(input.uncertainEvidence),
                oldDamagePresent: Value(input.oldDamagePresent),
                naturalEnemyQuickStatus: input.naturalEnemyQuickStatus,
                capturedAt: Value(now),
                evaluatorNotes: Value(input.evaluatorNotes),
                updatedAt: Value(now),
                deviceId: Value(input.deviceId),
                syncState: const Value(DatabaseCodes.queued),
              ),
            );
      } else {
        await (database.update(
          database.plantObservations,
        )..where((row) => row.id.equals(plantId))).write(
          PlantObservationsCompanion(
            sourcePlantingUnitObservationId: Value(
              input.sourcePlantingUnitObservationId,
            ),
            persistentPlantIdentifier: Value(input.persistentPlantIdentifier),
            assessable: Value(input.assessable),
            notAssessableReason: Value(input.notAssessableReason),
            plantStatus: Value(input.plantStatus),
            currentFawEvidence: Value(currentFawEvidence),
            possibleNonFawEvidence: Value(input.possibleNonFawEvidence),
            uncertainEvidence: Value(input.uncertainEvidence),
            oldDamagePresent: Value(input.oldDamagePresent),
            naturalEnemyQuickStatus: Value(input.naturalEnemyQuickStatus),
            capturedAt: Value(now),
            evaluatorNotes: Value(input.evaluatorNotes),
            updatedAt: Value(now),
            deviceId: Value(input.deviceId),
            syncState: const Value(DatabaseCodes.queued),
          ),
        );
      }

      final vegetativeValues = VegetativeObservationsCompanion(
        newestLeavesInspectedCount: Value(input.newestLeavesInspectedCount),
        smallFreshWindowpanes: Value(input.smallFreshWindowpanes),
        infestedWhorl: Value(infestedWhorl),
        scraping: Value(input.scraping),
        cuttingOrTearing: Value(input.cuttingOrTearing),
        freshFrass: Value(input.freshFrass),
        whorlFeedingSign: Value(input.whorlFeedingSign),
        larvaVisible: Value(input.larvaVisible),
        larvalSize: Value(input.larvalSize),
        eggMassVisible: Value(input.eggMassVisible),
        daBafsLeafDamageScore: Value(input.daBafsLeafDamageScore),
        damageScoreUncertain: Value(input.damageScoreUncertain),
        damageScoreReason: Value(input.damageScoreReason),
        damageAttribution: Value(input.damageAttribution),
        damageFreshness: Value(input.damageFreshness),
        updatedAt: Value(now),
      );
      if (previousVegetative == null) {
        await database
            .into(database.vegetativeObservations)
            .insert(
              VegetativeObservationsCompanion.insert(
                plantObservationId: plantId,
                newestLeavesInspectedCount:
                    vegetativeValues.newestLeavesInspectedCount,
                smallFreshWindowpanes: vegetativeValues.smallFreshWindowpanes,
                infestedWhorl: vegetativeValues.infestedWhorl,
                scraping: vegetativeValues.scraping,
                cuttingOrTearing: vegetativeValues.cuttingOrTearing,
                freshFrass: vegetativeValues.freshFrass,
                whorlFeedingSign: vegetativeValues.whorlFeedingSign,
                larvaVisible: vegetativeValues.larvaVisible,
                larvalSize: vegetativeValues.larvalSize,
                eggMassVisible: vegetativeValues.eggMassVisible,
                daBafsLeafDamageScore: vegetativeValues.daBafsLeafDamageScore,
                damageScoreUncertain: vegetativeValues.damageScoreUncertain,
                damageScoreReason: vegetativeValues.damageScoreReason,
                damageAttribution: vegetativeValues.damageAttribution,
                damageFreshness: vegetativeValues.damageFreshness,
                updatedAt: vegetativeValues.updatedAt,
              ),
            );
      } else {
        await (database.update(database.vegetativeObservations)
              ..where((row) => row.plantObservationId.equals(plantId)))
            .write(vegetativeValues);
      }

      final savedPlant = await (database.select(
        database.plantObservations,
      )..where((row) => row.id.equals(plantId))).getSingle();
      final savedVegetative = await (database.select(
        database.vegetativeObservations,
      )..where((row) => row.plantObservationId.equals(plantId))).getSingle();

      if (input.requireCameraPhaseAEvidence) {
        await _evidence.attachPlantEvidenceInCurrentTransaction(
          sessionId: input.evidenceCaptureSessionId!,
          stationId: input.stationId,
          plantPosition: input.plantPosition,
          plantObservationId: plantId,
          sourcePlantingUnitObservationId:
              input.sourcePlantingUnitObservationId,
          requiredViewTypes: input.requiredEvidenceViewTypes,
          actorPersonId: input.actorPersonId ?? '',
          pilotActiveDurationMs: input.pilotActiveDurationMs,
          manualFormUsed: input.manualFormUsed,
        );
      }

      await _mutations.record(
        entityType: 'plant_observations',
        entityId: plantId,
        action: previousPlant == null ? 'create' : 'update',
        actorPersonId: input.actorPersonId,
        deviceId: input.deviceId,
        before: previousPlant == null
            ? null
            : _auditSnapshot(previousPlant, previousVegetative),
        after: _auditSnapshot(savedPlant, savedVegetative),
      );

      return SavedVegetativePlant(
        plant: savedPlant,
        vegetative: savedVegetative,
      );
    });
  }

  void _validate(VegetativePlantSave input) {
    if (input.pilotActiveDurationMs < 0) {
      throw ArgumentError.value(
        input.pilotActiveDurationMs,
        'pilotActiveDurationMs',
        'Pilot active duration cannot be negative',
      );
    }
    if (input.plantPosition < 1 || input.plantPosition > 10) {
      throw ArgumentError.value(
        input.plantPosition,
        'plantPosition',
        'Plant position must be 1-10',
      );
    }
    if (!DatabaseCodes.plantStatuses.contains(input.plantStatus)) {
      throw ArgumentError.value(
        input.plantStatus,
        'plantStatus',
        'Unsupported evaluator-confirmed interpretation',
      );
    }
    if (!DatabaseCodes.naturalEnemyQuickStatuses.contains(
      input.naturalEnemyQuickStatus,
    )) {
      throw ArgumentError.value(
        input.naturalEnemyQuickStatus,
        'naturalEnemyQuickStatus',
        'Unsupported natural-enemy quick status',
      );
    }
    if (input.requireCameraPhaseAEvidence &&
        (input.evidenceCaptureSessionId == null ||
            input.evidenceCaptureSessionId!.isEmpty)) {
      throw ArgumentError(
        'Camera Phase A saves require the active evidence capture session.',
      );
    }
    if (input.requireCameraPhaseAEvidence &&
        (input.actorPersonId == null || input.actorPersonId!.isEmpty)) {
      throw ArgumentError(
        'Camera Phase A saves require the evaluator identity for audit.',
      );
    }
    if (!DatabaseCodes.larvalSizes.contains(input.larvalSize)) {
      throw ArgumentError.value(
        input.larvalSize,
        'larvalSize',
        'Unsupported larval-size group',
      );
    }
    if (!input.assessable) {
      if (input.plantStatus != DatabaseCodes.plantNotAssessable) {
        throw ArgumentError(
          'A non-assessable plant requires not_assessable interpretation.',
        );
      }
      if (input.notAssessableReason == null ||
          input.notAssessableReason!.trim().isEmpty) {
        throw ArgumentError('A non-assessable plant requires a reason.');
      }
    } else if (input.plantStatus == DatabaseCodes.plantNotAssessable) {
      throw ArgumentError(
        'An assessable plant cannot use not_assessable interpretation.',
      );
    }
    if (input.assessable &&
        input.newestLeavesInspectedCount != 3 &&
        input.newestLeavesInspectedCount != 4) {
      throw ArgumentError.value(
        input.newestLeavesInspectedCount,
        'newestLeavesInspectedCount',
        'An assessable vegetative plant requires inspection of 3 or 4 newest leaves',
      );
    }
    if (input.larvaVisible && input.larvalSize == 'none_seen') {
      throw ArgumentError(
        'A visible larva requires a larval-size group or uncertain.',
      );
    }
    if (!input.larvaVisible && input.larvalSize != 'none_seen') {
      throw ArgumentError(
        'Larval size must be none_seen when no larva is visible.',
      );
    }
    if (input.daBafsLeafDamageScore != null &&
        (input.daBafsLeafDamageScore! < 0 ||
            input.daBafsLeafDamageScore! > 9)) {
      throw ArgumentError.value(
        input.daBafsLeafDamageScore,
        'daBafsLeafDamageScore',
        'DA-BAFS score must be an integer from 0 through 9',
      );
    }
    if (input.damageAttribution != null &&
        !DatabaseCodes.damageAttributions.contains(input.damageAttribution)) {
      throw ArgumentError.value(
        input.damageAttribution,
        'damageAttribution',
        'Unsupported damage attribution',
      );
    }
    if (input.damageFreshness != null &&
        !DatabaseCodes.evidenceFreshnessValues.contains(
          input.damageFreshness,
        )) {
      throw ArgumentError.value(
        input.damageFreshness,
        'damageFreshness',
        'Unsupported damage freshness',
      );
    }
    if (input.damageScoreUncertain &&
        (input.damageScoreReason == null ||
            input.damageScoreReason!.trim().isEmpty)) {
      throw ArgumentError('An uncertain DA-BAFS score requires a reason.');
    }
  }

  Map<String, Object?> _auditSnapshot(
    PlantObservationRecord plant,
    VegetativeObservationRecord? vegetative,
  ) {
    return {
      'station_id': plant.stationId,
      'plant_position': plant.sequenceNumber,
      'source_planting_unit_observation_id':
          plant.sourcePlantingUnitObservationId,
      'assessable': plant.assessable,
      'not_assessable_reason': plant.notAssessableReason,
      'plant_status': plant.plantStatus,
      'current_faw_evidence': plant.currentFawEvidence,
      'possible_non_faw_evidence': plant.possibleNonFawEvidence,
      'uncertain_evidence': plant.uncertainEvidence,
      'old_damage_present': plant.oldDamagePresent,
      'natural_enemy_quick_status': plant.naturalEnemyQuickStatus,
      'newest_leaves_inspected_count': vegetative?.newestLeavesInspectedCount,
      'small_fresh_windowpanes': vegetative?.smallFreshWindowpanes,
      'infested_whorl': vegetative?.infestedWhorl,
      'scraping': vegetative?.scraping,
      'cutting_or_tearing': vegetative?.cuttingOrTearing,
      'fresh_frass': vegetative?.freshFrass,
      'whorl_feeding_sign': vegetative?.whorlFeedingSign,
      'larva_visible': vegetative?.larvaVisible,
      'larval_size': vegetative?.larvalSize,
      'egg_mass_visible': vegetative?.eggMassVisible,
      'da_bafs_leaf_damage_score': vegetative?.daBafsLeafDamageScore,
      'damage_score_uncertain': vegetative?.damageScoreUncertain,
      'damage_score_reason': vegetative?.damageScoreReason,
      'damage_attribution': vegetative?.damageAttribution,
      'damage_freshness': vegetative?.damageFreshness,
    };
  }
}
