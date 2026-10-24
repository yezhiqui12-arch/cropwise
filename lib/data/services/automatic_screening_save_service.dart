import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';
import '../repositories/evidence_capture_repository.dart';
import '../repositories/local_mutation_recorder.dart';
import '../../models/automatic_screening.dart';

class AutomaticScreeningSaveService {
  AutomaticScreeningSaveService(this.database);
  final AppDatabase database;

  Future<void> save({
    required String stationId,
    required int position,
    required String growthStage,
    required AutomaticScreening screening,
    required String actorId,
    String? sessionId,
    String? unitId,
    required String primaryView,
  }) => database.transaction(() async {
    if (sessionId != null && screening.evidenceSignature != null) {
      final media =
          await (database.select(database.evidenceMedia)..where(
                (m) =>
                    m.captureSessionId.equals(sessionId) &
                    m.deletedAt.isNull() &
                    m.storageState.equals(DatabaseCodes.evidenceStorageReady),
              ))
              .get();
      final checksums = media.map((m) => m.sha256Checksum).toList()..sort();
      if (!screening.matchesEvidence(
        checksums.join(':'),
        hasEvidence: media.isNotEmpty,
        allowLegacy: false,
      )) {
        throw StateError('The plant photos changed. Retry screening.');
      }
    }
    final existing =
        await (database.select(database.plantObservations)..where(
              (p) =>
                  p.stationId.equals(stationId) &
                  p.sequenceNumber.equals(position),
            ))
            .getSingleOrNull();
    final id = existing?.id ?? LocalId.generate();
    final now = DateTime.now().toUtc();
    final existingScreen = AutomaticScreening.parse(
      existing?.wholePlantContextNote,
    );
    final existingMetadata = existingScreen == null
        ? const <String, dynamic>{}
        : jsonDecode(existing!.wholePlantContextNote!) as Map<String, dynamic>;
    final preserveLegacy =
        existing != null &&
        (existingScreen == null ||
            existingMetadata['preserve_legacy_observations'] == true ||
            existingMetadata.containsKey('previous_context_note'));
    if (preserveLegacy) {
      // Store the actual rerun without rewriting historical biological fields.
      // Otherwise the UI cache has CV results that the saved plant never gets.
      await (database.update(
        database.plantObservations,
      )..where((p) => p.id.equals(id))).write(
        PlantObservationsCompanion(
          wholePlantContextNote: Value(
            jsonEncode({
              ...jsonDecode(screening.encode()) as Map<String, dynamic>,
              'preserve_legacy_observations': true,
              if (existingScreen == null &&
                  existing.wholePlantContextNote != null)
                'previous_context_note': existing.wholePlantContextNote,
              if (existingMetadata.containsKey('previous_context_note'))
                'previous_context_note':
                    existingMetadata['previous_context_note'],
            }),
          ),
          updatedAt: Value(now),
          syncState: const Value(DatabaseCodes.queued),
        ),
      );
    } else {
      await database
          .into(database.plantObservations)
          .insertOnConflictUpdate(
            PlantObservationsCompanion.insert(
              id: id,
              stationId: stationId,
              sequenceNumber: position,
              plantStatus: screening.status,
              assessable: Value(screening.available),
              notAssessableReason: Value(
                screening.available ? null : 'Screening unavailable',
              ),
              sourcePlantingUnitObservationId: Value(unitId),
              naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNotCollected,
              wholePlantContextNote: Value(screening.encode()),
              capturedAt: Value(now),
              updatedAt: Value(now),
              syncState: const Value(DatabaseCodes.queued),
            ),
          );
    }
    // Empty stage containers retain compatibility, not invented biological answers.
    if (growthStage == 'vt_r2') {
      await database
          .into(database.reproductiveObservations)
          .insert(
            ReproductiveObservationsCompanion.insert(plantObservationId: id),
            mode: InsertMode.insertOrIgnore,
          );
    } else if (growthStage == 'r3_r6') {
      await database
          .into(database.earObservations)
          .insert(
            EarObservationsCompanion.insert(
              id: existing == null ? LocalId.generate() : 'screen_ear_$id',
              plantObservationId: id,
              externallyAssessable: const Value(false),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await database
          .into(database.vegetativeObservations)
          .insert(
            VegetativeObservationsCompanion.insert(plantObservationId: id),
            mode: InsertMode.insertOrIgnore,
          );
    }
    if (sessionId != null) {
      final evidence = EvidenceCaptureRepository(database);
      await evidence.attachPlantEvidenceInCurrentTransaction(
        sessionId: sessionId,
        stationId: stationId,
        plantPosition: position,
        plantObservationId: id,
        sourcePlantingUnitObservationId: unitId,
        requiredViewTypes: {primaryView},
        actorPersonId: actorId,
        pilotActiveDurationMs: 0,
        manualFormUsed: false,
      );
      await evidence.recordPlantEvidenceReview(
        bundle: await evidence.loadBundle(sessionId),
        status: DatabaseCodes.evidenceReviewSufficient,
        actorPersonId: actorId,
      );
    }
    await LocalMutationRecorder(database).record(
      entityType: 'plant_observations',
      entityId: id,
      action: 'automatic_damage_screen_saved',
      actorPersonId: actorId,
      after: {
        'plant_status': screening.status,
        'screening': screening.result.toJson(),
      },
    );
  });
}
