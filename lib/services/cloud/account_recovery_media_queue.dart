import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../evidence_storage_service.dart';

/// A download belongs to one evidence record and one account. Keeping the
/// expected record checksum prevents older snapshots replacing newer evidence.
class AccountRecoveryMedia {
  const AccountRecoveryMedia({
    required this.mediaId,
    required this.localPath,
    required this.bucket,
    required this.remotePath,
    required this.evidenceChecksum,
    this.checksum,
    this.thumbnail = false,
    this.restoredState = DatabaseCodes.evidenceStorageReady,
  });

  final String mediaId;
  final String localPath;
  final String bucket;
  final String remotePath;
  final String evidenceChecksum;
  final String? checksum;
  final bool thumbnail;
  final String restoredState;

  Map<String, Object?> toJson() => {
    'media_id': mediaId,
    'local_path': localPath,
    'bucket': bucket,
    'remote_path': remotePath,
    'evidence_checksum': evidenceChecksum,
    'checksum': checksum,
    'thumbnail': thumbnail,
    'restored_state': restoredState,
  };

  factory AccountRecoveryMedia.fromJson(Map<String, dynamic> value) =>
      AccountRecoveryMedia(
        mediaId: value['media_id'] as String,
        localPath: value['local_path'] as String,
        bucket: value['bucket'] as String,
        remotePath: value['remote_path'] as String,
        evidenceChecksum: value['evidence_checksum'] as String,
        checksum: value['checksum'] as String?,
        thumbnail: value['thumbnail'] == true,
        restoredState: value['restored_state'] as String,
      );
}

/// Persists unfinished downloads before records are published to the UI.
/// A failed file leaves the other downloads usable and retries on the next sync.
class AccountRecoveryMediaQueue {
  AccountRecoveryMediaQueue({
    required this.database,
    required this.evidenceStorage,
    required this.directory,
    required this.download,
  });

  final AppDatabase database;
  final EvidenceStorageService evidenceStorage;
  final Future<Directory> Function() directory;
  final Future<Uint8List> Function(String bucket, String path) download;
  final Map<String, Map<String, AccountRecoveryMedia>> _accounts = {};
  String? lastError;

  Future<Map<String, AccountRecoveryMedia>> _jobs(String ownerId) async {
    final loaded = _accounts[ownerId];
    if (loaded != null) {
      return loaded;
    }
    final file = await _file(ownerId);
    final jobs = <String, AccountRecoveryMedia>{};
    if (await file.exists()) {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map ||
          value['owner_id'] != ownerId ||
          value['jobs'] is! List) {
        throw const FormatException('Invalid account recovery queue.');
      }
      for (final raw in value['jobs'] as List) {
        final job = AccountRecoveryMedia.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
        // Validate local paths even when an entry came from a local manifest.
        await evidenceStorage.resolve(job.localPath);
        jobs[job.localPath] = job;
      }
    }
    return _accounts[ownerId] = jobs;
  }

  Future<File> _file(String ownerId) async {
    final root = await directory();
    await root.create(recursive: true);
    final key = sha256.convert(utf8.encode(ownerId));
    return File('${root.path}${Platform.pathSeparator}$key.media.json');
  }

  Future<void> _save(String ownerId) async {
    final file = await _file(ownerId);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'owner_id': ownerId,
        'jobs': _accounts[ownerId]!.values.map((job) => job.toJson()).toList(),
      }),
      flush: true,
    );
    // rename replaces a regular file atomically, including on Windows.
    await temporary.rename(file.path);
  }

  Future<void> enqueue(
    String ownerId,
    Iterable<AccountRecoveryMedia> media, {
    bool replaceExisting = true,
  }) async {
    final jobs = await _jobs(ownerId);
    for (final job in media) {
      await evidenceStorage.resolve(job.localPath);
      if (replaceExisting || !jobs.containsKey(job.localPath)) {
        jobs[job.localPath] = job;
      }
    }
    await _save(ownerId);
  }

  Future<int> pendingCount(String ownerId) async =>
      (await _jobs(ownerId)).length;

  Future<List<AccountRecoveryMedia>> entries(String ownerId) async =>
      (await _jobs(ownerId)).values.toList();

  Future<EvidenceMediaRecord?> _matchingRecord(AccountRecoveryMedia job) async {
    final row =
        await (database.select(database.evidenceMedia)..where(
              (row) => row.id.equals(job.mediaId) & row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (row == null || row.sha256Checksum != job.evidenceChecksum) {
      return null;
    }
    final path = job.thumbnail ? row.thumbnailLocalUri : row.localUri;
    return path == job.localPath ? row : null;
  }

  Future<bool> drain(
    String ownerId, {
    required bool Function() isCurrentAccount,
  }) async {
    lastError = null;
    final jobs = await _jobs(ownerId);
    // Thumbnails are small; restore them first without gating record recovery.
    final work = jobs.values.toList()
      ..sort((a, b) => (a.thumbnail ? 0 : 1).compareTo(b.thumbnail ? 0 : 1));
    for (final job in work) {
      if (!isCurrentAccount()) {
        return false;
      }
      try {
        final row = await _matchingRecord(job);
        if (row == null) {
          jobs.remove(job.localPath);
          await _save(ownerId);
          continue;
        }
        final file = await evidenceStorage.resolve(job.localPath);
        var matches = false;
        if (await file.exists()) {
          matches =
              job.checksum == null ||
              sha256.convert(await file.readAsBytes()).toString() ==
                  job.checksum;
        }
        if (!matches) {
          final bytes = await download(job.bucket, job.remotePath);
          final checksum = sha256.convert(bytes).toString();
          if (job.checksum != null && checksum != job.checksum) {
            throw const FormatException(
              'Recovered evidence checksum did not match.',
            );
          }
          // Authentication or the selected record may change during I/O.
          if (!isCurrentAccount() || await _matchingRecord(job) == null) {
            return false;
          }
          await file.parent.create(recursive: true);
          final temporary = File('${file.path}.restore.tmp');
          await temporary.writeAsBytes(bytes, flush: true);
          if (!isCurrentAccount()) {
            await temporary.delete();
            return false;
          }
          await temporary.rename(file.path);
          if (!job.thumbnail && row.sha256Checksum.isEmpty) {
            await (database.update(database.evidenceMedia)..where(
                  (media) =>
                      media.id.equals(row.id) & media.sha256Checksum.equals(''),
                ))
                .write(EvidenceMediaCompanion(sha256Checksum: Value(checksum)));
          }
        }
        if (!isCurrentAccount() || await _matchingRecord(job) == null) {
          return false;
        }
        if (!job.thumbnail) {
          await (database.update(database.evidenceMedia)..where(
                (media) => media.id.equals(row.id) & media.deletedAt.isNull(),
              ))
              .write(
                EvidenceMediaCompanion(storageState: Value(job.restoredState)),
              );
        }
        jobs.remove(job.localPath);
        await _save(ownerId);
        // Thumbnail completion also refreshes evidence viewers without changing
        // observation timestamps or scientific provenance.
        database.notifyUpdates({TableUpdate.onTable(database.evidenceMedia)});
      } catch (error) {
        lastError = 'Some evidence photos are still waiting to restore: $error';
      }
    }
    return jobs.isEmpty;
  }
}
