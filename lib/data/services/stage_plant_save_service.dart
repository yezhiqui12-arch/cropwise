import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';
import '../repositories/evidence_capture_repository.dart';
import '../repositories/local_mutation_recorder.dart';

class ReproductivePlantSave {
  const ReproductivePlantSave({
    required this.stationId,
    required this.plantPosition,
    required this.assessable,
    required this.classification,
    required this.tasselExamined,
    required this.earBaseExamined,
    required this.upperAxilExamined,
    required this.lowerAxilExamined,
    required this.freshFeedingPresent,
    required this.frassPresent,
    required this.earHuskPenetrationVisible,
    required this.larvaPresent,
    required this.larvalSize,
    required this.possibleNonFawEvidence,
    required this.uncertainEvidence,
    required this.naturalEnemyQuickStatus,
    this.larvaCount,
    this.causeTags = const {},
    this.notAssessableReason,
    this.evaluatorNotes,
    this.actorPersonId,
    this.evidenceCaptureSessionId,
    this.requiredEvidenceViewTypes = const {},
    this.pilotActiveDurationMs = 0,
  });

  final String stationId;
  final int plantPosition;
  final bool assessable;
  final String classification;
  final bool tasselExamined;
  final bool earBaseExamined;
  final bool upperAxilExamined;
  final bool lowerAxilExamined;
  final bool freshFeedingPresent;
  final bool frassPresent;
  final bool earHuskPenetrationVisible;
  final bool larvaPresent;
  final int? larvaCount;
  final String larvalSize;
  final bool? possibleNonFawEvidence;
  final bool? uncertainEvidence;
  final String naturalEnemyQuickStatus;
  final Set<String> causeTags;
  final String? notAssessableReason;
  final String? evaluatorNotes;
  final String? actorPersonId;
  final String? evidenceCaptureSessionId;
  final Set<String> requiredEvidenceViewTypes;
  final int pilotActiveDurationMs;
}

class EarExternalPlantSave {
  const EarExternalPlantSave({
    required this.stationId,
    required this.plantPosition,
    required this.earPresent,
    required this.externallyAssessable,
    required this.designatedEarIdentity,
    required this.exteriorEarTipExamined,
    required this.baseShankSilkAxilsExamined,
    required this.externalDamagePresent,
    required this.activeInfestationPresent,
    required this.silkDamagePresent,
    required this.huskDamagePresent,
    required this.entryHolePresent,
    required this.frassPresent,
    required this.larvaPresent,
    required this.moldRotLikeSymptoms,
    required this.externalClassification,
    required this.naturalEnemyQuickStatus,
    this.frassFreshness,
    this.larvalSize,
    this.feedingFreshness,
    this.causeTags = const {},
    this.notAssessableReason,
    this.evaluatorNotes,
    this.actorPersonId,
    this.evidenceCaptureSessionId,
    this.requiredEvidenceViewTypes = const {},
    this.pilotActiveDurationMs = 0,
  });

  final String stationId;
  final int plantPosition;
  final bool? earPresent;
  final bool externallyAssessable;
  final String? designatedEarIdentity;
  final bool exteriorEarTipExamined;
  final bool baseShankSilkAxilsExamined;
  final bool? externalDamagePresent;
  final bool? activeInfestationPresent;
  final bool? silkDamagePresent;
  final bool? huskDamagePresent;
  final bool? entryHolePresent;
  final bool? frassPresent;
  final String? frassFreshness;
  final bool? larvaPresent;
  final String? larvalSize;
  final String? feedingFreshness;
  final bool? moldRotLikeSymptoms;
  final Set<String> causeTags;
  final String externalClassification;
  final String naturalEnemyQuickStatus;
  final String? notAssessableReason;
  final String? evaluatorNotes;
  final String? actorPersonId;
  final String? evidenceCaptureSessionId;
  final Set<String> requiredEvidenceViewTypes;
  final int pilotActiveDurationMs;
}

class LateSeasonSetupInput {
  const LateSeasonSetupInput({
    required this.assessmentId,
    required this.cropUse,
    required this.commercialHarvestStarted,
    required this.selectedEarsPartOfHarvest,
    required this.openingPermission,
    required this.maximumEarsPermitted,
    required this.earDesignationRule,
    required this.permissionRecordedAt,
    required this.blockRunIds,
    this.openingReason,
    this.permissionGrantedBy,
    this.evaluatorPersonId,
    this.remarks,
  });

  final String assessmentId;
  final String cropUse;
  final bool commercialHarvestStarted;
  final bool selectedEarsPartOfHarvest;
  final String openingPermission;
  final int maximumEarsPermitted;
  final String? openingReason;
  final String? permissionGrantedBy;
  final String? evaluatorPersonId;
  final DateTime permissionRecordedAt;
  final String earDesignationRule;
  final String? remarks;
  final List<String> blockRunIds;
}

class OpenedEarSave {
  const OpenedEarSave({
    required this.earObservationId,
    required this.selectionId,
    required this.huskIntactBeforeOpening,
    required this.internalDamagePresent,
    required this.cobDamagePresent,
    required this.brokenMissingUnderdevelopedKernels,
    required this.earRotPresent,
    required this.internalClassification,
    required this.evidenceCaptureSessionId,
    this.totalKernelsCounted,
    this.damagedKernelsCounted,
    this.kernelCountMethod,
    this.earTipDamageLengthMm,
    this.moldRotKernelsCounted,
    this.earRotSuspectedType,
    this.notes,
    this.actorPersonId,
  });

  final String earObservationId;
  final String selectionId;
  final bool huskIntactBeforeOpening;
  final bool internalDamagePresent;
  final int? totalKernelsCounted;
  final int? damagedKernelsCounted;
  final String? kernelCountMethod;
  final double? earTipDamageLengthMm;
  final bool cobDamagePresent;
  final bool brokenMissingUnderdevelopedKernels;
  final bool earRotPresent;
  final int? moldRotKernelsCounted;
  final String? earRotSuspectedType;
  final String internalClassification;
  final String evidenceCaptureSessionId;
  final String? notes;
  final String? actorPersonId;
}

class StagePlantSaveService {
  StagePlantSaveService(this.database)
    : _mutations = LocalMutationRecorder(database),
      _evidence = EvidenceCaptureRepository(database);

  final AppDatabase database;
  final LocalMutationRecorder _mutations;
  final EvidenceCaptureRepository _evidence;

  Future<void> saveReproductivePlant(ReproductivePlantSave input) async {
    _validateReproductive(input);
    await database.transaction(() async {
      final plant = await _upsertPlant(
        stationId: input.stationId,
        plantPosition: input.plantPosition,
        assessable: input.assessable,
        notAssessableReason: input.notAssessableReason,
        plantStatus: switch (input.classification) {
          DatabaseCodes.reproductiveInfested =>
            DatabaseCodes.plantCurrentPositive,
          DatabaseCodes.reproductiveUncertain => DatabaseCodes.plantUncertain,
          DatabaseCodes.reproductiveNotAssessable =>
            DatabaseCodes.plantNotAssessable,
          _ => DatabaseCodes.plantNegative,
        },
        currentFawEvidence:
            input.assessable &&
            (input.larvaPresent || input.freshFeedingPresent),
        possibleNonFawEvidence: input.possibleNonFawEvidence,
        uncertainEvidence: input.uncertainEvidence,
        naturalEnemyQuickStatus: input.naturalEnemyQuickStatus,
        evaluatorNotes: input.evaluatorNotes,
      );
      final previous =
          await (database.select(database.reproductiveObservations)
                ..where((row) => row.plantObservationId.equals(plant.id)))
              .getSingleOrNull();
      final values = ReproductiveObservationsCompanion(
        tasselExamined: Value(input.tasselExamined),
        earBaseExamined: Value(input.earBaseExamined),
        upperAxilExamined: Value(input.upperAxilExamined),
        lowerAxilExamined: Value(input.lowerAxilExamined),
        freshFeedingPresent: Value(input.freshFeedingPresent),
        larvaPresent: Value(input.larvaPresent),
        larvaCount: Value(input.larvaCount),
        larvalSize: Value(input.larvalSize),
        frassPresent: Value(input.frassPresent),
        earHuskPenetrationVisible: Value(input.earHuskPenetrationVisible),
        possibleNonFawEvidence: Value(input.possibleNonFawEvidence),
        uncertainEvidence: Value(input.uncertainEvidence),
        classification: Value(input.classification),
        causeTagsJson: Value(_encodeTags(input.causeTags)),
        percentInfestedPositive: Value(
          input.assessable && (input.larvaPresent || input.freshFeedingPresent),
        ),
        updatedAt: Value(DateTime.now().toUtc()),
      );
      if (previous == null) {
        await database
            .into(database.reproductiveObservations)
            .insert(
              ReproductiveObservationsCompanion.insert(
                plantObservationId: plant.id,
                tasselExamined: values.tasselExamined,
                earBaseExamined: values.earBaseExamined,
                upperAxilExamined: values.upperAxilExamined,
                lowerAxilExamined: values.lowerAxilExamined,
                freshFeedingPresent: values.freshFeedingPresent,
                larvaPresent: values.larvaPresent,
                larvaCount: values.larvaCount,
                larvalSize: values.larvalSize,
                frassPresent: values.frassPresent,
                earHuskPenetrationVisible: values.earHuskPenetrationVisible,
                possibleNonFawEvidence: values.possibleNonFawEvidence,
                uncertainEvidence: values.uncertainEvidence,
                classification: values.classification,
                causeTagsJson: values.causeTagsJson,
                percentInfestedPositive: values.percentInfestedPositive,
                updatedAt: values.updatedAt,
              ),
            );
      } else {
        await (database.update(database.reproductiveObservations)
              ..where((row) => row.plantObservationId.equals(plant.id)))
            .write(values);
      }
      await _attachEvidence(
        plant: plant,
        sessionId: input.evidenceCaptureSessionId,
        requiredViews: input.requiredEvidenceViewTypes,
        actorPersonId: input.actorPersonId,
        activeDurationMs: input.pilotActiveDurationMs,
      );
      await _recordPlantAudit(plant, input.actorPersonId, 'vt_r2_observation');
    });
  }

  Future<void> saveExternalEar(EarExternalPlantSave input) async {
    _validateExternalEar(input);
    await database.transaction(() async {
      final plant = await _upsertPlant(
        stationId: input.stationId,
        plantPosition: input.plantPosition,
        assessable: input.externallyAssessable,
        notAssessableReason: input.notAssessableReason,
        plantStatus: switch (input.externalClassification) {
          DatabaseCodes.earExternalActive => DatabaseCodes.plantCurrentPositive,
          DatabaseCodes.earExternalUncertain => DatabaseCodes.plantUncertain,
          DatabaseCodes.earExternalOtherPest ||
          DatabaseCodes.earExternalNonPest ||
          DatabaseCodes.earExternalMoldRot => DatabaseCodes.plantPossibleNonFaw,
          DatabaseCodes.earExternalOldDamage =>
            DatabaseCodes.plantOldDamageOnly,
          DatabaseCodes.earExternalNotAssessable =>
            DatabaseCodes.plantNotAssessable,
          _ => DatabaseCodes.plantNegative,
        },
        currentFawEvidence: input.activeInfestationPresent,
        possibleNonFawEvidence: input.causeTags.isNotEmpty,
        uncertainEvidence:
            input.externalClassification == DatabaseCodes.earExternalUncertain,
        naturalEnemyQuickStatus: input.naturalEnemyQuickStatus,
        evaluatorNotes: input.evaluatorNotes,
      );
      final previous =
          await (database.select(database.earObservations)..where(
                (row) =>
                    row.plantObservationId.equals(plant.id) &
                    row.earSequence.equals(1) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      final setup = await _setupForPlant(plant);
      final values = EarObservationsCompanion(
        earPresent: Value(input.earPresent),
        designatedEarIdentity: Value(input.designatedEarIdentity),
        externallyAssessable: Value(input.externallyAssessable),
        exteriorEarTipExamined: Value(input.exteriorEarTipExamined),
        baseShankSilkAxilsExamined: Value(input.baseShankSilkAxilsExamined),
        externalDamagePresent: Value(input.externalDamagePresent),
        activeInfestationPresent: Value(input.activeInfestationPresent),
        silkDamagePresent: Value(input.silkDamagePresent),
        huskDamagePresent: Value(input.huskDamagePresent),
        entryHolePresent: Value(input.entryHolePresent),
        frassPresent: Value(input.frassPresent),
        frassFreshness: Value(input.frassFreshness),
        larvaPresent: Value(input.larvaPresent),
        larvalSize: Value(input.larvalSize),
        feedingFreshness: Value(input.feedingFreshness),
        moldRotLikeSymptoms: Value(input.moldRotLikeSymptoms),
        causeTagsJson: Value(_encodeTags(input.causeTags)),
        externalClassification: Value(input.externalClassification),
        openingPermission: Value(setup.openingPermission),
        notes: Value(input.evaluatorNotes),
        updatedAt: Value(DateTime.now().toUtc()),
        syncState: const Value(DatabaseCodes.queued),
      );
      String earId;
      if (previous == null) {
        earId = LocalId.generate();
        await database
            .into(database.earObservations)
            .insert(
              EarObservationsCompanion.insert(
                id: earId,
                plantObservationId: plant.id,
                earPresent: values.earPresent,
                designatedEarIdentity: values.designatedEarIdentity,
                externallyAssessable: values.externallyAssessable,
                exteriorEarTipExamined: values.exteriorEarTipExamined,
                baseShankSilkAxilsExamined: values.baseShankSilkAxilsExamined,
                externalDamagePresent: values.externalDamagePresent,
                activeInfestationPresent: values.activeInfestationPresent,
                silkDamagePresent: values.silkDamagePresent,
                huskDamagePresent: values.huskDamagePresent,
                entryHolePresent: values.entryHolePresent,
                frassPresent: values.frassPresent,
                frassFreshness: values.frassFreshness,
                larvaPresent: values.larvaPresent,
                larvalSize: values.larvalSize,
                feedingFreshness: values.feedingFreshness,
                moldRotLikeSymptoms: values.moldRotLikeSymptoms,
                causeTagsJson: values.causeTagsJson,
                externalClassification: values.externalClassification,
                openingPermission: values.openingPermission,
                notes: values.notes,
                updatedAt: values.updatedAt,
                syncState: values.syncState,
              ),
            );
      } else {
        earId = previous.id;
        await (database.update(
          database.earObservations,
        )..where((row) => row.id.equals(earId))).write(values);
      }
      await _attachEvidence(
        plant: plant,
        sessionId: input.evidenceCaptureSessionId,
        requiredViews: input.requiredEvidenceViewTypes,
        actorPersonId: input.actorPersonId,
        activeDurationMs: input.pilotActiveDurationMs,
      );
      await _recordPlantAudit(plant, input.actorPersonId, 'r3_r6_external');
      await _mutations.record(
        entityType: 'ear_observations',
        entityId: earId,
        action: previous == null ? 'create_external' : 'update_external',
        actorPersonId: input.actorPersonId,
        after: {
          'plant_observation_id': plant.id,
          'external_classification': input.externalClassification,
          'externally_assessable': input.externallyAssessable,
        },
      );
    });
  }

  Future<LateSeasonAssessmentSetupRecord?> loadLateSeasonSetup(
    String assessmentId,
  ) =>
      (database.select(database.lateSeasonAssessmentSetups)..where(
            (row) =>
                row.assessmentId.equals(assessmentId) & row.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<LateSeasonAssessmentSetupRecord> saveLateSeasonSetup(
    LateSeasonSetupInput input,
  ) async {
    _validateLateSetup(input);
    return database.transaction(() async {
      final previous = await loadLateSeasonSetup(input.assessmentId);
      if (previous != null) return previous;
      final id = LocalId.generate();
      final now = DateTime.now().toUtc();
      await database
          .into(database.lateSeasonAssessmentSetups)
          .insert(
            LateSeasonAssessmentSetupsCompanion.insert(
              id: id,
              assessmentId: input.assessmentId,
              cropUse: input.cropUse,
              commercialHarvestStarted: input.commercialHarvestStarted,
              selectedEarsPartOfHarvest: input.selectedEarsPartOfHarvest,
              openingPermission: input.openingPermission,
              maximumEarsPermitted: Value(input.maximumEarsPermitted),
              openingReason: Value(input.openingReason),
              permissionGrantedBy: Value(input.permissionGrantedBy),
              evaluatorPersonId: Value(input.evaluatorPersonId),
              permissionRecordedAt: input.permissionRecordedAt.toUtc(),
              earDesignationRule: input.earDesignationRule,
              remarks: Value(input.remarks),
              updatedAt: Value(now),
              syncState: const Value(DatabaseCodes.queued),
            ),
          );
      await _createOpeningPlan(input);
      await _mutations.record(
        entityType: 'late_season_assessment_setups',
        entityId: id,
        action: 'create',
        actorPersonId: input.evaluatorPersonId,
        after: {
          'assessment_id': input.assessmentId,
          'crop_use': input.cropUse,
          'opening_permission': input.openingPermission,
          'maximum_ears_permitted': input.maximumEarsPermitted,
          'ear_designation_rule': input.earDesignationRule,
        },
      );
      return (database.select(
        database.lateSeasonAssessmentSetups,
      )..where((row) => row.id.equals(id))).getSingle();
    });
  }

  Future<List<EarOpeningSelectionRecord>> loadOpeningPlan({
    required String blockRunId,
    required int stationNumber,
  }) =>
      (database.select(database.earOpeningSelections)
            ..where(
              (row) =>
                  row.assessmentBlockRunId.equals(blockRunId) &
                  row.stationNumber.equals(stationNumber) &
                  row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.selectionOrder)]))
          .get();

  Future<EarOpeningSelectionRecord?> markOpeningSelectionFailed({
    required String selectionId,
    required String reason,
    required String? actorPersonId,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('A failed opened-ear selection requires a reason.');
    }
    return database.transaction(() async {
      final failed = await (database.select(
        database.earOpeningSelections,
      )..where((row) => row.id.equals(selectionId))).getSingle();
      if (!(failed.initiallySelected ||
          failed.selectionStatus == 'replacement_selected')) {
        throw StateError('Only an active opening selection can fail.');
      }
      if (failed.selectionStatus == 'opened') {
        throw StateError('An opened ear cannot be marked failed.');
      }
      final now = DateTime.now().toUtc();
      await (database.update(
        database.earOpeningSelections,
      )..where((row) => row.id.equals(failed.id))).write(
        EarOpeningSelectionsCompanion(
          selectionStatus: const Value('failed'),
          failureReason: Value(reason.trim()),
          updatedAt: Value(now),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
      final replacement =
          await (database.select(database.earOpeningSelections)
                ..where(
                  (row) =>
                      row.assessmentBlockRunId.equals(
                        failed.assessmentBlockRunId,
                      ) &
                      row.stationNumber.equals(failed.stationNumber) &
                      row.initiallySelected.equals(false) &
                      row.selectionStatus.equals('planned') &
                      row.deletedAt.isNull(),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.selectionOrder)])
                ..limit(1))
              .getSingleOrNull();
      if (replacement != null) {
        await (database.update(
          database.earOpeningSelections,
        )..where((row) => row.id.equals(replacement.id))).write(
          EarOpeningSelectionsCompanion(
            selectionStatus: const Value('replacement_selected'),
            replacesPlantPosition: Value(failed.plantPosition),
            updatedAt: Value(now),
            syncState: const Value(DatabaseCodes.queued),
          ),
        );
      }
      await _mutations.record(
        entityType: 'ear_opening_selections',
        entityId: failed.id,
        action: 'selection_failed',
        actorPersonId: actorPersonId,
        after: {
          'failure_reason': reason.trim(),
          'replacement_selection_id': replacement?.id,
          'replacement_plant_position': replacement?.plantPosition,
        },
      );
      return replacement == null
          ? null
          : (database.select(
              database.earOpeningSelections,
            )..where((row) => row.id.equals(replacement.id))).getSingle();
    });
  }

  Future<void> saveOpenedEar(OpenedEarSave input) async {
    _validateOpenedEar(input);
    await database.transaction(() async {
      final ear = await (database.select(
        database.earObservations,
      )..where((row) => row.id.equals(input.earObservationId))).getSingle();
      final selection = await (database.select(
        database.earOpeningSelections,
      )..where((row) => row.id.equals(input.selectionId))).getSingle();
      final plant = await (database.select(
        database.plantObservations,
      )..where((row) => row.id.equals(ear.plantObservationId))).getSingle();
      final station = await (database.select(
        database.stations,
      )..where((row) => row.id.equals(plant.stationId))).getSingle();
      if (selection.assessmentBlockRunId != station.assessmentBlockRunId ||
          selection.stationNumber != station.stationNumber ||
          selection.plantPosition != plant.sequenceNumber ||
          !(selection.initiallySelected ||
              selection.selectionStatus == 'replacement_selected') ||
          ear.externallyAssessable != true ||
          ear.earPresent != true) {
        throw StateError(
          'Opened ear does not match an active, externally assessable preselection.',
        );
      }
      final setup = await _setupForPlant(plant);
      if (setup.openingPermission != DatabaseCodes.openingPermissionGranted) {
        throw StateError('Ear opening permission was not granted.');
      }
      final openedCount = await _openedEarCount(setup.assessmentId);
      if (!ear.opened && openedCount >= setup.maximumEarsPermitted) {
        throw StateError('The authorized opened-ear maximum has been reached.');
      }
      final bundle = await _evidence.loadBundle(input.evidenceCaptureSessionId);
      if (bundle.session.stationId != plant.stationId ||
          bundle.session.plantObservationId != plant.id) {
        throw StateError('Opened-ear evidence is attached to the wrong plant.');
      }
      for (final view in const {
        DatabaseCodes.evidenceViewWholeEarBeforeOpening,
        DatabaseCodes.evidenceViewOpenedEarSideA,
        DatabaseCodes.evidenceViewOpenedEarSideB,
      }) {
        if (!bundle.isViewSatisfied(view)) {
          throw StateError('Opened-ear evidence is missing: $view.');
        }
      }
      await (database.update(
        database.earObservations,
      )..where((row) => row.id.equals(ear.id))).write(
        EarObservationsCompanion(
          opened: const Value(true),
          huskIntactBeforeOpening: Value(input.huskIntactBeforeOpening),
          internalDamagePresent: Value(input.internalDamagePresent),
          totalKernelsCounted: Value(input.totalKernelsCounted),
          damagedKernelsCounted: Value(input.damagedKernelsCounted),
          kernelCountMethod: Value(input.kernelCountMethod),
          earTipDamageLengthMm: Value(input.earTipDamageLengthMm),
          cobDamagePresent: Value(input.cobDamagePresent),
          brokenMissingUnderdevelopedKernels: Value(
            input.brokenMissingUnderdevelopedKernels,
          ),
          earRotPresent: Value(input.earRotPresent),
          moldRotKernelsCounted: Value(input.moldRotKernelsCounted),
          earRotSuspectedType: Value(input.earRotSuspectedType),
          internalClassification: Value(input.internalClassification),
          notes: Value(input.notes),
          updatedAt: Value(DateTime.now().toUtc()),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
      await (database.update(
        database.earOpeningSelections,
      )..where((row) => row.id.equals(selection.id))).write(
        EarOpeningSelectionsCompanion(
          selectionStatus: const Value('opened'),
          updatedAt: Value(DateTime.now().toUtc()),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
      await (database.update(database.evidenceMedia)..where(
            (row) =>
                row.captureSessionId.equals(bundle.session.id) &
                row.viewType.isIn(const [
                  DatabaseCodes.evidenceViewWholeEarBeforeOpening,
                  DatabaseCodes.evidenceViewOpenedEarSideA,
                  DatabaseCodes.evidenceViewOpenedEarSideB,
                ]),
          ))
          .write(EvidenceMediaCompanion(earObservationId: Value(ear.id)));
      await _mutations.record(
        entityType: 'ear_observations',
        entityId: ear.id,
        action: 'opened_ear_completed',
        actorPersonId: input.actorPersonId,
        after: {
          'selection_id': selection.id,
          'internal_damage_present': input.internalDamagePresent,
          'damaged_kernels_counted': input.damagedKernelsCounted,
          'total_kernels_counted': input.totalKernelsCounted,
          'internal_classification': input.internalClassification,
        },
      );
    });
  }

  Future<PlantObservationRecord> _upsertPlant({
    required String stationId,
    required int plantPosition,
    required bool assessable,
    required String? notAssessableReason,
    required String plantStatus,
    required bool? currentFawEvidence,
    required bool? possibleNonFawEvidence,
    required bool? uncertainEvidence,
    required String naturalEnemyQuickStatus,
    required String? evaluatorNotes,
  }) async {
    final previous =
        await (database.select(database.plantObservations)..where(
              (row) =>
                  row.stationId.equals(stationId) &
                  row.sequenceNumber.equals(plantPosition) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    final id = previous?.id ?? LocalId.generate();
    final now = DateTime.now().toUtc();
    final values = PlantObservationsCompanion(
      assessable: Value(assessable),
      notAssessableReason: Value(notAssessableReason),
      plantStatus: Value(plantStatus),
      currentFawEvidence: Value(currentFawEvidence),
      possibleNonFawEvidence: Value(possibleNonFawEvidence),
      uncertainEvidence: Value(uncertainEvidence),
      naturalEnemyQuickStatus: Value(naturalEnemyQuickStatus),
      capturedAt: Value(now),
      evaluatorNotes: Value(evaluatorNotes),
      updatedAt: Value(now),
      syncState: const Value(DatabaseCodes.queued),
    );
    if (previous == null) {
      await database
          .into(database.plantObservations)
          .insert(
            PlantObservationsCompanion.insert(
              id: id,
              stationId: stationId,
              sequenceNumber: plantPosition,
              plantStatus: plantStatus,
              assessable: values.assessable,
              notAssessableReason: values.notAssessableReason,
              currentFawEvidence: values.currentFawEvidence,
              possibleNonFawEvidence: values.possibleNonFawEvidence,
              uncertainEvidence: values.uncertainEvidence,
              naturalEnemyQuickStatus: naturalEnemyQuickStatus,
              capturedAt: values.capturedAt,
              evaluatorNotes: values.evaluatorNotes,
              updatedAt: values.updatedAt,
              syncState: values.syncState,
            ),
          );
    } else {
      await (database.update(
        database.plantObservations,
      )..where((row) => row.id.equals(id))).write(values);
    }
    return (database.select(
      database.plantObservations,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<void> _attachEvidence({
    required PlantObservationRecord plant,
    required String? sessionId,
    required Set<String> requiredViews,
    required String? actorPersonId,
    required int activeDurationMs,
  }) async {
    if (sessionId == null) return;
    await _evidence.attachPlantEvidenceInCurrentTransaction(
      sessionId: sessionId,
      stationId: plant.stationId,
      plantPosition: plant.sequenceNumber,
      plantObservationId: plant.id,
      sourcePlantingUnitObservationId: plant.sourcePlantingUnitObservationId,
      requiredViewTypes: requiredViews,
      actorPersonId: actorPersonId ?? '',
      pilotActiveDurationMs: activeDurationMs,
      manualFormUsed: true,
    );
  }

  Future<LateSeasonAssessmentSetupRecord> _setupForPlant(
    PlantObservationRecord plant,
  ) async {
    final station = await (database.select(
      database.stations,
    )..where((row) => row.id.equals(plant.stationId))).getSingle();
    final run = await (database.select(
      database.assessmentBlockRuns,
    )..where((row) => row.id.equals(station.assessmentBlockRunId))).getSingle();
    final setup = await loadLateSeasonSetup(run.assessmentId);
    if (setup == null) {
      throw StateError('Complete the late-season authorization first.');
    }
    return setup;
  }

  Future<int> _openedEarCount(String assessmentId) async {
    final runs =
        await (database.select(database.assessmentBlockRuns)..where(
              (row) =>
                  row.assessmentId.equals(assessmentId) &
                  row.deletedAt.isNull(),
            ))
            .get();
    final runIds = runs.map((row) => row.id).toList();
    if (runIds.isEmpty) return 0;
    final stations =
        await (database.select(database.stations)..where(
              (row) =>
                  row.assessmentBlockRunId.isIn(runIds) &
                  row.deletedAt.isNull(),
            ))
            .get();
    final stationIds = stations.map((row) => row.id).toList();
    if (stationIds.isEmpty) return 0;
    final plants =
        await (database.select(database.plantObservations)..where(
              (row) => row.stationId.isIn(stationIds) & row.deletedAt.isNull(),
            ))
            .get();
    final plantIds = plants.map((row) => row.id).toList();
    if (plantIds.isEmpty) return 0;
    final ears =
        await (database.select(database.earObservations)..where(
              (row) =>
                  row.plantObservationId.isIn(plantIds) &
                  row.opened.equals(true) &
                  row.deletedAt.isNull(),
            ))
            .get();
    return ears.length;
  }

  Future<void> _createOpeningPlan(LateSeasonSetupInput input) async {
    var remaining =
        input.openingPermission == DatabaseCodes.openingPermissionGranted
        ? input.maximumEarsPermitted
        : 0;
    for (final runId in input.blockRunIds) {
      for (var station = 1; station <= 5; station++) {
        final order = _deterministicOrder(
          '${input.assessmentId}:$runId:$station',
        );
        final stationAllowance = remaining > 2 ? 2 : remaining;
        for (var index = 0; index < order.length; index++) {
          await database
              .into(database.earOpeningSelections)
              .insert(
                EarOpeningSelectionsCompanion.insert(
                  id: LocalId.generate(),
                  assessmentBlockRunId: runId,
                  stationNumber: station,
                  plantPosition: order[index],
                  selectionOrder: index + 1,
                  initiallySelected: Value(index < stationAllowance),
                  updatedAt: Value(DateTime.now().toUtc()),
                  syncState: const Value(DatabaseCodes.queued),
                ),
              );
        }
        remaining -= stationAllowance;
      }
    }
  }

  List<int> _deterministicOrder(String key) {
    final values = List<int>.generate(10, (index) => index + 1);
    var state = key.codeUnits.fold<int>(2166136261, (value, unit) {
      return ((value ^ unit) * 16777619) & 0x7fffffff;
    });
    for (var index = values.length - 1; index > 0; index--) {
      state = (1103515245 * state + 12345) & 0x7fffffff;
      final swapIndex = state % (index + 1);
      final current = values[index];
      values[index] = values[swapIndex];
      values[swapIndex] = current;
    }
    return values;
  }

  Future<void> _recordPlantAudit(
    PlantObservationRecord plant,
    String? actorPersonId,
    String protocol,
  ) => _mutations.record(
    entityType: 'plant_observations',
    entityId: plant.id,
    action: 'stage_observation_saved',
    actorPersonId: actorPersonId,
    after: {
      'station_id': plant.stationId,
      'plant_position': plant.sequenceNumber,
      'plant_status': plant.plantStatus,
      'protocol': protocol,
    },
  );

  String? _encodeTags(Set<String> tags) {
    if (tags.isEmpty) return null;
    final sorted = tags.toList()..sort();
    return jsonEncode(sorted);
  }

  void _validateReproductive(ReproductivePlantSave input) {
    _validateCommon(
      input.plantPosition,
      input.assessable,
      input.notAssessableReason,
      input.naturalEnemyQuickStatus,
    );
    if (!DatabaseCodes.reproductiveClassifications.contains(
      input.classification,
    )) {
      throw ArgumentError.value(input.classification, 'classification');
    }
    if (input.assessable &&
        !(input.tasselExamined &&
            input.earBaseExamined &&
            input.upperAxilExamined &&
            input.lowerAxilExamined)) {
      throw ArgumentError('All four VT-R2 target zones must be examined.');
    }
    final derivedPositive = input.larvaPresent || input.freshFeedingPresent;
    if (input.assessable &&
        derivedPositive !=
            (input.classification == DatabaseCodes.reproductiveInfested)) {
      throw ArgumentError(
        'VT-R2 classification must agree with larva and fresh-feeding evidence.',
      );
    }
    _validateLarva(input.larvaPresent, input.larvalSize);
  }

  void _validateExternalEar(EarExternalPlantSave input) {
    _validateCommon(
      input.plantPosition,
      input.externallyAssessable,
      input.notAssessableReason,
      input.naturalEnemyQuickStatus,
    );
    if (!DatabaseCodes.earExternalClassifications.contains(
      input.externalClassification,
    )) {
      throw ArgumentError.value(
        input.externalClassification,
        'externalClassification',
      );
    }
    if (input.externallyAssessable && input.earPresent != true) {
      throw ArgumentError('An assessable external ear must be present.');
    }
    if (input.externallyAssessable &&
        !(input.exteriorEarTipExamined && input.baseShankSilkAxilsExamined)) {
      throw ArgumentError('Complete both external-ear target checks.');
    }
    if (input.larvaPresent != null) {
      _validateLarva(input.larvaPresent!, input.larvalSize ?? 'none_seen');
    }
  }

  void _validateLateSetup(LateSeasonSetupInput input) {
    if (!DatabaseCodes.openingPermissions.contains(input.openingPermission)) {
      throw ArgumentError.value(input.openingPermission, 'openingPermission');
    }
    if (input.cropUse.trim().isEmpty ||
        input.earDesignationRule.trim().isEmpty) {
      throw ArgumentError('Crop use and designated-ear rule are required.');
    }
    if (input.openingPermission == DatabaseCodes.openingPermissionGranted) {
      if (input.maximumEarsPermitted <= 0 ||
          input.openingReason?.trim().isEmpty != false ||
          input.permissionGrantedBy?.trim().isEmpty != false) {
        throw ArgumentError(
          'Granted opening permission requires a positive maximum, reason, and grantor.',
        );
      }
    } else if (input.maximumEarsPermitted != 0) {
      throw ArgumentError(
        'Refused or unavailable permission requires zero ears.',
      );
    }
  }

  void _validateOpenedEar(OpenedEarSave input) {
    if (!DatabaseCodes.earInternalClassifications.contains(
      input.internalClassification,
    )) {
      throw ArgumentError.value(
        input.internalClassification,
        'internalClassification',
      );
    }
    if (input.totalKernelsCounted != null ||
        input.damagedKernelsCounted != null) {
      if (input.totalKernelsCounted == null ||
          input.damagedKernelsCounted == null ||
          input.totalKernelsCounted! <= 0 ||
          input.damagedKernelsCounted! < 0 ||
          input.damagedKernelsCounted! > input.totalKernelsCounted!) {
        throw ArgumentError('Kernel counts are incomplete or inconsistent.');
      }
    }
    if (input.earTipDamageLengthMm != null && input.earTipDamageLengthMm! < 0) {
      throw ArgumentError('Ear-tip damage length cannot be negative.');
    }
  }

  void _validateCommon(
    int position,
    bool assessable,
    String? notAssessableReason,
    String naturalEnemyQuickStatus,
  ) {
    if (position < 1 || position > 10) {
      throw ArgumentError.value(position, 'plantPosition', 'Must be 1-10');
    }
    if (!assessable && notAssessableReason?.trim().isEmpty != false) {
      throw ArgumentError('A non-assessable position requires a reason.');
    }
    if (!DatabaseCodes.naturalEnemyQuickStatuses.contains(
      naturalEnemyQuickStatus,
    )) {
      throw ArgumentError.value(
        naturalEnemyQuickStatus,
        'naturalEnemyQuickStatus',
      );
    }
  }

  void _validateLarva(bool present, String size) {
    if (!DatabaseCodes.larvalSizes.contains(size) ||
        (present && size == 'none_seen') ||
        (!present && size != 'none_seen')) {
      throw ArgumentError('Larval presence and size are inconsistent.');
    }
  }
}
