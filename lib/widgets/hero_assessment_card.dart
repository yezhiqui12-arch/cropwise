import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import 'package:provider/provider.dart';

import '../data/local/database_codes.dart';
import '../data/repositories/field_repository.dart';
import '../providers/assessment_workspace_provider.dart';
import '../providers/field_workspace_provider.dart';
import '../screens/assessment_session_screen.dart';
import '../screens/assessment_setup_screen.dart';
import '../theme/app_colors.dart';

class HeroAssessmentCard extends StatelessWidget {
  const HeroAssessmentCard({super.key});

  @override
  Widget build(BuildContext context) {
    final assessmentProvider = context.watch<AssessmentWorkspaceProvider>();
    final workspace = context.watch<FieldWorkspaceProvider>().activeWorkspace;
    final assessment = assessmentProvider.currentAssessment;
    final fieldName = workspace?.field.name ?? 'the selected field';

    if (assessmentProvider.isLoading) {
      return const Card(
        child: SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (assessment?.status == DatabaseCodes.inProgress) {
      return _AssessmentActionCard(
        title: 'Continue Assessment',
        message:
            'The assessment setup for $fieldName is saved offline and ready for guided scouting.',
        badge: 'IN PROGRESS',
        icon: Icons.play_circle_outline,
        buttonKey: const Key('continue_assessment_button'),
        buttonLabel: 'Open Assessment',
        onPressed: () => _openSession(context),
      );
    }

    if (assessment?.status == DatabaseCodes.safetyBlocked) {
      return _AssessmentActionCard(
        title: 'Field Entry Needs Review',
        message:
            'The setup is saved, but scouting is blocked until the pesticide waiting period can be verified.',
        badge: 'SAFETY BLOCKED',
        icon: Icons.health_and_safety_outlined,
        warning: true,
        buttonKey: const Key('review_assessment_safety_button'),
        buttonLabel: 'Review Safety',
        onPressed: () => _openSetup(context),
      );
    }

    if (assessment != null) {
      return _AssessmentActionCard(
        title: 'Finish Assessment Setup',
        message:
            'An unfinished setup for $fieldName is saved offline. Complete its field-entry safety check.',
        badge: 'DRAFT',
        icon: Icons.assignment_outlined,
        buttonKey: const Key('resume_assessment_setup_button'),
        buttonLabel: 'Resume Setup',
        onPressed: () => _openSetup(context),
      );
    }

    return _StartAssessmentCard(
      title: 'Start FAW Assessment',
      message: _readyMessage(fieldName, workspace?.spatialState),
      buttonKey: const Key('start_assessment_button'),
      buttonLabel: workspace == null
          ? 'Select Field First'
          : 'Set Up Assessment',
      onPressed: workspace == null
          ? () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: AppText(
                  'Add or select a maize field before starting an assessment.',
                ),
              ),
            )
          : () => _openSetup(context),
    );
  }

  String _readyMessage(String fieldName, FieldSpatialState? spatialState) {
    return switch (spatialState) {
      null => 'Add or select a maize field before starting an assessment.',
      FieldSpatialState.approximateOutline =>
        'Set the growth stage, scouting route, evaluator, and field-entry safety for $fieldName.',
      FieldSpatialState.entranceLocation =>
        'The entrance GPS for $fieldName is recorded. Add its boundary to prepare the scouting map.',
      FieldSpatialState.reportedAreaOnly =>
        'Add the boundary of $fieldName to prepare its scouting map.',
    };
  }

  void _openSetup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AssessmentSetupScreen()),
    );
  }

  void _openSession(BuildContext context) {
    final assessmentId = context
        .read<AssessmentWorkspaceProvider>()
        .currentAssessment
        ?.id;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssessmentSessionScreen(assessmentId: assessmentId),
      ),
    );
  }
}

class _StartAssessmentCard extends StatelessWidget {
  const _StartAssessmentCard({
    required this.title,
    required this.message,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onPressed,
  });
  final String title;
  final String message;
  final Key buttonKey;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.fact_check_outlined, color: Colors.white70, size: 18),
            SizedBox(width: 7),
            AppText(
              'FIELD SCOUTING',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 47,
          child: FilledButton.icon(
            key: buttonKey,
            onPressed: onPressed,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(buttonLabel),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AssessmentActionCard extends StatelessWidget {
  const _AssessmentActionCard({
    required this.title,
    required this.message,
    required this.badge,
    required this.icon,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onPressed,
    this.warning = false,
  });

  final String title;
  final String message;
  final String badge;
  final IconData icon;
  final Key buttonKey;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final accent = warning ? const Color(0xFF9A6700) : AppColors.primary;
    final background = warning
        ? const Color(0xFFFFF8E1)
        : const Color(0xFFF0F7F1);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: accent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 47,
            child: FilledButton.icon(
              key: buttonKey,
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(
                buttonLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(backgroundColor: accent),
            ),
          ),
        ],
      ),
    );
  }
}
