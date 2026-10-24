import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';
import '../../services/assessment_area_policy.dart';
import 'local_mutation_recorder.dart';

class CreatedFieldCycle {
  const CreatedFieldCycle({
    required this.field,
    required this.boundary,
    required this.cropCycle,
  });

  final FieldRecord field;
  final BoundaryRecord? boundary;
  final CropCycleRecord cropCycle;
}

class ExpiredFieldDeletionCandidate {
  const ExpiredFieldDeletionCandidate({
    required this.field,
    required this.media,
  });

  final FieldRecord field;
  final List<EvidenceMediaRecord> media;
}

class FieldWorkspaceRecord {
  const FieldWorkspaceRecord({
    required this.field,
    this.boundary,
    this.cropCycle,
  });

  final FieldRecord field;
  final BoundaryRecord? boundary;
  final CropCycleRecord? cropCycle;

  bool get hasApproximateOutline =>
      boundary?.confirmationStatus == 'user_confirmed';

  bool get hasEntranceLocation =>
      boundary?.confirmationStatus == 'location_only' &&
      boundary?.centroidLatitude != null &&
      boundary?.centroidLongitude != null;

  FieldSpatialState get spatialState {
    if (hasApproximateOutline) return FieldSpatialState.approximateOutline;
    if (hasEntranceLocation) return FieldSpatialState.entranceLocation;
    return FieldSpatialState.reportedAreaOnly;
  }
}

enum FieldSpatialState {
  reportedAreaOnly,
  entranceLocation,
  approximateOutline,
}

class FieldRepository {
  FieldRepository(this.database) : _mutations = LocalMutationRecorder(database);

  final AppDatabase database;
  final LocalMutationRecorder _mutations;

  static const _activeFieldPreferenceKey = 'active_field_id';

  Future<String?> readPreferredFieldId() async {
    final preference =
        await (database.select(database.appPreferences)..where(
              (row) => row.preferenceKey.equals(_activeFieldPreferenceKey),
            ))
            .getSingleOrNull();
    return preference?.preferenceValue;
  }

  Future<void> savePreferredFieldId(String fieldId) {
    return database
        .into(database.appPreferences)
        .insertOnConflictUpdate(
          AppPreferencesCompanion.insert(
            preferenceKey: _activeFieldPreferenceKey,
            preferenceValue: fieldId,
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<void> clearPreferredFieldId() {
    return (database.delete(database.appPreferences)
          ..where((row) => row.preferenceKey.equals(_activeFieldPreferenceKey)))
        .go();
  }

  Future<String?> readPreferenceValue(String key) async {
    final preference = await (database.select(
      database.appPreferences,
    )..where((row) => row.preferenceKey.equals(key))).getSingleOrNull();
    return preference?.preferenceValue;
  }

  Future<void> savePreferenceValue(String key, String value) {
    return database
        .into(database.appPreferences)
        .insertOnConflictUpdate(
          AppPreferencesCompanion.insert(
            preferenceKey: key,
            preferenceValue: value,
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Stream<List<FieldRecord>> watchActiveFields() {
    final query = database.select(database.fields)
      ..where((row) => row.isArchived.equals(false) & row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    return query.watch();
  }

  Stream<List<FieldWorkspaceRecord>> watchFieldWorkspaces() {
    final query =
        database.select(database.fields).join([
            leftOuterJoin(
              database.fieldBoundaryVersions,
              database.fieldBoundaryVersions.id.equalsExp(
                database.fields.activeBoundaryVersionId,
              ),
            ),
            leftOuterJoin(
              database.cropCycles,
              database.cropCycles.fieldId.equalsExp(database.fields.id) &
                  database.cropCycles.status.equals('active'),
            ),
          ])
          ..where(
            database.fields.isArchived.equals(false) &
                database.fields.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm.asc(database.fields.name)]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => FieldWorkspaceRecord(
              field: row.readTable(database.fields),
              boundary: row.readTableOrNull(database.fieldBoundaryVersions),
              cropCycle: row.readTableOrNull(database.cropCycles),
            ),
          )
          .toList(growable: false),
    );
  }

  Stream<List<FieldWorkspaceRecord>> watchArchivedFieldWorkspaces() {
    final query =
        database.select(database.fields).join([
            leftOuterJoin(
              database.fieldBoundaryVersions,
              database.fieldBoundaryVersions.id.equalsExp(
                database.fields.activeBoundaryVersionId,
              ),
            ),
            leftOuterJoin(
              database.cropCycles,
              database.cropCycles.fieldId.equalsExp(database.fields.id) &
                  database.cropCycles.status.equals('active'),
            ),
          ])
          ..where(
            database.fields.isArchived.equals(true) &
                database.fields.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm.asc(database.fields.name)]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => FieldWorkspaceRecord(
              field: row.readTable(database.fields),
              boundary: row.readTableOrNull(database.fieldBoundaryVersions),
              cropCycle: row.readTableOrNull(database.cropCycles),
            ),
          )
          .toList(growable: false),
    );
  }

  Stream<List<FieldWorkspaceRecord>> watchRecentlyDeletedFieldWorkspaces() =>
      watchArchivedFieldWorkspaces();

  Future<void> renameField({
    required String fieldId,
    required String name,
    String? actorPersonId,
    String? deviceId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty');
    }
    await database.transaction(() async {
      final before = await (database.select(
        database.fields,
      )..where((row) => row.id.equals(fieldId))).getSingle();
      await (database.update(
        database.fields,
      )..where((row) => row.id.equals(fieldId))).write(
        FieldsCompanion(
          name: Value(trimmed),
          updatedAt: Value(DateTime.now().toUtc()),
          syncState: const Value('queued'),
        ),
      );
      await _mutations.record(
        entityType: 'fields',
        entityId: fieldId,
        action: 'rename',
        actorPersonId: actorPersonId,
        deviceId: deviceId,
        before: {'name': before.name},
        after: {'name': trimmed},
      );
    });
  }

  Future<void> updateFieldDetails({
    required String fieldId,
    required String name,
    String? barangay,
    String? varietyName,
    DateTime? plantingDate,
    String? actorPersonId,
    String? deviceId,
  }) async {
    final previous = await (database.select(
      database.fields,
    )..where((row) => row.id.equals(fieldId))).getSingle();
    final cycle =
        await (database.select(database.cropCycles)..where(
              (row) =>
                  row.fieldId.equals(fieldId) & row.status.equals('active'),
            ))
            .getSingleOrNull();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError.value(name, 'name');
    final updatedAt = DateTime.now().toUtc();

    await database.transaction(() async {
      await (database.update(
        database.fields,
      )..where((row) => row.id.equals(fieldId))).write(
        FieldsCompanion(
          name: Value(trimmedName),
          barangay: Value(_trimmedOrNull(barangay)),
          updatedAt: Value(updatedAt),
          syncState: const Value('queued'),
          deviceId: Value(deviceId),
        ),
      );
      if (cycle != null) {
        await (database.update(
          database.cropCycles,
        )..where((row) => row.id.equals(cycle.id))).write(
          CropCyclesCompanion(
            varietyName: Value(_trimmedOrNull(varietyName)),
            plantingDate: Value(plantingDate?.toUtc()),
            plantingDatePrecision: Value(
              plantingDate == null ? 'unknown' : 'exact_day',
            ),
            updatedAt: Value(updatedAt),
            syncState: const Value('queued'),
            deviceId: Value(deviceId),
          ),
        );
      }
      await _mutations.record(
        entityType: 'fields',
        entityId: fieldId,
        action: 'update_details',
        actorPersonId: actorPersonId,
        deviceId: deviceId,
        before: {'name': previous.name, 'barangay': previous.barangay},
        after: {'name': trimmedName, 'barangay': _trimmedOrNull(barangay)},
      );
    });
  }

  String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setFieldArchived({
    required String fieldId,
    required bool archived,
    String? actorPersonId,
    String? deviceId,
  }) async {
    await database.transaction(() async {
      final before = await (database.select(
        database.fields,
      )..where((row) => row.id.equals(fieldId))).getSingle();
      await (database.update(
        database.fields,
      )..where((row) => row.id.equals(fieldId))).write(
        FieldsCompanion(
          isArchived: Value(archived),
          updatedAt: Value(DateTime.now().toUtc()),
          syncState: const Value('queued'),
        ),
      );
      await _mutations.record(
        entityType: 'fields',
        entityId: fieldId,
        action: archived ? 'delete_requested' : 'restore',
        actorPersonId: actorPersonId,
        deviceId: deviceId,
        before: {'is_archived': before.isArchived},
        after: {
          'is_archived': archived,
          if (archived)
            'scheduled_permanent_deletion_at': DateTime.now()
                .toUtc()
                .add(const Duration(days: 30))
                .toIso8601String(),
        },
      );
    });
  }

  Future<List<ExpiredFieldDeletionCandidate>> expiredDeletionCandidates(
    DateTime nowUtc,
  ) async {
    final cutoff = nowUtc.toUtc().subtract(const Duration(days: 30));
    final fields =
        await (database.select(database.fields)..where(
              (row) =>
                  row.isArchived.equals(true) &
                  row.deletedAt.isNull() &
                  row.updatedAt.isSmallerOrEqualValue(cutoff),
            ))
            .get();
    final result = <ExpiredFieldDeletionCandidate>[];
    for (final field in fields) {
      final cycles = await (database.select(
        database.cropCycles,
      )..where((row) => row.fieldId.equals(field.id))).get();
      final cycleIds = cycles.map((record) => record.id).toList();
      final assessments = cycleIds.isEmpty
          ? const <AssessmentRecord>[]
          : await (database.select(
              database.assessments,
            )..where((row) => row.cropCycleId.isIn(cycleIds))).get();
      final assessmentIds = assessments.map((record) => record.id).toList();
      final media = assessmentIds.isEmpty
          ? const <EvidenceMediaRecord>[]
          : await (database.select(database.evidenceMedia)..where(
                  (row) =>
                      row.assessmentId.isIn(assessmentIds) &
                      row.deletedAt.isNull(),
                ))
                .get();
      result.add(ExpiredFieldDeletionCandidate(field: field, media: media));
    }
    return result;
  }

  Future<void> finalizeExpiredDeletion({
    required ExpiredFieldDeletionCandidate candidate,
    required DateTime deletedAtUtc,
  }) async {
    final deletedAt = deletedAtUtc.toUtc();
    await database.transaction(() async {
      final current = await (database.select(
        database.fields,
      )..where((row) => row.id.equals(candidate.field.id))).getSingle();
      if (!current.isArchived || current.deletedAt != null) return;
      if (current.updatedAt.isAfter(
        deletedAt.subtract(const Duration(days: 30)),
      )) {
        return;
      }
      final mediaIds = candidate.media.map((record) => record.id).toList();
      if (mediaIds.isNotEmpty) {
        await (database.update(
          database.evidenceMedia,
        )..where((row) => row.id.isIn(mediaIds))).write(
          EvidenceMediaCompanion(
            deletedAt: Value(deletedAt),
            storageState: const Value(DatabaseCodes.evidenceStorageDeleted),
            updatedAt: Value(deletedAt),
            syncState: const Value('queued'),
          ),
        );
      }
      await (database.update(
        database.fields,
      )..where((row) => row.id.equals(current.id))).write(
        FieldsCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(deletedAt),
          syncState: const Value('queued'),
        ),
      );
      await _mutations.record(
        entityType: 'fields',
        entityId: current.id,
        action: 'permanently_deleted',
        before: {'is_archived': true, 'deleted_at': null},
        after: {
          'deleted_at': deletedAt.toIso8601String(),
          'evidence_files_removed': mediaIds.length,
          'metadata_tombstone_retained': true,
        },
      );
    });
  }

  Future<CreatedFieldCycle> createFieldWithBoundaryAndCycle({
    required String name,
    required String geometryGeojson,
    double? areaHectares,
    required String boundarySourceMethod,
    String? ownerPersonId,
    String? fieldCode,
    String? barangay,
    String? municipalityCity,
    String? province,
    String? varietyName,
    DateTime? plantingDate,
    String plantingDatePrecision = 'unknown',
    String? waterRegime,
    String boundaryConfirmationStatus = 'user_confirmed',
    double? centroidLatitude,
    double? centroidLongitude,
    double? averageAccuracyM,
    double? worstAccuracyM,
    String? confidenceCode,
    String? boundaryNotes,
    String? deviceId,
    String? actorPersonId,
  }) async {
    if (areaHectares != null && (!areaHectares.isFinite || areaHectares <= 0)) {
      throw ArgumentError.value(
        areaHectares,
        'areaHectares',
        'Must be positive',
      );
    }

    if ((centroidLatitude == null) != (centroidLongitude == null)) {
      throw ArgumentError(
        'centroidLatitude and centroidLongitude must be supplied together.',
      );
    }

    final fieldId = LocalId.generate();
    final boundaryId = LocalId.generate();
    final cropCycleId = LocalId.generate();

    await database.transaction(() async {
      final outlineIsConfirmed = boundaryConfirmationStatus == 'user_confirmed';
      await database
          .into(database.fields)
          .insert(
            FieldsCompanion.insert(
              id: fieldId,
              name: name,
              ownerPersonId: Value(ownerPersonId),
              fieldCode: Value(fieldCode),
              barangay: Value(barangay),
              municipalityCity: Value(municipalityCity),
              province: Value(province),
              activeBoundaryVersionId: Value(
                areaHectares == null ? null : boundaryId,
              ),
              deviceId: Value(deviceId),
            ),
          );

      if (areaHectares != null)
        await database
            .into(database.fieldBoundaryVersions)
            .insert(
              FieldBoundaryVersionsCompanion.insert(
                id: boundaryId,
                fieldId: fieldId,
                versionNumber: 1,
                geometryGeojson: geometryGeojson,
                sourceMethod: boundarySourceMethod,
                areaHectares: areaHectares,
                centroidLatitude: Value(centroidLatitude),
                centroidLongitude: Value(centroidLongitude),
                averageAccuracyM: Value(averageAccuracyM),
                worstAccuracyM: Value(worstAccuracyM),
                confidenceCode: Value(confidenceCode),
                confirmationStatus: Value(boundaryConfirmationStatus),
                confirmedByPersonId: Value(
                  outlineIsConfirmed ? actorPersonId : null,
                ),
                confirmedAt: Value(
                  outlineIsConfirmed ? DateTime.now().toUtc() : null,
                ),
                notes: Value(boundaryNotes),
                deviceId: Value(deviceId),
              ),
            );

      await database
          .into(database.cropCycles)
          .insert(
            CropCyclesCompanion.insert(
              id: cropCycleId,
              fieldId: fieldId,
              varietyName: Value(varietyName),
              plantingDate: Value(plantingDate?.toUtc()),
              plantingDatePrecision: Value(plantingDatePrecision),
              waterRegime: Value(waterRegime),
              deviceId: Value(deviceId),
            ),
          );

      await _mutations.record(
        entityType: 'fields',
        entityId: fieldId,
        action: 'create',
        actorPersonId: actorPersonId,
        deviceId: deviceId,
        after: {
          'name': name,
          'area_hectares': areaHectares,
          'boundary_version_id': areaHectares == null ? null : boundaryId,
          'crop_cycle_id': cropCycleId,
        },
      );
    });

    final field = await (database.select(
      database.fields,
    )..where((row) => row.id.equals(fieldId))).getSingle();
    final boundary = await (database.select(
      database.fieldBoundaryVersions,
    )..where((row) => row.id.equals(boundaryId))).getSingleOrNull();
    final cycle = await (database.select(
      database.cropCycles,
    )..where((row) => row.id.equals(cropCycleId))).getSingle();
    return CreatedFieldCycle(
      field: field,
      boundary: boundary,
      cropCycle: cycle,
    );
  }

  Future<BoundaryRecord> addBoundaryVersion({
    required String fieldId,
    required String geometryGeojson,
    required double areaHectares,
    required String sourceMethod,
    double? centroidLatitude,
    double? centroidLongitude,
    String? notes,
    double? averageAccuracyM,
    double? worstAccuracyM,
    String? confidenceCode,
    String confirmationStatus = 'user_confirmed',
    String? actorPersonId,
    String? deviceId,
  }) async {
    if (areaHectares <= 0) {
      throw ArgumentError.value(
        areaHectares,
        'areaHectares',
        'Must be positive',
      );
    }

    final maxVersion = database.fieldBoundaryVersions.versionNumber.max();
    final versionQuery = database.selectOnly(database.fieldBoundaryVersions)
      ..addColumns([maxVersion])
      ..where(database.fieldBoundaryVersions.fieldId.equals(fieldId));
    final currentMax = (await versionQuery.getSingle()).read(maxVersion) ?? 0;
    final boundaryId = LocalId.generate();
    final outlineIsConfirmed = confirmationStatus == 'user_confirmed';

    await database.transaction(() async {
      await database
          .into(database.fieldBoundaryVersions)
          .insert(
            FieldBoundaryVersionsCompanion.insert(
              id: boundaryId,
              fieldId: fieldId,
              versionNumber: currentMax + 1,
              geometryGeojson: geometryGeojson,
              sourceMethod: sourceMethod,
              areaHectares: areaHectares,
              centroidLatitude: Value(centroidLatitude),
              centroidLongitude: Value(centroidLongitude),
              averageAccuracyM: Value(averageAccuracyM),
              worstAccuracyM: Value(worstAccuracyM),
              confidenceCode: Value(confidenceCode),
              confirmationStatus: Value(confirmationStatus),
              confirmedByPersonId: Value(
                outlineIsConfirmed ? actorPersonId : null,
              ),
              confirmedAt: Value(
                outlineIsConfirmed ? DateTime.now().toUtc() : null,
              ),
              notes: Value(notes),
              deviceId: Value(deviceId),
            ),
          );
      await (database.update(
        database.fields,
      )..where((row) => row.id.equals(fieldId))).write(
        FieldsCompanion(
          activeBoundaryVersionId: Value(boundaryId),
          updatedAt: Value(DateTime.now().toUtc()),
          syncState: const Value('queued'),
        ),
      );
      await _mutations.record(
        entityType: 'field_boundary_versions',
        entityId: boundaryId,
        action: 'create',
        actorPersonId: actorPersonId,
        deviceId: deviceId,
        after: {
          'field_id': fieldId,
          'version_number': currentMax + 1,
          'area_hectares': areaHectares,
        },
      );
    });

    return (database.select(
      database.fieldBoundaryVersions,
    )..where((row) => row.id.equals(boundaryId))).getSingle();
  }

  Future<FieldBlockRecord> addBlock({
    required String cropCycleId,
    required String boundaryVersionId,
    required int blockNumber,
    required String geometryGeojson,
    required double areaHectares,
    String? separationReason,
    bool isProvisional = true,
    String? actorPersonId,
    String? deviceId,
  }) async {
    if (!AssessmentAreaPolicy.isValidBlockArea(areaHectares)) {
      throw ArgumentError.value(
        areaHectares,
        'areaHectares',
        'Each assessment block must be greater than zero and no more than '
            '${AssessmentAreaPolicy.maxBlockAreaHectares.toStringAsFixed(0)} hectare.',
      );
    }
    if (blockNumber < 1 ||
        blockNumber >
            AssessmentAreaPolicy.requiredBlockCount(
              AssessmentAreaPolicy.maxAssessmentAreaHectares,
            )) {
      throw ArgumentError.value(
        blockNumber,
        'blockNumber',
        'Outside the supported assessment block range.',
      );
    }
    final id = LocalId.generate();
    await database.transaction(() async {
      await database
          .into(database.fieldBlocks)
          .insert(
            FieldBlocksCompanion.insert(
              id: id,
              cropCycleId: cropCycleId,
              boundaryVersionId: boundaryVersionId,
              blockNumber: blockNumber,
              geometryGeojson: geometryGeojson,
              areaHectares: areaHectares,
              separationReason: Value(separationReason),
              isProvisional: Value(isProvisional),
              deviceId: Value(deviceId),
            ),
          );
      await _mutations.record(
        entityType: 'field_blocks',
        entityId: id,
        action: 'create',
        actorPersonId: actorPersonId,
        deviceId: deviceId,
        after: {
          'crop_cycle_id': cropCycleId,
          'block_number': blockNumber,
          'area_hectares': areaHectares,
        },
      );
    });
    return (database.select(
      database.fieldBlocks,
    )..where((row) => row.id.equals(id))).getSingle();
  }
}
