import '../../models/da_severity.dart';

/// Facts derived from an immutable expert review, never from chat or CV output.
/// Nulls and legacy freshness remain unavailable; missing evidence is not zero.
Map<String, dynamic> expertDamageMonitoringFacts(Map<String, dynamic> row) {
  int? count(String key) {
    final value = row[key];
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value != value.round()) {
      return null;
    }
    return value.toInt();
  }

  final scored = count('scored_plants');
  final positive = count('positive_plants');
  final fresh = count('fresh_plants');
  final old = count('old_only_plants');
  final zero = count('zero_damage_plants');
  final damageAvailable =
      row['association_status'] != 'ambiguous' &&
      scored != null &&
      scored > 0 &&
      positive != null &&
      positive <= scored;
  final knownFreshness = fresh != null && old != null && zero != null
      ? fresh + old + zero
      : null;
  final freshnessAvailable =
      row['monitoring_version'] == 2 &&
      damageAvailable &&
      knownFreshness != null &&
      knownFreshness > 0 &&
      knownFreshness <= scored &&
      fresh! + old! <= positive &&
      positive + zero! == scored;
  return {
    'da_severity_classification': daSeverityClassification(
      row['mean_davis_score'] as num?,
    ),
    'classification_display_basis': daSeverityBandExplanation,
    'result_meanings': daSeverityExplanation,
    'formulas': daFormulaExplanation,
    'measurement_basis': 'finalized_expert_photo_review',
    'monitoring_version': row['monitoring_version'],
    'association_status': row['association_status'],
    for (final key in const [
      'reporting_version',
      'planned_plants',
      'latest_evidence_at',
      'finalized_by',
      'reviewed_plants',
      'scored_plants',
      'insufficient_plants',
      'positive_plants',
      'zero_damage_plants',
      'fresh_plants',
      'old_only_plants',
      'uncertain_freshness_plants',
      'unrecorded_freshness_plants',
      'median_davis_score',
      'mean_davis_score',
      'identity_version',
      'block_run_id',
      'block_sequence',
      'score_distribution',
      'block_summaries',
      'assessed_at',
      'finalized_at',
      'reviewer_name',
    ])
      key: row[key],
    'damage_percentage': {
      'value': damageAvailable ? positive / scored * 100 : null,
      'numerator': damageAvailable ? positive : null,
      'denominator': damageAvailable ? scored : null,
      'unit': 'percent_of_scored_photo_linked_plants',
    },
    'current_infestation_indicator': {
      'value': freshnessAvailable ? fresh / knownFreshness * 100 : null,
      'numerator': freshnessAvailable ? fresh : null,
      'denominator': freshnessAvailable ? knownFreshness : null,
      'unit': 'percent_of_freshness_assessable_photo_linked_plants',
      'availability': freshnessAvailable
          ? 'available'
          : row['association_status'] == 'ambiguous'
          ? 'ambiguous_station_association'
          : row['monitoring_version'] != 2
          ? 'freshness_not_recorded'
          : 'no_assessable_freshness_evidence',
    },
    'interpretation':
        'Davis > 0 contributes to FAW damage incidence. Fresh damage contributes to the current infestation indicator. Old-only damage and adequately scored zero-damage plants contribute to its denominator. Uncertain/unrecorded freshness and insufficient evidence are excluded. Findings describe submitted evidence at assessment time, not current live field conditions; they do not establish whole-field prevalence.',
    if (row['block_summaries'] is List)
      'blocks': [
        for (final block in row['block_summaries'] as List)
          if (block is Map)
            {
              'block_sequence': block['block_sequence'],
              ...expertDamageMonitoringFacts(Map<String, dynamic>.from(block)),
            },
      ],
    if (row['station_summaries'] is List)
      'stations': [
        for (final station in row['station_summaries'] as List)
          if (station is Map)
            {
              'station_number': station['station_number'],
              ...expertDamageMonitoringFacts(
                Map<String, dynamic>.from(station),
              ),
            },
      ],
  };
}
