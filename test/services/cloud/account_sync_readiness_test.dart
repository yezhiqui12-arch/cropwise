import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Uses the HTTP transport supplied by Supabase; no app dependency changes.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/services/cloud/account_app_data_service.dart';
import 'package:wormwise/services/cloud/wormwise_account_backup_service.dart';
import 'package:wormwise/services/cloud/wormwise_cloud_sync_service.dart';
import 'package:wormwise/widgets/account_recovery_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'submission sync excludes unrelated records and preserves field selection',
    () async {
      final requests = <http.Request>[];
      final fixture = await _fixture(
        transport: (request) async {
          requests.add(request);
          final single =
              request.url.path.endsWith('/fields') &&
              request.url.queryParameters.containsKey('id');
          return http.Response(
        single ? '{"id":"target","owner_id":"account"}' : '[]',
        200,
        headers: {'content-type': 'application/json'},
        request: request,
          );
        },
      );
      final db = fixture.database;
      await db.customStatement(
        "INSERT INTO people (id, display_name) VALUES ('person', 'Farmer')",
      );
      for (final field in ['unrelated', 'target']) {
        await db.customStatement(
          "INSERT INTO fields (id, name) VALUES (?, ?)",
          [field, field],
        );
        await db.customStatement(
          "INSERT INTO crop_cycles (id, field_id) VALUES (?, ?)",
          ['cycle-$field', field],
        );
        await db.customStatement(
          "INSERT INTO field_boundary_versions (id, field_id, version_number, geometry_geojson, source_method, area_hectares) VALUES (?, ?, 1, '{}', 'drawn', 1)",
          ['boundary-$field', field],
        );
        await db.customStatement(
          "INSERT INTO assessments (id, crop_cycle_id, boundary_version_id, evaluator_person_id, assessment_mode, scouting_pattern, growth_stage, protocol_version, formula_version, status, completed_at) VALUES (?, ?, ?, 'person', 'formal', 'w', 'v3_v6', '1', '1', 'completed', 1790000000)",
          ['assessment-$field', 'cycle-$field', 'boundary-$field'],
        );
      }
      await fixture.sync.synchronizeAssessmentForSubmission(
        'assessment-target',
      );
      final writes = requests.where((r) => r.method != 'GET').toList();
      expect(writes.map((r) => r.url.path.split('/').last), [
        'fields',
        'field_boundaries',
        'assessments',
      ]);
      expect(writes.any((r) => r.body.contains('unrelated')), isFalse);
      expect(writes.first.body.contains('is_current'), isFalse);
      expect(
        requests
            .where((r) => r.url.path.endsWith('/assessments'))
            .every(
              (r) =>
                  r.method != 'GET' ||
                  r.url.queryParameters['id'] == 'eq.assessment-target',
            ),
        isTrue,
      );
      expect(fixture.backup.restoreCalls, 0);
    },
  );
  test(
    'restart opens completed local account without another blocking restore',
    () async {
      final fixture = await _fixture();
      expect(await fixture.sync.restoreAccountView('account'), isTrue);
      final calls = fixture.backup.restoreCalls;
      final restarted = WormWiseCloudSyncService(
        fixture.database,
        fixture.client,
        accountBackup: fixture.backup,
      );
      addTearDown(restarted.dispose);
      await restarted.prepareAccountView('account', restoreRecords: false);
      expect(restarted.recordsReady, isTrue);
      expect(restarted.needsAccountRecovery, isFalse);
      expect(fixture.backup.restoreCalls, calls);
    },
  );
  test(
    'missing or different account marker still requires restoration',
    () async {
      final fixture = await _fixture();
      await fixture.sync.prepareAccountView('account', restoreRecords: false);
      expect(fixture.sync.needsAccountRecovery, isTrue);
      await fixture.database
          .into(fixture.database.appPreferences)
          .insertOnConflictUpdate(
            AppPreferencesCompanion.insert(
              preferenceKey:
                  WormWiseAccountBackupService.localRecoveryPreferenceKey,
              preferenceValue: 'another-account',
            ),
          );
      await fixture.sync.prepareAccountView('account', restoreRecords: false);
      expect(fixture.sync.needsAccountRecovery, isTrue);
    },
  );
  test(
    'device readiness stays in local views and is excluded from cloud restore',
    () async {
      final fixture = await _fixture();
      expect(await fixture.sync.restoreAccountView('account'), isTrue);
      final local = await fixture.backup.exportLocalTables(
        includeLocalRecovery: true,
      );
      final cloud = await fixture.backup.exportLocalTables();
      bool containsMarker(Map tables) =>
          (tables['app_preferences'] as List).any(
            (row) =>
                row['preference_key'] ==
                WormWiseAccountBackupService.localRecoveryPreferenceKey,
          );
      expect(containsMarker(local), isTrue);
      expect(containsMarker(cloud), isFalse);
      await fixture.database.delete(fixture.database.appPreferences).go();
      await fixture.backup.restoreLocalTables(local);
      expect(
        await fixture.database.select(fixture.database.appPreferences).get(),
        isEmpty,
      );
      await fixture.backup.restoreLocalTables(
        local,
        includeLocalRecovery: true,
      );
      expect(
        await fixture.database.select(fixture.database.appPreferences).get(),
        hasLength(1),
      );
    },
  );
  test(
    'restored media changes are included in the final verified snapshot',
    () async {
      final fixture = await _fixture();
      fixture.backup.restoreMediaChanges = true;
      expect(
        await fixture.sync.verifyAccountBackup(),
        isTrue,
        reason: fixture.sync.lastError,
      );
      expect(fixture.sync.backupVerified, isTrue);
    },
  );

  test(
    'essential records become ready while photos are still pending',
    () async {
      final media = Completer<bool>();
      final fixture = await _fixture(media: media.future);
      expect(await fixture.sync.restoreAccountView('account'), isTrue);
      expect(fixture.sync.recordsReady, isTrue);
      expect(fixture.sync.needsAccountRecovery, isFalse);
      expect(fixture.sync.backupVerified, isFalse);
      final verification = fixture.sync.verifyAccountBackup();
      await fixture.backup.mediaStarted.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError(
          fixture.sync.lastError ?? 'Media phase was not reached.',
        ),
      );
      expect(fixture.sync.backupVerified, isFalse);
      media.complete(true);
      expect(await verification, isTrue);
      expect(fixture.sync.lastVerifiedAt, isNotNull);
    },
  );

  test('incomplete snapshot cannot report a verified account backup', () async {
    final fixture = await _fixture(complete: false);
    expect(await fixture.sync.verifyAccountBackup(), isFalse);
    expect(fixture.sync.backupVerified, isFalse);
    expect(fixture.sync.lastVerifiedAt, isNull);
    expect(fixture.sync.recordsReady, isTrue);
  });

  test(
    'failed restoration retains the gate until explicit local access',
    () async {
      final fixture = await _fixture(restored: false);
      expect(await fixture.sync.restoreAccountView('account'), isFalse);
      expect(fixture.sync.recoveryState, AccountRecoveryState.error);
      expect(fixture.sync.needsAccountRecovery, isTrue);
      fixture.sync.continueWithLocalData();
      expect(fixture.sync.needsAccountRecovery, isFalse);
      expect(fixture.sync.recordsReady, isFalse);
      expect(fixture.sync.backupVerified, isFalse);
    },
  );

  test('a local change immediately invalidates backup verification', () async {
    final fixture = await _fixture();
    expect(
      await fixture.sync.verifyAccountBackup(),
      isTrue,
      reason: fixture.sync.lastError,
    );
    AccountAppDataEvents.changed();
    expect(fixture.sync.backupVerified, isFalse);
    expect(
      await fixture.sync.verifyAccountBackup(),
      isTrue,
      reason: fixture.sync.lastError,
    );
  });

  test('account changes during verification cannot report success', () async {
    final media = Completer<bool>();
    final fixture = await _fixture(media: media.future);
    final verification = fixture.sync.verifyAccountBackup();
    await fixture.backup.mediaStarted.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw StateError(
        fixture.sync.lastError ?? 'Media phase was not reached.',
      ),
    );
    await fixture.client.auth.signOut(scope: SignOutScope.local);
    media.complete(true);
    expect(await verification, isFalse);
    expect(fixture.sync.backupVerified, isFalse);
    expect(fixture.sync.state, isNot(WormWiseCloudSyncState.synced));
  });

  testWidgets('restoration view shows progress without empty account screens', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AccountRecoveryView(
            state: AccountRecoveryState.restoring,
            detail: 'Restoring fields and assessments',
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('account_recovery_progress')), findsOneWidget);
    expect(find.text('Restoring fields and assessments'), findsOneWidget);
    expect(find.byKey(const Key('retry_account_recovery')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restoration failure offers retry and explicit local access', (
    tester,
  ) async {
    var retries = 0;
    var local = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountRecoveryView(
            state: AccountRecoveryState.error,
            detail: 'Cloud history has not loaded.',
            onRetry: () => retries++,
            onContinueWithLocalData: () => local++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('retry_account_recovery')));
    await tester.tap(find.byKey(const Key('continue_with_local_account_data')));
    expect(retries, 1);
    expect(local, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<
  ({
    WormWiseCloudSyncService sync,
    _Backup backup,
    SupabaseClient client,
    AppDatabase database,
  })
>
_fixture({
  Future<http.Response> Function(http.Request)? transport,
  Future<bool>? media,
  bool restored = true,
  bool complete = true,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  final client = SupabaseClient(
    'https://example.supabase.co',
    'anon',
    httpClient: MockClient(
      transport ??
          (request) async => http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
    ),
  );
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${encode({'alg': 'HS256'})}.${encode({'sub': 'account', 'exp': expiry})}.signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'refresh_token': 'refresh',
      'token_type': 'bearer',
      'expires_at': expiry,
      'user': {
        'id': 'account',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'farmer@example.com',
        'is_anonymous': false,
        'created_at': DateTime.utc(2026).toIso8601String(),
      },
    }),
  );
  final backup = _Backup(
    database,
    client,
    media ?? Future.value(true),
    restored,
    complete,
  );
  final sync = WormWiseCloudSyncService(
    database,
    client,
    accountBackup: backup,
  );
  addTearDown(database.close);
  addTearDown(client.dispose);
  addTearDown(sync.dispose);
  return (sync: sync, backup: backup, client: client, database: database);
}

class _Backup extends WormWiseAccountBackupService {
  _Backup(
    super.database,
    super.client,
    this.media,
    this.restored,
    this.complete,
  );
  final Future<bool> media;
  final bool restored;
  int restoreCalls = 0;
  final bool complete;
  final mediaStarted = Completer<void>();
  bool restoreMediaChanges = false;

  @override
  Future<void> prepareAccountView(
    String ownerId, {
    bool assumeCurrentWhenUntracked = false,
  }) async {}
  @override
  Future<bool> restoreEssentialRecords(String ownerId) async {
    restoreCalls++;
    return restored;
  }

  @override
  Future<bool> synchronize(String ownerId) async => true;
  @override
  Future<bool> synchronizeMedia(String ownerId) async {
    if (!mediaStarted.isCompleted) {
      mediaStarted.complete();
    }
    final success = await media;
    if (restoreMediaChanges) {
      AccountAppDataEvents.changed();
      onSnapshotCapture?.call();
    }
    lastSnapshotHasData = true;
    lastPublishedSnapshotComplete = success && complete;
    return success;
  }
}
