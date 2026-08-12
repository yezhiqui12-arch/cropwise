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
