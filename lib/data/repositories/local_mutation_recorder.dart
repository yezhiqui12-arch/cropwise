import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/database_codes.dart';
import '../local/local_id.dart';

/// Writes the audit and synchronization records for a local mutation.
///
/// Call this from inside the same Drift transaction as the domain write.
class LocalMutationRecorder {
  LocalMutationRecorder(this.database);

  final AppDatabase database;

  Future<void> record({
    required String entityType,
    required String entityId,
    required String action,
    String operation = 'upsert',
    String? actorPersonId,
    String? deviceId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    String? reason,
    bool queueForSync = true,
  }) async {
    final now = DateTime.now().toUtc();
    await database
        .into(database.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            id: LocalId.generate(),
            actorPersonId: Value(actorPersonId),
            deviceId: Value(deviceId),
            entityType: entityType,
            entityId: entityId,
            action: action,
            beforeJson: Value(before == null ? null : jsonEncode(before)),
            afterJson: Value(after == null ? null : jsonEncode(after)),
            reason: Value(reason),
            occurredAt: now,
            syncState: const Value(DatabaseCodes.localOnly),
          ),
        );

    if (queueForSync) {
      await database
          .into(database.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              id: LocalId.generate(),
              entityType: entityType,
              entityId: entityId,
              operation: operation,
              payloadJson: Value(after == null ? null : jsonEncode(after)),
              status: const Value(DatabaseCodes.queued),
            ),
          );
    }
  }
}
