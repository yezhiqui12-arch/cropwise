import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../localization/app_text.dart';
import '../../models/da_assessment_results.dart';
import '../../models/da_severity.dart';
import '../../models/sampled_infestation.dart';
import '../../theme/app_colors.dart';

/// One report with a clear lead finding and supporting measurements.
class DaFindingsOverview extends StatelessWidget {
  const DaFindingsOverview({
    super.key,
    required this.sample,
    this.expert,
    required this.finalized,
    required this.loading,
    required this.failed,
    required this.onReview,
    required this.onExplain,
    required this.onRetry,
  });
  final DaSampleResults sample;
  final DaExpertResults? expert;
  final bool finalized, loading, failed;
  final VoidCallback onReview, onExplain, onRetry;

  @override
  Widget build(BuildContext context) {
    final reviewed = expert?.available == true;
    final missingPhotos = sample.plants
        .where((p) => sample.observation(p) != null && sample.photos(p).isEmpty)
        .length;
    final infestation = DaSampledInfestation(
      sample,
      finalized: finalized,
      expert: expert,
    );
    final date =
        sample.detail.assessment.completedAt ??
        sample.detail.assessment.startedAt ??
        sample.detail.assessment.createdAt;
    final signs = <({String label, IconData icon, int count, Color color})>[];
    for (final sign in [
      (
        2,
        'Potential larvae',
        Icons.pest_control_outlined,
        const Color(0xFF355D8E),
      ),
      (
        1,
        'Potential frass',
        Icons.scatter_plot_outlined,
        const Color(0xFF805C39),
      ),
      (3, 'Potential eggs', Icons.egg_outlined, const Color(0xFF87671D)),
    ]) {
      final count = sample.plants
          .where(
            (p) =>
                sample.isAssessable(p) &&
                sample
                    .screening(p)!
                    .result
                    .detectionBoxes
                    .any((b) => b.classId == sign.$1),
          )
          .length;
      if (count > 0) {
        signs.add((
          label: sign.$2,
          icon: sign.$3,
          count: count,
          color: sign.$4,
        ));
      }
    }
    String percent(double? value) =>
        value == null ? 'Unavailable' : '${value.toStringAsFixed(1)}%';
    final leadValue = reviewed
        ? expert!.mean == null
              ? 'Unavailable'
              : '${expert!.mean!.toStringAsFixed(2)} / 9'
        : percent(sample.screeningPercent);
    final leadColor = reviewed
        ? switch (daSeverityBand(expert!.mean)?.referenceRating) {
            1 => const Color(0xFF2D6541),
            3 => const Color(0xFF21608C),
            5 => const Color(0xFF53700F),
            7 => const Color(0xFF8A570B),
            9 => const Color(0xFFB52626),
            _ => AppColors.textSecondary,
          }
        : const Color(0xFF956022);
    return Container(
      key: const Key('da_findings_overview'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE5DB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _label(
                  reviewed ? 'EXPERT FINDINGS' : 'APP SCREENING',
                  reviewed
                      ? Icons.verified_outlined
                      : Icons.image_search_outlined,
                  leadColor,
                ),
                AppText(
                  'Assessed ${DateFormat('MMM d, yyyy').format(date.toLocal())}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            key: reviewed ? null : const Key('da_damage_screening'),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  reviewed ? 'Mean Davis severity' : 'Damage screening',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  leadValue,
                  style: TextStyle(
                    fontSize: 44,
                    height: 1.15,
                    letterSpacing: -1.5,
                    fontWeight: FontWeight.w800,
                    color: leadColor,
                  ),
                ),
                const SizedBox(height: 8),
                AppText(
                  reviewed
                      ? 'DA classification: ${daSeverityClassification(expert!.mean)}'
                      : '${sample.positivePlants} of ${sample.assessablePlants} screened plants flagged for damage',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: leadColor,
                  ),
                ),
                const SizedBox(height: 6),
                AppText(
                  reviewed
                      ? '${expert!.scoredPlants} plants scored'
                      : 'Saved model screening',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (!reviewed && sample.assessablePlants > 0) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: sample.screeningPercent! / 100,
                      minHeight: 6,
                      color: leadColor,
                      backgroundColor: const Color(0xFFF0ECE5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E9E2)),
          _metric(
            key: const Key('da_sampled_infestation'),
            icon: Icons.bug_report_outlined,
            title: finalized
                ? 'Current sampled infestation'
                : 'Provisional sampled infestation',
            value: percent(infestation.percent),
            detail:
                '${infestation.infested} of ${infestation.denominator} plants · ${infestation.assessable} assessable'
                '${infestation.unavailable > 0 ? ' · ${infestation.unavailable} unavailable' : ''}',
            note: finalized
                ? 'Expert-assessed fresh damage'
                : 'Potential eggs, larvae or frass',
          ),
          if (reviewed)
            _metric(
              key: const Key('da_expert_damage'),
              icon: Icons.fact_check_outlined,
              title: 'FAW damage incidence',
              value: percent(expert!.damagePercent),
              detail:
                  '${expert!.damagedPlants} of ${expert!.scoredPlants} scored plants',
              note: 'Includes old and fresh damage.',
            ),
          if (reviewed)
            _metric(
              key: const Key('da_damage_screening'),
              icon: Icons.image_search_outlined,
              title: 'Original app damage screening',
              value: percent(sample.screeningPercent),
              detail:
                  '${sample.positivePlants} of ${sample.assessablePlants} screened plants',
              note: 'Saved model result, separate from the expert findings.',
            ),
          if (signs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppText(
                    'APP-DETECTED SIGNS',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final sign in signs)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: sign.color.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(sign.icon, size: 16, color: sign.color),
                              const SizedBox(width: 5),
                              Flexible(
                                child: AppText(
                                  '${sign.label} · ${sign.count} plants',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: sign.color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  AppText(
                    finalized
                        ? 'Saved model indications'
                        : 'Potential signs in the saved plant photos',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFF4F7F1),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _label(
                  '${sample.savedPlants}/${sample.expectedPlants} plants saved',
                  Icons.checklist_outlined,
                  AppColors.primary,
                ),
                if (sample.remainingPlants > 0)
                  AppText(
                    '${sample.remainingPlants} still to record',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF956022),
                    ),
                  ),
                if (sample.unavailablePlants > 0)
                  AppText(
                    '${sample.unavailablePlants} screening unavailable',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF956022),
                    ),
                  ),
                if (missingPhotos > 0)
                  AppText(
                    '$missingPhotos plants without saved photos',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF956022),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton.icon(
                  onPressed: failed ? onRetry : onReview,
                  icon: Icon(
                    failed ? Icons.refresh_rounded : Icons.rate_review_outlined,
                    size: 17,
                  ),
                  label: AppText(
                    failed
                        ? 'Retry expert findings'
                        : reviewed
                        ? 'View expert ratings'
                        : loading
                        ? 'Loading expert findings…'
                        : finalized
                        ? 'Open finalized review'
                        : 'Expert review pending',
                  ),
                ),
                TextButton.icon(
                  onPressed: onExplain,
                  icon: const Icon(Icons.calculate_outlined, size: 17),
                  label: const AppText('How this is calculated'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, IconData icon, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Flexible(
        child: AppText(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    ],
  );

  Widget _metric({
    Key? key,
    required IconData icon,
    required String title,
    required String value,
    required String detail,
    required String note,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 9),
            Expanded(
              child: AppText(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          value,
          style: const TextStyle(
            fontSize: 27,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: Color(0xFF203B2C),
          ),
        ),
        const SizedBox(height: 4),
        AppText(detail, style: const TextStyle(fontSize: 12, height: 1.4)),
        const SizedBox(height: 3),
        AppText(
          note,
          style: const TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
