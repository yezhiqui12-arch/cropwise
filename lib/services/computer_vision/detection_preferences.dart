import 'package:drift/drift.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/field_repository.dart';
import '../../models/automatic_screening.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../cloud/account_app_data_service.dart';

/// Default for new assessments; every assessment persists its own fixed value.
abstract final class DetectionPreferences {
  static const _storage = FlutterSecureStorage();
  static const _key = 'experimental_faw_highlighting_v1';
  static const _introductionKey = 'evidence_detection_introduction_v1';
  static final enabled = ValueNotifier<bool>(false);
  static Future<void>? _loading;
  static Future<void> load() => _loading ??= _read();
  static Future<void> _read() async {
    try {
      enabled.value = await _storage.read(key: _key) == 'true';
    } catch (_) {
      enabled.value = false;
    }
  }

  static Future<void> reload() => _read();

  /// The only initial-choice exception to the ongoing-assessment model lock.
  /// No plant may have been recorded or photographed anywhere in this assessment.
  static Future<bool> needsIntroduction(
    AppDatabase database,
    String assessmentId,
  ) async {
    await load();
    if (await FieldRepository(database).readPreferenceValue(_introductionKey) !=
        null) {
      return false;
    }
    final assessment =
        await (database.select(database.assessments)
              ..where((a) => a.id.equals(assessmentId) & a.deletedAt.isNull()))
            .getSingleOrNull();
    if (assessment == null || !_openStatuses.contains(assessment.status)) {
      return false;
    }
    final otherCompleted =
        await (database.select(database.assessments)..where(
              (a) =>
                  a.id.equals(assessmentId).not() &
                  a.status.equals(DatabaseCodes.completed) &
                  a.deletedAt.isNull(),
            ))
            .get();
    if (otherCompleted.isNotEmpty) return false;
    final used = await database
        .customSelect(
          '''SELECT 1 FROM plant_observations p
         JOIN stations s ON s.id = p.station_id
         JOIN assessment_block_runs b ON b.id = s.assessment_block_run_id
         WHERE b.assessment_id = ?
         UNION ALL
         SELECT 1 FROM planting_unit_observations p
         JOIN stations s ON s.id = p.station_id
         JOIN assessment_block_runs b ON b.id = s.assessment_block_run_id
         WHERE b.assessment_id = ?
         UNION ALL
         SELECT 1 FROM evidence_media m
         JOIN evidence_capture_sessions c ON c.id = m.capture_session_id
         WHERE c.assessment_id = ? AND c.scope_type IN ('plant', 'planting_unit')
         LIMIT 1''',
          variables: [
            Variable<String>(assessmentId),
            Variable<String>(assessmentId),
            Variable<String>(assessmentId),
          ],
        )
        .get();
    return used.isEmpty;
  }

  static Future<void> chooseInitialDetection(
    bool value, {
    required AppDatabase database,
    required String assessmentId,
  }) async {
    await database.transaction(() async {
      if (!await needsIntroduction(database, assessmentId)) {
        throw StateError('The initial model choice is no longer available.');
      }
      // Keep any other unfinished assessment's configuration unchanged.
      final others =
          await (database.select(database.assessments)..where(
                (a) =>
                    a.id.equals(assessmentId).not() &
                    a.deletedAt.isNull() &
                    a.status.isIn(_openStatuses),
              ))
              .get();
      for (final other in others) {
        await forAssessment(database, other.id);
      }
      await _storage.write(key: _key, value: value.toString());
      final preferences = FieldRepository(database);
      await preferences.savePreferenceValue(
        'assessment_highlighting_v1:$assessmentId',
        value.toString(),
      );
      await preferences.savePreferenceValue(_introductionKey, value.toString());
    });
    enabled.value = value;
    AccountAppDataEvents.changed();
  }

  static const _openStatuses = [
    DatabaseCodes.draft,
    DatabaseCodes.safetyBlocked,
    DatabaseCodes.inProgress,
    DatabaseCodes.incomplete,
  ];

  // Use the latest assessment in the selected field, not drafts from other fields.
  static Selectable<QueryRow> _selectedAssessment(
    AppDatabase database,
  ) => database.customSelect(
    "SELECT a.id, a.status FROM assessments a "
    "JOIN crop_cycles c ON c.id = a.crop_cycle_id "
    "JOIN app_preferences p ON p.preference_key = 'active_field_id' AND p.preference_value = c.field_id "
    "WHERE a.deleted_at IS NULL AND c.deleted_at IS NULL "
    "ORDER BY a.created_at DESC, a.id DESC LIMIT 1",
    readsFrom: {
      database.assessments,
      database.cropCycles,
      database.appPreferences,
    },
  );

  static Stream<({int count, bool? enabled})> watchLock(AppDatabase database) {
    return _selectedAssessment(database).watchSingleOrNull().asyncMap((
      row,
    ) async {
      final locked =
          row != null && _openStatuses.contains(row.read<String>('status'));
      return (
        count: locked ? 1 : 0,
        enabled: locked
            ? await forAssessment(database, row.read<String>('id'))
            : null,
      );
    });
  }

  static Future<bool> forAssessment(
    AppDatabase database,
    String assessmentId,
  ) async {
    await load();
    return database.transaction(() async {
      final preferences = FieldRepository(database);
      final key = 'assessment_highlighting_v1:$assessmentId';
      final stored = await preferences.readPreferenceValue(key);
      if (stored != null) return stored == 'true';
      // Recover the original configuration for assessments started before locking.
      final blocks =
          await (database.select(database.assessmentBlockRuns)..where(
                (b) =>
                    b.assessmentId.equals(assessmentId) & b.deletedAt.isNull(),
              ))
              .get();
      final stations = blocks.isEmpty
          ? <StationRecord>[]
          : await (database.select(database.stations)..where(
                  (s) =>
                      s.assessmentBlockRunId.isIn(blocks.map((b) => b.id)) &
                      s.deletedAt.isNull(),
                ))
                .get();
      bool? original;
      if (stations.isNotEmpty) {
        final plants =
            await (database.select(database.plantObservations)
                  ..where(
                    (p) =>
                        p.stationId.isIn(stations.map((s) => s.id)) &
                        p.deletedAt.isNull(),
                  )
                  ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
                .get();
        for (final plant in plants) {
          final screen = AutomaticScreening.parse(plant.wholePlantContextNote);
          if (screen == null) continue;
          final model = screen.result.modelName;
          if (model.contains('overlay=true')) {
            original = true;
            break;
          }
          if (model.contains('overlay=false')) {
            original = false;
            break;
          }
        }
      }
      final value = original ?? enabled.value;
      await preferences.savePreferenceValue(key, value.toString());
      return value;
    });
  }

  static Future<void> setEnabled(
    bool value, {
    required AppDatabase database,
  }) async {
    await load();
    await database.transaction(() async {
      final selected = await _selectedAssessment(database).getSingleOrNull();
      if (selected != null &&
          _openStatuses.contains(selected.read<String>('status'))) {
        throw StateError(
          'Finish this field’s active assessment before changing models.',
        );
      }
      // Preserve configurations for older unfinished assessments before changing
      // the default used by new assessments in another field.
      final unfinished =
          await (database.select(database.assessments)..where(
                (a) => a.deletedAt.isNull() & a.status.isIn(_openStatuses),
              ))
              .get();
      for (final assessment in unfinished) {
        await forAssessment(database, assessment.id);
      }
      await _storage.write(key: _key, value: value.toString());
      AccountAppDataEvents.changed();
      enabled.value = value;
    });
  }
}
