import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/local_id.dart';
import 'local_mutation_recorder.dart';

class CreatedFieldCycle {
  const CreatedFieldCycle({
    required this.field,
    required this.boundary,
    required this.cropCycle,
  });

  final FieldRecord field;
  final BoundaryRecord boundary;
  final CropCycleRecord cropCycle;
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

  Future<CreatedFieldCycle> createFieldWithBoundaryAndCycle({
    required String name,
    required String geometryGeojson,
    required double areaHectares,
    required String boundarySourceMethod,
    String? ownerPersonId,
    String? fieldCode,
    String? barangay,
    String? municipalityCity,
    String? province,
    String? locationDescription,
    String? varietyName,
    String? intendedUse,
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
    if (areaHectares <= 0) {
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
              locationDescription: Value(locationDescription),
              activeBoundaryVersionId: Value(boundaryId),
              deviceId: Value(deviceId),
            ),
          );

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
              intendedUse: Value(intendedUse),
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
          'boundary_version_id': boundaryId,
          'crop_cycle_id': cropCycleId,
        },
      );
    });

    final field = await (database.select(
      database.fields,
    )..where((row) => row.id.equals(fieldId))).getSingle();
    final boundary = await (database.select(
      database.fieldBoundaryVersions,
    )..where((row) => row.id.equals(boundaryId))).getSingle();
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
