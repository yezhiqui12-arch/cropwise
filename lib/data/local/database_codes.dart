/// Stable database codes.
///
/// Persist these values instead of translated labels. UI copy can change without
/// requiring a database migration.
abstract final class DatabaseCodes {
  static const implementedGrowthStages = {'ve', 'v1', 'v2', 'v3_v6', 'v7_v12'};

  static bool isGrowthStageImplemented(String stage) =>
      implementedGrowthStages.contains(stage);

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

  // VE-V2 planting-unit conditions and evaluator interpretations.
  static const veUnitHealthy = 'occupied_healthy';
  static const veUnitFeedingInjury = 'occupied_feeding_injury';
  static const veUnitCutSevered = 'cut_or_severed';
  static const veUnitWiltedDead = 'wilted_or_dead';
  static const veUnitEmptyUnexplained = 'empty_unexplained';
  static const veUnitPositionUncertain = 'position_uncertain';
  static const veUnitNotAssessable = 'not_assessable';
  static const veUnitConditions = {
    veUnitHealthy,
    veUnitFeedingInjury,
    veUnitCutSevered,
    veUnitWiltedDead,
    veUnitEmptyUnexplained,
    veUnitPositionUncertain,
    veUnitNotAssessable,
  };

  // Raw VE-V2 routing facts captured before evaluator interpretation. These
  // describe what physical position should be processed next; they are not
  // model findings or pest classifications.
  static const veOccupancySeedling = 'seedling_present';
  static const veOccupancyEmpty = 'empty_position';
  static const veOccupancyRemnant = 'recognizable_remnant';
  static const veOccupancyUncertain = 'occupancy_uncertain';
  static const veOccupancyNotAssessable = 'occupancy_not_assessable';
  static const veOccupancyStatuses = {
    veOccupancySeedling,
    veOccupancyEmpty,
    veOccupancyRemnant,
    veOccupancyUncertain,
    veOccupancyNotAssessable,
  };

  static const veInterpretationConfirmedFaw = 'confirmed_faw_present';
  static const veInterpretationFawConsistent = 'injury_consistent_with_faw';
  static const veInterpretationOtherPest = 'possible_other_pest';
  static const veInterpretationNonPest = 'likely_non_pest_cause';
  static const veInterpretationMixed = 'mixed_causes_or_organisms';
  static const veInterpretationUncertain = 'uncertain';
  static const veInterpretationNone = 'no_relevant_evidence';
  static const veInterpretations = {
    veInterpretationConfirmedFaw,
    veInterpretationFawConsistent,
    veInterpretationOtherPest,
    veInterpretationNonPest,
    veInterpretationMixed,
    veInterpretationUncertain,
    veInterpretationNone,
  };

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
  static const evidenceScopePlantingUnit = 'planting_unit';
  static const evidenceViewStationContext = 'station_context';
  static const evidenceViewWhorlOverview = 'whorl_newest_leaves_overview';
  static const evidenceViewCloseUp = 'evidence_close_up';
  static const evidenceViewDiagnosticDetail = 'diagnostic_detail';
  static const evidenceViewVeRowContext = 've_v2_row_context';
  static const evidenceViewVePlantingPosition = 've_v2_planting_position';
  static const evidenceViewWholeSeedling = 'whole_seedling';
  static const evidenceViewStemBase = 'stem_base';
  static const evidenceViewLarvaDorsal = 'larva_dorsal_body';
  static const evidenceViewLarvaHead = 'larva_head';
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

  // Versioned station evidence policies. Older versions remain readable so
  // accepted evidence is never deleted or silently reclassified.
  static const evidencePolicyStation1TwoViewV1 = 'capture_first_station1_v1';
  static const evidencePolicyHumanWorkloadSafeV1 = 'human_workload_safe_v1';
  static const evidencePolicyCameraFirstOverviewConditionalV1 =
      'camera_first_overview_conditional_v1';
  static const evidencePolicyVeV2ModelReadyCaptureV1 =
      've_v2_model_ready_capture_v1';
  static const evidencePolicyVeV2UnitEvidenceV1 = 've_v2_unit_evidence_v1';

  static const evidenceReviewSufficient = 'sufficient';
  static const evidenceReviewInsufficient = 'insufficient';
  static const evidenceReviewStatuses = {
    evidenceReviewSufficient,
    evidenceReviewInsufficient,
  };

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
