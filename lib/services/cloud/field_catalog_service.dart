import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/local/app_database.dart';

class FieldCatalogService {
  const FieldCatalogService(this.database, this.client);
  final AppDatabase database;
  final SupabaseClient? client;
  static const barangays = [
    'Apayao',
    'Aquib',
    'Baung',
    'Calaoagan',
    'Catarauan',
    'Dugayung',
    'Gumarueng',
    'Macapil',
    'Maguilling',
    'Minanga',
    'Poblacion I',
    'Poblacion II',
    'Santa Barbara',
    'Santo Domingo',
    'Sicatna',
    'Villa Rey',
    'Villa Reyno',
    'Warat',
  ];
  static const varieties = [
    'Pioneer P3530YHR',
    'Pioneer 30T80',
    'Dekalb DK 8131S',
    'NK 6410',
    'NK 8840',
    'IPB Var 6',
  ];
  static String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  static List<String> verifiedNames(Iterable<String> names) => names
      .where(
        (name) => !const [
          'dekalbdk8888s',
          'dekalb8888s',
          'nativetraditionalwhitecorn',
        ].contains(normalize(name)),
      )
      .map(
        (name) => normalize(name) == 'pioneerp3530' ? 'Pioneer P3530YHR' : name,
      )
      .toSet()
      .toList();

  Future<List<String>> cached(String key, List<String> fallback) async {
    final row = await (database.select(
      database.appPreferences,
    )..where((r) => r.preferenceKey.equals(key))).getSingleOrNull();
    try {
      final names = row == null
          ? fallback
          : List<String>.from(jsonDecode(row.preferenceValue));
      return key == 'maize_variety_catalog' ? verifiedNames(names) : names;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<String>> refresh(String table, String key) async {
    final remote = client;
    if (remote == null || remote.auth.currentUser == null)
      throw StateError('Offline');
    final query = remote.from(table).select('name');
    final rows = table == 'piat_barangays'
        ? await query
              .eq('municipality_code', '0201520000')
              .eq('active', true)
              .order('name')
              .timeout(const Duration(seconds: 8))
        : await query
              .eq('active', true)
              .order('name')
              .timeout(const Duration(seconds: 8));
    final rawNames = rows.map((r) => r['name'] as String).toList();
    final names = table == 'maize_varieties'
        ? verifiedNames(rawNames)
        : rawNames;
    if (names.isEmpty) throw StateError('Catalog is empty');
    final encoded = jsonEncode(names);
    final old = await (database.select(
      database.appPreferences,
    )..where((r) => r.preferenceKey.equals(key))).getSingleOrNull();
    if (old?.preferenceValue != encoded) {
      await database
          .into(database.appPreferences)
          .insertOnConflictUpdate(
            AppPreferencesCompanion.insert(
              preferenceKey: key,
              preferenceValue: encoded,
            ),
          );
    }
    return names;
  }

  Future<void> queueVariety(String name) async {
    final trimmed = name.trim();
    final key = normalize(trimmed);
    if (trimmed.isEmpty || key.isEmpty) return;
    final user = client?.auth.currentUser?.id;
    await database
        .into(database.syncOutbox)
        .insertOnConflictUpdate(
          SyncOutboxCompanion.insert(
            id: 'variety_${user ?? 'local'}_$key',
            entityType: 'maize_variety',
            entityId: key,
            operation: 'suggest',
            payloadJson: Value(jsonEncode({'name': trimmed, 'ownerId': user})),
            status: const Value('queued'),
          ),
        );
  }

  Future<void> flush() async {
    final remote = client;
    final user = remote?.auth.currentUser?.id;
    if (remote == null || user == null) return;
    final pending =
        await (database.select(database.syncOutbox)..where(
              (r) =>
                  r.entityType.equals('maize_variety') &
                  r.status.equals('queued'),
            ))
            .get();
    for (final row in pending) {
      final payload =
          jsonDecode(row.payloadJson ?? '{}') as Map<String, dynamic>;
      if (payload['ownerId'] != null && payload['ownerId'] != user) continue;
      await remote
          .rpc('suggest_maize_variety', params: {'p_name': payload['name']})
          .timeout(const Duration(seconds: 10));
      await (database.update(database.syncOutbox)
            ..where((r) => r.id.equals(row.id)))
          .write(const SyncOutboxCompanion(status: Value('synced')));
    }
  }
}
