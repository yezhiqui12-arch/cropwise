import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../localization/app_language.dart';
import '../cloud/supabase_bootstrap.dart';
import '../cloud/wormwise_cloud_sync_service.dart';
import '../cloud/wormwise_identity_service.dart';
import '../evidence_capture_coordinator.dart';
import '../evidence_storage_service.dart';

class AppStartupResources {
  AppStartupResources(
    this.database,
    this.language,
    this.identity,
    this.cloudSync, {
    this.unresolvedCaptures = 0,
  });
  final int unresolvedCaptures;
  final AppDatabase database;
  final AppLanguageController language;
  final WormWiseIdentityService identity;
  final WormWiseCloudSyncService cloudSync;
  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    cloudSync.dispose();
    language.dispose();
    identity.dispose();
    await database.close();
  }
}

Future<AppStartupResources> initializeWormWise(
  void Function(String) report,
) async {
  AppDatabase? database;
  AppLanguageController? language;
  WormWiseIdentityService? identity;
  WormWiseCloudSyncService? sync;
  try {
    report('Opening your account');
    final cloud = await SupabaseBootstrap.initialize();
    identity = WormWiseIdentityService(cloud.client);
    await identity.restoreAccessState();
    database = AppDatabase();
    report('Opening saved records');
    await database.customSelect('SELECT 1').get();
    sync = WormWiseCloudSyncService(database, cloud.client);
    final user = identity.user;
    if (user != null && !user.isAnonymous) {
      await sync.prepareAccountView(
        user.id,
        assumeCurrentWhenUntracked: true,
        restoreRecords: false,
      );
    } else if (identity.hasAppAccess) {
      await sync.prepareGuestView();
    }
    // Recovery runs only after the account's local database view is prepared.
    report('Recovering unfinished photo saves');
    final evidence = EvidenceCaptureCoordinator(
      repository: EvidenceCaptureRepository(database),
      storage: EvidenceStorageService(),
    );
    var unresolvedCaptures = await evidence.recoverPreparedCaptures();
    for (final assessment in await assessmentsNeedingEvidenceRecovery(
      database,
    )) {
      try {
        await evidence.reconcileAssessment(
          assessmentId: assessment.id,
          actorPersonId: assessment.evaluatorPersonId,
        );
      } on FileSystemException {
        unresolvedCaptures++;
      } on FormatException {
        unresolvedCaptures++;
      } on ArgumentError {
        unresolvedCaptures++;
      }
    }
    language = AppLanguageController(database);
    await language.load();
    final resources = AppStartupResources(
      database,
      language,
      identity,
      sync,
      unresolvedCaptures: unresolvedCaptures,
    );
    final readyIdentity = identity;
    unawaited(
      readyIdentity.initialize().catchError((Object error, StackTrace stack) {
        debugPrint('Optional cloud connection unavailable: $error');
      }),
    );
    return resources;
  } catch (_) {
    sync?.dispose();
    language?.dispose();
    identity?.dispose();
    await database?.close();
    rethrow;
  }
}

/// Ready historical media is checked when its assessment opens, rather than
/// making every launch inspect every photograph on the device.
Future<List<AssessmentRecord>> assessmentsNeedingEvidenceRecovery(
  AppDatabase database,
) async {
  final rows = await database
      .customSelect(
        '''
    SELECT a.* FROM assessments a WHERE a.id IN (
      SELECT assessment_id FROM evidence_media
      INDEXED BY evidence_pending_recovery_idx
      WHERE storage_state NOT IN ('ready', 'deleted')
    )
  ''',
        readsFrom: {database.assessments, database.evidenceMedia},
      )
      .get();
  return [for (final row in rows) database.assessments.map(row.data)];
}
