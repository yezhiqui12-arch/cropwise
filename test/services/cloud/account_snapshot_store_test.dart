import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wormwise/services/cloud/account_snapshot_store.dart';

class _Storage implements BackupObjectStorage {
  final files = <String, Uint8List>{};
  final removed = <String>[];
  bool failManifest = false;
  bool failDelete = false;
  String? corruptRead;
  @override
  Future<Uint8List> read(String path) async {
    if (!files.containsKey(path)) {
      throw const StorageException('Object not found', statusCode: '404');
    }
    return path == corruptRead ? Uint8List.fromList([0]) : files[path]!;
  }

  @override
  Future<void> write(String path, Uint8List bytes, String type) async {
    if (failManifest && path.endsWith('manifest.json')) {
      throw StateError('manifest upload failed');
    }
    files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<List<BackupObject>> list(String path) async {
    final entries = <String, BackupObject>{};
    for (final key in files.keys.where((p) => p.startsWith('$path/'))) {
      final name = key.substring(path.length + 1).split('/').first;
      entries[name] = BackupObject(name, '2026-10-01T00:00:00Z');
    }
    return entries.values.toList();
  }

  @override
  Future<void> remove(List<String> paths) async {
    if (failDelete) throw StateError('cleanup denied');
    for (final path in paths) {
      removed.add(path);
      files.remove(path);
    }
  }
}

void main() {
  const owner = 'account';
  const device = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  late _Storage storage;
  late AccountSnapshotStore store;
  late int tick;
  Future<void> publish({bool complete = true, bool Function()? current}) =>
      store.publish(
        owner: owner,
        device: device,
        bytes: Uint8List.fromList([++tick]),
        complete: complete,
        isCurrentAccount: current ?? () => true,
      );
  setUp(() {
    tick = 0;
    storage = _Storage();
    store = AccountSnapshotStore(
      storage,
      now: () => DateTime.utc(2026, 10, 24, 0, 0, tick),
    );
  });
  test('publishes verified manifest and retains three snapshots', () async {
    for (var i = 0; i < 6; i++) {
      await publish();
    }
    final candidates = (await store.candidates(owner))[device]!;
    expect(candidates, hasLength(3));
    expect(await store.download(candidates.first), [6]);
    expect(storage.removed, hasLength(3));
    expect(
      storage.removed.every((p) => p.contains('/devices/$device/snapshot-')),
      isTrue,
    );
  });
  test(
    'incomplete snapshots preserve a complete fallback beyond the newest three',
    () async {
      await publish();
      for (var i = 0; i < 5; i++) {
        await publish(complete: false);
      }
      final candidates = (await store.candidates(owner))[device]!;
      expect(candidates, hasLength(4));
      expect(candidates.last.complete, isTrue);
      expect(await store.download(candidates.last), [1]);
    },
  );
  test(
    'failed manifest publication never deletes the existing recovery point',
    () async {
      await publish();
      final before = Map<String, Uint8List>.from(storage.files);
      storage.failManifest = true;
      await expectLater(publish(), throwsStateError);
      expect(storage.removed, isEmpty);
      for (final key in before.keys) {
        expect(storage.files[key], before[key]);
      }
      expect(
        (await store.candidates(owner))[device]!.first.checksum,
        isNotNull,
      );
    },
  );
  test(
    'checksum mismatch is rejected and old candidates remain available',
    () async {
      await publish();
      await publish();
      final candidates = (await store.candidates(owner))[device]!;
      storage.corruptRead = candidates.first.path;
      await expectLater(
        store.download(candidates.first),
        throwsFormatException,
      );
      expect(await store.download(candidates.last), [1]);
    },
  );
  test(
    'legacy recovery and interrupted first publication remain discoverable',
    () async {
      storage.files['account/$device-1.json.gz'] = Uint8List.fromList([1]);
      storage.files['account/devices/$device/snapshot-2.json.gz'] =
          Uint8List.fromList([2]);
      final candidates = (await store.candidates(owner))[device]!;
      expect(candidates, hasLength(2));
      expect(await store.download(candidates.first), [2]);
      expect(await store.download(candidates.last), [1]);
    },
  );
  test(
    'cleanup preserves other devices, evidence and legacy fallbacks',
    () async {
      for (var i = 0; i < 7; i++) {
        storage.files['account/$device-$i.json.gz'] = Uint8List.fromList([i]);
      }
      storage.files['account/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-1.json.gz'] =
          Uint8List.fromList([9]);
      storage.files['account/evidence/plant.jpg'] = Uint8List.fromList([9]);
      await publish();
      expect(
        storage.files.keys.where((p) => p.startsWith('account/$device-')),
        hasLength(3),
      );
      expect(storage.files.containsKey('account/evidence/plant.jpg'), isTrue);
      expect(
        storage.files.containsKey(
          'account/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-1.json.gz',
        ),
        isTrue,
      );
    },
  );
  test(
    'malformed manifests cannot authorize deletion or publication',
    () async {
      storage.files['account/devices/$device/manifest.json'] =
          Uint8List.fromList(utf8.encode('{}'));
      await expectLater(publish(), throwsFormatException);
      expect(storage.removed, isEmpty);
    },
  );
  test('cleanup failure does not invalidate verified recovery', () async {
    storage.failDelete = true;
    for (var i = 0; i < 4; i++) {
      await publish();
    }
    expect(store.maintenanceError, isNotNull);
    expect((await store.candidates(owner))[device], hasLength(3));
  });
  test('account switch prevents publication', () async {
    await expectLater(publish(current: () => false), throwsStateError);
    expect(storage.files, isEmpty);
  });
  test(
    'account switch after snapshot verification leaves the old manifest intact',
    () async {
      await publish();
      final pointer = 'account/devices/$device/manifest.json';
      final previous = Uint8List.fromList(storage.files[pointer]!);
      var checks = 0;
      await expectLater(publish(current: () => ++checks < 3), throwsStateError);
      expect(storage.files[pointer], previous);
      expect(storage.removed, isEmpty);
    },
  );
  test('a manifest cannot authorize paths in another account', () async {
    await publish();
    final pointer = 'account/devices/$device/manifest.json';
    final json = jsonDecode(utf8.decode(storage.files[pointer]!)) as Map;
    (json['snapshots'] as List).first['path'] =
        'other-account/devices/$device/snapshot-1.json.gz';
    storage.files[pointer] = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    await expectLater(publish(), throwsFormatException);
    expect(storage.removed, isEmpty);
  });
  test(
    'concurrent publishers for one device preserve both verified pointers',
    () async {
      await Future.wait([publish(), publish()]);
      final entries = (await store.candidates(owner))[device]!;
      expect(entries, hasLength(2));
      expect(await store.download(entries.first), [2]);
      expect(await store.download(entries.last), [1]);
    },
  );
}
