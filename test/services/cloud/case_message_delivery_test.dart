import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Supabase's existing transport; no additional application dependency.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wormwise/services/cloud/case_message_service.dart';
import 'package:wormwise/services/cloud/wormwise_identity_service.dart';
import 'package:wormwise/services/evidence_storage_service.dart';

class _Identity extends WormWiseIdentityService {
  _Identity(super.client);
  @override
  String get userId => 'farmer';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final uncertain in [false, true]) {
    test(
      uncertain
          ? 'lost send acknowledgement keeps safe retry and avoids duplicate publication'
          : 'rejected photo reply stays editable and retries staged upload with its original identity',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final root = await Directory.systemTemp.createTemp(
          'wormwise-delivery-',
        );
        addTearDown(() => root.delete(recursive: true));
        await File('${root.path}/photo.jpg').writeAsBytes([1, 2, 3]);
        var uploads = 0, publications = 0;
        bool published = false;
        Map<String, dynamic>? sent;
        final client = SupabaseClient(
          'https://example.invalid',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/case_messages') {
              return http.Response(
                jsonEncode(
                  published
                      ? [
                          {'id': 'reply'},
                        ]
                      : [],
                ),
                200,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path.startsWith('/storage/v1/object/')) {
              uploads++;
              return uploads == 1
                  ? http.Response('{"Key":"uploaded"}', 200, request: request)
                  : http.Response(
                      '{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}',
                      409,
                      request: request,
                    );
            }
            if (request.url.path == '/rest/v1/rpc/send_case_message') {
              publications++;
              sent = jsonDecode(request.body) as Map<String, dynamic>;
              if (publications == 1) {
                if (uncertain) {
                  published = true;
                  throw const SocketException('Acknowledgement lost');
                }
                return http.Response(
                  '{"code":"P0001","message":"Please check the requested photo"}',
                  400,
                  request: request,
                  headers: {'content-type': 'application/json'},
                );
              }
              published = true;
              return http.Response(
                '"reply"',
                200,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            throw StateError('Unexpected request: ${request.url.path}');
          }),
        );
        addTearDown(client.dispose);
        final service = CaseMessageService(
          _Identity(client),
          files: EvidenceStorageService(rootDirectory: () async => root),
        );
        final draft = CaseMessageDraft(
          id: 'reply',
          requestId: 'request',
          targetBlockId: 'block2',
          targetBlockSequence: 2,
          targetPlant: 8,
          samePlantConfirmed: true,
          photos: [
            CaseMessagePhoto(
              id: 'photo',
              localUri: 'photo.jpg',
              thumbnailUri: 'photo.jpg',
              station: 8,
              plant: 1,
              blockRunId: 'block2',
              captureSource: 'gallery',
            ),
          ],
        );
        await expectLater(
          service.send(
            owner: 'farmer',
            caseId: 'case',
            draft: draft,
            progress: (_) {},
          ),
          uncertain
              ? throwsA(isA<SocketException>())
              : throwsA(isA<PostgrestException>()),
        );
        expect(draft.attempted, uncertain);
        expect((await service.loadDraft('farmer', 'case')).photos.length, 1);
        await service.send(
          owner: 'farmer',
          caseId: 'case',
          draft: draft,
          progress: (_) {},
        );
        expect(publications, uncertain ? 1 : 2);
        expect(uploads, uncertain ? 1 : 2);
        expect(sent!['p_request_message_id'], 'request');
        expect(
          sent!['p_body'],
          '',
        ); // A caption or message is optional for photo replies.
        final photo = (sent!['p_attachments'] as List).single as Map;
        expect(photo['station_number'], 8);
        expect(photo['plant_number'], 1);
        expect(photo['block_run_id'], 'block2');
        expect(photo['same_plant_confirmed'], true);
        expect(photo['captured_at'], isNull);
        expect((await service.loadDraft('farmer', 'case')).photos, isEmpty);
      },
    );
  }
}
