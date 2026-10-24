import 'package:flutter/material.dart';
import '../../localization/app_text.dart';
import '../../localization/app_language.dart';

import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';

class FieldWorkflowShell extends StatelessWidget {
  const FieldWorkflowShell({
    super.key,
    required this.children,
    required this.bottomBar,
    this.scrollKey,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.lg,
    ),
  });

  final List<Widget> children;
  final Widget bottomBar;
  final Key? scrollKey;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.workflowMaxWidth,
            ),
            child: SingleChildScrollView(
              key: scrollKey,
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
      bottomBar,
    ],
  );
}

class WorkflowContextHeader extends StatelessWidget {
  const WorkflowContextHeader({
    super.key,
    required this.stageLabel,
    this.stationNumber,
    required this.title,
    required this.subtitle,
    required this.completedCount,
    required this.totalCount,
    required this.attentionCount,
    this.blockNumber,
    this.connectionLabel = 'Offline ready',
  });

  final String stageLabel;
  final int? blockNumber;
  final int? stationNumber;
  final String title;
  final String subtitle;
  final int completedCount;
  final int totalCount;
  final int attentionCount;
  final String connectionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = completedCount == totalCount && attentionCount == 0;
    return Semantics(
      container: true,
      header: true,
      label:
          '$title. $completedCount of $totalCount complete. '
          '$attentionCount need attention.',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: ready ? AppColors.lowSeverityBg : AppColors.surfaceCard,
          borderRadius: AppRadii.prominentBorder,
          border: Border.all(
            color: ready ? AppColors.lowSeverityRing : AppColors.outlineVariant,
            width: ready ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    WorkflowBadge(
                      label: stageLabel,
                      icon: Icons.checklist_outlined,
                      foreground: AppColors.onPrimary,
                      background: AppColors.primary,
                    ),
                    WorkflowBadge(
                      label: [
                        if (blockNumber != null) 'Block $blockNumber',
                        if (stationNumber != null) 'Station $stationNumber',
                      ].join(' · '),
                      icon: Icons.location_on_outlined,
                    ),
                  ],
                ),
                WorkflowBadge(
                  label: connectionLabel,
                  icon: Icons.offline_bolt_outlined,
                  foreground: AppColors.highContrastGreen,
                  background: AppColors.primaryLight,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppWords.of(context).translate(title),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              AppWords.of(context).translate(subtitle),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: totalCount == 0 ? 0 : completedCount / totalCount,
                      minHeight: 9,
                      backgroundColor: AppColors.surfaceContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppText(
                  '$completedCount/$totalCount',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.highContrastGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WorkflowBadge extends StatelessWidget {
  const WorkflowBadge({
    super.key,
    required this.label,
    this.icon,
    this.foreground = AppColors.textSecondary,
    this.background = AppColors.surfaceContainer,
  });

  final String label;
  final IconData? icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: foreground.withValues(alpha: 0.24)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: AppSpacing.xxs),
        ],
        Flexible(
          child: Text(
            AppWords.of(context).translate(label),
            softWrap: true,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ),
      ],
    ),
  );
}

class WorkflowSectionHeader extends StatelessWidget {
  const WorkflowSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xxs,
      AppSpacing.md,
      AppSpacing.xxs,
      AppSpacing.xs,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppWords.of(context).translate(title),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  AppWords.of(context).translate(subtitle!),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    ),
  );
}

class WorkflowFormSection extends StatelessWidget {
  const WorkflowFormSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.completed = false,
    this.initiallyExpanded = true,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool completed;
  final bool initiallyExpanded;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.55,
    child: Container(
      key: PageStorageKey<String>('workflow_form_$title'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: completed
                      ? AppColors.primaryLight
                      : AppColors.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  completed ? Icons.check : icon,
                  size: 20,
                  color: completed
                      ? AppColors.highContrastGreen
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppWords.of(context).translate(title),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        AppWords.of(context).translate(subtitle!),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index != children.length - 1)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class StickyWorkflowActionBar extends StatelessWidget {
  const StickyWorkflowActionBar({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
    this.actionKey,
    this.isSaving = false,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String message;
  final String actionLabel;
  final Key? actionKey;
  final VoidCallback? onPressed;
  final bool isSaving;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => Material(
    elevation: AppElevation.stickyAction,
    color: AppColors.surfaceCard,
    surfaceTintColor: Colors.transparent,
    child: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.workflowMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        AppWords.of(context).translate(message),
                        maxLines:
                            MediaQuery.textScalerOf(context).scale(1) >= 1.5
                            ? 2
                            : null,
                        overflow:
                            MediaQuery.textScalerOf(context).scale(1) >= 1.5
                            ? TextOverflow.ellipsis
                            : TextOverflow.visible,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (secondaryLabel == null)
                  FilledButton.icon(
                    key: actionKey,
                    onPressed: isSaving ? null : onPressed,
                    icon: isSaving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: Text(AppWords.of(context).translate(actionLabel)),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stackActions =
                          constraints.maxWidth < 420 ||
                          MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                      final secondary = OutlinedButton(
                        onPressed: isSaving ? null : onSecondary,
                        child: Text(
                          AppWords.of(context).translate(secondaryLabel!),
                        ),
                      );
                      final primary = FilledButton.icon(
                        key: actionKey,
                        onPressed: isSaving ? null : onPressed,
                        icon: isSaving
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          AppWords.of(context).translate(actionLabel),
                        ),
                      );
                      if (stackActions) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            primary,
                            TextButton(
                              onPressed: isSaving ? null : onSecondary,
                              child: Text(
                                AppWords.of(context).translate(secondaryLabel!),
                              ),
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: secondary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(flex: 2, child: primary),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String growthStageLabel(String growthStage) => switch (growthStage) {
  've' || 'v1' || 'v2' => 'VE–V2',
  'v3_v6' => 'V3–V6',
  'v7_v12' => 'V7–V12',
  'vt_r2' => 'VT–R2',
  'r3_r6' => 'R3–R6',
  _ => growthStage.toUpperCase(),
};
