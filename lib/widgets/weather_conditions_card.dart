import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import 'package:provider/provider.dart';

import '../providers/assessment_workspace_provider.dart';
import '../providers/field_workspace_provider.dart';
import '../theme/app_colors.dart';

class WeatherConditionsCard extends StatelessWidget {
  const WeatherConditionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final fieldName = context
        .watch<FieldWorkspaceProvider>()
        .activeWorkspace
        ?.field
        .name;
    final recordedContext = context
        .watch<AssessmentWorkspaceProvider>()
        .currentAssessment
        ?.weatherContext;
    final conditions = _FieldConditions.parse(recordedContext);

    return Container(
      key: const Key('field_conditions_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppText(
                      'Field conditions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    AppText(
                      '${fieldName ?? 'Active maize field'}  •  ${conditions.updatedLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 14),
          if (conditions.hasRecordedValues)
            Row(
              children: [
                Expanded(
                  child: _ConditionTile(
                    icon: Icons.water_drop,
                    label: 'Recent rain',
                    value: conditions.precipitationLabel,
                    color: const Color(0xFF1687B5),
                  ),
                ),
                const _ConditionDivider(),
                Expanded(
                  child: _ConditionTile(
                    icon: Icons.grass,
                    label: 'Field surface',
                    value: conditions.surfaceLabel,
                    color: AppColors.primary,
                  ),
                ),
                const _ConditionDivider(),
                Expanded(
                  child: _ConditionTile(
                    icon: Icons.agriculture_outlined,
                    label: 'Conditions',
                    value: conditions.conditionLabel,
                    color: AppColors.primary,
                  ),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const AppText(
                'Field conditions have not been recorded yet. WormWise asks about recent rain and the field surface when an assessment is prepared.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConditionTile extends StatelessWidget {
  const _ConditionTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 6),
        AppText(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ConditionDivider extends StatelessWidget {
  const _ConditionDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 62, color: AppColors.outlineVariant);
}

class _FieldConditions {
  const _FieldConditions({
    this.rainCode,
    this.surfaceCode,
    this.precipitationMm,
    this.updatedAt,
  });

  final String? rainCode;
  final String? surfaceCode;
  final double? precipitationMm;
  final DateTime? updatedAt;

  bool get hasRecordedValues =>
      rainCode != null || surfaceCode != null || precipitationMm != null;

  String get precipitationLabel => precipitationMm != null
      ? '${precipitationMm!.toStringAsFixed(1)} mm / 48h'
      : rainLabel;

  String get conditionLabel => switch (surfaceCode) {
    'dry' || 'damp' => 'Good',
    'muddy' || 'standing_water' => 'Use caution',
    _ => rainCode == 'yes' ? 'Wet' : 'Recorded',
  };

  String get updatedLabel {
    final date = updatedAt;
    if (date == null) return 'Saved conditions';
    final hours = DateTime.now().toUtc().difference(date.toUtc()).inHours;
    return hours <= 1 ? 'Updated recently' : 'Updated $hours hr ago';
  }

  String get rainLabel => switch (rainCode) {
    'yes' => 'Yes',
    'no' => 'No',
    'not_sure' => 'Not sure',
    _ => 'Not recorded',
  };

  String get surfaceLabel => switch (surfaceCode) {
    'dry' => 'Mostly dry and firm',
    'damp' => 'Damp but easy to walk',
    'muddy' => 'Muddy or slippery',
    'standing_water' => 'Standing water is present',
    'not_sure' => 'Not sure',
    _ => 'Not recorded',
  };

  static _FieldConditions parse(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      return const _FieldConditions();
    }
    final values = <String, String>{};
    for (final part in encoded.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0 || separator == part.length - 1) continue;
      values[part.substring(0, separator)] = part.substring(separator + 1);
    }
    return _FieldConditions(
      rainCode: values['rain_wet_field_last_48h'],
      surfaceCode: values['field_surface'],
      precipitationMm: double.tryParse(
        values['open_meteo_precipitation_last_48h_mm'] ?? '',
      ),
      updatedAt: DateTime.tryParse(values['weather_fetched_at_utc'] ?? ''),
    );
  }
}
