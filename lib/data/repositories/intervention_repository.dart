import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/local_id.dart';
import 'local_mutation_recorder.dart';

class InterventionRepository {
  InterventionRepository(this.database)
    : _mutations = LocalMutationRecorder(database);

  final AppDatabase database;
  final LocalMutationRecorder _mutations;

  Future<InterventionRecord> create({
    required String cropCycleId,
    required String interventionType,
    String? statedPurpose,
    String? targetPestOrCondition,
    DateTime? occurredStartAt,
    DateTime? occurredEndAt,
    String timePrecision = 'unknown',
    String? applicationMethod,
    String? applicatorPersonId,
    String? adviserPersonId,
    String? reporterPersonId,
    String? weatherDescription,
    String? rainfallAfterDescription,
    String? ppeReported,
    String? notes,
    String? deviceId,
  }) async {
    final id = LocalId.generate();
    await database.transaction(() async {
      await database
          .into(database.interventions)
          .insert(
            InterventionsCompanion.insert(
              id: id,
              cropCycleId: cropCycleId,
              interventionType: interventionType,
              statedPurpose: Value(statedPurpose),
              targetPestOrCondition: Value(targetPestOrCondition),
              occurredStartAt: Value(occurredStartAt?.toUtc()),
              occurredEndAt: Value(occurredEndAt?.toUtc()),
              timePrecision: Value(timePrecision),
              applicationMethod: Value(applicationMethod),
              applicatorPersonId: Value(applicatorPersonId),
              adviserPersonId: Value(adviserPersonId),
              reporterPersonId: Value(reporterPersonId),
              weatherDescription: Value(weatherDescription),
              rainfallAfterDescription: Value(rainfallAfterDescription),
              ppeReported: Value(ppeReported),
              notes: Value(notes),
              deviceId: Value(deviceId),
            ),
          );
      await _mutations.record(
        entityType: 'interventions',
        entityId: id,
        action: 'create',
        actorPersonId: reporterPersonId,
        deviceId: deviceId,
        after: {
          'crop_cycle_id': cropCycleId,
          'intervention_type': interventionType,
          'occurred_start_at': occurredStartAt?.toUtc().toIso8601String(),
        },
      );
    });
    return (database.select(
      database.interventions,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<InterventionInputRecord> addReportedInput({
    required String interventionId,
    String? productName,
    String? activeIngredientOrAgent,
    String? registrationNumber,
    String? reportedCrop,
    String? reportedTarget,
    String? reportedRate,
    String? reiText,
    String? phiText,
    String provenanceState = 'reported',
    String? actorPersonId,
    String? deviceId,
  }) async {
    final id = LocalId.generate();
    await database.transaction(() async {
      await database
          .into(database.interventionInputs)
          .insert(
            InterventionInputsCompanion.insert(
              id: id,
              interventionId: interventionId,
              reportedProductName: Value(productName),
              reportedActiveIngredientOrAgent: Value(activeIngredientOrAgent),
              reportedRegistrationNumber: Value(registrationNumber),
              reportedCrop: Value(reportedCrop),
              reportedTarget: Value(reportedTarget),
              reportedRateText: Value(reportedRate),
              reiText: Value(reiText),
              phiText: Value(phiText),
              provenanceState: Value(provenanceState),
              deviceId: Value(deviceId),
            ),
          );
      await _mutations.record(
        entityType: 'intervention_inputs',
        entityId: id,
        action: 'create',
        actorPersonId: actorPersonId,
        deviceId: deviceId,
        after: {
          'intervention_id': interventionId,
          'reported_product_name': productName,
          'reported_active_ingredient_or_agent': activeIngredientOrAgent,
        },
      );
    });
    return (database.select(
      database.interventionInputs,
    )..where((row) => row.id.equals(id))).getSingle();
  }
}
