import 'dart:io';
import '../../localization/app_text.dart';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import 'field_workflow_components.dart';

enum ReviewPositionState {
  confirmed,
  notReviewed,
  missing,
  insufficient,
  fallback,
  notAssessable,
}

class StationReviewHeader extends StatelessWidget {
  const StationReviewHeader({
    super.key,
    required this.stationNumber,
    required this.confirmedCount,
    required this.itemLabel,
    this.needsAttentionCount = 0,
    this.blockNumber,
    this.stageLabel = 'FIELD REVIEW',
    this.healthyCount,
    this.infestedCount,
    this.progressSubtitle,
  });

  final int stationNumber;
  final int confirmedCount;
  final String itemLabel;
  final int needsAttentionCount;
  final int? blockNumber;
  final String stageLabel;
  final int? healthyCount;
  final int? infestedCount;
  final String? progressSubtitle;

  @override
  Widget build(BuildContext context) => WorkflowContextHeader(
    stageLabel: stageLabel,
    blockNumber: blockNumber,
    stationNumber: stationNumber,
    title: 'Station Evidence Review',
    subtitle:
        progressSubtitle ??
        '$confirmedCount of 10 $itemLabel recorded and reviewed',
    completedCount: confirmedCount,
    totalCount: 10,
    attentionCount: 0,
  );
}

class StationAgronomicThreatCard extends StatelessWidget {
  const StationAgronomicThreatCard({
    super.key,
    required this.growthStage,
    this.totalPlants = 10,
    this.screeningMode = false,
    required this.infestedCount,
    required this.healthyCount,
    this.notAssessableCount = 0,
    this.avgDavisGrade,
    this.larvaeCount = 0,
    this.frassCount = 0,
    this.whorlDamageCount = 0,
    this.cutSeedlingCount = 0,
    this.emptySpotCount = 0,
    this.tasselSilkInfestedCount = 0,
    this.earDamageCount = 0,
  });

  final String growthStage;
  final int totalPlants;
  final bool screeningMode;
  final int infestedCount;
  final int healthyCount;
  final int notAssessableCount;
  final double? avgDavisGrade;
  final int larvaeCount;
  final int frassCount;
  final int whorlDamageCount;
  final int cutSeedlingCount;
  final int emptySpotCount;
  final int tasselSilkInfestedCount;
  final int earDamageCount;

  @override
  Widget build(BuildContext context) {
    final signalColor = screeningMode && totalPlants == 0
        ? Colors.grey
        : infestedCount > 0
        ? AppColors.severeSeverityRing
        : AppColors.highContrastGreen;
    final signalBackground = screeningMode && totalPlants == 0
        ? const Color(0xFFF1F5F9)
        : infestedCount > 0
        ? AppColors.severeSeverityBg
        : AppColors.primaryLight;
    final sampledFraction = totalPlants == 0
        ? 0.0
        : (infestedCount / totalPlants).clamp(0.0, 1.0);
    return Card(
      key: const Key('agronomic_threat_card'),
      color: signalBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.monitor_heart_outlined,
                      color: signalColor,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText(
                            screeningMode
                                ? 'Damage-screening preview'
                                : 'Agronomic threat preview',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: signalColor),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            screeningMode
                                ? (totalPlants == 0
                                      ? 'Not assessed'
                                      : '$infestedCount of $totalPlants plants screened positive.')
                                : infestedCount > 0
                                ? '$infestedCount of $totalPlants assessed plants have current FAW-consistent evidence.'
                                : 'No current FAW-consistent evidence is recorded in assessed plants.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: sampledFraction,
                          minHeight: 8,
                          backgroundColor: AppColors.surfaceContainer,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            signalColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppText(
                      '$infestedCount of $totalPlants',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: signalColor),
                    ),
                  ],
                ),
                const Divider(),
                if (!screeningMode) _buildStageMetrics(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageMetrics(BuildContext context) {
    final chips = <Widget>[];

    switch (growthStage) {
      case 've_v2':
        final emergedCount = totalPlants - emptySpotCount;
        chips.addAll([
          _MetricBadge(
            label: 'Emergence recorded',
            value: '$emergedCount of $totalPlants positions',
            color: AppColors.highContrastGreen,
          ),
          if (cutSeedlingCount > 0)
            _MetricBadge(
              label: 'Cut or remnant',
              value: '$cutSeedlingCount positions',
              color: AppColors.severeSeverityRing,
            ),
          if (emptySpotCount > 0)
            _MetricBadge(
              label: 'Empty Spots',
              value: '$emptySpotCount',
              color: Colors.black54,
            ),
        ]);
        break;

      case 'vt_r2':
        chips.addAll([
          _MetricBadge(
            label: 'Current tassel/ear-region evidence',
            value: '$tasselSilkInfestedCount of $totalPlants',
            color: tasselSilkInfestedCount > 0
                ? AppColors.severeSeverityRing
                : AppColors.highContrastGreen,
          ),
          if (larvaeCount > 0)
            _MetricBadge(
              label: 'Larvae Observed',
              value: '$larvaeCount',
              color: const Color(0xFFB3261E),
            ),
          if (frassCount > 0)
            _MetricBadge(
              label: 'Ear Axil Frass',
              value: '$frassCount plants',
              color: const Color(0xFFB3261E),
            ),
        ]);
        break;

      case 'r3_r6':
        chips.addAll([
          _MetricBadge(
            label: 'Ears with current evidence',
            value: '$earDamageCount of $totalPlants',
            color: earDamageCount > 0
                ? const Color(0xFFB3261E)
                : const Color(0xFF176B3A),
          ),
          if (larvaeCount > 0)
            _MetricBadge(
              label: 'Ear Boring Larvae',
              value: '$larvaeCount',
              color: const Color(0xFFB3261E),
            ),
        ]);
        break;

      default: // v3_v6, v7_v12, vegetative
        chips.addAll([
          if (avgDavisGrade != null && avgDavisGrade! > 1.0)
            _MetricBadge(
              label: 'Avg Damage Severity',
              value: 'Davis Grade ${avgDavisGrade!.toStringAsFixed(1)}',
              color: avgDavisGrade! >= 4.0
                  ? const Color(0xFFB3261E)
                  : const Color(0xFFE67C00),
            ),
          if (larvaeCount > 0)
            _MetricBadge(
              label: 'Larvae Detected',
              value: '$larvaeCount',
              color: const Color(0xFFB3261E),
            ),
          if (frassCount > 0)
            _MetricBadge(
              label: 'Fresh Frass',
              value: '$frassCount plants',
              color: const Color(0xFFB3261E),
            ),
          if (whorlDamageCount > 0)
            _MetricBadge(
              label: 'Whorl Feeding',
              value: '$whorlDamageCount plants',
              color: const Color(0xFFB3261E),
            ),
        ]);
    }

    if (chips.isEmpty) {
      chips.add(
        const _MetricBadge(
          label: 'Recorded status',
          value: 'No current signs in assessed plants',
          color: AppColors.highContrastGreen,
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 6, children: chips);
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        softWrap: true,
      ),
    );
  }
}

class StationReviewStatusStrip extends StatelessWidget {
  const StationReviewStatusStrip({
    super.key,
    required this.states,
    required this.itemLabel,
    required this.onSelected,
  });

  final Map<int, ReviewPositionState> states;
  final String itemLabel;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$itemLabel review progress',
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var position = 1; position <= 10; position++)
          _PositionButton(
            position: position,
            state: states[position] ?? ReviewPositionState.notReviewed,
            itemLabel: itemLabel,
            onTap: () => onSelected(position),
          ),
      ],
    ),
  );
}

class StationReviewBottomBar extends StatelessWidget {
  const StationReviewBottomBar({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.actionKey,
    required this.onPressed,
    this.isSaving = false,
  });

  final String message;
  final String actionLabel;
  final Key actionKey;
  final VoidCallback? onPressed;
  final bool isSaving;

  @override
  Widget build(BuildContext context) => StickyWorkflowActionBar(
    message: message,
    actionLabel: actionLabel,
    actionKey: actionKey,
    onPressed: onPressed,
    isSaving: isSaving,
  );
}

class _PositionButton extends StatelessWidget {
  const _PositionButton({
    required this.position,
    required this.state,
    required this.itemLabel,
    required this.onTap,
  });

  final int position;
  final ReviewPositionState state;
  final String itemLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon, label) = switch (state) {
      ReviewPositionState.confirmed => (
        const Color(0xFFDDF1E2),
        const Color(0xFF176B3A),
        Icons.check,
        'confirmed',
      ),
      ReviewPositionState.missing => (
        const Color(0xFFFFE3DE),
        const Color(0xFF9F2D20),
        Icons.image_not_supported_outlined,
        'missing evidence',
      ),
      ReviewPositionState.insufficient => (
        const Color(0xFFFFE3DE),
        const Color(0xFF9F2D20),
        Icons.priority_high,
        'insufficient evidence',
      ),
      ReviewPositionState.fallback => (
        const Color(0xFFE3EDF7),
        const Color(0xFF24547A),
        Icons.description_outlined,
        'manual fallback',
      ),
      ReviewPositionState.notAssessable => (
        const Color(0xFFE8EAEB),
        const Color(0xFF4E585C),
        Icons.block_outlined,
        'not assessable',
      ),
      ReviewPositionState.notReviewed => (
        const Color(0xFFFFEBC4),
        const Color(0xFF7A4A00),
        Icons.pending_outlined,
        'not reviewed',
      ),
    };
    return Semantics(
      button: true,
      label: '$itemLabel $position, $label',
      child: InkWell(
        key: Key('review_position_$position'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 54, minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: foreground.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: foreground),
              const SizedBox(height: 2),
              FittedBox(
                child: AppText(
                  '$position',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompactPlantAuditTile extends StatelessWidget {
  const CompactPlantAuditTile({
    super.key,
    required this.position,
    this.itemLabel = 'Plant',
    required this.statusLabel,
    required this.statusColor,
    required this.statusBgColor,
    this.symptomsSummary,
    this.thumbnailFile,
    this.isUnassessed = false,
    required this.onTap,
  });

  final int position;
  final String itemLabel;
  final String statusLabel;
  final Color statusColor;
  final Color statusBgColor;
  final String? symptomsSummary;
  final File? thumbnailFile;
  final bool isUnassessed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      color: Colors.white,
      child: InkWell(
        key: Key('compact_plant_tile_$position'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: statusColor.withValues(alpha: 0.15),
                foregroundColor: statusColor,
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: AppText(
                      '$position',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppText(
                          '$itemLabel $position',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusBgColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (symptomsSummary != null &&
                        symptomsSummary!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        symptomsSummary!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (thumbnailFile != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    thumbnailFile!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right, color: Colors.black38, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class StationDetailsFooterStrip extends StatelessWidget {
  const StationDetailsFooterStrip({
    super.key,
    this.gpsAccuracyM,
    this.notLocatedReason,
    this.contextPhotoFile,
    this.onTapContextPhoto,
    this.durationLabel,
  });

  final double? gpsAccuracyM;
  final String? notLocatedReason;
  final File? contextPhotoFile;
  final VoidCallback? onTapContextPhoto;
  final String? durationLabel;

  @override
  Widget build(BuildContext context) {
    final gpsText = gpsAccuracyM != null
        ? 'GPS accurate to ±${gpsAccuracyM!.toStringAsFixed(1)}m'
        : 'GPS: ${notLocatedReason ?? "Saved"}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  gpsText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (contextPhotoFile != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onTapContextPhoto,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      contextPhotoFile!,
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (durationLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              durationLabel!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
