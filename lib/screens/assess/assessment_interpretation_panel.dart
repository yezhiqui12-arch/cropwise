import 'package:flutter/material.dart';
import '../../localization/app_text.dart';
import '../../models/da_severity.dart';
import '../../theme/app_colors.dart';
import 'assessment_action_modal.dart';

class AssessmentInterpretationPanel extends StatelessWidget {
  const AssessmentInterpretationPanel({
    super.key,
    required this.facts,
    required this.interpretation,
    required this.sourceLabel,
    required this.loading,
    required this.aiEnabled,
    this.availabilityMessage,
    required this.onAiChanged,
    required this.onRegenerate,
  });
  final Map<String, dynamic> facts;
  final String interpretation, sourceLabel;
  final bool loading, aiEnabled;
  final String? availabilityMessage;
  final ValueChanged<bool> onAiChanged;
  final VoidCallback onRegenerate;

  String _rate(dynamic value) => value is num && value.isFinite
      ? '${value.toStringAsFixed(1)}%'
      : 'Unavailable';

  void _showResults(BuildContext context) {
    final expert = facts['finalized_expert_findings'] as Map?;
    final damage = facts['damage_screen'] as Map? ?? const {};
    final infestation = facts['sampled_infestation'] as Map? ?? const {};
    final expertDamage = expert?['damage_percentage'] as Map? ?? const {};
    showDialog<bool>(
      context: context,
      builder: (_) => AssessmentActionModal(
        title: 'Assessment results',
        eyebrow: expert == null ? 'APP SCREENING' : 'FINALIZED EXPERT REVIEW',
        icon: Icons.analytics_outlined,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (expert != null)
              _result(
                'Mean Davis severity',
                expert['mean_davis_score'] is num
                    ? '${(expert['mean_davis_score'] as num).toStringAsFixed(2)} / 9'
                    : 'Unavailable',
                '${expert['scored_plants'] ?? 0} plants scored',
              ),
            _result(
              expert == null
                  ? 'Damage screening'
                  : 'Original app damage screening',
              _rate(damage['percent']),
              '${damage['damaged_count'] ?? 0} of ${damage['eligible_count'] ?? 0} screened plants',
            ),
            _result(
              expert == null
                  ? 'Provisional sampled infestation'
                  : 'Current sampled infestation',
              _rate(infestation['percent']),
              '${infestation['infested_count'] ?? 'Unavailable'} of ${infestation['denominator'] ?? 'Unavailable'} plants',
            ),
            if (expert != null)
              _result(
                'FAW damage incidence',
                _rate(expertDamage['value']),
                '${expertDamage['numerator'] ?? 'Unavailable'} of ${expertDamage['denominator'] ?? 'Unavailable'} scored plants',
              ),
          ],
        ),
      ),
    );
  }

  Widget _result(String label, String value, String count) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 5),
        AppText(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 3),
        AppText(
          count,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  void _showSettings(BuildContext context) {
    var enabled = aiEnabled;
    showDialog<bool>(
      context: context,
      builder: (_) => AssessmentActionModal(
        title: 'Guidance settings',
        eyebrow: 'THIS ASSESSMENT',
        icon: Icons.tune_rounded,
        content: StatefulBuilder(
          builder: (context, setModalState) => Column(
            children: [
              Material(
                color: Colors.transparent,
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const AppText('Use AI advice'),
                  value: enabled,
                  onChanged: (value) {
                    setModalState(() => enabled = value);
                    onAiChanged(value);
                  },
                ),
              ),
              if (availabilityMessage != null)
                AppText(
                  availabilityMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              TextButton.icon(
                onPressed: loading
                    ? null
                    : () {
                        Navigator.pop(context);
                        onRegenerate();
                      },
                icon: const Icon(Icons.refresh),
                label: const AppText('Refresh guidance'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expert = facts['finalized_expert_findings'] as Map?;
    final damage = facts['damage_screen'] as Map? ?? const {};
    final plants = (facts['plants'] as List? ?? const []).whereType<Map>();
    final mean = expert?['mean_davis_score'] as num?;
    final flagged = damage['damaged_count'] as num? ?? 0;
    final screened = damage['eligible_count'] as num? ?? 0;
    final headline = expert != null
        ? daSeverityClassification(mean)
        : screened == 0
        ? 'Screening results unavailable'
        : flagged == 0
        ? 'No damage flagged in the sample'
        : '$flagged ${flagged == 1 ? 'plant' : 'plants'} flagged for damage';
    final summary = expert != null
        ? 'Mean Davis ${mean?.toStringAsFixed(2) ?? 'Unavailable'} / 9 · ${expert['scored_plants'] ?? 0} scored plants'
        : '${_rate(damage['percent'])} screened damage · $flagged of $screened plants';
    final signs = <String>[];
    if (expert == null) {
      for (final sign in ['larvae', 'frass', 'eggs']) {
        final count = plants
            .where((p) => (p['model_suggestions'] as Map?)?[sign] == true)
            .length;
        if (count > 0) {
          signs.add('$sign on $count ${count == 1 ? 'plant' : 'plants'}');
        }
      }
    }
    final missingPhotos = plants.where((p) => p['photo_count'] == 0).length;
    final remaining = facts['remaining_plants'] as num? ?? 0;
    final coverage = missingPhotos > 0
        ? '$missingPhotos plants without saved photos'
        : remaining > 0
        ? '$remaining plants still to record'
        : '${facts['saved_plants'] ?? facts['recorded_plants'] ?? plants.length} plants recorded';
    return Container(
      key: const Key('assessment_interpretation_panel'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE4DE)),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFF193F35),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      color: Color(0xFFCADFD4),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: AppText(
                        'Field interpretation',
                        style: TextStyle(
                          color: Color(0xFFCADFD4),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AppText(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                AppText(
                  summary,
                  style: const TextStyle(
                    color: Color(0xFFE0EBE5),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                if (signs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  AppText(
                    'Potential ${signs.join(' · ')}',
                    style: const TextStyle(
                      color: Color(0xFFF4D69C),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.checklist_outlined,
                  size: 17,
                  color: Color(0xFF87602B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText(
                    coverage,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Color(0xFF6E542C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppText(
                  expert == null
                      ? 'Provisional app findings'
                      : 'Expert-reviewed severity',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                TextButton.icon(
                  key: const Key('view_interpretation_results'),
                  onPressed: () => _showResults(context),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const AppText('View results'),
                ),
                IconButton(
                  tooltip: 'Guidance settings',
                  onPressed: () => _showSettings(context),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
