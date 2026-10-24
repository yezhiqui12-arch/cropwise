import 'account_snapshot_store.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide TableUpdate;

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../evidence_storage_service.dart';
import 'account_recovery_media_queue.dart';
import 'account_app_data_service.dart';

/// An account-scoped recovery copy of the local database and evidence files.
/// Nothing is removed from the phone when the account changes. The backup is
/// Records and evidence recover separately. Version 2 snapshots explicitly
/// record whether every referenced media file has reached account storage.
class WormWiseAccountBackupService {
  WormWiseAccountBackupService(
    this.database,
    this.client, {
    EvidenceStorageService? evidenceStorage,
    FlutterSecureStorage? secureStorage,
    this.localViewDirectory,
    AccountAppDataService? appData,
    this.onRecoveryProgress,
    AccountSnapshotStore? snapshotStore,
  }) : snapshotStore =
           snapshotStore ??
           AccountSnapshotStore(SupabaseBackupObjectStorage(client, bucket)),
       evidenceStorage = evidenceStorage ?? EvidenceStorageService(),
       secureStorage = secureStorage ?? const FlutterSecureStorage(),
       appData =
           appData ??
           AccountAppDataService(
             storage: secureStorage,
             directoryProvider: localViewDirectory == null
                 ? null
                 : () async => Directory('${localViewDirectory.path}/app-data'),
           );

  static const bucket = 'wormwise-account-backups';
  static const _deviceKey = 'wormwise_account_backup_device_id';
  static const _replaceLocalDataOnSignInKey =
      'wormwise_replace_local_data_on_account_sign_in';
  static const _activeLocalViewKey = 'wormwise_active_local_view';
  static const _pendingGuestTransferKey = 'wormwise_pending_guest_transfer';
  static const _guestView = 'guest';
  static const _formatVersion = 2;

  final AccountSnapshotStore snapshotStore;
  String? get lastBackupMaintenanceError => snapshotStore.maintenanceError;

  final AppDatabase database;
  final SupabaseClient client;
  final EvidenceStorageService evidenceStorage;
  final FlutterSecureStorage secureStorage;
  final AccountAppDataService appData;
  final void Function(String stage)? onRecoveryProgress;
  // Device readiness must never be restored from a cloud snapshot.
  static const localRecoveryPreferenceKey =
      'wormwise_local_account_recovery_v1';

  bool lastPublishedSnapshotComplete = false;
  void Function()? onSnapshotCapture;
  bool lastSnapshotHasData = false;
  bool _freshMediaVerification = false;
  Future<bool>? _restoringRecords;

  void requireFreshVerification() {
    _freshMediaVerification = true;
    _lastSnapshotChecksum = null;
    _uploadedMedia.clear();
    lastPublishedSnapshotComplete = false;
    appData.requireFreshMediaVerification();
  }

  final Directory? localViewDirectory;
  final Set<String> _restoredOwners = {};
  final Set<String> _uploadedMedia = {};
  Future<bool>? _synchronizing;
  Future<bool>? _synchronizingMedia;
  Future<bool>? _switchingView;
  String? _lastSnapshotChecksum;
  String? lastMediaError;
  String? lastRecordError;
  late final mediaQueue = AccountRecoveryMediaQueue(
    database: database,
    evidenceStorage: evidenceStorage,
    directory: _viewDirectory,
    download: (bucket, path) => client.storage.from(bucket).download(path),
  );

  bool _isCurrentAccount(String ownerId) =>
      client.auth.currentUser?.id == ownerId &&
      client.auth.currentUser?.isAnonymous == false;

  Future<bool> synchronize(String ownerId) {
    return _synchronizing ??= _synchronize(ownerId).whenComplete(() {
      _synchronizing = null;
    });
  }

  Future<bool> _synchronize(String ownerId) async {
    if (_switchingView != null) {
      await _switchingView;
    }
    if (_synchronizingMedia != null) {
      await _synchronizingMedia;
    }
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous || user.id != ownerId) {
      return false;
    }
    final replaceLocal =
        await secureStorage.read(key: _replaceLocalDataOnSignInKey) == 'true';
    final activeView = await secureStorage.read(key: _activeLocalViewKey);
    if (replaceLocal || (activeView != null && activeView != ownerId)) {
      await _switchLocalView(ownerId);
      await secureStorage.delete(key: _replaceLocalDataOnSignInKey);
    } else if (activeView == null) {
      // Existing installations already signed into an account own this view.
      await secureStorage.write(key: _activeLocalViewKey, value: ownerId);
    }
    await _applyPendingGuestTransfer(ownerId);
    await restoreEssentialRecords(ownerId);
    if (!_isCurrentAccount(ownerId)) {
      return false;
    }
    return _uploadRecords(ownerId);
  }

  /// Restores the account graph without waiting for photo uploads/downloads.
  Future<bool> restoreEssentialRecords(String ownerId) async {
    final running = _restoringRecords;
    if (running != null) {
      await running;
    }
    if (!_isCurrentAccount(ownerId)) {
      return false;
    }
    if (_restoredOwners.contains(ownerId)) {
      return true;
    }
    final operation = _restoreEssentialRecords(ownerId);
    _restoringRecords = operation;
    try {
      return await operation;
    } finally {
      if (identical(_restoringRecords, operation)) {
        _restoringRecords = null;
      }
    }
  }

  Future<bool> _restoreEssentialRecords(String ownerId) async {
    onRecoveryProgress?.call('Checking your saved backups');
    final recovered = await _restoreAccountRecords(ownerId);
    if (!_isCurrentAccount(ownerId)) {
      return false;
    }
    onRecoveryProgress?.call('Restoring linked guest history');
    await _restoreCloudSummaries(ownerId);
    if (!_isCurrentAccount(ownerId)) {
      return false;
    }
    if (recovered) {
      _restoredOwners.add(ownerId);
    }
    return recovered;
  }

  /// Called after structured cloud sync. Media errors never gate record import
  /// or prevent other photos from being recovered.
  Future<bool> synchronizeMedia(String ownerId) =>
      _synchronizingMedia ??= _synchronizeMedia(ownerId).whenComplete(() {
        _synchronizingMedia = null;
      });

  Future<bool> _synchronizeMedia(String ownerId) async {
    if (!_isCurrentAccount(ownerId)) {
      return false;
    }
    final restored = await mediaQueue.drain(
      ownerId,
      isCurrentAccount: () => _isCurrentAccount(ownerId),
    );
    if (!_isCurrentAccount(ownerId)) {
      return false;
    }
    final uploaded = await _uploadMedia(ownerId);
    final advisorMedia = await appData.synchronizeMedia(
      ownerId,
      client,
      bucket,
      isCurrentAccount: () => _isCurrentAccount(ownerId),
    );
    lastMediaError =
        mediaQueue.lastError ?? lastMediaError ?? appData.lastMediaError;
    await _uploadRecords(ownerId);
    return restored && uploaded && advisorMedia;
  }

  /// Switches the shared Drift database to an account before its screens load.
  /// The previous view is saved on this device for a later account/guest switch.
  Future<void> prepareAccountView(
    String ownerId, {
    bool assumeCurrentWhenUntracked = false,
  }) async {
    if (_synchronizing != null) {
      await _synchronizing;
    }
    if (_synchronizingMedia != null) {
      await _synchronizingMedia;
    }
    if (assumeCurrentWhenUntracked &&
        await secureStorage.read(key: _activeLocalViewKey) == null &&
        await secureStorage.read(key: _replaceLocalDataOnSignInKey) != 'true') {
      await secureStorage.write(key: _activeLocalViewKey, value: ownerId);
    } else {
      await _switchLocalView(ownerId);
    }
    await _applyPendingGuestTransfer(ownerId);
  }

  Future<void> beginGuestTransfer() async {
    final active = await secureStorage.read(key: _activeLocalViewKey);
    if (active != null && active != _guestView) {
      throw StateError('Open the guest profile before transferring it.');
    }
    await secureStorage.write(key: _pendingGuestTransferKey, value: 'true');
  }

  Future<void> cancelGuestTransfer() =>
      secureStorage.delete(key: _pendingGuestTransferKey);

  Future<void> _applyPendingGuestTransfer(String ownerId) async {
    if (await secureStorage.read(key: _pendingGuestTransferKey) != 'true') {
      return;
    }
    final active = await secureStorage.read(key: _activeLocalViewKey);
    if (active != ownerId) {
      return;
    }
    final guestFile = await _localViewFile(_guestView);
    if (!await guestFile.exists()) {
      throw const FormatException('Guest profile data could not be found.');
    }
    await _restoreLocalView(_guestView);
    await secureStorage.delete(key: _pendingGuestTransferKey);
    _lastSnapshotChecksum = null;
  }

  Future<void> prepareGuestView() async {
    if (_synchronizing != null) {
      await _synchronizing;
    }
    if (_synchronizingMedia != null) {
      await _synchronizingMedia;
    }
    await _switchLocalView(_guestView);
  }

  Future<bool> _switchLocalView(String target) async {
    if (_switchingView != null) {
      await _switchingView;
    }
    final operation = _performLocalViewSwitch(target);
    _switchingView = operation;
    try {
      return await operation;
    } finally {
      if (identical(_switchingView, operation)) {
        _switchingView = null;
      }
    }
  }

  Future<bool> _performLocalViewSwitch(String target) async {
    final current =
        await secureStorage.read(key: _activeLocalViewKey) ?? _guestView;
    if (current == target) {
      return false;
    }
    await _saveLocalView(current);
    try {
      await _clearLocalAccountView();
      await _restoreLocalView(target);
      await secureStorage.write(key: _activeLocalViewKey, value: target);
      _restoredOwners.remove(target);
      _lastSnapshotChecksum = null;
      return true;
    } catch (_) {
      await _clearLocalAccountView();
      await _restoreLocalView(current);
      rethrow;
    }
  }

  Future<Directory> _viewDirectory() async {
    final directory =
        localViewDirectory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}wormwise_local_views',
        );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _localViewFile(String view) async {
    final directory = await _viewDirectory();
    final name = sha256.convert(utf8.encode(view)).toString();
    return File('${directory.path}${Platform.pathSeparator}$name.json.gz');
  }

  Future<void> _saveLocalView(String view) async {
    final destination = await _localViewFile(view);
    final temporary = File('${destination.path}.tmp');
    final bytes = gzip.encode(
      utf8.encode(
        jsonEncode({
          'tables': await exportLocalTables(includeLocalRecovery: true),
          'app_data': await appData.capture(),
        }),
      ),
    );
    await temporary.writeAsBytes(bytes, flush: true);
    final previous = File('${destination.path}.bak');
    if (await previous.exists()) {
      await previous.delete();
    }
    if (await destination.exists()) {
      await destination.rename(previous.path);
    }
    try {
      await temporary.rename(destination.path);
    } catch (_) {
      if (await previous.exists()) {
        await previous.rename(destination.path);
      }
      rethrow;
    }
    if (await previous.exists()) {
      await previous.delete();
    }
  }

  Future<void> _restoreLocalView(String view) async {
    final file = await _localViewFile(view);
    if (!await file.exists()) {
      return;
    }
    final decoded = jsonDecode(
      utf8.decode(gzip.decode(await file.readAsBytes())),
    );
    if (decoded is! Map) {
      throw const FormatException('The saved local profile is invalid.');
    }
    await restoreLocalTables(
      decoded['tables'] is Map ? decoded['tables'] as Map : decoded,
      includeLocalRecovery: true,
    );
    if (decoded['app_data'] != null) {
      await appData.restore(decoded['app_data']);
    }
  }

  Future<void> _clearLocalAccountView() async {
    await database.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await database.transaction(() async {
        for (final table in database.allTables.toList().reversed) {
          await database.customStatement(
            'DELETE FROM "${table.actualTableName}"',
          );
        }
      });
    } finally {
      await database.customStatement('PRAGMA foreign_keys = ON');
    }
    await appData.restore(null, replace: true);
    database.notifyUpdates({
      for (final table in database.allTables) TableUpdate.onTable(table),
    });
  }

  Future<bool> _restoreAccountRecords(String ownerId) async {
    lastRecordError = null;
    final byDevice = await snapshotStore.candidates(ownerId);
    // Protect unsynchronized edits already present on this phone.
    final protectedRows = await _pendingLocalRows();
    final errors = <Object>[];
    for (final candidates in byDevice.values) {
      Object? failure;
      var restored = false;
      for (final snapshot in candidates) {
        try {
          final compressed = await snapshotStore.download(snapshot);
          if (!_isCurrentAccount(ownerId)) {
            throw StateError('Account changed during recovery.');
          }
          final decoded = jsonDecode(utf8.decode(gzip.decode(compressed)));
          await restoreSnapshotRecords(
            ownerId,
            decoded,
            protectedRows: protectedRows,
          );
          restored = true;
          break;
        } catch (error) {
          failure ??= error;
          if (!_isCurrentAccount(ownerId)) {
            rethrow;
          }
        }
      }
      // An older fallback is useful, but recovery remains incomplete until
      // the preferred snapshot succeeds. Keep retrying it on future syncs.
      if (failure != null) {
        errors.add(failure);
      }
      if (!restored && failure == null) {
        errors.add(StateError('No recoverable snapshot was available.'));
      }
    }
    if (errors.isNotEmpty) {
      lastRecordError =
          'Some account records are still waiting to recover: ${errors.first}';
    }
    return errors.isEmpty;
  }

  /// Imports a validated snapshot before any photo I/O. The durable queue is
  /// written first so an interruption after the transaction can resume media.
  Future<void> restoreSnapshotRecords(
    String ownerId,
    Object? decoded, {
    Map<String, Set<String>> protectedRows = const {},
  }) async {
    if (decoded is! Map<String, dynamic> ||
        !{1, _formatVersion}.contains(decoded['format_version']) ||
        !(decoded['schema_version'] is int &&
            decoded['schema_version'] >= 7 &&
            decoded['schema_version'] <= database.schemaVersion) ||
        decoded['owner_id'] != ownerId ||
        decoded['tables'] is! Map ||
        decoded['media'] is! List ||
        !(_hasRecoverableRecords(decoded['tables'] as Map) ||
            appData.hasData(decoded['app_data']))) {
      throw const FormatException('The account backup is incompatible.');
    }
    appData.validate(decoded['app_data']);
    final manifest = <String, String>{};
    for (final item in decoded['media'] as List) {
      if (item is! Map ||
          item['path'] is! String ||
          item['sha256'] is! String) {
        throw const FormatException('Invalid evidence entry in backup.');
      }
      final path = item['path'] as String;
      await evidenceStorage.resolve(path);
      manifest[path] = item['sha256'] as String;
    }
    final jobs = <AccountRecoveryMedia>[];
    final rawMedia = (decoded['tables'] as Map)['evidence_media'];
    if (rawMedia is List) {
      for (final raw in rawMedia) {
        if (raw is! Map || raw['deleted_at'] != null) {
          continue;
        }
        final id = raw['id'] as String;
        final checksum = raw['sha256_checksum'] as String;
        for (final thumbnail in [false, true]) {
          final path = raw[thumbnail ? 'thumbnail_local_uri' : 'local_uri'];
          if (path is! String || !manifest.containsKey(path)) {
            continue;
          }
          jobs.add(
            AccountRecoveryMedia(
              mediaId: id,
              localPath: path,
              bucket: bucket,
              remotePath: '$ownerId/evidence/$path',
              evidenceChecksum: checksum,
              checksum: manifest[path],
              thumbnail: thumbnail,
              restoredState:
                  raw['storage_state'] as String? ??
                  DatabaseCodes.evidenceStorageReady,
            ),
          );
        }
      }
    }
    // Enqueue only after validation; importing the graph is one transaction.
    await mediaQueue.enqueue(ownerId, jobs, replaceExisting: false);
    onRecoveryProgress?.call('Restoring fields and assessments');
    await restoreLocalTables(
      decoded['tables'] as Map,
      reconcileNewer: true,
      protectedRows: protectedRows,
    );
    if (decoded['app_data'] != null) {
      onRecoveryProgress?.call('Restoring chats and settings');
      await appData.restore(decoded['app_data']);
    }
    final selected = {
      for (final row in await database.select(database.evidenceMedia).get())
        row.id: row,
    };
    final matchingJobs = jobs.where((job) {
      final row = selected[job.mediaId];
      return row != null &&
          row.deletedAt == null &&
          row.sha256Checksum == job.evidenceChecksum &&
          (job.thumbnail ? row.thumbnailLocalUri : row.localUri) ==
              job.localPath;
    }).toList();
    await mediaQueue.enqueue(ownerId, matchingJobs);
    if (!_freshMediaVerification &&
        (decoded['format_version'] == 1 || decoded['media_complete'] == true)) {
      for (final job in matchingJobs) {
        _uploadedMedia.add(
          '$ownerId/evidence/${job.localPath}:${job.checksum}',
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _cloudRows(
    String table,
    String ownerId,
  ) async {
    final rows = <Map<String, dynamic>>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final page = await client
          .from(table)
          .select()
          .eq('owner_id', ownerId)
          .order('id')
          .range(offset, offset + pageSize - 1);
      rows.addAll(page.map((row) => Map<String, dynamic>.from(row)));
      if (page.length < pageSize) {
        return rows;
      }
    }
  }

  Future<void> _restoreCloudSummaries(String ownerId) async {
    final own = await Future.wait([
      for (final table in [
        'fields',
        'field_boundaries',
        'assessments',
        'assessment_stations',
        'evidence_files',
      ])
        _cloudRows(table, ownerId),
    ]);
    if (!_isCurrentAccount(ownerId)) {
      throw StateError('Account changed during recovery.');
    }
    await restoreLinkedGuestCloudRecords([
      {
        'guest_id': ownerId,
        'fields': own[0],
        'boundaries': own[1],
        'assessments': own[2],
        'stations': own[3],
        'evidence': own[4],
      },
    ], ownerId: ownerId);
    try {
      final linked = await client.rpc('linked_guest_cloud_records');
      if (!_isCurrentAccount(ownerId)) {
        throw StateError('Account changed during recovery.');
      }
      await restoreLinkedGuestCloudRecords(linked, ownerId: ownerId);
    } on PostgrestException catch (error) {
      // Backups remain recoverable on installations predating guest links.
      if (!{'PGRST202', '42883'}.contains(error.code)) {
        rethrow;
      }
    }
  }

  /// Also used by schema round-trip tests without contacting Supabase.
  Future<bool> restoreLinkedGuestCloudRecords(
    Object? response, {
    String? ownerId,
  }) async {
    if (response is! List || response.isEmpty) {
      return false;
    }
    var restoredAny = false;
    for (final rawSource in response) {
      if (rawSource is! Map) {
        continue;
      }
      final guestId = rawSource['guest_id']?.toString();
      if (guestId == null) {
        continue;
      }
      List<Map<String, dynamic>> rows(String key) => [
        for (final item
            in rawSource[key] is List ? rawSource[key] as List : const [])
          if (item is Map) Map<String, dynamic>.from(item),
      ];

      final fields = rows('fields');
      final boundaries = rows('boundaries');
      final assessments = rows('assessments');
      final stations = rows('stations');
      final evidence = rows('evidence');
      if (fields.isEmpty) {
        continue;
      }
      restoredAny = true;

      // Full snapshots are authoritative. Cloud relational rows contain only
      // summaries and must not create duplicate cycles or replace plant graphs.
      final existingFields = {
        for (final field in await database.select(database.fields).get())
          field.id: field,
      };
      final existingAssessments = {
        for (final assessment
            in await database.select(database.assessments).get())
          assessment.id,
      };
      final existingCycles = await database.select(database.cropCycles).get();
      final existingBlocks = await database.select(database.fieldBlocks).get();
      final missingAssessments = assessments
          .where((row) => !existingAssessments.contains(row['id']?.toString()))
          .toList();
      final neededFields = {
        for (final row in fields)
          if (!existingFields.containsKey(row['id']?.toString()))
            row['id']?.toString(),
        for (final row in missingAssessments) row['field_id']?.toString(),
      };
      if (neededFields.isEmpty) {
        continue;
      }

      final personId = 'recovered-person-$guestId';
      final imported = <String, List<Map<String, dynamic>>>{
        'people': [
          {'id': personId, 'display_name': 'Recovered field evaluator'},
        ],
        'fields': [],
        'field_boundary_versions': [],
        'crop_cycles': [],
        'field_blocks': [],
        'assessments': [],
        'assessment_block_runs': [],
        'stations': [],
        'evidence_media': [],
        'metric_results': [],
        'app_preferences': [],
      };
      final fieldIds = <String>{};
      for (final field in fields) {
        final id = field['id']?.toString();
        if (id == null || !neededFields.contains(id)) {
          continue;
        }
        // A local tombstone must not be revived by a summary fallback.
        if (existingFields[id]?.deletedAt != null) {
          continue;
        }
        fieldIds.add(id);
        imported['fields']!.add({
          'id': id,
          'owner_person_id': personId,
          'name': field['name']?.toString() ?? 'Recovered field',
          'barangay': field['barangay'],
          'municipality_city': field['municipality_city'],
          'province': field['province'],
          'location_description': null,
          'is_archived': field['status'] == 'archived' ? 1 : 0,
          'deleted_at': field['status'] == 'deleted'
              ? _sqliteTime(field['client_updated_at'] ?? field['updated_at'])
              : null,
          'sync_state': DatabaseCodes.synced,
          'created_at': _sqliteTime(field['created_at']),
          'updated_at': _sqliteTime(
            field['client_updated_at'] ?? field['updated_at'],
          ),
        });
        imported['crop_cycles']!.add({
          'id': 'recovered-cycle-$id',
          'field_id': id,
          'status':
              existingCycles.any(
                (cycle) => cycle.fieldId == id && cycle.status == 'active',
              )
              ? 'recovered'
              : 'active',
          'sync_state': DatabaseCodes.synced,
        });
      }
      if (fieldIds.isNotEmpty) {
        imported['app_preferences']!.add({
          'preference_key': 'active_field_id',
          'preference_value': fieldIds.first,
          'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        });
      }
      final boundariesByField = <String, List<Map<String, dynamic>>>{};
      for (final boundary in boundaries) {
        final id = boundary['id']?.toString();
        final fieldId = boundary['field_id']?.toString();
        if (id == null || fieldId == null || !fieldIds.contains(fieldId)) {
          continue;
        }
        (boundariesByField[fieldId] ??= []).add(boundary);
        imported['field_boundary_versions']!.add({
          'id': id,
          'field_id': fieldId,
          'version_number': boundary['version_number'],
          'geometry_geojson': jsonEncode(boundary['geometry_geojson']),
          'area_hectares': _asDouble(boundary['area_hectares']),
          'centroid_latitude': boundary['centroid_latitude'],
          'centroid_longitude': boundary['centroid_longitude'],
          'source_method': boundary['source_method']?.toString() ?? 'recovered',
          'sync_state': DatabaseCodes.synced,
          'created_at': _sqliteTime(boundary['created_at']),
          'updated_at': _sqliteTime(boundary['updated_at']),
        });
      }
      for (final field in imported['fields']!) {
        final versions = boundariesByField[field['id']] ?? [];
        versions.sort(
          (a, b) => (a['version_number'] as int).compareTo(
            b['version_number'] as int,
          ),
        );
        if (versions.isNotEmpty) {
          field['active_boundary_version_id'] = versions.last['id'];
        }
      }
      final assessmentIds = <String>{};
      final runsByAssessment = <String, List<String>>{};
      final blockNumberByField = <String, int>{};
      for (final fieldId in fieldIds) {
        blockNumberByField[fieldId] = existingBlocks
            .where((block) => block.cropCycleId == 'recovered-cycle-$fieldId')
            .fold(0, (number, block) => max(number, block.blockNumber));
      }
      for (final assessment in missingAssessments) {
        final id = assessment['id']?.toString();
        final fieldId = assessment['field_id']?.toString();
        if (id == null || fieldId == null || !fieldIds.contains(fieldId)) {
          continue;
        }
        final fieldBoundaries = boundariesByField[fieldId] ?? const [];
        if (fieldBoundaries.isEmpty) {
          continue;
        }
        final preferred = assessment['boundary_id']?.toString();
        final boundaryId = fieldBoundaries.any((b) => b['id'] == preferred)
            ? preferred!
            : fieldBoundaries.last['id'].toString();
        assessmentIds.add(id);
        final snapshot = assessment['result_snapshot'] is Map
            ? Map<String, dynamic>.from(assessment['result_snapshot'] as Map)
            : <String, dynamic>{};
        imported['assessments']!.add({
          'id': id,
          'crop_cycle_id': 'recovered-cycle-$fieldId',
          'boundary_version_id': boundaryId,
          'evaluator_person_id': personId,
          'assessment_type': DatabaseCodes.formal,
          'status': assessment['status'] == 'submitted'
              ? DatabaseCodes.completed
              : assessment['status']?.toString() ?? DatabaseCodes.draft,
          'assessment_mode': 'recovered_cloud_summary',
          'scouting_pattern': 'recovered',
          'growth_stage': assessment['growth_stage']?.toString() ?? 'unknown',
          'protocol_version':
              assessment['protocol_version']?.toString() ?? 'recovered',
          'formula_version':
              assessment['formula_version']?.toString() ?? 'recovered',
          'preferred_language':
              snapshot['preferred_language']?.toString() ?? 'en',
          'validation_status': 'recovered_summary',
          'started_at': _sqliteTime(assessment['started_at']),
          'completed_at': _sqliteTime(assessment['completed_at']),
          'created_at': _sqliteTime(assessment['created_at']),
          'updated_at': _sqliteTime(
            assessment['client_updated_at'] ?? assessment['updated_at'],
          ),
          'completion_note':
              'Recovered from the earlier cloud sync. Individual plant observations may be unavailable.',
          'sync_state': DatabaseCodes.synced,
        });
        final metrics = snapshot['metrics'] is List
            ? snapshot['metrics'] as List
            : const [];
        final routes = snapshot['sampling_routes'] is List
            ? snapshot['sampling_routes'] as List
            : const [];
        final runIds = <String>{
          for (final route in routes)
            if (route is Map && route['block_run_id'] is String)
              route['block_run_id'] as String,
          for (final metric in metrics)
            if (metric is Map &&
                metric['scope_type'] == 'block' &&
                metric['scope_id'] is String)
              metric['scope_id'] as String,
          for (final station in stations)
            if (station['assessment_id'] == id &&
                station['block_run_id'] is String)
              station['block_run_id'] as String,
        };
        if (runIds.isEmpty) {
          runIds.add('recovered-run-$id');
        }
        runsByAssessment[id] = runIds.toList();
        final boundary = fieldBoundaries.firstWhere(
          (row) => row['id'] == boundaryId,
        );
        var sequence = 0;
        for (final runId in runIds) {
          sequence++;
          final blockNumber = (blockNumberByField[fieldId] ?? 0) + 1;
          blockNumberByField[fieldId] = blockNumber;
          final blockId = 'recovered-block-$id-$sequence';
          imported['field_blocks']!.add({
            'id': blockId, 'crop_cycle_id': 'recovered-cycle-$fieldId',
            'boundary_version_id': boundaryId, 'block_number': blockNumber,
            'geometry_geojson': jsonEncode(boundary['geometry_geojson']),
            // Original block outlines and areas are absent from relational
            // summaries. Do not invent surveyed geometry or block acreage.
            'area_hectares': 0.0, 'is_provisional': 1,
            'separation_reason':
                'Recovered summary; original block geometry unavailable.',
            'sync_state': DatabaseCodes.synced,
          });
          final matchingRoutes = routes.where(
            (route) => route is Map && route['block_run_id'] == runId,
          );
          final route = matchingRoutes.isEmpty
              ? null
              : matchingRoutes.first as Map;
          imported['assessment_block_runs']!.add({
            'id': runId,
            'assessment_id': id,
            'field_block_id': blockId,
            'block_sequence': route?['block_sequence'] ?? sequence,
            'scouting_pattern':
                route?['scouting_pattern'] ??
                snapshot['scouting_pattern'] ??
                'recovered',
            'route_geojson': route?['route_geojson'] == null
                ? null
                : jsonEncode(route!['route_geojson']),
            'status': assessment['status'] == 'draft' ? 'draft' : 'completed',
            'sync_state': DatabaseCodes.synced,
          });
        }
        var metricNumber = 0;
        for (final metric in metrics) {
          if (metric is! Map ||
              metric['scope_type'] != 'block' ||
              metric['metric_code'] is! String) {
            continue;
          }
          final scopeId =
              metric['scope_id']?.toString() ??
              (runIds.length == 1 ? runIds.first : null);
          if (!runIds.contains(scopeId)) {
            continue;
          }
          imported['metric_results']!.add({
            'id': 'recovered-metric-$id-${metricNumber++}',
            'assessment_id': id,
            'scope_type': 'block',
            'scope_id': scopeId,
            'metric_code': metric['metric_code'],
            'numerator': metric['numerator'],
            'denominator': metric['denominator'],
            'value': metric['value'],
            'unit': metric['unit']?.toString() ?? 'percent',
            'formula_version':
                metric['formula_version'] ??
                assessment['formula_version'] ??
                'recovered',
            'validation_status': metric['validation_status'] ?? 'provisional',
            'warning_code': 'recovered_cloud_summary',
            'calculated_at':
                _sqliteTime(
                  assessment['completed_at'] ??
                      assessment['updated_at'] ??
                      assessment['created_at'],
                ) ??
                DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
            'sync_state': DatabaseCodes.synced,
          });
        }
      }
      final stationByAssessmentNumber = <String, String>{};
      final stationSequence = <String, int>{};
      for (final station in stations) {
        final id = station['id']?.toString();
        final assessmentId = station['assessment_id']?.toString();
        if (id == null ||
            assessmentId == null ||
            !assessmentIds.contains(assessmentId)) {
          continue;
        }
        final runIds = runsByAssessment[assessmentId]!;
        final runId = runIds.contains(station['block_run_id'])
            ? station['block_run_id'] as String
            : runIds.first;
        final number = (stationSequence[runId] ?? 0) + 1;
        stationSequence[runId] = number;
        stationByAssessmentNumber.putIfAbsent(
          '$assessmentId:${station['station_number']}',
          () => id,
        );
        imported['stations']!.add({
          'id': id,
          'assessment_block_run_id': runId,
          'station_number': station['station_number'] ?? number,
          'latitude': station['latitude'],
          'longitude': station['longitude'],
          'gps_accuracy_m': station['gps_accuracy_m'],
          'location_source': station['location_source'] ?? 'unverified',
          'location_captured_at': _sqliteTime(station['location_captured_at']),
          'captured_at': _sqliteTime(station['captured_at']),
          'sync_state': DatabaseCodes.synced,
        });
      }
      for (final item in evidence) {
        final id = item['id']?.toString();
        final assessmentId = item['assessment_id']?.toString();
        final remotePath = item['storage_path']?.toString();
        if (id == null ||
            assessmentId == null ||
            remotePath == null ||
            !assessmentIds.contains(assessmentId)) {
          continue;
        }
        final mime = item['mime_type']?.toString() ?? 'image/jpeg';
        final extension = mime == 'image/png'
            ? 'png'
            : mime == 'image/webp'
            ? 'webp'
            : 'jpg';
        final relativePath = 'recovered/$assessmentId/$id.$extension';
        imported['evidence_media']!.add({
          'id': id,
          'assessment_id': assessmentId,
          'station_id':
              stationByAssessmentNumber['$assessmentId:${item['station_number']}'],
          'media_type': 'image',
          'view_type': 'recovered',
          'local_uri': relativePath,
          'remote_uri': remotePath,
          'mime_type': mime,
          'sha256_checksum': item['sha256']?.toString() ?? '',
          'captured_at': _sqliteTime(item['captured_at']),
          'storage_state': DatabaseCodes.evidenceStorageReady,
          'sync_state': DatabaseCodes.synced,
        });
      }
      if (ownerId != null) {
        await mediaQueue.enqueue(ownerId, [
          for (final row in imported['evidence_media']!)
            AccountRecoveryMedia(
              mediaId: row['id'] as String,
              localPath: row['local_uri'] as String,
              bucket: 'assessment-evidence',
              remotePath: row['remote_uri'] as String,
              evidenceChecksum: row['sha256_checksum'] as String,
              checksum: (row['sha256_checksum'] as String).isEmpty
                  ? null
                  : row['sha256_checksum'] as String,
            ),
        ]);
      }
      await restoreLocalTables(imported);
    }
    return restoredAny;
  }

  int? _sqliteTime(Object? value) {
    if (value == null) {
      return null;
    }
    return DateTime.parse(value.toString()).millisecondsSinceEpoch ~/ 1000;
  }

  double _asDouble(Object? value) =>
      value is num ? value.toDouble() : double.parse(value.toString());

  String _rowKey(Map row, List<String> primaryKeys) =>
      jsonEncode(primaryKeys.map((key) => row[key]).toList());

  Future<Map<String, Set<String>>> _pendingLocalRows() async {
    final protected = <String, Set<String>>{};
    for (final table in database.allTables) {
      final name = table.actualTableName;
      final schema = await database
          .customSelect('PRAGMA table_info("$name")')
          .get();
      if (!schema.any((column) => column.data['name'] == 'sync_state')) {
        continue;
      }
      final keys = schema
          .where((column) => (column.data['pk'] as int) > 0)
          .map((column) => column.data['name'] as String)
          .toList();
      final rows = await database
          .customSelect(
            'SELECT * FROM "$name" WHERE sync_state <> ?',
            variables: [Variable(DatabaseCodes.synced)],
          )
          .get();
      protected[name] = rows.map((row) => _rowKey(row.data, keys)).toSet();
    }
    return protected;
  }

  /// Full snapshots reconcile newer versions; summary fallbacks only fill
  /// gaps. Existing unsynchronized edits and newer deletion tombstones win.
  Future<void> restoreLocalTables(
    Map rawTables, {
    bool reconcileNewer = false,
    bool includeLocalRecovery = false,
    Map<String, Set<String>> protectedRows = const {},
  }) async {
    await database.transaction(() async {
      await database.customStatement('PRAGMA defer_foreign_keys = ON');
      // Replace only untouched summary projections before importing a complete
      // graph. Their synthetic run sequence would otherwise collide with real
      // runs. Never discard a projection to which local observations were added.
      final incomingAssessments = rawTables['assessments'];
      if (reconcileNewer && incomingAssessments is List) {
        for (final incoming
            in incomingAssessments.whereType<Map<String, dynamic>>()) {
          if (incoming['assessment_mode'] == 'recovered_cloud_summary' ||
              protectedRows['assessments']?.contains(
                    _rowKey(incoming, ['id']),
                  ) ==
                  true) {
            continue;
          }
          final previous = await database
              .customSelect(
                "SELECT * FROM assessments WHERE id = ? AND assessment_mode = 'recovered_cloud_summary' AND deleted_at IS NULL",
                variables: [Variable<String>(incoming['id'] as String)],
              )
              .getSingleOrNull();
          if (previous == null) {
            continue;
          }
          final stations = await database
              .customSelect(
                '''
            SELECT stations.id FROM stations
            JOIN assessment_block_runs runs ON runs.id = stations.assessment_block_run_id
            WHERE runs.assessment_id = ?
          ''',
                variables: [Variable<String>(incoming['id'] as String)],
              )
              .get();
          var untouched = true;
          for (final station in stations) {
            for (final table in [
              'plant_observations',
              'planting_unit_observations',
            ]) {
              final count = await database
                  .customSelect(
                    'SELECT 1 FROM "$table" WHERE station_id = ? LIMIT 1',
                    variables: [Variable<String>(station.read<String>('id'))],
                  )
                  .get();
              if (count.isNotEmpty) {
                untouched = false;
              }
            }
          }
          if (!untouched) {
            throw const FormatException(
              'Recovered history has local observations; automatic replacement was stopped.',
            );
          }
          await database.customStatement(
            '''
            UPDATE evidence_media SET station_id = NULL
            WHERE assessment_id = ? AND view_type = 'recovered'
          ''',
            [incoming['id']],
          );
          await database.customStatement(
            '''
            DELETE FROM stations WHERE assessment_block_run_id IN
              (SELECT id FROM assessment_block_runs WHERE assessment_id = ?)
          ''',
            [incoming['id']],
          );
          await database.customStatement(
            'DELETE FROM assessment_block_runs WHERE assessment_id = ?',
            [incoming['id']],
          );
          await database.customStatement(
            "DELETE FROM metric_results WHERE assessment_id = ? AND id LIKE 'recovered-metric-%'",
            [incoming['id']],
          );
        }
      }
      for (final table in database.allTables) {
        final name = table.actualTableName;
        if (name == 'sync_outbox') {
          continue;
        }
        final rawRows = rawTables[name];
        if (rawRows is! List) {
          continue;
        }
        final schema = await database
            .customSelect('PRAGMA table_info("$name")')
            .get();
        final allowedColumns = schema
            .map((row) => row.data['name'])
            .whereType<String>()
            .toSet();
        final primaryKeys = schema
            .where((column) => (column.data['pk'] as int) > 0)
            .map((column) => column.data['name'] as String)
            .toList();
        final existing = {
          for (final row
              in await database.customSelect('SELECT * FROM "$name"').get())
            _rowKey(row.data, primaryKeys): row.data,
        };
        for (final sourceRow in rawRows) {
          if (sourceRow is! Map<String, dynamic> ||
              sourceRow.isEmpty ||
              !allowedColumns.containsAll(sourceRow.keys) ||
              !sourceRow.keys.toSet().containsAll(primaryKeys)) {
            throw const FormatException('Invalid record in account backup.');
          }
          // Decode/copy into a mutable nullable-value map before normalization;
          // callers may supply Map<String, String> or an immutable typed map.
          final rawRow = Map<String, dynamic>.from(sourceRow);
          // Retired form fields must not return through an older backup.
          if (name == 'fields') rawRow['location_description'] = null;
          if (name == 'crop_cycles') rawRow['intended_use'] = null;
          if (!includeLocalRecovery &&
              name == 'app_preferences' &&
              rawRow['preference_key'] == localRecoveryPreferenceKey) {
            continue;
          }
          final columns = rawRow.keys.toList();
          final key = _rowKey(rawRow, primaryKeys);
          final previous = existing[key];
          if (previous != null) {
            if (!reconcileNewer || protectedRows[name]?.contains(key) == true) {
              continue;
            }
            final promotedSummary =
                name == 'assessments' &&
                previous['assessment_mode'] == 'recovered_cloud_summary' &&
                rawRow['assessment_mode'] != 'recovered_cloud_summary';
            final promotedField =
                name == 'fields' &&
                previous['owner_person_id']?.toString().startsWith(
                      'recovered-person-',
                    ) ==
                    true &&
                rawRow['owner_person_id']?.toString().startsWith(
                      'recovered-person-',
                    ) !=
                    true;
            int version(Map row) {
              final updated = row['updated_at'] as int? ?? 0;
              final deleted = row['deleted_at'] as int? ?? 0;
              return max(updated, deleted);
            }

            if (!promotedSummary &&
                !promotedField &&
                version(rawRow) <= version(previous)) {
              continue;
            }
            // A complete graph may replace a fallback summary at the same
            // timestamp, but never resurrect a newer deliberate deletion.
            if (previous['deleted_at'] != null &&
                version(rawRow) <= version(previous)) {
              continue;
            }
            final changed = columns
                .where((column) => !primaryKeys.contains(column))
                .toList();
            if (changed.isEmpty) {
              continue;
            }
            await database.customStatement(
              'UPDATE "$name" SET ${changed.map((column) => '"$column" = ?').join(', ')} '
              'WHERE ${primaryKeys.map((column) => '"$column" = ?').join(' AND ')}',
              [
                ...changed.map((column) => rawRow[column]),
                ...primaryKeys.map((column) => rawRow[column]),
              ],
            );
            existing[key] = {...previous, ...rawRow};
            continue;
          }
          final quoted = columns.map((column) => '"$column"').join(', ');
          final placeholders = List.filled(columns.length, '?').join(', ');
          await database.customStatement(
            'INSERT INTO "$name" ($quoted) VALUES ($placeholders)',
            columns.map((column) => rawRow[column]).toList(),
          );
          existing[key] = rawRow;
        }
      }
      // A later complete snapshot can replace a recovered assessment graph.
      // Keep its historical fallback cycle, but stop it duplicating workspaces.
      await database.customStatement('''
        UPDATE crop_cycles SET status = 'recovered'
        WHERE id LIKE 'recovered-cycle-%' AND status = 'active'
          AND EXISTS (SELECT 1 FROM crop_cycles actual
            WHERE actual.field_id = crop_cycles.field_id
              AND actual.id NOT LIKE 'recovered-cycle-%'
              AND actual.status = 'active' AND actual.deleted_at IS NULL)
      ''');
    });
    database.notifyUpdates({
      for (final table in database.allTables) TableUpdate.onTable(table),
    });
  }

  Future<bool> _uploadRecords(String ownerId) async {
    lastPublishedSnapshotComplete = false;
    lastSnapshotHasData = false;
    if (!_isCurrentAccount(ownerId)) {
      return false;
    }
    onSnapshotCapture?.call();
    final tables = await exportLocalTables();
    final accountAppData = await appData.capture();
    final appMediaComplete = await appData.mediaComplete(ownerId);
    // Never replace a usable cloud recovery copy with an empty local database.
    // This also covers a user clearing app data while still signed in.
    if (!_hasRecoverableRecords(tables) && !appData.hasData(accountAppData)) {
      return false;
    }
    lastSnapshotHasData = true;
    final deviceId = await _deviceId();
    final media = <Map<String, String>>[];
    var mediaComplete = true;
    final pending = {
      for (final job in await mediaQueue.entries(ownerId)) job.localPath: job,
    };
    final records = await database.select(database.evidenceMedia).get();
    for (final record in records) {
      if (record.deletedAt != null) {
        continue;
      }
      for (final relativePath in [
        record.localUri,
        if (record.thumbnailLocalUri != null) record.thumbnailLocalUri!,
      ]) {
        String? checksum = relativePath == record.localUri
            ? record.sha256Checksum
            : pending[relativePath]?.checksum;
        if (checksum == null || checksum.isEmpty) {
          final file = await evidenceStorage.resolve(relativePath);
          if (await file.exists()) {
            checksum = sha256.convert(await file.readAsBytes()).toString();
          }
        }
        if (checksum == null || checksum.isEmpty) {
          mediaComplete = false;
          continue;
        }
        media.add({'path': relativePath, 'sha256': checksum});
        if (!_uploadedMedia.contains(
          '$ownerId/evidence/$relativePath:$checksum',
        )) {
          mediaComplete = false;
        }
      }
    }

    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'tables': tables,
              'app_data': accountAppData,
              'app_media_complete': appMediaComplete,
              'media': media,
              'media_complete': mediaComplete,
              'records_complete': lastRecordError == null,
            }),
          ),
        )
        .toString();
    final complete =
        mediaComplete && appMediaComplete && lastRecordError == null;
    if (_lastSnapshotChecksum == fingerprint) {
      lastPublishedSnapshotComplete = complete;
      return true;
    }
    final payload = <String, dynamic>{
      'format_version': _formatVersion,
      'schema_version': database.schemaVersion,
      'owner_id': ownerId,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
      'app_data': accountAppData,
      'app_media_complete': appMediaComplete,
      'media': media,
      'media_complete': mediaComplete,
      'records_complete': lastRecordError == null,
    };
    final compressed = Uint8List.fromList(
      gzip.encode(utf8.encode(jsonEncode(payload))),
    );
    await snapshotStore.publish(
      owner: ownerId,
      device: deviceId,
      bytes: compressed,
      complete: complete,
      isCurrentAccount: () => _isCurrentAccount(ownerId),
    );
    if (!_isCurrentAccount(ownerId)) return false;
    _lastSnapshotChecksum = fingerprint;
    lastPublishedSnapshotComplete = complete;
    return true;
  }

  Future<bool> _uploadMedia(String ownerId) async {
    lastMediaError = null;
    var complete = true;
    final storage = client.storage.from(bucket);
    final records = await database.select(database.evidenceMedia).get();
    for (final record in records) {
      if (record.deletedAt != null) {
        continue;
      }
      for (final path in [
        record.localUri,
        if (record.thumbnailLocalUri != null) record.thumbnailLocalUri!,
      ]) {
        if (!_isCurrentAccount(ownerId)) {
          return false;
        }
        try {
          final remotePath = '$ownerId/evidence/$path';
          if (path == record.localUri &&
              _uploadedMedia.contains('$remotePath:${record.sha256Checksum}')) {
            continue;
          }
          final file = await evidenceStorage.resolve(path);
          if (!await file.exists()) {
            throw const FileSystemException(
              'Evidence photo is not yet available on this phone.',
            );
          }
          final bytes = await file.readAsBytes();
          final checksum = sha256.convert(bytes).toString();
          if (path == record.localUri &&
              record.sha256Checksum.isNotEmpty &&
              checksum != record.sha256Checksum) {
            throw const FormatException(
              'Local evidence checksum did not match.',
            );
          }
          if (_uploadedMedia.contains('$remotePath:$checksum')) {
            continue;
          }
          if (_freshMediaVerification) {
            try {
              final existing = await storage.download(remotePath);
              if (!_isCurrentAccount(ownerId)) {
                return false;
              }
              if (sha256.convert(existing).toString() == checksum) {
                _uploadedMedia.add('$remotePath:$checksum');
                continue;
              }
            } catch (_) {
              // A missing copy can be repaired from verified local evidence.
            }
          }
          if (!_isCurrentAccount(ownerId)) {
            return false;
          }
          await storage.uploadBinary(
            remotePath,
            bytes,
            fileOptions: FileOptions(
              contentType: path.toLowerCase().endsWith('.png')
                  ? 'image/png'
                  : path.toLowerCase().endsWith('.webp')
                  ? 'image/webp'
                  : 'image/jpeg',
              upsert: true,
            ),
          );
          final readBack = await storage.download(remotePath);
          if (sha256.convert(readBack).toString() != checksum) {
            throw const FormatException('Evidence backup verification failed.');
          }
          if (!_isCurrentAccount(ownerId)) {
            return false;
          }
          _uploadedMedia.add('$remotePath:$checksum');
        } catch (error) {
          complete = false;
          lastMediaError =
              'Records are saved; some evidence photos are still waiting to back up: $error';
        }
      }
    }
    return complete;
  }

  Future<Map<String, List<Map<String, dynamic>>>> exportLocalTables({
    bool includeLocalRecovery = false,
  }) async {
    return database.transaction(() async {
      final tables = <String, List<Map<String, dynamic>>>{};
      for (final table in database.allTables) {
        final name = table.actualTableName;
        if (name == 'sync_outbox') {
          continue;
        }
        final rows = await database.customSelect('SELECT * FROM "$name"').get();
        tables[name] = [
          for (final row in rows)
            if (includeLocalRecovery ||
                name != 'app_preferences' ||
                row.data['preference_key'] != localRecoveryPreferenceKey)
              {
                ...row.data,
                if (name == 'fields') 'location_description': null,
                if (name == 'crop_cycles') 'intended_use': null,
              },
        ];
      }
      return tables;
    });
  }

  bool _hasRecoverableRecords(Map tables) {
    const nonUserData = {'audit_logs', 'sync_outbox'};
    for (final entry in tables.entries) {
      if (nonUserData.contains(entry.key)) {
        continue;
      }
      if (entry.value is List && (entry.value as List).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<String> _deviceId() async {
    final existing = await secureStorage.read(key: _deviceKey);
    if (existing != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(existing)) {
      return existing;
    }
    final random = Random.secure();
    final created = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await secureStorage.write(key: _deviceKey, value: created);
    return created;
  }
}
