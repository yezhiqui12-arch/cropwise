import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/services/offline_field_map_store.dart';

const response =
    '{"elements":[{"type":"way","tags":{"highway":"track"},"geometry":[{"lat":17.79,"lon":121.47},{"lat":17.791,"lon":121.471}]}]}';
const points = [LatLng(17.79, 121.47), LatLng(17.791, 121.471)];

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wormwise-map-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('download survives reopening with no network', () async {
    final store = OfflineFieldMapStore(
      rootDirectory: () async => directory,
      fetch: (query) async {
        expect(query, contains('way[highway]'));
        expect(query, isNot(contains('tile.openstreetmap')));
        return response;
      },
    );
    final saved = await store.save('boundary-1', points);
    expect(saved.features.single.kind, 'road');
    final offline = OfflineFieldMapStore(
      rootDirectory: () async => directory,
      fetch: (_) async => throw const SocketException('offline'),
    );
    final restored = await offline.load('boundary-1', points);
    expect(restored!.features.single.points.length, 2);
    expect(restored.area.contains(points.first), isTrue);
  });

  test('failed update preserves the previous download', () async {
    var fail = false;
    final store = OfflineFieldMapStore(
      rootDirectory: () async => directory,
      fetch: (_) async {
        if (fail) throw const SocketException('offline');
        return response;
      },
    );
    final first = await store.save('boundary-1', points);
    fail = true;
    await expectLater(
      store.save('boundary-1', points),
      throwsA(isA<SocketException>()),
    );
    expect((await store.load('boundary-1', points))!.savedAt, first.savedAt);
  });

  test('incomplete server responses never replace a good download', () async {
    var body = response;
    final store = OfflineFieldMapStore(
      rootDirectory: () async => directory,
      fetch: (_) async => body,
    );
    await store.save('boundary-1', points);
    body = '{"remark":"timeout","elements":[]}';
    await expectLater(store.save('boundary-1', points), throwsFormatException);
    expect((await store.load('boundary-1', points))!.features.length, 1);
  });

  test(
    'changed coverage requires a new download and removal deletes only map',
    () async {
      final store = OfflineFieldMapStore(
        rootDirectory: () async => directory,
        fetch: (_) async => response,
      );
      await store.save('boundary-1', points);
      await store.save('boundary-2', points);
      expect(await store.load('boundary-1', [const LatLng(18, 122)]), isNull);
      await store.remove('boundary-1');
      expect(await store.load('boundary-1', points), isNull);
      expect(await store.load('boundary-2', points), isNotNull);
    },
  );

  test('rejects unsafe identifiers and excessive download areas', () async {
    var calls = 0;
    final store = OfflineFieldMapStore(
      rootDirectory: () async => directory,
      fetch: (_) async {
        calls++;
        return response;
      },
    );
    await expectLater(store.save('../outside', points), throwsFormatException);
    await expectLater(
      store.save('boundary-1', [const LatLng(0, 0), const LatLng(1, 1)]),
      throwsFormatException,
    );
    expect(calls, 0);
  });
}
