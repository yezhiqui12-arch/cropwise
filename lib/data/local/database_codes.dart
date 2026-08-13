/// Stable database codes.
///
/// Persist these values instead of translated labels. UI copy can change without
/// requiring a database migration.
abstract final class DatabaseCodes {
  // Synchronization.
  static const localOnly = 'local_only';
  static const queued = 'queued';
  static const syncing = 'syncing';
  static const synced = 'synced';
  static const conflict = 'conflict';
  static const error = 'error';

  // Assessment status and type.
  static const formal = 'formal';
  static const quickCheck = 'quick_check';
  static const draft = 'draft';
  static const safetyBlocked = 'safety_blocked';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const incomplete = 'incomplete';
  static const invalid = 'invalid';
  static const cancelled = 'cancelled';

  // Assessment modes.
  static const modeVeV6 = 've_v6';
  static const modeV7V12 = 'v7_v12';
  static const modeVtR2 = 'vt_r2';
  static const modeR3R6 = 'r3_r6';

  // Scouting patterns.
  static const patternW = 'w';
  static const patternLadder = 'ladder';
  static const patternNone = 'none';

  // Plant status.
  static const plantNegative = 'negative';
  static const plantCurrentPositive = 'current_positive';
  static const plantOldDamageOnly = 'old_damage_only';
  static const plantPossibleNonFaw = 'possible_non_faw';
  static const plantUncertain = 'uncertain';
  static const plantNotAssessable = 'not_assessable';

  // Natural-enemy quick status.
  static const naturalEnemyNoneSeen = 'none_seen';
  static const naturalEnemyObserved = 'observed';
  static const naturalEnemyUncertain = 'uncertain';
  static const naturalEnemyNotAssessable = 'not_assessable';
  static const naturalEnemyNotCollected = 'not_collected';

  static const plantStatuses = {
    plantNegative,
    plantCurrentPositive,
    plantOldDamageOnly,
    plantPossibleNonFaw,
    plantUncertain,
    plantNotAssessable,
  };

  static const naturalEnemyQuickStatuses = {
    naturalEnemyNoneSeen,
    naturalEnemyObserved,
    naturalEnemyUncertain,
    naturalEnemyNotAssessable,
    naturalEnemyNotCollected,
  };

  static const larvalSizes = {
    'none_seen',
    'small',
    'medium',
    'large',
    'uncertain',
  };

  // Station location-unavailable reasons.
  static const stationLocationServicesOff = 'location_services_off';
  static const stationPermissionDenied = 'permission_denied';
  static const stationPermissionBlocked = 'permission_blocked';
  static const stationNoCurrentFix = 'no_current_fix';
  static const stationUnsafeToWait = 'unsafe_to_wait';
  static const stationLocationDeviceError = 'device_or_location_error';
  static const stationLocationOther = 'other';

  static const stationNotLocatedReasons = {
    stationLocationServicesOff,
    stationPermissionDenied,
    stationPermissionBlocked,
    stationNoCurrentFix,
    stationUnsafeToWait,
    stationLocationDeviceError,
    stationLocationOther,
  };

  // Local evidence capture. These states do not imply remote upload.
  static const evidenceScopeStationContext = 'station_context';
  static const evidenceScopePlant = 'plant';
  static const evidenceViewStationContext = 'station_context';
  static const evidenceViewWhorlOverview = 'whorl_newest_leaves_overview';
  static const evidenceViewCloseUp = 'evidence_close_up';
  static const evidenceSessionInProgress = 'in_progress';
  static const evidenceSessionComplete = 'complete';
  static const evidenceSessionManualFallback = 'manual_fallback';
  static const evidenceCollectionCamera = 'camera';
  static const evidenceCollectionCameraWithFallback =
      'camera_with_manual_fallback';
  static const evidenceStorageStaged = 'staged';
  static const evidenceStorageReady = 'ready';
  static const evidenceStorageDeletionPending = 'deletion_pending';
  static const evidenceStorageDeleted = 'deleted';
  static const evidenceStorageMissing = 'missing';
  static const evidenceCaptureSourceCamera = 'camera';
  static const evidenceQualityEvaluatorConfirmed = 'evaluator_confirmed';

  static const evidenceFallbackPermissionDenied = 'permission_denied';
  static const evidenceFallbackPermissionBlocked = 'permission_blocked';
  static const evidenceFallbackNoCamera = 'no_camera_hardware';
  static const evidenceFallbackStorage = 'storage_unavailable';
  static const evidenceFallbackCaptureFailure = 'capture_failure';
  static const evidenceFallbackUnsafe = 'unsafe_to_photograph';
  static const evidenceFallbackPrivacy = 'privacy_or_consent';
  static const evidenceFallbackFraming = 'unable_to_frame_evidence';
  static const evidenceFallbackOther = 'other';

  static const evidenceFallbackReasons = {
    evidenceFallbackPermissionDenied,
    evidenceFallbackPermissionBlocked,
    evidenceFallbackNoCamera,
    evidenceFallbackStorage,
    evidenceFallbackCaptureFailure,
    evidenceFallbackUnsafe,
    evidenceFallbackPrivacy,
    evidenceFallbackFraming,
    evidenceFallbackOther,
  };

  // Safety gate.
  static const noRecentTreatment = 'no_recent_treatment';
  static const safeIntervalCompleted = 'safe_interval_completed';
  static const blockedReiActive = 'blocked_rei_active';
  static const cannotConfirmSafety = 'cannot_confirm';
  static const treatmentHistoryUnknown = 'history_unknown';

  // Metric codes.
  static const vegetativeCurrentInfestationPercent =
      'vegetative_current_infestation_percent';
  static const smallFreshWindowpanePercent = 'sfw_percent';
  static const infestedWhorlPercent = 'iw_percent';
  static const vtR2InfestedPlantPercent = 'vt_r2_ip_percent';
  static const externalEarDamagePercent = 'external_ear_damage_percent';
  static const activeEarInfestationPercent = 'active_ear_infestation_percent';
}
