import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/repositories/field_repository.dart';
import '../providers/assessment_workspace_provider.dart';
import '../providers/field_workspace_provider.dart';
import '../screens/fields_screen.dart';
import '../theme/app_colors.dart';

class ActiveWorkspaceCard extends StatelessWidget {
  const ActiveWorkspaceCard({super.key});

  void _openFields(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FieldsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fieldProvider = context.watch<FieldWorkspaceProvider>();
    final isAssessmentInProgress = context
        .select<AssessmentWorkspaceProvider, bool>(
          (provider) => provider.isInProgress,
        );

    if (fieldProvider.isLoading) {
      return const SizedBox(
        height: 180,
        child: Card(child: Center(child: CircularProgressIndicator())),
      );
    }

    final workspace = fieldProvider.activeWorkspace;
    if (workspace == null) {
      return _EmptyWorkspaceCard(onAdd: () => _openFields(context));
    }

    return _WorkspaceCard(
      workspace: workspace,
      isAssessmentInProgress: isAssessmentInProgress,
      onChangeField: () => _openFields(context),
    );
  }
}

class _EmptyWorkspaceCard extends StatelessWidget {
  const _EmptyWorkspaceCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.landscape_outlined,
              size: 34,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          const AppText(
            'Set up your first maize field',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const AppText(
            'Field details are saved on this phone and keep outlines, crop cycles, and assessments together.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('home_add_first_field_button'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const AppText('Add your first field'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.workspace,
    required this.isAssessmentInProgress,
    required this.onChangeField,
  });

  final FieldWorkspaceRecord workspace;
  final bool isAssessmentInProgress;
  final VoidCallback onChangeField;

  @override
  Widget build(BuildContext context) {
    final field = workspace.field;
    final boundary = workspace.boundary;
    final cycle = workspace.cropCycle;
    final spatialState = workspace.spatialState;
    final hasOutline = spatialState == FieldSpatialState.approximateOutline;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
        boxShadow: AppColors.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 118,
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF66A144)],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
            ),
            child: const Stack(
              children: [
                Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(
                    Icons.agriculture,
                    size: 76,
                    color: Color(0x55FFFFFF),
                  ),
                ),
                Align(alignment: Alignment.topLeft, child: _ActiveBadge()),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                _StatusBadge(
                  warning: false,
                  label: isAssessmentInProgress
                      ? 'Assessment in progress'
                      : switch (spatialState) {
                          FieldSpatialState.approximateOutline =>
                            'Ready - approximate outline saved',
                          FieldSpatialState.entranceLocation =>
                            'Ready - entrance GPS saved',
                          FieldSpatialState.reportedAreaOnly =>
                            'Ready - reported area only',
                        },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      _MetaItem(
                        icon: Icons.location_on,
                        label: 'LOCATION',
                        value: _locationLabel(field),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MetaItem(
                              icon: Icons.straighten,
                              label: hasOutline
                                  ? 'OUTLINE AREA'
                                  : 'REPORTED AREA',
                              value: boundary == null
                                  ? 'Not entered'
                                  : '${boundary.areaHectares.toStringAsFixed(2)} ha',
                            ),
                          ),
                          const Expanded(
                            child: _MetaItem(
                              icon: Icons.agriculture_outlined,
                              label: 'GROWTH STAGE',
                              value: 'Not assessed',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MetaItem(
                              icon: Icons.calendar_today,
                              label: 'CROP AGE',
                              value: _cropAgeLabel(cycle?.plantingDate),
                            ),
                          ),
                          Expanded(
                            child: _MetaItem(
                              icon: Icons.event,
                              label: 'PLANTING DATE',
                              value: cycle?.plantingDate == null
                                  ? 'Not entered'
                                  : DateFormat(
                                      'MMM d, yyyy',
                                    ).format(cycle!.plantingDate!.toLocal()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: onChangeField,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: AppColors.outlineVariant,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: const AppText(
                      'Change Field',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _locationLabel(dynamic field) {
    final parts = [
      field.barangay,
      field.municipalityCity,
      field.province,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(', ');
    return 'Location not entered';
  }

  String _cropAgeLabel(DateTime? plantingDate) {
    if (plantingDate == null) return 'Not available';
    final days = DateTime.now().difference(plantingDate.toLocal()).inDays;
    return '${days < 0 ? 0 : days} DAP';
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF8BCB82)),
      ),
      child: const AppText(
        'ACTIVE WORKSPACE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.warning, required this.label});

  final bool warning;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = warning ? const Color(0xFF9A6700) : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF3CD) : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AppColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
