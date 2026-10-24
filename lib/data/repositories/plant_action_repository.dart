import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/app_database.dart';
import '../../models/plant_action_guidance.dart';
import '../../services/cloud/account_app_data_service.dart';
import 'field_repository.dart';

/// Separate optional local records; neither DA observations nor model scores.
/// App preferences participate in the existing private SQLite account backup.
class PlantActionRepository {
  const PlantActionRepository(this.database, this.ownerId);
  final AppDatabase database;
  final String ownerId;
  String get _preferences => 'plant_action_guides_v1_$ownerId';
  String _key(String assessment, String block, int number) =>
      'plant_actions_v1_${ownerId}_${assessment}_${block}_$number';
  Future<Map<String, dynamic>> _read(String key) async {
    final raw = await FieldRepository(database).readPreferenceValue(key);
    if (raw == null) return {};
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved action record');
    }
    return value;
  }

  Future<Set<String>> learnedGuides() async =>
      ((await _read(_preferences))['collapsed'] as List? ?? [])
          .whereType<String>()
          .toSet();
  Future<void> rememberCollapsed(PlantActionGuide guide) async {
    await database.transaction(() async {
      final learned = (await learnedGuides())..add(guide.preferenceId);
      await FieldRepository(database).savePreferenceValue(
        _preferences,
        jsonEncode({'version': 1, 'collapsed': learned.toList()}),
      );
    });
    AccountAppDataEvents.changed();
  }

  Future<List<PlantActionGuide>> pendingNotices(
    String assessment,
    List<PlantActionGuide> guides,
  ) async {
    final data = await _read('plant_action_notices_v1_${ownerId}_$assessment');
    final shown = (data['shown'] as List? ?? []).whereType<String>().toSet();
    return guides.where((g) => !shown.contains(g.preferenceId)).toList();
  }

  /// Stored separately from collapsed cards and optional actions: displaying a
  /// notice does not claim that the farmer read it or removed the pest.
  Future<void> markNoticesShown(
    String assessment,
    List<PlantActionGuide> guides,
  ) async {
    await database.transaction(() async {
      final key = 'plant_action_notices_v1_${ownerId}_$assessment';
      final data = await _read(key);
      final shown = (data['shown'] as List? ?? []).whereType<String>().toSet()
        ..addAll(guides.map((g) => g.preferenceId));
      await FieldRepository(database).savePreferenceValue(
        key,
        jsonEncode({'version': 1, 'shown': shown.toList()}),
      );
    });
    AccountAppDataEvents.changed();
  }

  /// Offering a tutorial once is distinct from the farmer saying it is learned.
  /// Reopening its original plant remains expanded until explicitly collapsed.
  Future<Set<String>> firstOffers(
    String assessment,
    String block,
    int number,
    List<PlantActionGuide> guides,
  ) => database.transaction(() async {
    final key = 'plant_action_offers_v1_${ownerId}_$assessment';
    final data = await _read(key);
    final offered = Map<String, dynamic>.from(data['offered'] as Map? ?? {});
    final plant = '$block:$number';
    var changed = false;
    final first = <String>{};
    for (final guide in guides) {
      if (!offered.containsKey(guide.preferenceId)) {
        offered[guide.preferenceId] = plant;
        changed = true;
      }
      if (offered[guide.preferenceId] == plant) first.add(guide.id);
    }
    if (changed) {
      await FieldRepository(database).savePreferenceValue(
        key,
        jsonEncode({'version': 1, 'offered': offered}),
      );
      AccountAppDataEvents.changed();
    }
    return first;
  });

  Future<Map<String, PlantActionRecord>> load(
    String assessment,
    String block,
    int number,
  ) async {
    final raw = (await _read(_key(assessment, block, number)))['active'];
    if (raw is! Map) return {};
    final records = <String, PlantActionRecord>{};
    for (final entry in raw.entries) {
      final record = PlantActionRecord.parse(entry.value);
      if (record != null) records[entry.key.toString()] = record;
    }
    return records;
  }

  Future<void> record({
    required String assessment,
    required String block,
    required int number,
    required PlantActionGuide guide,
    required String signature,
    required bool imported,
    bool undo = false,
  }) async {
    if (assessment.isEmpty ||
        block.isEmpty ||
        ownerId.isEmpty ||
        number < 1 ||
        number > 20 ||
        signature.isEmpty) {
      throw ArgumentError('Invalid plant action scope');
    }
    await database.transaction(() async {
      final key = _key(assessment, block, number);
      final data = await _read(key);
      final active = Map<String, dynamic>.from(data['active'] as Map? ?? {});
      final history = List<dynamic>.from(data['history'] as List? ?? []);
      final record = PlantActionRecord(
        guideId: guide.id,
        signature: signature,
        recordedAt: DateTime.now().toUtc(),
        imported: imported,
      );
      history.add({...record.toJson(), 'event': undo ? 'undone' : 'recorded'});
      if (undo) {
        active.remove(guide.id);
      } else {
        // A second photograph cannot overwrite when the action was performed.
        active.putIfAbsent(guide.id, record.toJson);
      }
      await FieldRepository(database).savePreferenceValue(
        key,
        jsonEncode({
          'version': 1,
          'assessment_id': assessment,
          'block_run_id': block,
          'plant_number': number,
          'active': active,
          'history': history,
        }),
      );
    });
    AccountAppDataEvents.changed();
  }

  Stream<Map<String, int>> watchSummary(String assessment) {
    final prefix = 'plant_actions_v1_${ownerId}_${assessment}_';
    return (database.select(database.appPreferences)..where(
          (p) => p.preferenceKey.substr(1, prefix.length).equals(prefix),
        ))
        .watch()
        .map((rows) {
          final counts = <String, int>{};
          for (final row in rows) {
            try {
              final data = jsonDecode(row.preferenceValue);
              if (data is! Map || data['assessment_id'] != assessment) continue;
              final active = data['active'];
              if (active is! Map) continue;
              for (final kind in PlantActionKind.values) {
                if (PlantActionRecord.parse(active[kind.name]) != null) {
                  counts.update(kind.name, (v) => v + 1, ifAbsent: () => 1);
                }
              }
            } catch (_) {
              /* Skip unreadable optional records; never invent zero. */
            }
          }
          return counts;
        });
  }
}
