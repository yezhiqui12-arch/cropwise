import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/services/cloud/wormwise_cloud_sync_service.dart';

void main() {
  testWidgets('automatic resume preserves local-only field data', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.customStatement(
      'INSERT INTO fields (id, name) VALUES (?, ?)',
      ['local-field', 'Offline field'],
    );
    final sync = WormWiseCloudSyncService(database, null);
    await sync.start();
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    await sync.synchronizeNow();
    expect(sync.state, WormWiseCloudSyncState.localOnly);
    expect(sync.lastSyncedAt, isNull);
    expect((await database.select(database.fields).get()).single.name, 'Offline field');
    sync.dispose();
    await database.close();
  });
}
