import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/local_id.dart';
import 'local_mutation_recorder.dart';

class PeopleRepository {
  PeopleRepository(this.database)
    : _mutations = LocalMutationRecorder(database);

  final AppDatabase database;
  final LocalMutationRecorder _mutations;

  Future<PersonRecord> findOrCreateEvaluator(String displayName) async {
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'Enter the name of the person conducting the assessment.',
      );
    }

    final existing =
        await (database.select(database.people)
              ..where(
                (row) =>
                    row.displayName.equals(normalizedName) &
                    row.deletedAt.isNull(),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing;

    return create(displayName: normalizedName, roleLabel: 'field_evaluator');
  }

  Future<PersonRecord?> findById(String id) {
    return (database.select(database.people)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<PersonRecord> create({
    required String displayName,
    String? roleLabel,
    String? organization,
    String? phone,
    String? email,
    String? deviceId,
  }) async {
    final id = LocalId.generate();
    await database.transaction(() async {
      await database
          .into(database.people)
          .insert(
            PeopleCompanion.insert(
              id: id,
              displayName: displayName,
              roleLabel: Value(roleLabel),
              organization: Value(organization),
              phone: Value(phone),
              email: Value(email),
              deviceId: Value(deviceId),
            ),
          );
      await _mutations.record(
        entityType: 'people',
        entityId: id,
        action: 'create',
        actorPersonId: id,
        deviceId: deviceId,
        after: {
          'display_name': displayName,
          'role_label': roleLabel,
          'organization': organization,
        },
      );
    });
    return (database.select(
      database.people,
    )..where((row) => row.id.equals(id))).getSingle();
  }
}
