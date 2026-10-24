import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// Supabase's existing HTTP transport; no new app dependency.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/assessment_history_repository.dart';
import 'package:wormwise/services/cloud/expert_case_submission_service.dart';
import 'package:wormwise/services/evidence_storage_service.dart';
import '../../support/da_results_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'submitted photo identity repairs once, skips published reviews, and never reuploads',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final detail = await daResultsFixture(db);
      final point = detail.stations[6];
      for (final id in ['needs-identity', 'already-linked']) {
        await db
            .into(db.evidenceMedia)
            .insert(
              EvidenceMediaCompanion.insert(
                id: id,
                assessmentId: detail.assessment.id,
                stationId: Value(point.station!.id),
                plantObservationId: Value(point.plants.single.plant.id),
                mediaType: 'image',
                localUri: 'missing-on-this-phone.jpg',
                sha256Checksum: id,
                storageState: const Value('missing'),
              ),
            );
      }
      final requests = <http.Request>[];
      final client = await _client((request) async {
        requests.add(request);
        final body = switch (request.url.path.split('/').last) {
          'expert_cases' => [
            {'id': 'open-case', 'assessment_id': detail.assessment.id},
            {'id': 'published-case', 'assessment_id': 'published-assessment'},
          ],
          'expert_severity_summaries' => [
            {'case_id': 'published-case'},
          ],
          'evidence_files' => [
            {
              'id': 'needs-identity',
              'block_run_id': null,
              'block_sequence': null,
            },
            {
              'id': 'already-linked',
              'block_run_id': point.prepared.run.id,
              'block_sequence': 1,
            },
            {'id': 'not-local', 'block_run_id': null, 'block_sequence': null},
          ],
          'sync_evidence_block_identity' => true,
          _ => throw StateError('Unexpected request: ${request.url.path}'),
        };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      addTearDown(client.dispose);
      var storageTouched = false;
      final service = ExpertCaseSubmissionService(
        database: db,
        client: client,
        storage: EvidenceStorageService(
          rootDirectory: () async {
            storageTouched = true;
            return Directory.systemTemp;
          },
        ),
      );
      await service.synchronizeSubmittedBlockIdentities();
      final writes = requests.where((r) => r.method != 'GET').toList();
      expect(writes, hasLength(1));
      expect(jsonDecode(writes.single.body), {
        'p_evidence_id': 'needs-identity',
        'p_block_run_id': point.prepared.run.id,
        'p_block_sequence': 1,
      });
      expect(storageTouched, isFalse);
      expect(requests.every((r) => !r.url.path.contains('/storage/')), isTrue);
      expect(
        requests
            .where((r) => r.url.path.endsWith('/evidence_files'))
            .single
            .url
            .queryParameters['owner_id'],
        'eq.account',
      );
      expect(
        (await AssessmentHistoryRepository(
          db,
        ).loadDetail(detail.assessment.id))!.stations[6].prepared.run.id,
        point.prepared.run.id,
      );
    },
  );
}

Future<SupabaseClient> _client(
  Future<http.Response> Function(http.Request) transport,
) async {
  final client = SupabaseClient(
    'https://example.invalid',
    'public-test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(transport),
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
  return client;
}
