import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/station1_workflow_provider.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../services/evidence_camera_service.dart';
import '../../services/assessment_protocol_selector.dart';
import '../../services/phone_location_service.dart';
import '../../theme/app_colors.dart';
import 'plant_observation_step.dart';
import 'continuous_plant_capture_step.dart';
import 'evidence_capture_panel.dart';
import 'evidence_photo_viewer.dart';
import 'guided_camera_screen.dart';
import 'plant_selection_step.dart';
import 'resume_assessment_step.dart';
import 'station_location_step.dart';
import 'station_context_evidence_step.dart';
import 'station_review_step.dart';

class Station1WorkflowScreen extends StatelessWidget {
  const Station1WorkflowScreen({
    super.key,
    required this.fieldName,
    required this.captureLocation,
    this.cameraFactory = const PluginEvidenceCameraFactory(),
  });

  final String fieldName;
  final Future<AveragedPhoneLocation> Function() captureLocation;
  final EvidenceCameraFactory cameraFactory;

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
          Station1ViewState.stationContextEvidence =>
            StationContextEvidenceStep(
              bundle: workflow.stationContextEvidence!,
              isSaving: workflow.isSaving,
              resolveFile: workflow.resolveEvidenceFile,
              onCapture: () async {
                await _captureEvidence(
                  context,
                  workflow,
                  DatabaseCodes.evidenceViewStationContext,
                );
              },
              onInspect: (media) async {
                await _inspectEvidence(context, workflow, media);
              },
              onAccept: (media) =>
                  _run(context, () => workflow.acceptEvidence(media)),
              onRetake: (media) async {
                await _retakeEvidence(context, workflow, media);
              },
              onRemove: (media) =>
                  _run(context, () => workflow.removeEvidence(media)),
              onManualFallback: (reason, note) => _run(
                context,
                () => workflow.waiveEvidence(
                  viewType: DatabaseCodes.evidenceViewStationContext,
                  reasonCode: reason,
                  note: note,
                ),
              ),
              onContinue: workflow.continueAfterStationContext,
            ),
          Station1ViewState.plantSelection => PlantSelectionStep(
            onBegin: () => _run(context, workflow.beginTenConsecutivePlants),
          ),
          Station1ViewState.plantCapture => ContinuousPlantCaptureStep(
            key: ValueKey('capture_plant_${workflow.currentPlantPosition}'),
            position: workflow.currentPlantPosition!,
            capturedPlantCount: workflow.capturedPlantCount,
            initialLeavesInspectedCount: workflow.capturedLeavesInspectedFor(
              workflow.currentPlantPosition!,
            ),
            bundle: workflow.currentEvidence!,
            isSaving: workflow.isSaving,
            resolveFile: workflow.resolveEvidenceFile,
            onCapture: (viewType) =>
                _captureEvidence(context, workflow, viewType),
            onInspect: (media) => _inspectEvidence(context, workflow, media),
            onAccept: (media) =>
                _tryRun(context, () => workflow.acceptEvidence(media)),
            onRetake: (media) => _retakeEvidence(context, workflow, media),
            onRemove: (media) =>
                _run(context, () => workflow.removeEvidence(media)),
            onManualFallback: (viewType, reason, note) => _tryRun(
              context,
              () => workflow.waiveEvidence(
                viewType: viewType,
                reasonCode: reason,
                note: note,
              ),
            ),
            onLeavesInspected: workflow.recordCurrentPlantInspection,
            onCompletePlant: (activeDuration, newestLeavesInspectedCount) =>
                _run(
                  context,
                  () => workflow.completeCurrentPlantCapture(
                    activeDuration,
                    newestLeavesInspectedCount,
                  ),
                ),
            onCannotAssess: (reason, activeDuration) => _run(
              context,
              () => workflow.saveCaptureNotAssessable(
                reason: reason,
                activeDuration: activeDuration,
              ),
            ),
          ),
          Station1ViewState.plantEntry => PlantObservationStep(
            key: ValueKey('plant_${workflow.currentPlantPosition}'),
            position: workflow.currentPlantPosition!,
            savedCount: workflow.savedPlantCount,
            stationId: workflow.snapshot!.station!.id,
            actorPersonId: workflow.assessment!.evaluatorPersonId,
            existing: workflow.currentPlant,
            initialLeavesInspectedCount: workflow.capturedLeavesInspectedFor(
              workflow.currentPlantPosition!,
            ),
            isSaving: workflow.isSaving,
            onSave: workflow.savePlant,
            onCancelEdit: workflow.savedPlantCount == 10
                ? workflow.returnToReview
                : null,
            evidence: workflow.currentEvidence,
            resolveEvidenceFile: workflow.resolveEvidenceFile,
            onCaptureEvidence: (viewType) async {
              await _captureEvidence(context, workflow, viewType);
            },
            onInspectEvidence: (media) async {
              await _inspectEvidence(context, workflow, media);
            },
            onAcceptEvidence: (media) =>
                _run(context, () => workflow.acceptEvidence(media)),
            onRetakeEvidence: (media) async {
              await _retakeEvidence(context, workflow, media);
            },
            onRemoveEvidence: (media) =>
                _run(context, () => workflow.removeEvidence(media)),
            onManualFallback: (viewType, reason, note) => _run(
              context,
              () => workflow.waiveEvidence(
                viewType: viewType,
                reasonCode: reason,
                note: note,
              ),
            ),
          ),
          Station1ViewState.stationReview => StationReviewStep(
            snapshot: workflow.snapshot!,
            isSaving: workflow.isSaving,
            onEdit: (position) =>
                _run(context, () => workflow.editPlant(position)),
            onConfirm: () => _run(context, workflow.confirmStationReview),
            evidenceBundles: workflow.stationEvidenceBundles,
            resolveEvidenceFile: workflow.resolveEvidenceFile,
            onOpenEvidence: (media, scopeLabel) =>
                _openReadOnlyEvidence(context, workflow, media, scopeLabel),
            pilotWorkloadMetrics: workflow.pilotWorkloadMetrics,
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

  static Future<bool> _tryRun(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
      return false;
    }
  }

  Future<String?> _captureEvidence(
    BuildContext context,
    Station1WorkflowProvider workflow,
    String viewType,
  ) async {
    final (title, viewLabel, instruction) = switch (viewType) {
      DatabaseCodes.evidenceViewStationContext => (
        'Station context',
        'Station-context view',
        'Frame the maize row and immediate Station 1 surroundings. Avoid people and identifying documents.',
      ),
      DatabaseCodes.evidenceViewCloseUp => (
        'Whorl detail',
        'Required closer view',
        'Move closer to the whorl interior or inspected feeding surface. This is required even when no sign is visible.',
      ),
      DatabaseCodes.evidenceViewDiagnosticDetail => (
        'Extra evidence detail',
        'Conditional detail',
        'Frame the larva, egg mass, ambiguous feature, or other sign that needs its own detail view.',
      ),
      _ => (
        'Whorl overview',
        'Whorl and newest leaves',
        'Gently expose the whorl and frame the newest three or four emerging leaves together.',
      ),
    };
    final result = await Navigator.push<GuidedCameraResult>(
      context,
      MaterialPageRoute(
        builder: (_) => GuidedCameraScreen(
          title: title,
          viewLabel: viewLabel,
          instruction: instruction,
          cameraFactory: cameraFactory,
        ),
      ),
    );
    if (!context.mounted || result == null) return null;
    if (result.sourcePath != null) {
      final staged = await _tryRun(
        context,
        () => workflow.stageEvidence(
          viewType: viewType,
          sourcePath: result.sourcePath!,
        ),
      );
      if (!staged || !context.mounted) return null;
      final bundle = viewType == DatabaseCodes.evidenceViewStationContext
          ? workflow.stationContextEvidence
          : workflow.currentEvidence;
      final media = bundle?.mediaForView(viewType);
      if (media != null &&
          media.storageState == DatabaseCodes.evidenceStorageStaged) {
        return _inspectEvidence(context, workflow, media);
      }
      return null;
    }
    final fallback = await showEvidenceFallbackDialog(
      context,
      suggestedReasonCode: result.fallbackReasonCode,
    );
    if (!context.mounted || fallback == null) return null;
    final saved = await _tryRun(
      context,
      () => workflow.waiveEvidence(
        viewType: viewType,
        reasonCode: fallback.reasonCode,
        note: fallback.note,
      ),
    );
    return saved ? viewType : null;
  }

  Future<String?> _inspectEvidence(
    BuildContext context,
    Station1WorkflowProvider workflow,
    EvidenceMediaRecord media,
  ) async {
    final bundle = media.viewType == DatabaseCodes.evidenceViewStationContext
        ? workflow.stationContextEvidence
        : workflow.currentEvidence;
    final scopeLabel = bundle?.session.plantPosition == null
        ? 'Block 1 · Station 1'
        : 'Plant ${bundle!.session.plantPosition}';
    final action = await Navigator.push<EvidencePhotoAction>(
      context,
      MaterialPageRoute(
        builder: (_) => EvidencePhotoViewer(
          media: media,
          scopeLabel: scopeLabel,
          resolveFile: workflow.resolveEvidenceFile,
          allowActions: true,
          allowAddCloseUp:
              media.viewType == DatabaseCodes.evidenceViewWhorlOverview &&
              bundle?.mediaForView(DatabaseCodes.evidenceViewCloseUp) == null,
          allowAddDiagnosticDetail:
              media.viewType == DatabaseCodes.evidenceViewCloseUp &&
              bundle?.mediaForView(
                    DatabaseCodes.evidenceViewDiagnosticDetail,
                  ) ==
                  null,
        ),
      ),
    );
    if (!context.mounted || action == null) return null;
    switch (action) {
      case EvidencePhotoAction.usePhoto:
        final accepted = await _tryRun(
          context,
          () => workflow.acceptEvidence(media),
        );
        return accepted ? media.viewType : null;
      case EvidencePhotoAction.retake:
        return _retakeEvidence(context, workflow, media);
      case EvidencePhotoAction.addCloseUp:
        if (media.storageState == DatabaseCodes.evidenceStorageStaged) {
          final accepted = await _tryRun(
            context,
            () => workflow.acceptEvidence(media),
          );
          if (!accepted) return null;
        }
        if (context.mounted) {
          return _captureEvidence(
            context,
            workflow,
            DatabaseCodes.evidenceViewCloseUp,
          );
        }
        return null;
      case EvidencePhotoAction.addDiagnosticDetail:
        if (media.storageState == DatabaseCodes.evidenceStorageStaged) {
          final accepted = await _tryRun(
            context,
            () => workflow.acceptEvidence(media),
          );
          if (!accepted) return null;
        }
        if (context.mounted) {
          return _captureEvidence(
            context,
            workflow,
            DatabaseCodes.evidenceViewDiagnosticDetail,
          );
        }
        return null;
      case EvidencePhotoAction.remove:
        final confirmed = await _confirmEvidenceRemoval(context, retake: false);
        if (!context.mounted) return null;
        if (confirmed) {
          await _run(context, () => workflow.removeEvidence(media));
        }
        return null;
    }
  }

  Future<String?> _retakeEvidence(
    BuildContext context,
    Station1WorkflowProvider workflow,
    EvidenceMediaRecord media,
  ) async {
    final confirmed = await _confirmEvidenceRemoval(context, retake: true);
    if (!context.mounted || !confirmed) return null;
    final removed = await _tryRun(
      context,
      () => workflow.removeEvidence(media, retake: true),
    );
    if (!removed) return null;
    if (context.mounted) {
      return _captureEvidence(context, workflow, media.viewType!);
    }
    return null;
  }

  Future<bool> _confirmEvidenceRemoval(
    BuildContext context, {
    required bool retake,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(retake ? 'Retake this photo?' : 'Remove this photo?'),
          content: const Text(
            'The image file will be deleted. WormWise keeps only an audited metadata tombstone and checksum.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_viewer_evidence_removal'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(retake ? 'Delete and retake' : 'Delete photo'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _openReadOnlyEvidence(
    BuildContext context,
    Station1WorkflowProvider workflow,
    EvidenceMediaRecord media,
    String scopeLabel,
  ) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => EvidencePhotoViewer(
        media: media,
        scopeLabel: scopeLabel,
        resolveFile: workflow.resolveEvidenceFile,
      ),
    ),
  );

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
