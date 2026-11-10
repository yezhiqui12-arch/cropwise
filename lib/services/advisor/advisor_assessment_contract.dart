import '../../services/scouting_sampling_protocol.dart';
import '../../models/da_severity.dart';

/// Current app workflow, shared by both AI surfaces and their local fallbacks.
/// Sampling dimensions describe the saved assessment, not historical chat text.
abstract final class AdvisorAssessmentContract {
  static const version = 'da-assessment-ai-v3';
  static const instruction = '''
CURRENT CROPWISE ASSESSMENT WORKFLOW:
New assessments use the DA dispersed sampling method: 20 different plants in each sampling block of at most 1 hectare. Larger fields use multiple blocks. Guided scouting shows numbered plant pins and a walk to the next plant. Inspect the upper 3–4 leaves and whorl. Sampling locations are generated inside the boundary with a 3 m margin; phone GPS and field access determine the actual plant recorded. The manual specifies dispersed selection, not an exact app-generated route. Never choose plants just because they look damaged.
Capture or import 1–3 photos for the SAME plant, then save and continue. Batch import assigns photos to individual plants in a block before screening. Count each plant once, never count photos as plants. Refer to DA records as Block and Plant; an internal station_number is the displayed plant number and observation sequence 1 is not a second plant number. Older saved assessments keep their recorded method and counts; do not apply the new sample size to their history.
RESULT MEANINGS:
Model 1 provides saved FAW damage / No FAW damage classifications. Damage screening percentage is damaged-screened plants / successfully screened plants × 100. Optional Model 2 provides damage, frass, larvae, eggs and pest suggestions. Sampled infestation counts provisional eggs OR larvae OR frass detection, once per plant; damage alone is excluded. Its percentage uses all planned plants (20 per DA block). Keep detection coverage separate: unavailable plants remain unknown, not Not infested. Detection skipped, disabled, failed or incomplete without those signs is Unavailable, not Not infested. Model 1 can still be available when infestation is unavailable.
Finalized expert findings replace provisional infestation when supplied. Fresh positive damage is Infested; zero damage or old-only damage is Not infested; uncertain freshness, insufficient evidence and ambiguous matches are Unavailable. Do not fall back to CV to fill missing finalized expert findings. Davis severity is the mean of finalized scores from 0–9, including zero and excluding insufficient evidence. Keep DA severity classification, FAW damage incidence and current sampled infestation separate. The DA labels are No infestation, Light infestation, Moderate infestation, Severe infestation and Highly severe; they describe Davis leaf-damage severity, not biological pest absence or percentage infestation. Use the supplied classification rather than inventing new bands. Current sampled infestation is a scouting estimate based on expert-assessed fresh damage, not a confirmed count of live larvae. New finalized DA reports require all 20 plants per block scored with assessable freshness. Complete blocks use 20 as the denominator; multiple blocks use 20 times the block count. Historical partial records retain their recorded denominators and must disclose partial coverage. A block mean describes sampled severity for that block; it is not a percentage or hectares destroyed. Use block identity to distinguish plants with the same number in different blocks.
Use the supplied assessment date, protocol, planned/recorded coverage, saved model results and latest finalized expert record. Supplied current records and this workflow override earlier assistant messages and general reference sampling examples. Never reuse old chat counts or assume completion means every plant has a usable result. Null/unavailable is never zero percent. Preserve the supplied calculation denominator, detection coverage and missing count. Do not infer leaf area, yield loss or whole-field damaged hectares from Davis scores.
DA monitoring uses presence checkboxes for eggs, larvae, pupae and damage (Pinsala); these are not organism counts or Davis grades. L1, L2 and later columns are dated monitoring visits. Saved rain context and the natural-enemy confirmation belong to the visit. Optional farmer corrections are observations, not new model predictions or expert grades. After sampling is completed, the DA monitoring form can export. Expert findings PDF requires finalized expert findings.
Keep advice practical, concise and relevant to the actual results. Describe sampled infestation as Infested, Not infested or Unavailable, not positive/negative. Only use positive/negative when explaining the underlying binary damage model. Do not invent observations, scores, thresholds or recheck dates. Gemini explains saved structured results; it does not inspect the photos or run the CV models.
''';

  static Map<String, dynamic> sampling(String protocol, int blocks) => {
    'context_version': version,
    'protocol_version': protocol,
    'method': ScoutingSamplingProtocol.isDa(protocol)
        ? 'DA dispersed plant sampling'
        : 'Historical saved assessment method',
    'blocks': blocks,
    if (ScoutingSamplingProtocol.isDa(protocol)) ...{
      'plants_per_block': ScoutingSamplingProtocol.plantsPerBlock,
      'maximum_block_area_hectares': 1,
      'planned_plants': blocks * ScoutingSamplingProtocol.plantsPerBlock,
      'boundary_margin_meters': ScoutingSamplingProtocol.edgeMarginMeters,
      'plant_identity':
          'block_run_id + station_number (one plant per location)',
      'inspection': 'upper 3–4 leaves and whorl',
    },
    'photos_per_plant_maximum': 3,
    'denominator_unit': 'unique plants, not photos',
  };

  /// Polling/loading state is not a change to the underlying advice facts.
  static Map<String, dynamic> stableFacts(Map<String, dynamic> facts) =>
      Map<String, dynamic>.from(facts)..remove('expert_review');

  static bool isObsoleteSamplingAdvice(String text) => RegExp(
    r'(?:five|5)[\s-]+stations?.{0,100}(?:ten|10)\s+(?:consecutive\s+)?(?:plants?|positions?)|(?:ten|10)\s+consecutive\s+plants?\s+(?:at|per|in)\s+(?:each|a|every)\s+station|at least two guided views',
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(text);

  /// Select only an immutable finalized record, including legacy cached cases.
  static Map<String, dynamic>? finalized(Map<String, dynamic> review) {
    final cases =
        (review['cases'] as List? ?? const [])
            .whereType<Map>()
            .where(
              (c) =>
                  c['severity'] is Map &&
                  DateTime.tryParse(
                        '${(c['severity'] as Map)['finalized_at']}',
                      ) !=
                      null,
            )
            .toList()
          ..sort(
            (a, b) =>
                DateTime.parse(
                  '${(b['severity'] as Map)['finalized_at']}',
                ).compareTo(
                  DateTime.parse('${(a['severity'] as Map)['finalized_at']}'),
                ),
          );
    if (cases.isEmpty) return null;
    final result = Map<String, dynamic>.from(cases.first['severity'] as Map);
    // Median is not the DA mean. Recover a mean only from a complete histogram.
    final distribution = result['score_distribution'];
    final scored = result['scored_plants'];
    if (result['association_status'] == 'ambiguous') {
      result['mean_davis_score'] = null;
    } else if (distribution is List &&
        distribution.length == 10 &&
        distribution.every((n) => n is int && n >= 0) &&
        scored is int &&
        scored > 0 &&
        distribution.fold<int>(0, (a, n) => a + (n as int)) == scored) {
      result['mean_davis_score'] =
          List.generate(
            10,
            (i) => i * (distribution[i] as int),
          ).fold<int>(0, (a, n) => a + n) /
          scored;
    } else {
      final mean = result['mean_davis_score'];
      if (mean is! num ||
          !mean.isFinite ||
          mean < 0 ||
          mean > 9 ||
          scored is! num ||
          scored <= 0) {
        result['mean_davis_score'] = null;
      }
    }
    result['da_severity_classification'] = daSeverityClassification(
      result['mean_davis_score'] as num?,
    );
    result['classification_display_basis'] = daSeverityBandExplanation;
    result['result_meanings'] = daSeverityExplanation;
    result['formulas'] = daFormulaExplanation;
    return result;
  }

  static Map<String, dynamic> infestation({
    required Map<String, dynamic> model,
    required Map<String, dynamic> review,
    required int? plannedPlants,
  }) {
    final expert = finalized(review);
    final indicator = expert?['current_infestation_indicator'];
    final assessed = expert == null
        ? model['eligible_count']
        : indicator is Map && indicator['availability'] == 'available'
        ? indicator['denominator']
        : null;
    final infested = expert == null
        ? model['infested_count']
        : indicator is Map && indicator['availability'] == 'available'
        ? indicator['numerator']
        : null;
    final valid =
        expert?['association_status'] != 'ambiguous' &&
        assessed is num &&
        infested is num &&
        assessed > 0 &&
        infested >= 0 &&
        infested <= assessed;
    final denominator = expert == null
        ? plannedPlants ?? model['denominator'] ?? model['sample_count']
        : assessed;
    final validRate = valid && denominator is num && denominator >= assessed;
    return {
      'source': expert == null
          ? 'model_eggs_or_larvae_or_frass'
          : 'finalized_expert_findings',
      'provisional': expert == null,
      'infested_count': valid ? infested : null,
      'not_infested_count': valid
          ? expert == null
                ? model['not_infested_count']
                : assessed - infested
          : null,
      'eligible_count': valid ? assessed : 0,
      'planned_plants': plannedPlants,
      'denominator': validRate ? denominator : null,
      'unavailable_count': plannedPlants == null
          ? model['unavailable_count']
          : (plannedPlants - (valid ? assessed.toInt() : 0)).clamp(
              0,
              plannedPlants,
            ),
      'percent': validRate ? 100 * infested / denominator : null,
      'case_label': valid && infested > 0
          ? 'Infested'
          : valid && plannedPlants != null && assessed == plannedPlants
          ? 'Not infested'
          : 'Unavailable',
    };
  }
}
