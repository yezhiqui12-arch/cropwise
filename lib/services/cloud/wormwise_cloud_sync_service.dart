import '../../models/automatic_screening.dart';
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/advisor_model_results_reader.dart';
import 'wormwise_account_backup_service.dart';
import 'automatic_sync_scheduler.dart';
import 'field_catalog_service.dart';
import 'account_app_data_service.dart';
import '../computer_vision/detection_preferences.dart';
import '../scouting_sampling_protocol.dart';
import 'expert_case_submission_service.dart';
import '../evidence_storage_service.dart';

enum WormWiseCloudSyncState { localOnly, idle, syncing, synced, error }

enum AccountRecoveryState { idle, restoring, ready, error }

/// Pushes account backups plus the cloud-supported relational records.
/// Drift remains authoritative offline. Registered accounts back up their
/// private evidence files to account-scoped Storage for recovery on a new phone.
class WormWiseCloudSyncService extends ChangeNotifier
    with WidgetsBindingObserver {
  WormWiseCloudSyncService(
    this._database,
    this._client, {
    WormWiseAccountBackupService? accountBackup,
  }) {
    _accountBackup =
        accountBackup ??
        (_client == null
            ? null
            : WormWiseAccountBackupService(
                _database,
                _client,
                onRecoveryProgress: (stage) {
                  if (_recoveryState == AccountRecoveryState.restoring &&
                      _recoveryOwner == _client.auth.currentUser?.id) {
                    _recoveryDetail = stage;
                    if (!_disposed) {
                      notifyListeners();
                    }
                  }
                },
              ));
    _accountBackup?.onSnapshotCapture = () => _snapshotRevision = _dataRevision;
    if (_client != null) {
      _subscriptions.addAll([
        AccountAppDataEvents.changes.stream.listen((_) => _localDataChanged()),
        AccountAppDataEvents.restores.stream.listen(
          (_) => unawaited(DetectionPreferences.reload()),
        ),
      ]);
    }
  }

  final AppDatabase _database;
  final SupabaseClient? _client;
  late final WormWiseAccountBackupService? _accountBackup;
  AccountRecoveryState _recoveryState = AccountRecoveryState.idle;
  String? _recoveryOwner;
  String _recoveryDetail = 'Opening your account';
  Future<bool>? _recovering;
  String? _localAccessOwner;
  String? _preparedOwner;
  int _dataRevision = 0;
  int? _snapshotRevision;
  Future<bool>? _manualVerification;
  int? _verifiedRevision;
  String? _verifiedOwner;
  DateTime? _lastVerifiedAt;

  bool get hasRegisteredAccount =>
      _client?.auth.currentUser?.isAnonymous == false;
  bool get hasBackupData => _accountBackup?.lastSnapshotHasData == true;
  bool get canContinueWithLocalData =>
      hasRegisteredAccount && _preparedOwner == _client?.auth.currentUser?.id;
  AccountRecoveryState get recoveryState =>
      _recoveryOwner == _client?.auth.currentUser?.id
      ? _recoveryState
      : AccountRecoveryState.idle;
  String get recoveryDetail => _recoveryDetail;
  bool get recordsReady =>
      hasRegisteredAccount && recoveryState == AccountRecoveryState.ready;
  bool get needsAccountRecovery =>
      hasRegisteredAccount &&
      !recordsReady &&
      _localAccessOwner != _client?.auth.currentUser?.id;
  bool get backupVerified =>
      hasRegisteredAccount &&
      _verifiedOwner == _client?.auth.currentUser?.id &&
      _accountBackup?.lastPublishedSnapshotComplete == true &&
      _verifiedRevision == _dataRevision &&
      _lastVerifiedAt != null;
  DateTime? get lastVerifiedAt =>
      _verifiedOwner == _client?.auth.currentUser?.id ? _lastVerifiedAt : null;

  void continueWithLocalData() {
    if (!canContinueWithLocalData) {
      return;
    }
    _localAccessOwner = _client?.auth.currentUser?.id;
    notifyListeners();
    _scheduler.request(immediate: true);
  }

  Future<bool> restoreAccountView(String ownerId) async {
    if (!hasRegisteredAccount || _client?.auth.currentUser?.id != ownerId) {
      return false;
    }
    final running = _recovering;
    if (running != null) {
      await running;
    }
    if (_client?.auth.currentUser?.id != ownerId) {
      return false;
    }
    if (recordsReady) {
      return true;
    }
    final operation = _restoreRecords(ownerId);
    _recovering = operation;
    try {
      return await operation;
    } finally {
      if (identical(_recovering, operation)) {
        _recovering = null;
      }
    }
  }

  Future<bool> _restoreRecords(String ownerId) async {
    _recoveryOwner = ownerId;
    _recoveryState = AccountRecoveryState.restoring;
    _recoveryDetail = 'Opening your account';
    if (!_disposed) {
      notifyListeners();
    }
    try {
      final backup = _accountBackup!;
      await backup.prepareAccountView(
        ownerId,
        assumeCurrentWhenUntracked: true,
      );
      if (_client?.auth.currentUser?.id != ownerId) {
        return false;
      }
      _preparedOwner = ownerId;
      if (await _useRestoredLocalView(ownerId)) return true;
      final recovered = await backup.restoreEssentialRecords(ownerId);
      if (_disposed || _client?.auth.currentUser?.id != ownerId) {
        return false;
      }
      if (recovered) {
        await _database
            .into(_database.appPreferences)
            .insertOnConflictUpdate(
              AppPreferencesCompanion.insert(
                preferenceKey:
                    WormWiseAccountBackupService.localRecoveryPreferenceKey,
                preferenceValue: ownerId,
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );
        if (_disposed || _client?.auth.currentUser?.id != ownerId) return false;
      }
      _recoveryState = recovered
          ? AccountRecoveryState.ready
          : AccountRecoveryState.error;
      _recoveryDetail = recovered
          ? 'Your account records are ready'
          : 'Some account history has not finished restoring. Retry to load it.';
      notifyListeners();
      if (recovered) {
        _scheduler.request(immediate: true);
      }
      return recovered;
    } catch (error) {
      if (!_disposed && _client?.auth.currentUser?.id == ownerId) {
        _recoveryState = AccountRecoveryState.error;
        _recoveryDetail =
            'Could not restore account history. Check your connection and retry.';
        notifyListeners();
      }
      return false;
    }
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  StreamSubscription<AuthState>? _authSubscription;
  late final _scheduler = AutomaticSyncScheduler(_attemptSync);
  StreamSubscription<InternetStatus>? _connectionSubscription;
  bool _disposed = false;
  bool _started = false;
  WormWiseCloudSyncState _state = WormWiseCloudSyncState.localOnly;
  String? _lastError;
  DateTime? _lastSyncedAt;

  WormWiseCloudSyncState get state => _state;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Future<void> beginGuestTransfer() async {
    final backup = _accountBackup;
    if (backup == null) {
      throw StateError('Account backup is unavailable.');
    }
    await backup.beginGuestTransfer();
  }

  Future<void> cancelGuestTransfer() async {
    await _accountBackup?.cancelGuestTransfer();
  }

  Future<void> prepareAccountView(
    String ownerId, {
    bool assumeCurrentWhenUntracked = false,
    bool restoreRecords = true,
  }) async {
    final backup = _accountBackup;
    if (backup == null) {
      return;
    }
    await backup.prepareAccountView(
      ownerId,
      assumeCurrentWhenUntracked: assumeCurrentWhenUntracked,
    );
    _preparedOwner = ownerId;
    await _useRestoredLocalView(ownerId);
    if (restoreRecords && !await restoreAccountView(ownerId)) {
      throw StateError('Account records have not finished restoring.');
    }
  }

  /// Read only after switching to the correct locally saved account view.
  Future<bool> _useRestoredLocalView(String ownerId) async {
    final marker =
        await (_database.select(_database.appPreferences)..where(
              (row) => row.preferenceKey.equals(
                WormWiseAccountBackupService.localRecoveryPreferenceKey,
              ),
            ))
            .getSingleOrNull();
    if (_disposed ||
        !hasRegisteredAccount ||
        _client?.auth.currentUser?.id != ownerId ||
        marker?.preferenceValue != ownerId)
      return false;
    _recoveryOwner = ownerId;
    _recoveryState = AccountRecoveryState.ready;
    _recoveryDetail = 'Your account records are ready';
    notifyListeners();
    return true;
  }

  Future<void> prepareGuestView() async {
    final backup = _accountBackup;
    if (backup == null) {
      return;
    }
    await backup.prepareGuestView();
    _recoveryOwner = null;
    _recoveryState = AccountRecoveryState.idle;
    _verifiedOwner = null;
    _localAccessOwner = null;
    _preparedOwner = null;
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// A successful sign-in is not proof that local guest records reached the
  /// account. This completes and reads back a private snapshot before the UI
  /// may describe the data as backed up.
  Future<bool> verifyAccountBackup() =>
      _manualVerification ??= _verifyAccountBackup().whenComplete(() {
        _manualVerification = null;
      });

  Future<bool> _verifyAccountBackup() async {
    final client = _client;
    final backup = _accountBackup;
    final ownerId = client?.auth.currentUser?.id;
    if (client == null || backup == null || ownerId == null) {
      return false;
    }
    if (!hasRegisteredAccount) {
      return false;
    }
    await _scheduler.runManual(() {
      _verifiedRevision = null;
      backup.requireFreshVerification();
      if (!_disposed) notifyListeners();
    });
    return client.auth.currentUser?.id == ownerId && backupVerified;
  }

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    if (_client == null) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _connectionSubscription = InternetConnection().onStatusChange.listen(
      (status) => _scheduler.setOnline(status == InternetStatus.connected),
      onError: (Object error) => _scheduleSync(),
    );
    _authSubscription = _client.auth.onAuthStateChange.listen(
      (_) => _scheduleSync(),
    );
    _subscriptions.addAll([
      for (final table in _database.allTables)
        if (table.actualTableName != 'sync_outbox')
          _database
              .customSelect(
                'SELECT 1 FROM "${table.actualTableName}" LIMIT 1',
                readsFrom: {table},
              )
              .watch()
              .listen((_) => _localDataChanged()),
    ]);
    _setState(WormWiseCloudSyncState.idle);
    await synchronizeNow();
  }

  void _scheduleSync() {
    _scheduler.request();
  }

  void _localDataChanged() {
    _dataRevision++;
    if (!_disposed) {
      notifyListeners();
    }
    _scheduleSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reachability events can be suspended by the OS while backgrounded.
      _scheduler.setOnline(true);
    }
  }

  Future<void> synchronizeNow() => _scheduler.runNow();

  /// Expert submission must not depend on unrelated local account records or
  /// on completion of a device-wide recovery/media backup.
  Future<void> synchronizeAssessmentForSubmission(
    String assessmentId,
  ) => _scheduler.runExclusive(() async {
    final client = _client;
    final ownerId = client?.auth.currentUser?.id;
    if (client == null || ownerId == null) {
      throw StateError('Sign in before sending this assessment.');
    }
    final assessment =
        await (_database.select(_database.assessments)..where(
              (row) => row.id.equals(assessmentId) & row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (assessment == null || assessment.status != DatabaseCodes.completed) {
      throw StateError('Only a saved completed assessment can be sent.');
    }
    if (ScoutingSamplingProtocol.isRetired(
      assessment.protocolVersion,
      pattern: assessment.scoutingPattern,
    )) {
      throw StateError(
        'This assessment uses an outdated scouting method. '
        'Create a new DA assessment with 20 plants per block.',
      );
    }
    final cycle = await (_database.select(
      _database.cropCycles,
    )..where((row) => row.id.equals(assessment.cropCycleId))).getSingleOrNull();
    if (cycle == null) {
      throw StateError('The assessment crop cycle is missing.');
    }
    void checkAccount() {
      if (_disposed || client.auth.currentUser?.id != ownerId) {
        throw StateError(
          'The signed-in account changed. Reopen the assessment and retry.',
        );
      }
    }

    checkAccount();
    await _syncFields(client, ownerId, fieldId: cycle.fieldId);
    checkAccount();
    await _syncBoundaries(client, ownerId, fieldId: cycle.fieldId);
    checkAccount();
    await _syncAssessments(client, ownerId, assessmentId: assessmentId);
    checkAccount();
    await _syncStations(client, ownerId, assessmentId: assessmentId);
    checkAccount();
  });

  Future<bool> _attemptSync() async {
    if (_disposed) {
      return true;
    }
    final client = _client;
    final ownerId = client?.auth.currentUser?.id;
    if (client == null || ownerId == null) {
      _setState(
        client == null
            ? WormWiseCloudSyncState.localOnly
            : WormWiseCloudSyncState.idle,
      );
      return true;
    }
    _setState(WormWiseCloudSyncState.syncing);
    try {
      // Restore an account snapshot on an empty phone before it can publish an
      // empty local database. On the original phone, upload the guest records
      // under the newly signed-in account without changing local ownership.
      if (hasRegisteredAccount && !await restoreAccountView(ownerId)) {
        _lastError = recoveryDetail;
        _setState(WormWiseCloudSyncState.error);
        return false;
      }
      await _accountBackup?.synchronize(ownerId);
      if (client.auth.currentUser?.id != ownerId) {
        return false;
      }
      String? relationalError;
      try {
        await _syncFields(client, ownerId);
        await _syncBoundaries(client, ownerId);
        await _syncAssessments(client, ownerId);
        await _syncStations(client, ownerId);
        await ExpertCaseSubmissionService(
          database: _database,
          client: client,
          storage: EvidenceStorageService(),
        ).synchronizeSubmittedBlockIdentities();
      } catch (error) {
        // The private recovery copy must still finish when dashboard sync fails.
        relationalError = error.toString();
      }
      try {
        await FieldCatalogService(_database, client).flush();
      } catch (error) {
        debugPrint('Variety suggestions remain queued: $error');
      }
      // Records have already reached SQLite and the relational cloud tables.
      // A missing or interrupted photo remains retryable without hiding history.
      final verificationRevision = _dataRevision;
      _snapshotRevision = null;
      final mediaReady =
          client.auth.currentUser?.isAnonymous != false ||
          await _accountBackup!.synchronizeMedia(ownerId);
      if (!mediaReady || _accountBackup?.lastRecordError != null) {
        _lastError =
            _accountBackup?.lastRecordError ??
            _accountBackup?.lastMediaError ??
            'Records are saved; evidence photos are still restoring.';
        _setState(WormWiseCloudSyncState.error);
        return false;
      }
      if (client.auth.currentUser?.id != ownerId) {
        _setState(WormWiseCloudSyncState.idle);
        return false;
      }
      if (hasRegisteredAccount && !hasBackupData) {
        _lastError = null;
        _setState(WormWiseCloudSyncState.idle);
        return true;
      }
      if (hasRegisteredAccount &&
          (_accountBackup?.lastPublishedSnapshotComplete != true ||
              (_snapshotRevision ?? verificationRevision) != _dataRevision ||
              client.auth.currentUser?.id != ownerId)) {
        _lastError = 'Your latest changes are still waiting to be verified.';
        _setState(WormWiseCloudSyncState.error);
        return false;
      }
      if (hasRegisteredAccount) {
        _verifiedOwner = ownerId;
        _verifiedRevision = _dataRevision;
        _lastVerifiedAt = DateTime.now().toUtc();
      }
      if (relationalError != null) {
        _lastError =
            'Account backup verified; dashboard sync is pending: $relationalError';
        _setState(WormWiseCloudSyncState.error);
        return false;
      }
      _lastError = null;
      _lastSyncedAt = DateTime.now().toUtc();
      _setState(WormWiseCloudSyncState.synced);
      return true;
    } catch (error) {
      _lastError = error.toString();
      _setState(WormWiseCloudSyncState.error);
      return false;
    }
  }

  Future<void> _syncFields(
    SupabaseClient client,
    String ownerId, {
    String? fieldId,
  }) async {
    final query = _database.select(_database.fields);
    if (fieldId != null) query.where((row) => row.id.equals(fieldId));
    final fields = await query.get();
    final remoteFields = await client
        .from('fields')
        .select('id')
        .eq('owner_id', ownerId);
    final remoteFieldIds = remoteFields.map((row) => row['id']).toSet();
    final currentId = await _readCurrentFieldId();

    // Clear the remote selection first so changing fields cannot violate the
    // one-current-field-per-owner unique index during the transition.
    if (fieldId == null) {
      await client
          .from('fields')
          .update({'is_current': false})
          .eq('owner_id', ownerId)
          .eq('is_current', true);
    }
    for (final field in fields) {
      // Relational recovery summaries retain their original cloud owner and
      // are backed up privately. Never claim linked guest rows by upserting
      // their IDs as a different account.
      if (field.ownerPersonId?.startsWith('recovered-person-') == true) {
        continue;
      }
      // A local synced flag can survive account restore or loss of a remote
      // row. Verify presence for this account rather than silently skipping a
      // parent required by the assessment INSERT policy.
      if (field.syncState == DatabaseCodes.synced &&
          remoteFieldIds.contains(field.id)) {
        continue;
      }
      await client.from('fields').upsert({
        'id': field.id,
        'owner_id': ownerId,
        'name': field.name,
        'barangay': field.barangay,
        'municipality_city': field.municipalityCity ?? 'Piat',
        'province': field.province ?? 'Cagayan',
        'location_description': null,
        if (fieldId == null) 'is_current': field.id == currentId,
        'status': field.deletedAt != null
            ? 'deleted'
            : field.isArchived
            ? 'archived'
            : 'active',
        'client_updated_at': field.updatedAt.toUtc().toIso8601String(),
        'created_at': field.createdAt.toUtc().toIso8601String(),
      });
      await _markFieldSynced(field.id, field.updatedAt);
    }
    // A repeated sync may have no dirty fields, but still clears the selection.
    if (fieldId == null && currentId != null) {
      await client
          .from('fields')
          .update({'is_current': true})
          .eq('owner_id', ownerId)
          .eq('id', currentId)
          .eq('status', 'active');
    }
  }

  Future<void> _syncBoundaries(
    SupabaseClient client,
    String ownerId, {
    String? fieldId,
  }) async {
    final query = _database.select(_database.fieldBoundaryVersions);
    if (fieldId != null) query.where((row) => row.fieldId.equals(fieldId));
    final boundaries = await query.get();
    final remoteBoundaries = await client
        .from('field_boundaries')
        .select('id')
        .eq('owner_id', ownerId);
    final remoteBoundaryIds = remoteBoundaries.map((row) => row['id']).toSet();
    for (final boundary in boundaries) {
      if (boundary.deletedAt != null) {
        continue;
      }
      final field = await (_database.select(
        _database.fields,
      )..where((row) => row.id.equals(boundary.fieldId))).getSingleOrNull();
      if (field?.ownerPersonId?.startsWith('recovered-person-') == true) {
        continue;
      }
      if (boundary.syncState == DatabaseCodes.synced &&
          remoteBoundaryIds.contains(boundary.id)) {
        continue;
      }
      await client.from('field_boundaries').upsert({
        'id': boundary.id,
        'owner_id': ownerId,
        'field_id': boundary.fieldId,
        'version_number': boundary.versionNumber,
        'geometry_geojson': jsonDecode(boundary.geometryGeojson),
        'area_hectares': boundary.areaHectares,
        'centroid_latitude': boundary.centroidLatitude,
        'centroid_longitude': boundary.centroidLongitude,
        'source_method': boundary.sourceMethod,
        'client_updated_at': boundary.updatedAt.toUtc().toIso8601String(),
        'created_at': boundary.createdAt.toUtc().toIso8601String(),
      });
      await _markBoundarySynced(boundary.id, boundary.updatedAt);
    }
  }

  Future<void> _syncAssessments(
    SupabaseClient client,
    String ownerId, {
    String? assessmentId,
  }) async {
    final query = _database.select(_database.assessments);
    if (assessmentId != null) query.where((row) => row.id.equals(assessmentId));
    final assessments = await query.get();
    for (final assessment in assessments) {
      if (assessment.deletedAt != null ||
          ScoutingSamplingProtocol.isRetired(
            assessment.protocolVersion,
            pattern: assessment.scoutingPattern,
          )) {
        continue;
      }
      if (assessment.assessmentMode == 'recovered_cloud_summary') {
        continue;
      }
      final pendingRoutes =
          await (_database.select(_database.assessmentBlockRuns)..where(
                (row) =>
                    row.assessmentId.equals(assessment.id) &
                    row.syncState.equals(DatabaseCodes.synced).not() &
                    row.deletedAt.isNull(),
              ))
              .get();
      if (assessmentId == null &&
          assessment.syncState == DatabaseCodes.synced &&
          pendingRoutes.isEmpty) {
        continue;
      }
      final submission =
          await (_database.select(_database.syncOutbox)..where(
                (row) =>
                    row.id.equals('report_assessment_${assessment.id}') &
                    row.status.isIn(['submitted', DatabaseCodes.synced]),
              ))
              .getSingleOrNull();
      if (submission != null) {
        continue;
      }
      final cycle =
          await (_database.select(_database.cropCycles)
                ..where((row) => row.id.equals(assessment.cropCycleId)))
              .getSingleOrNull();
      if (cycle == null) {
        continue;
      }
      final remote = await client
          .from('assessments')
          .select('id,owner_id,status')
          .eq('id', assessment.id)
          .maybeSingle();
      if (remote != null && remote['owner_id'] != ownerId) {
        throw StateError(
          'Assessment ${assessment.id} is owned by another cloud account.',
        );
      }
      if (remote?['status'] == 'submitted') {
        // The submission RPC may have succeeded before its local receipt was
        // saved. Submitted assessments are immutable under RLS. Do not attempt
        // to upsert them back to completed or block every subsequent report.
        continue;
      }
      final remoteField = await client
          .from('fields')
          .select('id,owner_id')
          .eq('id', cycle.fieldId)
          .maybeSingle();
      if (remoteField == null || remoteField['owner_id'] != ownerId) {
        throw StateError(
          'Assessment ${assessment.id} cannot synchronize: its field '
          '${cycle.fieldId} is not visible as owned by the signed-in account. '
          'The server field record or its access policy needs verification.',
        );
      }
      try {
        await client.from('assessments').upsert({
          'id': assessment.id,
          'owner_id': ownerId,
          'field_id': cycle.fieldId,
          'boundary_id': assessment.boundaryVersionId,
          'status': _cloudAssessmentStatus(assessment.status),
          'growth_stage': assessment.growthStage,
          'protocol_version': assessment.protocolVersion,
          'formula_version': assessment.formulaVersion,
          'result_snapshot': await _resultSnapshot(assessment),
          'started_at': assessment.startedAt?.toUtc().toIso8601String(),
          'completed_at': assessment.completedAt?.toUtc().toIso8601String(),
          'client_updated_at': assessment.updatedAt.toUtc().toIso8601String(),
          'created_at': assessment.createdAt.toUtc().toIso8601String(),
        });
      } on PostgrestException catch (error) {
        throw StateError(
          'Assessment ${assessment.id} cloud write rejected '
          '(field ${cycle.fieldId}, existing status ${remote?['status'] ?? 'not visible'}, '
          'requested status ${_cloudAssessmentStatus(assessment.status)}): '
          '${error.message} (${error.code}).',
        );
      }
      await _markAssessmentSynced(assessment.id, assessment.updatedAt);
      for (final run in pendingRoutes) {
        await (_database.update(_database.assessmentBlockRuns)..where(
              (row) =>
                  row.id.equals(run.id) & row.updatedAt.equals(run.updatedAt),
            ))
            .write(
              const AssessmentBlockRunsCompanion(
                syncState: Value(DatabaseCodes.synced),
              ),
            );
      }
    }
  }

  Future<Map<String, Object?>> _resultSnapshot(
    AssessmentRecord assessment,
  ) async {
    final metrics = await (_database.select(
      _database.metricResults,
    )..where((row) => row.assessmentId.equals(assessment.id))).get();
    final runs =
        await (_database.select(_database.assessmentBlockRuns)
              ..where(
                (row) =>
                    row.assessmentId.equals(assessment.id) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.blockSequence)]))
            .get();
    final savedStations = <StationRecord>[];
    for (final run in runs) {
      final stations =
          await (_database.select(_database.stations)..where(
                (row) =>
                    row.assessmentBlockRunId.equals(run.id) &
                    row.deletedAt.isNull(),
              ))
              .get();
      savedStations.addAll(stations);
    }
    final models = await _savedModelResults(
      assessment.id,
      stations: savedStations,
    );
    return {
      'measurement_basis':
          models.samples.any((sample) => sample.result != null) ||
              metrics.any((m) => m.metricCode == AutomaticScreening.metric)
          ? 'damage_screening'
          : 'field_observations',
      'automatic_sampled_infestation': {
        ...models.sampledInfestationSummary,
        'stations': [
          for (final station in savedStations)
            {
              'station_id': station.id,
              'station_number': station.stationNumber,
              'block_run_id': station.assessmentBlockRunId,
              ...AdvisorModelResults(
                models.samples.where((s) => s.stationId == station.id).toList(),
              ).sampledInfestationSummary,
            },
        ],
      },
      'automatic_damage_screen': {
        ...models.summary['automatic_damage_screen'] as Map<String, dynamic>,
        'stations': [
          for (final station in savedStations)
            {
              'station_id': station.id,
              'station_number': station.stationNumber,
              'block_run_id': station.assessmentBlockRunId,
              'block_sequence': runs
                  .firstWhere((run) => run.id == station.assessmentBlockRunId)
                  .blockSequence,
              ...AdvisorModelResults(
                    models.samples
                        .where((sample) => sample.stationId == station.id)
                        .toList(),
                  ).summary['automatic_damage_screen']
                  as Map<String, dynamic>,
            },
        ],
      },
      'assessment_mode': assessment.assessmentMode,
      'scouting_pattern': assessment.scoutingPattern,
      'preferred_language': assessment.preferredLanguage,
      'validation_status': assessment.validationStatus,
      'growth_stage_uncertain': assessment.growthStageUncertain,
      'sampling_summary': {
        'station_count': savedStations.length,
        'planned_station_count':
            runs.length *
            ScoutingSamplingProtocol.locationCount(assessment.protocolVersion),
        'planned_sample_count':
            runs.length *
            ScoutingSamplingProtocol.locationCount(assessment.protocolVersion) *
            ScoutingSamplingProtocol.plantsPerLocation(
              assessment.protocolVersion,
            ),
      },
      'warnings': <String>[
        if (assessment.growthStageUncertain)
          'The recorded growth stage was marked uncertain.',
        if (assessment.safetySummaryStatus ==
            DatabaseCodes.treatmentHistoryUnknown)
          'Recent treatment history could not be confirmed.',
        if (assessment.completionNote?.trim().isNotEmpty == true)
          assessment.completionNote!.trim(),
        for (final code
            in metrics
                .map((metric) => metric.warningCode)
                .whereType<String>()
                .where((code) => code.trim().isNotEmpty)
                .toSet())
          code,
      ],
      'metrics': [
        for (final metric in metrics)
          {
            'scope_type': metric.scopeType,
            'scope_id': metric.scopeId,
            'metric_code': metric.metricCode,
            'numerator': metric.numerator,
            'denominator': metric.denominator,
            'value': metric.value,
            'unit': metric.unit,
            'formula_version': metric.formulaVersion,
            'validation_status': metric.validationStatus,
          },
      ],
      'sampling_routes': [
        for (final run in runs)
          if (run.routeGeojson != null && run.routeGeojson!.trim().isNotEmpty)
            {
              'block_run_id': run.id,
              'block_sequence': run.blockSequence,
              'scouting_pattern': run.scoutingPattern,
              'route_geojson': _decodeGeoJson(run.routeGeojson!),
            },
      ],
    };
  }

  // Cloud monitoring and Advisor must read the same saved CV evidence. Legacy
  // model caches are accepted only when their evidence signatures still match.
  Future<AdvisorModelResults> _savedModelResults(
    String assessmentId, {
    List<StationRecord>? stations,
  }) async {
    if (stations == null) {
      final runs =
          await (_database.select(_database.assessmentBlockRuns)..where(
                (row) =>
                    row.assessmentId.equals(assessmentId) &
                    row.deletedAt.isNull(),
              ))
              .get();
      stations = runs.isEmpty
          ? <StationRecord>[]
          : await (_database.select(_database.stations)..where(
                  (row) =>
                      row.assessmentBlockRunId.isIn(runs.map((run) => run.id)) &
                      row.deletedAt.isNull(),
                ))
                .get();
    }
    final plants = stations.isEmpty
        ? <PlantObservationRecord>[]
        : await (_database.select(_database.plantObservations)..where(
                (row) =>
                    row.stationId.isIn(stations!.map((station) => station.id)) &
                    row.deletedAt.isNull(),
              ))
              .get();
    return AdvisorModelResultsReader(
      _database,
    ).load(assessmentId: assessmentId, stations: stations, plants: plants);
  }

  Future<void> _syncStations(
    SupabaseClient client,
    String ownerId, {
    String? assessmentId,
  }) async {
    final runs =
        await (_database.select(_database.assessmentBlockRuns)..where(
              (row) =>
                  row.deletedAt.isNull() &
                  (assessmentId == null
                      ? const Constant(true)
                      : row.assessmentId.equals(assessmentId)),
            ))
            .get();
    final eligibleAssessments = <String, bool>{};
    final modelResults = <String, AdvisorModelResults>{};
    for (final run in runs) {
      // Restored guest records and deleted assessments can still have local
      // station rows. Never upload those rows as the current account's data.
      var eligible = eligibleAssessments[run.assessmentId];
      if (eligible == null) {
        final local =
            await (_database.select(_database.assessments)..where(
                  (row) =>
                      row.id.equals(run.assessmentId) & row.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        final remote =
            local == null ||
                local.assessmentMode == 'recovered_cloud_summary' ||
                ScoutingSamplingProtocol.isRetired(
                  local.protocolVersion,
                  pattern: local.scoutingPattern,
                )
            ? null
            : await client
                  .from('assessments')
                  .select('id,status')
                  .eq('id', run.assessmentId)
                  .eq('owner_id', ownerId)
                  .maybeSingle();
        // Preserve the station snapshot that accompanied an already submitted
        // assessment, including retries whose local receipt was lost.
        eligible = remote != null && remote['status'] != 'submitted';
        eligibleAssessments[run.assessmentId] = eligible;
      }
      if (!eligible) {
        continue;
      }
      final models = modelResults[run.assessmentId] ??=
          await _savedModelResults(run.assessmentId);
      final stations =
          await (_database.select(_database.stations)..where(
                (row) =>
                    row.assessmentBlockRunId.equals(run.id) &
                    row.deletedAt.isNull(),
              ))
              .get();
      for (final station in stations) {
        final samples = models.samples
            .where((sample) => sample.stationId == station.id)
            .toList();
        final inspected = samples.where((sample) => sample.eligible).toList();
        final infested = inspected.where((sample) => sample.positive).length;
        await client.from('assessment_stations').upsert({
          'id': station.id,
          'owner_id': ownerId,
          'assessment_id': run.assessmentId,
          'block_run_id': run.id,
          'station_number': station.stationNumber,
          'location_source': station.locationSource,
          'location_captured_at': station.locationCapturedAt
              ?.toUtc()
              .toIso8601String(),
          'plant_locations': [
            for (final sample in samples)
              {
                'id': sample.plant?.id,
                'plant_number': sample.position,
                'assessable': sample.eligible,
                'measurement_basis': 'damage_screening',
                'damage_screen': sample.modelJson,
                'damage_screen_availability': sample.availability,
                'damage_screen_source': sample.source,
                'latitude': sample.plant?.locationSource == 'phone_gps'
                    ? sample.plant?.latitude
                    : null,
                'longitude': sample.plant?.locationSource == 'phone_gps'
                    ? sample.plant?.longitude
                    : null,
                'gps_accuracy_m': sample.plant?.locationSource == 'phone_gps'
                    ? sample.plant?.gpsAccuracyM
                    : null,
                'location_source': sample.plant?.locationSource,
                'location_captured_at': sample.plant?.locationCapturedAt
                    ?.toUtc()
                    .toIso8601String(),
                'observed_at': sample.plant?.capturedAt
                    ?.toUtc()
                    .toIso8601String(),
              },
          ],
          'latitude': station.latitude,
          'longitude': station.longitude,
          'gps_accuracy_m': station.gpsAccuracyM,
          'plants_inspected': inspected.length,
          'plants_infested': infested,
          'captured_at': station.capturedAt?.toUtc().toIso8601String(),
          'client_updated_at': station.updatedAt.toUtc().toIso8601String(),
        });
        if (station.syncState != DatabaseCodes.synced) {
          await (_database.update(_database.stations)..where(
                (row) =>
                    row.id.equals(station.id) &
                    row.syncState.equals(DatabaseCodes.synced).not() &
                    row.updatedAt.equals(station.updatedAt),
              ))
              .write(
                const StationsCompanion(syncState: Value(DatabaseCodes.synced)),
              );
        }
      }
    }
  }

  Object? _decodeGeoJson(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  String _cloudAssessmentStatus(String status) {
    if (status == DatabaseCodes.inProgress) {
      return 'in_progress';
    }
    if (status == DatabaseCodes.completed) {
      return 'completed';
    }
    return 'draft';
  }

  Future<String?> _readCurrentFieldId() async {
    final value =
        await (_database.select(_database.appPreferences)
              ..where((row) => row.preferenceKey.equals('active_field_id')))
            .getSingleOrNull();
    return value?.preferenceValue;
  }

  Future<void> _markFieldSynced(String id, DateTime uploadedVersion) async {
    final changed =
        await (_database.update(_database.fields)..where(
              (row) =>
                  row.id.equals(id) &
                  row.syncState.equals(DatabaseCodes.synced).not() &
                  row.updatedAt.equals(uploadedVersion),
            ))
            .write(
              const FieldsCompanion(syncState: Value(DatabaseCodes.synced)),
            );
    if (changed > 0) {
      await _markOutboxSynced('fields', id, uploadedVersion);
    }
  }

  Future<void> _markBoundarySynced(String id, DateTime uploadedVersion) async {
    final changed =
        await (_database.update(_database.fieldBoundaryVersions)..where(
              (row) =>
                  row.id.equals(id) &
                  row.syncState.equals(DatabaseCodes.synced).not() &
                  row.updatedAt.equals(uploadedVersion),
            ))
            .write(
              const FieldBoundaryVersionsCompanion(
                syncState: Value(DatabaseCodes.synced),
              ),
            );
    if (changed > 0) {
      await _markOutboxSynced('field_boundary_versions', id, uploadedVersion);
    }
  }

  Future<void> _markAssessmentSynced(
    String id,
    DateTime uploadedVersion,
  ) async {
    final changed =
        await (_database.update(_database.assessments)..where(
              (row) =>
                  row.id.equals(id) &
                  row.syncState.equals(DatabaseCodes.synced).not() &
                  row.updatedAt.equals(uploadedVersion),
            ))
            .write(
              const AssessmentsCompanion(
                syncState: Value(DatabaseCodes.synced),
              ),
            );
    if (changed > 0) {
      await _markOutboxSynced('assessments', id, uploadedVersion);
    }
  }

  Future<void> _markOutboxSynced(
    String type,
    String id,
    DateTime uploadedVersion,
  ) async {
    await (_database.update(_database.syncOutbox)..where(
          (row) =>
              row.entityType.equals(type) &
              row.entityId.equals(id) &
              row.updatedAt.isSmallerOrEqualValue(uploadedVersion),
        ))
        .write(
          SyncOutboxCompanion(
            status: const Value(DatabaseCodes.synced),
            lastError: const Value(null),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  void _setState(WormWiseCloudSyncState value) {
    if (_disposed) {
      return;
    }
    if (_state == value) {
      return;
    }
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _scheduler.dispose();
    if (_started && _client != null) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _connectionSubscription?.cancel();
    _authSubscription?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
