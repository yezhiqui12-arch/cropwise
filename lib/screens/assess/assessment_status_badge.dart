import '../../localization/app_text.dart';
import 'package:flutter/material.dart';
import '../../models/assessment_history_models.dart';
import '../../theme/app_colors.dart';

/// Icon and text communicate status independently of color.
class AssessmentStatusBadge extends StatelessWidget {
  const AssessmentStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });
  final String status;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final attention = status == 'safety_blocked' || status == 'invalid';
    final completed = status == 'completed';
    final warning =
        status == 'draft' ||
        status == 'incomplete' ||
        status == 'safety_blocked' ||
        status == 'invalid';
    final background = attention
        ? colors.errorContainer
        : completed
        ? const Color(0xFFDDF1DB)
        : warning
        ? const Color(0xFFFFE7A3)
        : colors.primaryContainer;
    final foreground = attention
        ? colors.onErrorContainer
        : completed
        ? AppColors.highContrastGreen
        : warning
        ? const Color(0xFF725000)
        : colors.onPrimaryContainer;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AppText(
        assessmentStatusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
