import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/app_database.dart';
import '../../models/da_monitoring.dart';
import '../../services/cloud/account_app_data_service.dart';
import 'field_repository.dart';
import 'local_mutation_recorder.dart';

/// Private assessment metadata, included in the existing SQLite account backup.
class DaMonitoringRepository {
  const DaMonitoringRepository(this.database);
  final AppDatabase database;
  String key(String assessmentId) => 'da_monitoring_v1_$assessmentId';
  Future<DaMonitoringRecord> load(String id) async => DaMonitoringRecord.parse(
    await FieldRepository(database).readPreferenceValue(key(id)),
  );
  Future<Map<String, dynamic>> loadProfile(String cycleId) async =>
      DaMonitoringRecord.parse(
        await FieldRepository(
          database,
        ).readPreferenceValue('da_field_profile_v1_$cycleId'),
      ).fields;
  Future<void> saveProfile(String cycleId, Map<String, dynamic> fields) async {
    final profile = Map<String, dynamic>.from(fields)
      ..remove('week')
      ..remove('remarks')
      ..remove('collector');
    await FieldRepository(database).savePreferenceValue(
      'da_field_profile_v1_$cycleId',
      jsonEncode({'fields': profile}),
    );
    AccountAppDataEvents.changed();
  }

  Future<void> _save(
    String id,
    String action,
    void Function(Map<String, dynamic>) update,
  ) async {
    await database.transaction(() async {
      final current = await load(id);
      final before =
          jsonDecode(jsonEncode(current.data)) as Map<String, dynamic>;
      update(current.data);
      current.data['version'] = 1;
      await database
          .into(database.appPreferences)
          .insertOnConflictUpdate(
            AppPreferencesCompanion.insert(
              preferenceKey: key(id),
              preferenceValue: jsonEncode(current.data),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      await LocalMutationRecorder(database).record(
        entityType: 'da_monitoring',
        entityId: id,
        action: action,
        before: before,
        after: current.data,
        queueForSync: false,
      );
    });
    AccountAppDataEvents.changed();
  }

  Future<void> saveFields(String id, Map<String, dynamic> fields) =>
      _save(id, 'report_details_saved', (data) => data['fields'] = fields);
  Future<void> saveEnemies(String id, String block, List<String> selected) {
    if (selected.isEmpty ||
        selected.any((s) => !daEnemyLabels.containsKey(s)) ||
        selected.length != selected.toSet().length ||
        selected.length > 1 &&
            selected.any(
              (s) => ['none', 'unknown', 'not_recorded'].contains(s),
            )) {
      throw ArgumentError(
        'Choose natural enemies or one unavailable/none option.',
      );
    }
    return _save(id, 'natural_enemies_confirmed', (data) {
      final blocks = Map<String, dynamic>.from(data['blocks'] as Map? ?? {});
      blocks[block] = {
        'natural_enemies': selected,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      };
      data['blocks'] = blocks;
    });
  }

  Future<void> saveCorrection(
    String id,
    String block,
    int number,
    String signature,
    Map<String, bool?> overrides,
  ) {
    if (number < 1 ||
        number > 20 ||
        overrides.keys.any((k) => !daSignLabels.containsKey(k)))
      throw ArgumentError('Invalid plant correction');
    return _save(id, 'plant_report_corrected', (data) {
      final plants = Map<String, dynamic>.from(data['plants'] as Map? ?? {});
      final values = {
        for (final e in overrides.entries)
          if (e.value != null) e.key: e.value,
      };
      if (values.isEmpty) {
        plants.remove('$block:$number');
      } else {
        plants['$block:$number'] = {
          'signature': signature,
          'overrides': values,
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        };
      }
      data['plants'] = plants;
    });
  }
}
