import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BackupObject {
  const BackupObject(this.name, this.updatedAt);
  final String name;
  final String? updatedAt;
}

abstract interface class BackupObjectStorage {
  Future<Uint8List> read(String path);
  Future<void> write(String path, Uint8List bytes, String contentType);
  Future<List<BackupObject>> list(String path);
  Future<void> remove(List<String> paths);
}

class SupabaseBackupObjectStorage implements BackupObjectStorage {
  SupabaseBackupObjectStorage(this.client, this.bucket);
  final SupabaseClient client;
  final String bucket;
  @override
  Future<Uint8List> read(String path) =>
      client.storage.from(bucket).download(path);
  @override
  Future<void> write(String path, Uint8List bytes, String contentType) async {
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
  }

  @override
  Future<List<BackupObject>> list(String path) async {
    final result = <BackupObject>[];
    var offset = 0;
    while (true) {
      final page = await client.storage
          .from(bucket)
          .list(
            path: path,
            searchOptions: SearchOptions(limit: 100, offset: offset),
          );
      result.addAll(page.map((o) => BackupObject(o.name, o.updatedAt)));
      if (page.length < 100) return result;
      offset += page.length;
    }
  }

  @override
  Future<void> remove(List<String> paths) async {
    if (paths.isNotEmpty) await client.storage.from(bucket).remove(paths);
  }
}

class BackupSnapshot {
  const BackupSnapshot({
    required this.path,
    this.checksum,
    this.complete = false,
    required this.createdAt,
  });
  final String path;
  final String? checksum;
  final bool complete;
  final String createdAt;
  Map<String, Object?> toJson() => {
    'path': path,
    'sha256': checksum,
    'complete': complete,
    'created_at': createdAt,
  };
}

/// Verified per-device recovery pointers. Evidence objects are never pruned here.
class AccountSnapshotStore {
  AccountSnapshotStore(this.storage, {DateTime Function()? now})
    : now = now ?? (() => DateTime.now().toUtc());
  final BackupObjectStorage storage;
  final DateTime Function() now;
  String? maintenanceError;
  static final _device = RegExp(r'^[a-f0-9]{32}$');
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  static final _name = RegExp(r'^snapshot-[0-9]+(?:-[a-f0-9]{16})?\.json\.gz$');

  String _folder(String owner, String device) {
    if (owner.isEmpty ||
        owner.contains('/') ||
        owner.contains('\\') ||
        owner.contains('..') ||
        !_device.hasMatch(device)) {
      throw const FormatException('Invalid backup identity.');
    }
    return '$owner/devices/$device';
  }

  List<BackupSnapshot> _parse(Uint8List bytes, String owner, String device) {
    final folder = _folder(owner, device);
    if (bytes.length > 16384) {
      throw const FormatException('Backup manifest is too large.');
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map ||
        json['format_version'] != 1 ||
        json['owner_id'] != owner ||
        json['device_id'] != device ||
        json['snapshots'] is! List ||
        (json['snapshots'] as List).isEmpty ||
        (json['snapshots'] as List).length > 4) {
      throw const FormatException('Invalid backup manifest.');
    }
    final entries = <BackupSnapshot>[];
    for (final raw in json['snapshots'] as List) {
      if (raw is! Map ||
          raw['path'] is! String ||
          raw['sha256'] is! String ||
          !_hash.hasMatch(raw['sha256']) ||
          raw['complete'] is! bool ||
          raw['created_at'] is! String ||
          DateTime.tryParse(raw['created_at']) == null) {
        throw const FormatException('Invalid backup entry.');
      }
      final path = raw['path'] as String;
      if (!path.startsWith('$folder/') ||
          !_name.hasMatch(path.substring(folder.length + 1))) {
        throw const FormatException('Backup entry belongs to another device.');
      }
      if (entries.any((e) => e.path == path)) {
        throw const FormatException('Duplicate backup entry.');
      }
      entries.add(
        BackupSnapshot(
          path: path,
          checksum: raw['sha256'],
          complete: raw['complete'],
          createdAt: raw['created_at'],
        ),
      );
    }
    return entries;
  }

  bool _missing(Object error) =>
      error is StorageException &&
      (error.statusCode == '404' ||
          error.statusCode == '400' &&
              error.message.toLowerCase().contains('not found'));

  Future<List<BackupSnapshot>> _manifest(String owner, String device) async {
    try {
      return _parse(
        await storage.read('${_folder(owner, device)}/manifest.json'),
        owner,
        device,
      );
    } catch (error) {
      if (_missing(error)) return [];
      rethrow;
    }
  }

  Future<Uint8List> download(BackupSnapshot snapshot) async {
    final bytes = await storage.read(snapshot.path);
    if (snapshot.checksum != null &&
        sha256.convert(bytes).toString() != snapshot.checksum) {
      throw const FormatException('Snapshot checksum did not match.');
    }
    return bytes;
  }

  static final _publications = <String, Future<void>>{};

  Future<void> publish({
    required String owner,
    required String device,
    required Uint8List bytes,
    required bool complete,
    required bool Function() isCurrentAccount,
  }) async {
    final key = _folder(owner, device);
    final previous = _publications[key];
    final done = Completer<void>();
    _publications[key] = done.future;
    try {
      if (previous != null) await previous;
      await _publish(
        owner: owner,
        device: device,
        bytes: bytes,
        complete: complete,
        isCurrentAccount: isCurrentAccount,
      );
    } finally {
      done.complete();
      if (identical(_publications[key], done.future)) _publications.remove(key);
    }
  }

  Future<void> _publish({
    required String owner,
    required String device,
    required Uint8List bytes,
    required bool complete,
    required bool Function() isCurrentAccount,
  }) async {
    maintenanceError = null;
    final folder = _folder(owner, device);
    if (!isCurrentAccount()) throw StateError('Account changed during backup.');
    // Never overwrite a malformed or inaccessible manifest and then prune its history.
    final previous = await _manifest(owner, device);
    final time = now().toUtc();
    final nonce = List.generate(
      8,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final entry = BackupSnapshot(
      path: '$folder/snapshot-${time.microsecondsSinceEpoch}-$nonce.json.gz',
      checksum: sha256.convert(bytes).toString(),
      complete: complete,
      createdAt: time.toIso8601String(),
    );
    if (!isCurrentAccount()) throw StateError('Account changed during backup.');
    await storage.write(entry.path, bytes, 'application/gzip');
    await download(entry);
    if (!isCurrentAccount()) throw StateError('Account changed during backup.');
    final retained = <BackupSnapshot>[entry, ...previous].take(3).toList();
    final completeFallback = previous.where((e) => e.complete).firstOrNull;
    if (!complete &&
        completeFallback != null &&
        !retained.any((e) => e.path == completeFallback.path)) {
      retained.add(completeFallback);
    }
    final manifest = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format_version': 1,
          'owner_id': owner,
          'device_id': device,
          'snapshots': retained.map((e) => e.toJson()).toList(),
        }),
      ),
    );
    final manifestPath = '$folder/manifest.json';
    await storage.write(manifestPath, manifest, 'application/json');
    final verified = await storage.read(manifestPath);
    if (sha256.convert(verified) != sha256.convert(manifest)) {
      throw const FormatException('Backup manifest verification failed.');
    }
    if (!isCurrentAccount()) throw StateError('Account changed during backup.');
    try {
      final keep = retained.map((e) => e.path).toSet();
      final obsolete = previous
          .where((e) => !keep.contains(e.path))
          .map((e) => e.path)
          .toSet();
      // Only this device's old, unreferenced objects are eligible. A grace period
      // preserves interrupted publications; complete legacy history is retained
      // until this device has a fully verified complete recovery point.
      if (complete) {
        final legacy =
            (await storage.list(owner))
                .where(
                  (o) =>
                      RegExp('^$device-[0-9]+\\.json\\.gz\$').hasMatch(o.name),
                )
                .toList()
              ..sort((a, b) => b.name.compareTo(a.name));
        obsolete.addAll(legacy.skip(3).map((o) => '$owner/${o.name}'));
      }
      for (final object in await storage.list(folder)) {
        final updated = DateTime.tryParse(object.updatedAt ?? '');
        final path = '$folder/${object.name}';
        if (_name.hasMatch(object.name) &&
            !keep.contains(path) &&
            updated != null &&
            time.difference(updated.toUtc()) > const Duration(days: 1)) {
          obsolete.add(path);
        }
      }
      if (!isCurrentAccount()) return;
      // Recheck the pointer immediately before deletion. Do not prune after a
      // competing publication, even if it came from a copied device identity.
      if (sha256.convert(await storage.read(manifestPath)) !=
          sha256.convert(manifest)) {
        return;
      }
      if (!isCurrentAccount()) return;
      final paths = obsolete.toList();
      for (var i = 0; i < paths.length; i += 100) {
        if (!isCurrentAccount()) return;
        await storage.remove(paths.skip(i).take(100).toList());
      }
    } catch (error) {
      // The verified recovery copy remains valid if optional cleanup fails.
      maintenanceError = 'Backup verified; old snapshot cleanup will retry.';
    }
  }

  Future<Map<String, List<BackupSnapshot>>> candidates(String owner) async {
    final result = <String, List<BackupSnapshot>>{};
    final legacy =
        (await storage.list(owner))
            .where(
              (o) =>
                  o.name.endsWith('.json.gz') &&
                  !o.name.contains('/') &&
                  !o.name.contains('\\') &&
                  !o.name.contains('..'),
            )
            .toList()
          ..sort((a, b) => (b.updatedAt ?? '').compareTo(a.updatedAt ?? ''));
    for (final object in legacy) {
      final device = object.name
          .replaceFirst(RegExp(r'\.json\.gz$'), '')
          .split('-')
          .first;
      (result[device] ??= []).add(
        BackupSnapshot(
          path: '$owner/${object.name}',
          createdAt: object.updatedAt ?? '',
        ),
      );
    }
    for (final object in await storage.list('$owner/devices')) {
      if (!_device.hasMatch(object.name)) continue;
      final folder = _folder(owner, object.name);
      List<BackupSnapshot> entries;
      try {
        entries = await _manifest(owner, object.name);
      } on FormatException {
        entries = [];
      }
      if (entries.isEmpty) {
        // Recover interrupted first publications and malformed manifests using
        // validated snapshot payloads, preserving the old recovery mechanism.
        entries =
            (await storage.list(folder))
                .where((o) => _name.hasMatch(o.name))
                .map(
                  (o) => BackupSnapshot(
                    path: '$folder/${o.name}',
                    createdAt: o.updatedAt ?? '',
                  ),
                )
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      result[object.name] = [...entries, ...?result[object.name]];
    }
    return result;
  }
}
