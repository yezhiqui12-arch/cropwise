import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/station1_workflow_provider.dart';
import '../../services/assessment_protocol_selector.dart';
import '../../services/phone_location_service.dart';
import '../../theme/app_colors.dart';
import 'plant_observation_step.dart';
import 'plant_selection_step.dart';
import 'resume_assessment_step.dart';
import 'station_location_step.dart';
import 'station_review_step.dart';

class Station1WorkflowScreen extends StatelessWidget {
  const Station1WorkflowScreen({
    super.key,
    required this.fieldName,
    required this.captureLocation,
  });

  final String fieldName;
  final Future<AveragedPhoneLocation> Function() captureLocation;

  @override
  Widget build(BuildContext context) {
    final workflow = context.watch<Station1WorkflowProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Block 1 · Station 1')),
      body: SafeArea(
        child: switch (workflow.state) {
          Station1ViewState.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          Station1ViewState.boundaryRequired => _MessageStep(
            key: const Key('station1_boundary_required'),
            status: 'FIELD OUTLINE REQUIRED',
            title: 'Complete field outline',
            message:
                'Confirm the approximate field outline before continuing to Station 1. Your draft remains saved on this phone.',
            supporting:
                'The outline is a scouting guide, not a legal or survey-grade property boundary.',
            actionLabel: 'Return to Scan',
            onAction: () => Navigator.pop(context),
          ),
          Station1ViewState.setupRequired => _MessageStep(
            status: 'SETUP REQUIRED',
            title: 'Finish assessment setup',
            message:
                'This assessment is not ready for field observations. Return to Scan and complete setup.',
            actionLabel: 'Return to Scan',
            onAction: () => Navigator.pop(context),
          ),
          Station1ViewState.safetyBlocked => _MessageStep(
            key: const Key('station1_safety_blocked'),
            warning: true,
            status: 'FIELD ENTRY BLOCKED',
            title: 'Review field-entry safety',
            message:
                'Do not enter the field. A treatment or unverified condition requires a new safety check.',
            supporting: 'All earlier answers and timestamps remain saved.',
            actionLabel: 'Return to Scan',
            onAction: () => Navigator.pop(context),
          ),
          Station1ViewState.unsupportedStage => _MessageStep(
            key: const Key('station1_unsupported_stage'),
            status: 'NOT AVAILABLE IN THIS PILOT',
            title: 'This growth stage needs a different protocol',
            message:
                '${AssessmentProtocolSelector.growthStageLabel(workflow.assessment!.growthStage)} must not use the V3–V12 Station 1 form.',
            supporting:
                'The assessment remains saved on this phone. No plant observations were created.',
            actionLabel: 'Return to Scan',
            onAction: () => Navigator.pop(context),
          ),
          Station1ViewState.stageConfirmation => _MessageStep(
            key: const Key('station1_stage_confirmation'),
            status: 'CONFIRM GROWTH STAGE',
            title: AssessmentProtocolSelector.growthStageLabel(
              workflow.assessment!.growthStage,
            ),
            message:
                'Before using the V3–V12 form, confirm this is the best current growth-stage estimate.',
            supporting:
                'If it is not correct, return to setup. Do not force another stage into this form.',
            actionLabel: 'Confirm and continue',
            onAction: () => _run(context, workflow.confirmGrowthStage),
          ),
          Station1ViewState.largeFieldBlocked => _MessageStep(
            key: const Key('station1_large_field_blocked'),
            warning: true,
            status: 'MULTIPLE BLOCKS REQUIRED',
            title: 'This field cannot proceed as one block',
            message:
                'The confirmed outline is ${workflow.boundary!.areaHectares.toStringAsFixed(2)} ha. Fields larger than one hectare require multiple assessment blocks.',
            supporting:
                'Block selection is not part of this pilot. No block or station was created.',
            actionLabel: 'Return to Scan',
            onAction: () => Navigator.pop(context),
          ),
          Station1ViewState.blockPreparation => _BlockPreparationStep(
            fieldName: fieldName,
            areaHectares: workflow.boundary!.areaHectares,
            isSaving: workflow.isSaving,
            onContinue: () => _run(context, workflow.prepareBlockOne),
          ),
          Station1ViewState.resumeCheck => ResumeAssessmentStep(
            isSaving: workflow.isSaving,
            onSubmit: workflow.submitResumeCheck,
          ),
          Station1ViewState.stationLocation => StationLocationStep(
            captureLocation: captureLocation,
            isSaving: workflow.isSaving,
            onUseLocation: workflow.saveStationCoordinates,
            onSaveUnavailable: workflow.saveStationUnavailable,
          ),
          Station1ViewState.plantSelection => PlantSelectionStep(
            onBegin: workflow.beginTenConsecutivePlants,
          ),
          Station1ViewState.plantEntry => PlantObservationStep(
            key: ValueKey('plant_${workflow.currentPlantPosition}'),
            position: workflow.currentPlantPosition!,
            savedCount: workflow.savedPlantCount,
            stationId: workflow.snapshot!.station!.id,
            actorPersonId: workflow.assessment!.evaluatorPersonId,
            existing: workflow.currentPlant,
            isSaving: workflow.isSaving,
            onSave: workflow.savePlant,
            onCancelEdit: workflow.savedPlantCount == 10
                ? workflow.returnToReview
                : null,
          ),
          Station1ViewState.stationReview => StationReviewStep(
            snapshot: workflow.snapshot!,
            isSaving: workflow.isSaving,
            onEdit: workflow.editPlant,
            onConfirm: () => _run(context, workflow.confirmStationReview),
          ),
          Station1ViewState.stationComplete => _MessageStep(
            key: const Key('station1_complete'),
            status: 'STATION 1 REVIEWED',
            title: 'Ten plant positions saved',
            message: 'Block 1, Station 1 is complete and saved on this phone.',
            supporting:
                'This pilot does not complete the overall assessment or calculate a result.',
            actionLabel: 'Return to Scan',
            onAction: () => Navigator.pop(context),
          ),
          Station1ViewState.pausedConditions => _MessageStep(
            key: const Key('station1_conditions_paused'),
            warning: true,
            status: 'PAUSED',
            title: 'Conditions changed',
            message:
                'Do not add new observations until you can confirm the assessment is still comparable and safe to continue.',
            supporting: 'Previous answers and timestamps remain saved.',
            actionLabel: 'Return to Scan',
            onAction: () => Navigator.pop(context),
          ),
          Station1ViewState.error => _MessageStep(
            key: const Key('station1_load_error'),
            warning: true,
            status: 'LOCAL DATA ERROR',
            title: 'Could not load Station 1',
            message: _friendlyError(workflow.error),
            supporting:
                'Existing saved records have not been intentionally changed.',
            actionLabel: 'Retry',
            onAction: workflow.retry,
          ),
        },
      ),
    );
  }

  static Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  static String _friendlyError(Object? error) {
    if (error == null) return 'Try again. Your earlier records remain saved.';
    return error.toString().replaceFirst('Bad state: ', '');
  }
}

class _BlockPreparationStep extends StatelessWidget {
  const _BlockPreparationStep({
    required this.fieldName,
    required this.areaHectares,
    required this.isSaving,
    required this.onContinue,
  });

  final String fieldName;
  final double areaHectares;
  final bool isSaving;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _StepList(
      children: [
        const _Eyebrow('BLOCK PREPARATION'),
        const SizedBox(height: 8),
        const Text(
          'Block 1 is the whole field',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          '$fieldName has a confirmed approximate outline of ${areaHectares.toStringAsFixed(2)} ha. For this pilot, a field up to one hectare is recorded as one block.',
          style: const TextStyle(height: 1.45),
        ),
        const SizedBox(height: 16),
        const _InfoCard(
          icon: Icons.grid_view_outlined,
          title: 'Active block and station',
          message: 'Block 1 · Station 1',
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          key: const Key('prepare_block_one_button'),
          label: 'Prepare Block 1',
          busy: isSaving,
          onPressed: onContinue,
        ),
      ],
    );
  }
}

class _MessageStep extends StatelessWidget {
  const _MessageStep({
    super.key,
    required this.status,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.supporting,
    this.warning = false,
  });

  final String status;
  final String title;
  final String message;
  final String? supporting;
  final String actionLabel;
  final VoidCallback onAction;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return _StepList(
      children: [
        Icon(
          warning ? Icons.warning_amber_rounded : Icons.fact_check_outlined,
          size: 52,
          color: warning ? const Color(0xFF8A5A00) : AppColors.primary,
        ),
        const SizedBox(height: 14),
        _Eyebrow(status),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(height: 1.45)),
        if (supporting != null) ...[
          const SizedBox(height: 12),
          Text(
            supporting!,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
          ),
        ],
        const SizedBox(height: 24),
        _PrimaryButton(label: actionLabel, onPressed: onAction),
      ],
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('station1_step_scroll_view'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: children,
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.primary,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.7,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: const TextStyle(height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 56,
        minWidth: double.infinity,
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}
