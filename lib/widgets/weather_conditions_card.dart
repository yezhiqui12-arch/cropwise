import 'package:flutter/material.dart';
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
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Field conditions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      fieldName ?? 'Active maize field',
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'OFFLINE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (conditions.hasRecordedValues) ...[
            _ConditionRow(
              icon: Icons.water_drop_outlined,
              label: 'Rain wet the field in the last 48 hours',
              value: conditions.rainLabel,
            ),
            const Divider(height: 18),
            _ConditionRow(
              icon: Icons.landscape_outlined,
              label: 'Recorded field surface',
              value: conditions.surfaceLabel,
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Field conditions have not been recorded yet. WormWise asks about recent rain and the field surface when an assessment is prepared.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
            ),
          const SizedBox(height: 12),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.textSecondary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Live temperature, rainfall, and wind are not connected yet. No forecast values are estimated or invented.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldConditions {
  const _FieldConditions({this.rainCode, this.surfaceCode});

  final String? rainCode;
  final String? surfaceCode;

  bool get hasRecordedValues => rainCode != null || surfaceCode != null;

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
    );
  }
}
