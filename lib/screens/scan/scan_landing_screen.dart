import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/local/database_codes.dart';
import '../../providers/assessment_workspace_provider.dart';
import '../../providers/field_workspace_provider.dart';
import '../../theme/app_colors.dart';
import '../assessment_session_screen.dart';
import '../assessment_setup_screen.dart';

class ScanLandingScreen extends StatelessWidget {
  const ScanLandingScreen({
    super.key,
    required this.onRegisterField,
    required this.onCompleteFieldOutline,
  });

  final VoidCallback onRegisterField;
  final VoidCallback onCompleteFieldOutline;

  @override
  Widget build(BuildContext context) {
    final fields = context.watch<FieldWorkspaceProvider>();
    final assessments = context.watch<AssessmentWorkspaceProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: SafeArea(child: _buildContent(context, fields, assessments)),
    );
  }

  Widget _buildContent(
    BuildContext context,
    FieldWorkspaceProvider fields,
    AssessmentWorkspaceProvider assessments,
  ) {
    if (fields.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (fields.error != null) {
      return const _ScanMessage(
        icon: Icons.storage_outlined,
        status: 'LOCAL DATA ERROR',
        title: 'Could not load saved field data',
        message:
            'Close and reopen WormWise. Your existing records have not been intentionally changed.',
      );
    }

    final workspace = fields.activeWorkspace;
    if (workspace == null) {
      return _ScanMessage(
        icon: Icons.agriculture_outlined,
        status: 'FIELD REQUIRED',
        title: 'Register a maize field',
        message:
            'Add or select a maize field before setting up guided scouting.',
        actionKey: const Key('register_field_from_scan_button'),
        actionLabel: 'Register field',
        onAction: onRegisterField,
      );
    }

    final assessment = assessments.currentAssessment;
    if (!workspace.hasApproximateOutline) {
      return _ScanMessage(
        fieldName: workspace.field.name,
        icon: Icons.polyline_outlined,
        status: 'FIELD OUTLINE REQUIRED',
        title: 'Complete field outline',
        message: assessment == null
            ? 'Confirm the approximate outline used to organize scouting for ${workspace.field.name}.'
            : 'Your assessment setup remains saved on this phone. Confirm the field outline before continuing it.',
        supportingMessage:
            'The outline is an approximate scouting guide, not a legal or survey-grade property boundary.',
        actionKey: const Key('complete_field_outline_from_scan_button'),
        actionLabel: 'Complete field outline',
        onAction: onCompleteFieldOutline,
      );
    }

    if (assessments.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (assessments.error != null) {
      return _ScanMessage(
        fieldName: workspace.field.name,
        icon: Icons.storage_outlined,
        status: 'LOCAL DATA ERROR',
        title: 'Could not load the saved assessment',
        message:
            'Close and reopen WormWise. The field and assessment records remain saved on this phone.',
      );
    }

    if (assessment == null) {
      return _ScanMessage(
        fieldName: workspace.field.name,
        icon: Icons.fact_check_outlined,
        status: 'READY FOR SETUP',
        title: 'Set up an assessment',
        message:
            'Confirm the evaluator, maize growth stage, scouting route, field conditions, and field-entry safety.',
        supportingMessage: 'Field outline confirmed. Saved on this phone.',
        actionKey: const Key('setup_assessment_from_scan_button'),
        actionLabel: 'Set up assessment',
        onAction: () => _openSetup(context),
      );
    }

    if (assessment.status == DatabaseCodes.safetyBlocked) {
      return _ScanMessage(
        fieldName: workspace.field.name,
        icon: Icons.health_and_safety_outlined,
        warning: true,
        status: 'FIELD ENTRY BLOCKED',
        title: 'Field entry needs review',
        message:
            'Do not enter the field until the required waiting period or treatment history can be verified.',
        supportingMessage: 'Assessment setup saved on this phone.',
        actionKey: const Key('review_safety_from_scan_button'),
        actionLabel: 'Review field-entry safety',
        onAction: () => _openSetup(context),
      );
    }

    if (assessment.status == DatabaseCodes.inProgress) {
      return _ScanMessage(
        fieldName: workspace.field.name,
        icon: Icons.play_circle_outline,
        status: 'ASSESSMENT ACTIVE',
        title: 'Resume assessment',
        message:
            'The assessment setup is active. Open its saved overview to continue.',
        supportingMessage: 'Saved on this phone.',
        actionKey: const Key('resume_assessment_from_scan_button'),
        actionLabel: 'Resume assessment',
        onAction: () => _openSession(context),
      );
    }

    return _ScanMessage(
      fieldName: workspace.field.name,
      icon: Icons.assignment_outlined,
      status: 'SETUP SAVED',
      title: 'Finish assessment setup',
      message:
          'Continue the saved setup and complete the field-entry safety check.',
      supportingMessage: 'Saved on this phone.',
      actionKey: const Key('resume_setup_from_scan_button'),
      actionLabel: 'Continue setup',
      onAction: () => _openSetup(context),
    );
  }

  void _openSetup(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const AssessmentSetupScreen()),
    );
  }

  void _openSession(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const AssessmentSessionScreen()),
    );
  }
}

class _ScanMessage extends StatelessWidget {
  const _ScanMessage({
    required this.icon,
    required this.status,
    required this.title,
    required this.message,
    this.fieldName,
    this.supportingMessage,
    this.actionKey,
    this.actionLabel,
    this.onAction,
    this.warning = false,
  });

  final IconData icon;
  final String status;
  final String title;
  final String message;
  final String? fieldName;
  final String? supportingMessage;
  final Key? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final accent = warning ? const Color(0xFF8A5A00) : AppColors.primary;
    final background = warning
        ? const Color(0xFFFFF3CD)
        : AppColors.surfaceCard;

    return ListView(
      key: const Key('scan_landing_scroll_view'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        if (fieldName != null) ...[
          const Text(
            'CURRENT FIELD',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fieldName!,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 40),
              const SizedBox(height: 14),
              Text(
                status,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              if (supportingMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  supportingMessage!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: double.infinity,
                    minHeight: 56,
                  ),
                  child: FilledButton.icon(
                    key: actionKey,
                    onPressed: onAction,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(actionLabel!),
                    style: FilledButton.styleFrom(backgroundColor: accent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
