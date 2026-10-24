import 'package:flutter/material.dart';
import '../../localization/app_text.dart';

import '../../models/assessment_history_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';

class AssessmentSummaryCard extends StatelessWidget {
  const AssessmentSummaryCard({super.key, required this.detail});

  final AssessmentHistoryDetail detail;

  @override
  Widget build(BuildContext context) {
    final workAreas = detail.requiredWorkAreaCount;
    final passed = detail.readiness.isValid;
    final historical = detail.assessment.status == 'completed';
    final observations = detail.stations.fold<int>(
      0,
      (count, station) => count + station.plants.length,
    );
    final title = historical
        ? passed
              ? 'Completion checks passed'
              : 'Needs verification'
        : passed
        ? 'Ready to complete'
        : 'Not ready to complete';
    final message = passed
        ? historical
              ? 'This completed record still meets the current completion checks.'
              : 'Saved records meet the current sampling checks.'
        : historical
        ? 'This assessment remains completed. Some saved data does not match current verification rules; no new fieldwork is required here.'
        : workAreas > 0
        ? '$workAreas previously reviewed ${workAreas == 1 ? 'station needs' : 'stations need'} attention.'
        : 'Continue scouting to complete the remaining stations and observations.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const Key('assessment_readiness_banner'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: passed ? AppColors.primaryLight : const Color(0xFFFFF1CF),
            borderRadius: AppRadii.cardBorder,
            border: Border.all(
              color: passed ? const Color(0xFFC9E4C6) : const Color(0xFFF2D896),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                passed ? Icons.task_alt : Icons.warning_amber_rounded,
                color: passed ? AppColors.primary : const Color(0xFFA65E00),
                size: 26,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: passed
                            ? AppColors.highContrastGreen
                            : const Color(0xFF8A4E00),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(message),
                    if (historical && !passed) ...[
                      const SizedBox(height: 5),
                      const AppText(
                        'The original completed status remains unchanged.',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _AssessmentCounts(
          observations: observations,
          photos: detail.evidence.length,
          remaining: workAreas,
          remainingLabel: historical ? 'Checks flagged' : 'Areas to review',
        ),
      ],
    );
  }
}

class _AssessmentCounts extends StatelessWidget {
  const _AssessmentCounts({
    required this.observations,
    required this.photos,
    required this.remaining,
    required this.remainingLabel,
  });

  final int observations;
  final int photos;
  final int remaining;
  final String remainingLabel;

  @override
  Widget build(BuildContext context) {
    final values = <({IconData icon, int value, String label})>[
      (
        icon: Icons.analytics_outlined,
        value: observations,
        label: 'Observations',
      ),
      (icon: Icons.photo_camera_outlined, value: photos, label: 'Photos'),
      (icon: Icons.checklist_rounded, value: remaining, label: remainingLabel),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < values.length; index++) ...[
            if (index > 0) const SizedBox(width: 6),
            Expanded(child: _CountTile(data: values[index])),
          ],
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.data});

  final ({IconData icon, int value, String label}) data;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: AppRadii.cardBorder,
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(data.icon, size: 20, color: AppColors.highContrastGreen),
            const SizedBox(width: 5),
            AppText(
              '${data.value}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          data.label,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    ),
  );
}
