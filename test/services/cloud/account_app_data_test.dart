import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise Supabase's existing HTTP transport without changing app dependencies.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/services/advisor/advisor_chat_session_store.dart';
import 'package:wormwise/services/advisor/advisor_conversation_store.dart';
import 'package:wormwise/services/cloud/account_app_data_service.dart';
import 'package:wormwise/services/cloud/wormwise_account_backup_service.dart';
import 'package:wormwise/services/wormwise_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AccountAppDataService appData;
  const storage = FlutterSecureStorage();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('wormwise-app-data-');
    appData = AccountAppDataService(directoryProvider: () async => directory);
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'fresh install restores complete chats, notification state and preferences without secrets',
    () async {
      final conversation = FileAdvisorConversationStore(
        directoryProvider: () async => directory,
      );
      final sessions = AdvisorChatSessionStore(
        directoryProvider: () async => directory,
      );
      final messages = List.generate(
        105,
        (index) => AdvisorStoredMessage(
          id: '$index',
          role: 'farmer',
          text: 'Message $index',
        ),
      );
      await conversation.save(messages);
      for (var index = 0; index < 22; index++) {
        await sessions.save(
          AdvisorChatSession(
            id: 'session-$index',
            title: 'Chat $index',
            updatedAt: DateTime.utc(2026),
            messages: messages,
          ),
        );
      }
      final notification = WormWiseNotification(
        id: 'notice',
        kind: WormWiseNotificationKind.adviceReady,
        title: 'Advice',
        body: 'Saved notification',
        createdAt: DateTime.utc(2026),
      );
      await storage.write(
        key: 'notification_history_v1',
        value: jsonEncode([notification.toJson()]),
      );
      await storage.write(key: 'notification_read_ids', value: '["notice"]');
      await storage.write(key: 'notification_follow_up_days', value: '14');
      await storage.write(
        key: 'wormwise_gemini_share_location',
        value: 'false',
      );
      await storage.write(
        key: 'wormwise_pending_upgrade_password',
        value: 'do-not-export',
      );
      final snapshot = await appData.capture();
      expect(jsonEncode(snapshot), isNot(contains('do-not-export')));
      final next = Directory('${directory.path}/new-install');
      final restored = AccountAppDataService(
        directoryProvider: () async => next,
      );
      FlutterSecureStorage.setMockInitialValues({});
      await restored.restore(snapshot);
      expect(
        await FileAdvisorConversationStore(
          directoryProvider: () async => next,
        ).load(),
        hasLength(105),
      );
      final chats = await AdvisorChatSessionStore(
        directoryProvider: () async => next,
      ).load();
      expect(chats, hasLength(22));
      expect(chats.every((chat) => chat.messages.length == 105), isTrue);
      expect(await storage.read(key: 'notification_read_ids'), '["notice"]');
      expect(await storage.read(key: 'notification_follow_up_days'), '14');
      expect(
        await storage.read(key: 'wormwise_gemini_share_location'),
        'false',
      );
      final history =
          jsonDecode((await storage.read(key: 'notification_history_v1'))!)
              as List;
      expect(WormWiseNotification.fromJson(history.single)!.id, 'notice');
    },
  );

  test(
    'newer local settings and session deletion survive stale snapshots; read IDs merge',
    () async {
      final remote = _snapshot({
        'preference:notification_follow_up_days': _entry('14', 1),
        'preference:notification_read_ids': _entry('["remote"]', 1),
        'session:old': _entry(_session('old'), 1),
      });
      await appData.restore(remote);
      await storage.write(key: 'notification_follow_up_days', value: '30');
      await storage.write(key: 'notification_read_ids', value: '["local"]');
      await AdvisorChatSessionStore(
        directoryProvider: () async => directory,
      ).take('old');
      await appData.capture();
      await appData.restore(remote);
      expect(await storage.read(key: 'notification_follow_up_days'), '30');
      expect(
        (jsonDecode((await storage.read(key: 'notification_read_ids'))!)
                as List)
            .toSet(),
        {'local', 'remote'},
      );
      expect(
        await AdvisorChatSessionStore(
          directoryProvider: () async => directory,
        ).load(),
        isEmpty,
      );
    },
  );

  test(
    'guest transfer includes chats and preferences while a different account stays empty',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final client = SupabaseClient('https://example.supabase.co', 'anon');
      addTearDown(database.close);
      addTearDown(client.dispose);
      final backup = WormWiseAccountBackupService(
        database,
        client,
        localViewDirectory: Directory('${directory.path}/views'),
        appData: appData,
      );
      await FileAdvisorConversationStore(
        directoryProvider: () async => directory,
      ).save([
        const AdvisorStoredMessage(
          id: 'guest',
          role: 'farmer',
          text: 'Guest chat',
        ),
      ]);
      await storage.write(
        key: 'notification_read_ids',
        value: '["guest-notice"]',
      );
      await backup.beginGuestTransfer();
      await backup.prepareAccountView('first');
      expect(
        await FileAdvisorConversationStore(
          directoryProvider: () async => directory,
        ).load(),
        hasLength(1),
      );
      expect(
        await storage.read(key: 'notification_read_ids'),
        '["guest-notice"]',
      );
      await backup.prepareAccountView('second');
      expect(
        await FileAdvisorConversationStore(
          directoryProvider: () async => directory,
        ).load(),
        isEmpty,
      );
      expect(await storage.read(key: 'notification_read_ids'), isNull);
      await backup.prepareAccountView('first');
      expect(
        (await FileAdvisorConversationStore(
          directoryProvider: () async => directory,
        ).load()).single.text,
        'Guest chat',
      );
      await backup.prepareGuestView();
      expect(
        (await FileAdvisorConversationStore(
          directoryProvider: () async => directory,
        ).load()).single.text,
        'Guest chat',
      );
    },
  );

  test(
    'app data restores even when there are no field or assessment records',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final client = SupabaseClient('https://example.supabase.co', 'anon');
      addTearDown(database.close);
      addTearDown(client.dispose);
      final backup = WormWiseAccountBackupService(
        database,
        client,
        localViewDirectory: Directory('${directory.path}/views'),
        appData: appData,
      );
      await backup.restoreSnapshotRecords('account', {
        'format_version': 2,
        'schema_version': database.schemaVersion,
        'owner_id': 'account',
        'tables': {},
        'media': [],
        'app_data': _snapshot({
          'advisor:active': _entry([_message('Saved chat')], 1),
        }),
      });
      expect(
        (await FileAdvisorConversationStore(
          directoryProvider: () async => directory,
        ).load()).single.text,
        'Saved chat',
      );
    },
  );

  test(
    'conflicting active chats are preserved as saved conversations',
    () async {
      await appData.restore(
        _snapshot({
          'advisor:active': _entry([_message('First phone')], 1),
        }),
      );
      await appData.restore(
        _snapshot({
          'advisor:active': _entry([_message('Second phone')], 2),
        }),
      );
      expect(
        (await FileAdvisorConversationStore(
          directoryProvider: () async => directory,
        ).load()).single.text,
        'Second phone',
      );
      expect(
        (await AdvisorChatSessionStore(
          directoryProvider: () async => directory,
        ).load()).single.messages.single.text,
        'First phone',
      );
    },
  );

  test(
    'Advisor photos use portable paths and checksum retries do not block text restoration',
    () async {
      final photo = File('${directory.path}/original.jpg');
      final bytes = utf8.encode('photo-content');
      await photo.writeAsBytes(bytes);
      await FileAdvisorConversationStore(
        directoryProvider: () async => directory,
      ).save([
        AdvisorStoredMessage(
          id: 'image',
          role: 'farmer',
          text: 'Photo question',
          imagePath: photo.path,
        ),
      ]);
      final snapshot = await appData.capture();
      await photo.delete();
      expect(await appData.capture(), snapshot);
      final next = Directory('${directory.path}/new-install');
      FlutterSecureStorage.setMockInitialValues({});
      final restored = AccountAppDataService(
        directoryProvider: () async => next,
      );
      await restored.restore(snapshot);
      final messages = await FileAdvisorConversationStore(
        directoryProvider: () async => next,
      ).load();
      expect(messages.single.text, 'Photo question');
      final target = File(messages.single.imagePath!);
      expect(await target.exists(), isFalse);
      var corrupt = true;
      var uploads = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon',
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response.bytes(corrupt ? [0] : bytes, 200);
          }
          uploads++;
          return http.Response(
            '{"Key":"uploaded"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      expect(
        await restored.synchronizeMedia(
          'account',
          client,
          'wormwise-account-backups',
          isCurrentAccount: () => true,
        ),
        isFalse,
      );
      expect(await target.exists(), isFalse);
      corrupt = false;
      expect(
        await restored.synchronizeMedia(
          'account',
          client,
          'wormwise-account-backups',
          isCurrentAccount: () => true,
        ),
        isTrue,
      );
      expect(sha256.convert(await target.readAsBytes()), sha256.convert(bytes));
      expect(await restored.mediaComplete('account'), isTrue);
      expect(uploads, 1);
      restored.requireFreshMediaVerification();
      expect(
        await restored.synchronizeMedia(
          'account',
          client,
          'wormwise-account-backups',
          isCurrentAccount: () => true,
        ),
        isTrue,
      );
      expect(
        uploads,
        1,
        reason: 'Fresh verification should read existing cloud photos.',
      );
    },
  );

  test('unknown secret keys are rejected before materialization', () async {
    await expectLater(
      appData.restore(
        _snapshot({
          'preference:wormwise_pending_upgrade_password': _entry('secret', 1),
        }),
      ),
      throwsFormatException,
    );
    expect(
      await storage.read(key: 'wormwise_pending_upgrade_password'),
      isNull,
    );
  });
}

Map<String, dynamic> _snapshot(Map<String, dynamic> entries) => {
  'version': 1,
  'entries': entries,
};
Map<String, dynamic> _entry(Object? value, int version) => {
  'updated_at': version,
  'value': value,
};
Map<String, dynamic> _message(String text) => {
  'id': 'message',
  'role': 'farmer',
  'text': text,
};
Map<String, dynamic> _session(String id) => {
  'id': id,
  'title': 'Saved chat',
  'updatedAt': DateTime.utc(2026).toIso8601String(),
  'messages': [_message('Saved message')],
};
