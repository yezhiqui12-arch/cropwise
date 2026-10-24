import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/services/cloud/account_recovery_media_queue.dart';
import 'package:wormwise/services/cloud/wormwise_account_backup_service.dart';
import 'package:wormwise/services/evidence_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture fixture;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    fixture = await _Fixture.create();
  });
  tearDown(() => fixture.close());

  test(
    'snapshot records are available before missing photos download',
    () async {
      await fixture.seed();
      final source = await fixture.backup.exportLocalTables();
      await fixture.database.customStatement('DELETE FROM evidence_media');
      await fixture.backup.restoreSnapshotRecords('account', {
        'format_version': 1,
        'schema_version': fixture.database.schemaVersion,
        'owner_id': 'account',
        'tables': source,
        'media': [
          {'path': 'photos/one.jpg', 'sha256': fixture.checksum},
        ],
      });
      expect(
        await fixture.database.select(fixture.database.assessments).get(),
        hasLength(1),
      );
      expect(
        await fixture.database.select(fixture.database.evidenceMedia).get(),
        hasLength(1),
      );
      expect(await fixture.backup.mediaQueue.pendingCount('account'), 1);
      expect(await fixture.storage.exists('photos/one.jpg'), isFalse);
    },
  );

  test(
    'newer snapshot updates merge without reviving newer tombstones or pending edits',
    () async {
      await fixture.database.customStatement(
        'INSERT INTO fields (id,name,updated_at,sync_state,deleted_at) VALUES '
        "('newer','Before',10,'synced',NULL),"
        "('deleted','Deleted',30,'synced',30),"
        "('pending','Offline edit',10,'queued',NULL)",
      );
      await fixture.backup.restoreLocalTables(
        {
          'fields': [
            {'id': 'newer', 'name': 'After', 'updated_at': 20},
            {
              'id': 'deleted',
              'name': 'Old active record',
              'updated_at': 20,
              'deleted_at': null,
            },
            {'id': 'pending', 'name': 'Remote edit', 'updated_at': 40},
          ],
        },
        reconcileNewer: true,
        protectedRows: {
          'fields': {
            jsonEncode(['pending']),
          },
        },
      );
      final rows = {
        for (final row
            in await fixture.database.select(fixture.database.fields).get())
          row.id: row,
      };
      expect(rows['newer']!.name, 'After');
      expect(rows['deleted']!.deletedAt, isNotNull);
      expect(rows['pending']!.name, 'Offline edit');
    },
  );

  test(
    'invalid graph rolls back rather than silently dropping records',
    () async {
      await expectLater(
        fixture.backup.restoreLocalTables({
          'fields': [
            {'id': 'rollback-field', 'name': 'Must roll back'},
          ],
          'crop_cycles': [
            {'id': 'bad-cycle', 'field_id': 'missing-parent'},
          ],
        }),
        throwsA(isA<Exception>()),
      );
      expect(
        await fixture.database.select(fixture.database.fields).get(),
        isEmpty,
      );
    },
  );

  test(
    'a snapshot for another account is rejected before any import',
    () async {
      await expectLater(
        fixture.backup.restoreSnapshotRecords('account', {
          'format_version': 2,
          'schema_version': 8,
          'owner_id': 'other',
          'tables': {
            'fields': [
              {'id': 'wrong-owner', 'name': 'Wrong account'},
            ],
          },
          'media': [],
        }),
        throwsFormatException,
      );
      expect(
        await fixture.database.select(fixture.database.fields).get(),
        isEmpty,
      );
    },
  );

  test(
    'linked guest fallback restores saved metrics and never duplicates a full graph',
    () async {
      await fixture.seed();
      final cyclesBefore = await fixture.database
          .select(fixture.database.cropCycles)
          .get();
      await fixture.backup.restoreLinkedGuestCloudRecords(
        _guestSummary('assessment'),
      );
      expect(
        await fixture.database.select(fixture.database.cropCycles).get(),
        hasLength(cyclesBefore.length),
      );
      expect(
        (await fixture.database.select(fixture.database.assessments).get())
            .single
            .assessmentMode,
        'formal',
      );
      await fixture.backup.restoreLinkedGuestCloudRecords(
        _guestSummary('older-assessment'),
      );
      final rows = await fixture.database
          .select(fixture.database.assessments)
          .get();
      expect(rows, hasLength(2));
      final metrics = await fixture.database
          .select(fixture.database.metricResults)
          .get();
      expect(metrics.single.numerator, 20);
      expect(metrics.single.denominator, 50);
      expect(metrics.single.formulaVersion, 'v1');
      expect(metrics.single.scopeId, 'old-run');
      // Repeated recovery does not add cycles, blocks, or duplicate metrics.
      await fixture.backup.restoreLinkedGuestCloudRecords(
        _guestSummary('older-assessment'),
      );
      expect(
        await fixture.database.select(fixture.database.metricResults).get(),
        hasLength(1),
      );
      expect(
        (await fixture.database.select(fixture.database.cropCycles).get())
            .where((cycle) => cycle.status == 'active'),
        hasLength(1),
      );
    },
  );

  test(
    'complete snapshot replaces summary runs without sequence collisions',
    () async {
      await fixture.seed();
      await fixture.database.customStatement(
        "INSERT INTO field_blocks(id,crop_cycle_id,boundary_version_id,block_number,geometry_geojson,area_hectares) VALUES ('real-block','cycle','boundary',1,'{}',1)",
      );
      await fixture.database.customStatement(
        "INSERT INTO assessment_block_runs(id,assessment_id,field_block_id,block_sequence,scouting_pattern) VALUES ('real-run','assessment','real-block',1,'ladder')",
      );
      final complete = await fixture.backup.exportLocalTables();
      await fixture.database.customStatement('DELETE FROM evidence_media');
      await fixture.database.customStatement(
        'DELETE FROM assessment_block_runs',
      );
      await fixture.database.customStatement('DELETE FROM assessments');
      await fixture.backup.restoreLinkedGuestCloudRecords(
        _guestSummary('assessment'),
      );
      await fixture.backup.restoreLocalTables(complete, reconcileNewer: true);
      final runs = await fixture.database
          .select(fixture.database.assessmentBlockRuns)
          .get();
      expect(runs.single.id, 'real-run');
      expect(
        (await fixture.database.select(fixture.database.assessments).get())
            .single
            .assessmentMode,
        'formal',
      );
      expect(
        await fixture.database.select(fixture.database.metricResults).get(),
        isEmpty,
      );
    },
  );

  test(
    'failed photo does not block other photos and resumes after restart',
    () async {
      await fixture.seed(secondPhoto: true);
      var attempts = 0;
      final queue = fixture.queue((bucket, path) async {
        attempts++;
        if (path.endsWith('one.jpg')) {
          throw const SocketException('Interrupted');
        }
        return fixture.bytes;
      });
      await queue.enqueue('account', [fixture.job('one'), fixture.job('two')]);
      expect(
        await queue.drain('account', isCurrentAccount: () => true),
        isFalse,
      );
      expect(attempts, 2);
      expect(await fixture.storage.exists('photos/two.jpg'), isTrue);
      expect(await queue.pendingCount('account'), 1);
      final restarted = fixture.queue((bucket, path) async => fixture.bytes);
      expect(
        await restarted.drain('account', isCurrentAccount: () => true),
        isTrue,
      );
      expect(await fixture.storage.exists('photos/one.jpg'), isTrue);
      expect(await restarted.pendingCount('account'), 0);
    },
  );

  test('checksum failure never publishes a damaged evidence file', () async {
    await fixture.seed();
    final queue = fixture.queue(
      (bucket, path) async => Uint8List.fromList([99]),
    );
    await queue.enqueue('account', [fixture.job('one')]);
    expect(await queue.drain('account', isCurrentAccount: () => true), isFalse);
    expect(await fixture.storage.exists('photos/one.jpg'), isFalse);
    expect(await queue.pendingCount('account'), 1);
  });

  test(
    'an account change during download prevents publishing its file',
    () async {
      await fixture.seed();
      var current = true;
      final queue = fixture.queue((bucket, path) async {
        current = false;
        return fixture.bytes;
      });
      await queue.enqueue('account', [fixture.job('one')]);
      expect(
        await queue.drain('account', isCurrentAccount: () => current),
        isFalse,
      );
      expect(await fixture.storage.exists('photos/one.jpg'), isFalse);
      expect(await queue.pendingCount('account'), 1);
    },
  );

  test(
    'deleted evidence is removed from the download queue without fetching',
    () async {
      await fixture.seed();
      var calls = 0;
      final queue = fixture.queue((bucket, path) async {
        calls++;
        return fixture.bytes;
      });
      await queue.enqueue('account', [fixture.job('one')]);
      await fixture.database.customStatement(
        'UPDATE evidence_media SET deleted_at=30',
      );
      expect(
        await queue.drain('account', isCurrentAccount: () => true),
        isTrue,
      );
      expect(calls, 0);
    },
  );

  test(
    'record backup succeeds and remains verifiable when a local photo is missing',
    () async {
      // Flutter's widget binding otherwise replaces HTTP with a 400 response.
      // This test talks only to the ephemeral loopback server below.
      final previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousHttpOverrides);
      await fixture.seed();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final snapshots = <String, List<int>>{};
      final subscription = server.listen((request) async {
        final path = request.uri.path;
        if (path.startsWith('/storage/v1/object/list/')) {
          request.response.headers.contentType = ContentType.json;
          request.response.write('[]');
        } else if (path.startsWith('/storage/v1/object/') &&
            request.method == 'POST') {
          final body = latin1.decode(
            await request.fold<List<int>>(
              [],
              (bytes, chunk) => bytes..addAll(chunk),
            ),
          );
          final boundary = request.headers.contentType!.parameters['boundary']!;
          final upload = body
              .split('--$boundary')
              .firstWhere((part) => part.contains('filename=""'));
          final content = upload.substring(upload.indexOf('\r\n\r\n') + 4);
          // The SDK sends a multipart upload, followed by one framing CRLF.
          snapshots[path] = latin1.encode(
            content.substring(0, content.length - 2),
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'Key': path}));
        } else if (path.startsWith('/storage/v1/object/') &&
            request.method == 'GET') {
          final key = path.replaceFirst('/object/authenticated/', '/object/');
          final bytes = snapshots[key];
          if (bytes == null) {
            request.response.statusCode = 404;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({'message': 'Object not found', 'statusCode': '404'}),
            );
          } else {
            request.response.add(bytes);
          }
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write('[]');
        }
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      try {
        await client.auth.recoverSession(
          jsonEncode({
            'access_token': 'test-token',
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'user': {
              'id': 'account',
              'app_metadata': {},
              'user_metadata': {},
              'aud': 'authenticated',
              'created_at': '2026-09-01T00:00:00Z',
              'is_anonymous': false,
            },
          }),
        );
        final backup = WormWiseAccountBackupService(
          fixture.database,
          client,
          evidenceStorage: fixture.storage,
          localViewDirectory: Directory('${fixture.directory.path}/views'),
        );
        expect(await backup.synchronize('account'), isTrue);
        final decoded =
            jsonDecode(
                  utf8.decode(
                    gzip.decode(
                      snapshots.entries
                          .where((entry) => entry.key.endsWith('.json.gz'))
                          .single
                          .value,
                    ),
                  ),
                )
                as Map;
        expect(decoded['format_version'], 2);
        expect(decoded['media_complete'], isFalse);
        expect((decoded['tables'] as Map)['assessments'], hasLength(1));
        expect(await backup.synchronizeMedia('account'), isFalse);
        expect(backup.lastMediaError, contains('waiting'));
      } finally {
        await client.dispose();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}

List<Map<String, dynamic>> _guestSummary(String assessmentId) => [
  {
    'guest_id': 'guest',
    'fields': [
      {
        'id': 'field',
        'name': 'Old field',
        'status': 'active',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
      },
    ],
    'boundaries': [
      {
        'id': 'boundary',
        'field_id': 'field',
        'version_number': 1,
        'geometry_geojson': {'type': 'Polygon', 'coordinates': []},
        'area_hectares': 1.0,
        'source_method': 'draw',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
      },
    ],
    'assessments': [
      {
        'id': assessmentId,
        'field_id': 'field',
        'boundary_id': 'boundary',
        'status': 'submitted',
        'growth_stage': 'v7',
        'protocol_version': 'v1',
        'formula_version': 'v1',
        'completed_at': '2026-09-01T01:00:00Z',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T01:00:00Z',
        'result_snapshot': {
          'metrics': [
            {
              'scope_type': 'block',
              'scope_id': 'old-run',
              'metric_code': 'vegetative_current_infestation_percent',
              'numerator': 20,
              'denominator': 50,
              'value': 40.0,
              'unit': 'percent',
              'formula_version': 'v1',
            },
          ],
        },
      },
    ],
    'stations': [],
    'evidence': [],
  },
];

class _Fixture {
  _Fixture(this.database, this.client, this.directory) {
    storage = EvidenceStorageService(
      rootDirectory: () async => Directory('${directory.path}/media'),
    );
    backup = WormWiseAccountBackupService(
      database,
      client,
      evidenceStorage: storage,
      localViewDirectory: Directory('${directory.path}/views'),
    );
  }
  final AppDatabase database;
  final SupabaseClient client;
  final Directory directory;
  late final EvidenceStorageService storage;
  late final WormWiseAccountBackupService backup;
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  String get checksum => sha256.convert(bytes).toString();
  static Future<_Fixture> create() async => _Fixture(
    AppDatabase(NativeDatabase.memory()),
    SupabaseClient('https://example.supabase.co', 'test-key'),
    await Directory.systemTemp.createTemp('wormwise-recovery-'),
  );
  Future<void> close() async {
    await database.close();
    await client.dispose();
    await directory.delete(recursive: true);
  }

  Future<void> seed({bool secondPhoto = false}) async {
    await database.customStatement(
      "INSERT INTO people(id,display_name) VALUES ('person','Farmer')",
    );
    await database.customStatement(
      "INSERT INTO fields(id,name,owner_person_id) VALUES ('field','Full field','person')",
    );
    await database.customStatement(
      "INSERT INTO crop_cycles(id,field_id) VALUES ('cycle','field')",
    );
    await database.customStatement(
      "INSERT INTO field_boundary_versions(id,field_id,version_number,geometry_geojson,source_method,area_hectares) VALUES ('boundary','field',1,'{}','draw',1)",
    );
    await database.customStatement(
      "INSERT INTO assessments(id,crop_cycle_id,boundary_version_id,evaluator_person_id,assessment_mode,scouting_pattern,growth_stage,protocol_version,formula_version) VALUES ('assessment','cycle','boundary','person','formal','ladder','v7','v1','v1')",
    );
    for (final id in ['one', if (secondPhoto) 'two']) {
      await database.customStatement(
        'INSERT INTO evidence_media(id,assessment_id,media_type,local_uri,sha256_checksum,storage_state) VALUES (?,?,?,?,?,?)',
        [id, 'assessment', 'image', 'photos/$id.jpg', checksum, 'ready'],
      );
    }
  }

  AccountRecoveryMedia job(String id) => AccountRecoveryMedia(
    mediaId: id,
    localPath: 'photos/$id.jpg',
    bucket: 'wormwise-account-backups',
    remotePath: 'account/evidence/photos/$id.jpg',
    evidenceChecksum: checksum,
    checksum: checksum,
  );
  AccountRecoveryMediaQueue queue(
    Future<Uint8List> Function(String, String) download,
  ) => AccountRecoveryMediaQueue(
    database: database,
    evidenceStorage: storage,
    directory: () async => Directory('${directory.path}/queue'),
    download: download,
  );
}
