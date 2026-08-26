import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:provider/provider.dart';

import '../../providers/five_station_workflow_provider.dart';
import '../../providers/station1_workflow_provider.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/scouting_workflow_repository.dart';
import '../../services/evidence_camera_service.dart';
import '../../services/field_imagery_provider.dart';
import '../../services/assessment_protocol_selector.dart';
import '../../services/phone_location_service.dart';
import '../../services/scouting_route_generator.dart';
import '../../theme/app_colors.dart';
import '../../widgets/offline_scouting_route_map.dart';
import '../scan/route_preparation_step.dart';
import '../scan/station_route_guidance_step.dart';
import '../scan/station_target_adjustment_step.dart';
import '../../data/services/atomic_ve_v2_save_service.dart';
import '../growth_stage_correction_screen.dart';
import '../ve_v2/ve_v2_pilot_steps.dart';
import 'plant_capture_board_step.dart';
import 'plant_observation_step.dart';
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
    required this.watchLocation,
    this.cameraFactory = const PluginEvidenceCameraFactory(),
    this.testMode = false,
    this.debugFeaturesEnabled = kDebugMode,
    this.imageryProvider,
  });

  final String fieldName;
  final Future<AveragedPhoneLocation> Function() captureLocation;
  final Future<Stream<PhoneLocationReading>> Function() watchLocation;
  final EvidenceCameraFactory cameraFactory;
  final bool testMode;
  final bool debugFeaturesEnabled;
  final FieldImageryProvider? imageryProvider;

  @override
  Widget build(BuildContext context) {
    final workflow = context.watch<FiveStationWorkflowProvider>();
    final showTestTools = kDebugMode && debugFeaturesEnabled && testMode;

    return _StationWorkflowBackBoundary(
      onSystemBack: () => _handleSystemBack(context, workflow),
      builder: (exitRoute) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('station_workflow_back_button'),
            tooltip: 'Return to Scan',
            onPressed: workflow.isSaving
                ? null
                : () => _exitToScan(context, workflow, exitRoute),
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            'Block ${workflow.blockNumber} · Station ${workflow.stationNumber}',
          ),
          actions: [
            if (kDebugMode && debugFeaturesEnabled && testMode)
              IconButton(
                key: const Key('test_station_shortcuts_button'),
                tooltip: 'TEST DATA shortcuts',
                onPressed: () => _showTestShortcuts(context, workflow),
                icon: const Icon(Icons.science_outlined),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (showTestTools)
                TestDataWorkflowActions(
                  stationNumber: workflow.stationNumber,
                  isVeV2: workflow.isVeV2,
                  isSaving: workflow.isSaving,
                  onCompleteCurrent: () =>
                      _run(context, workflow.completeTestStation),
                  onCompleteAll: () =>
                      _run(context, workflow.completeAllRemainingTestStations),
                ),
              Expanded(
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
                    supporting:
                        'All earlier answers and timestamps remain saved.',
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
                        'Before beginning stage-specific observations, confirm this is the best current growth-stage estimate.',
                    supporting:
                        'If it is not correct, return to setup. Do not force another stage into this form.',
                    actionLabel: 'Confirm and continue',
                    onAction: () => _run(context, workflow.confirmGrowthStage),
                    secondaryActionLabel: 'Change growth stage',
                    onSecondaryAction: () async {
                      final changed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GrowthStageCorrectionScreen(),
                        ),
                      );
                      if (changed == true) workflow.retry();
                    },
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
                    onContinue: () =>
                        _run(context, workflow.prepareRequiredBlocks),
                  ),
                  Station1ViewState.resumeCheck => ResumeAssessmentStep(
                    isSaving: workflow.isSaving,
                    onSubmit: workflow.submitResumeCheck,
                  ),
                  Station1ViewState.routePreparation => RoutePreparationStep(
                    blockNumber: workflow.blockNumber,
                    boundary: workflow.blockBoundary,
                    plan: workflow.routePlan!,
                    completedStationLocations:
                        workflow.completedStationLocations,
                    completedStationNumbers: workflow.completedStationNumbers,
                    captureLocation: captureLocation,
                    isSaving: workflow.isSaving,
                    onSavePreparation: workflow.saveRoutePreparation,
                    onGenerate: workflow.generateRoute,
                    imageryProvider: imageryProvider,
                  ),
                  Station1ViewState.stationTravel => StationRouteGuidanceStep(
                    blockNumber: workflow.blockNumber,
                    stationNumber: workflow.stationNumber,
                    boundary: workflow.blockBoundary,
                    plan: workflow.routePlan!,
                    completedStationLocations:
                        workflow.completedStationLocations,
                    completedStationNumbers: workflow.completedStationNumbers,
                    watchLocation: watchLocation,
                    isSaving: workflow.isSaving,
                    onConfirmReached: workflow.confirmReachedActiveStation,
                    onAdjustTarget: workflow.beginTargetAdjustment,
                    onEditRoute: workflow.editRoutePreparation,
                    imageryProvider: imageryProvider,
                  ),
                  Station1ViewState.targetAdjustment =>
                    StationTargetAdjustmentStep(
                      boundary: workflow.blockBoundary,
                      plan: workflow.routePlan!,
                      completedStationLocations:
                          workflow.completedStationLocations,
                      completedStationNumbers: workflow.completedStationNumbers,
                      isSaving: workflow.isSaving,
                      onSaveDraft: workflow.saveTargetAdjustmentDraft,
                      onApply: workflow.applyTargetAdjustment,
                      onCancel: workflow.cancelTargetAdjustment,
                      imageryProvider: imageryProvider,
                    ),
                  Station1ViewState.stationLocation => StationLocationStep(
                    stationNumber: workflow.stationNumber,
                    captureLocation: captureLocation,
                    isSaving: workflow.isSaving,
                    onUseLocation: workflow.saveStationCoordinates,
                    onSaveUnavailable: workflow.saveStationUnavailable,
                  ),
                  Station1ViewState.stationContextEvidence =>
                    StationContextEvidenceStep(
                      blockNumber: workflow.blockNumber,
                      stationNumber: workflow.stationNumber,
                      isVeV2: workflow.isVeV2,
                      bundle: workflow.stationContextEvidence!,
                      isSaving: workflow.isSaving,
                      resolveFile: workflow.resolveEvidenceFile,
                      onCapture: () async {
                        final accepted = await _captureEvidence(
                          context,
                          workflow,
                          DatabaseCodes.evidenceViewStationContext,
                        );
                        if (accepted != null && context.mounted) {
                          await _run(
                            context,
                            workflow.continueAfterStationContext,
                          );
                        }
                      },
                      onInspect: (media) async {
                        final accepted = await _inspectEvidence(
                          context,
                          workflow,
                          media,
                        );
                        if (accepted != null && context.mounted) {
                          await _run(
                            context,
                            workflow.continueAfterStationContext,
                          );
                        }
                      },
                      onAccept: (media) => _run(context, () async {
                        await workflow.acceptEvidence(media);
                        await workflow.continueAfterStationContext();
                      }),
                      onRetake: (media) async {
                        await _retakeEvidence(context, workflow, media);
                      },
                      onRemove: (media) =>
                          _run(context, () => workflow.removeEvidence(media)),
                      onManualFallback: (reason, note) => _run(
                        context,
                        () async {
                          await workflow.waiveEvidence(
                            viewType: DatabaseCodes.evidenceViewStationContext,
                            reasonCode: reason,
                            note: note,
                          );
                          await workflow.continueAfterStationContext();
                        },
                      ),
                      onContinue: workflow.continueAfterStationContext,
                    ),
                  Station1ViewState.veV2StationSetup => VeV2StationSetupStep(
                    stationNumber: workflow.stationNumber,
                    stationId: workflow.snapshot!.station!.id,
                    growthStage: workflow.assessment!.growthStage,
                    actorPersonId: workflow.assessment!.evaluatorPersonId,
                    isSaving: workflow.isSaving,
                    onSave: workflow.saveVeV2StationSetup,
                  ),
                  Station1ViewState.veV2RowContextEvidence =>
                    VeV2RowContextStep(
                      stationNumber: workflow.stationNumber,
                      bundle: workflow.veV2RowContextEvidence!,
                      resolveFile: workflow.resolveEvidenceFile,
                      onCapture: () => _captureEvidence(
                        context,
                        workflow,
                        DatabaseCodes.evidenceViewVeRowContext,
                      ),
                      onInspect: (media) =>
                          _inspectEvidence(context, workflow, media),
                      onAccept: (media) =>
                          _run(context, () => workflow.acceptEvidence(media)),
                      onRetake: (media) =>
                          _retakeEvidence(context, workflow, media),
                      onRemove: (media) =>
                          _run(context, () => workflow.removeEvidence(media)),
                      onFallback: (reason, note) => _run(
                        context,
                        () => workflow.waiveEvidence(
                          viewType: DatabaseCodes.evidenceViewVeRowContext,
                          reasonCode: reason,
                          note: note,
                        ),
                      ),
                      onContinue: workflow.continueAfterVeV2RowContext,
                    ),
                  Station1ViewState.veV2ContinuousCapture =>
                    PlantCaptureBoardStep(
                      key: const ValueKey('ve_v2_plant_capture_board_step'),
                      isVeV2: true,
                      selectedPosition: workflow.currentPlantPosition ?? 1,
                      blockNumber: workflow.blockNumber,
                      stationNumber: workflow.stationNumber,
                      evidencePolicy: workflow.currentEvidencePolicy,
                      capturedPlantCount: workflow.capturedPlantCount,
                      stationBundles: workflow.stationEvidenceBundles,
                      veV2Units: workflow.veV2Units,
                      isSaving: workflow.isSaving,
                      resolveFile: workflow.resolveEvidenceFile,
                      cvDiagnoses: workflow.cvDiagnoses,
                      onSelectPlant: (pos) =>
                          _run(context, () => workflow.selectCapturePlant(pos)),
                      onMarkAllHealthy: () =>
                          _run(context, workflow.markEntireStationClean),
                      onCapture: (position, viewType) async {
                        await workflow.selectCapturePlant(position);
                        if (!context.mounted) return null;
                        return _captureEvidence(context, workflow, viewType);
                      },
                      onInspect: (media) =>
                          _inspectEvidence(context, workflow, media),
                      onAccept: (media) => _tryRun(context, () async {
                        await workflow.acceptEvidence(media);
                        if (workflow.currentPlantPosition != null) {
                          await workflow.analyzePlantEvidence(
                            media: media,
                            plantPosition: workflow.currentPlantPosition!,
                          );
                        }
                      }),
                      onRetake: (media) =>
                          _retakeEvidence(context, workflow, media),
                      onRemove: (media) =>
                          _run(context, () => workflow.removeEvidence(media)),
                      onManualFallback: (position, viewType, reason, note) =>
                          _tryRun(context, () async {
                            await workflow.selectCapturePlant(position);
                            await workflow.waiveEvidence(
                              viewType: viewType,
                              reasonCode: reason,
                              note: note,
                            );
                          }),
                      onCompleteStationCapture: () =>
                          _run(context, workflow.proceedToStationReview),
                      onCannotAssess: (position, reason) =>
                          _run(context, () async {
                            await workflow.selectCapturePlant(position);
                            await workflow.saveCaptureNotAssessable(
                              reason: reason,
                              activeDuration: Duration.zero,
                            );
                          }),
                      onSaveVeV2UnitException: (position, occupancy, reason) =>
                          _run(context, () async {
                            await workflow.selectCapturePlant(position);
                            final bundle = workflow.currentEvidence;
                            await workflow.saveVeV2CaptureRouting(
                              VeV2CaptureRoutingSave(
                                stationId: workflow.snapshot!.station!.id,
                                sequenceNumber: position,
                                occupancyStatus: occupancy,
                                observedSeedlingCount:
                                    occupancy ==
                                        DatabaseCodes.veOccupancySeedling
                                    ? 1
                                    : 0,
                                inspectionDurationMs: 0,
                                evidenceCaptureSessionId:
                                    bundle?.session.id ?? '',
                                requiredEvidenceViewTypes: const {},
                                actorPersonId:
                                    workflow.assessment!.evaluatorPersonId,
                                notAssessableReason: reason,
                              ),
                            );
                          }),
                    ),
                  Station1ViewState.veV2PlantingUnitEntry =>
                    VeV2PlantingUnitStep(
                      key: ValueKey('ve_unit_${workflow.currentPlantPosition}'),
                      position: workflow.currentPlantPosition!,
                      stationId: workflow.snapshot!.station!.id,
                      actorPersonId: workflow.assessment!.evaluatorPersonId,
                      existing: workflow.currentVeV2Unit,
                      bundle: workflow.currentEvidence!,
                      isSaving: workflow.isSaving,
                      resolveFile: workflow.resolveEvidenceFile,
                      onCapture: (view) =>
                          _captureEvidence(context, workflow, view),
                      onInspect: (media) =>
                          _inspectEvidence(context, workflow, media),
                      onAccept: (media) =>
                          _run(context, () => workflow.acceptEvidence(media)),
                      onRetake: (media) =>
                          _retakeEvidence(context, workflow, media),
                      onRemove: (media) =>
                          _run(context, () => workflow.removeEvidence(media)),
                      onFallback: (view, reason, note) => _run(
                        context,
                        () => workflow.waiveEvidence(
                          viewType: view,
                          reasonCode: reason,
                          note: note,
                        ),
                      ),
                      onSave: workflow.saveVeV2PlantingUnit,
                    ),
                  Station1ViewState.veV2LivingSeedlingEntry =>
                    VeV2LivingSeedlingStep(
                      key: ValueKey(
                        've_living_${workflow.currentPlantPosition}',
                      ),
                      position: workflow.currentPlantPosition!,
                      stationId: workflow.snapshot!.station!.id,
                      actorPersonId: workflow.assessment!.evaluatorPersonId,
                      existing: workflow.currentPlant,
                      suggestedSourceUnitId:
                          workflow.veV2CaptureTarget?.sourcePlantingUnitId,
                      initialLeavesInspectedCount: workflow
                          .capturedLeavesInspectedFor(
                            workflow.currentPlantPosition!,
                          ),
                      linkableUnits: workflow.linkableVeV2Units,
                      bundle: workflow.currentEvidence!,
                      isSaving: workflow.isSaving,
                      resolveFile: workflow.resolveEvidenceFile,
                      onCapture: (view) =>
                          _captureEvidence(context, workflow, view),
                      onInspect: (media) =>
                          _inspectEvidence(context, workflow, media),
                      onAccept: (media) =>
                          _run(context, () => workflow.acceptEvidence(media)),
                      onRetake: (media) =>
                          _retakeEvidence(context, workflow, media),
                      onRemove: (media) =>
                          _run(context, () => workflow.removeEvidence(media)),
                      onFallback: (view, reason, note) => _run(
                        context,
                        () => workflow.waiveEvidence(
                          viewType: view,
                          reasonCode: reason,
                          note: note,
                        ),
                      ),
                      onSave: workflow.saveVeV2LivingSeedling,
                    ),
                  Station1ViewState.veV2StationReview => VeV2StationReviewStep(
                    stationNumber: workflow.stationNumber,
                    units: workflow.veV2Units,
                    plants: workflow.snapshot?.plants ?? const [],
                    inspection: workflow.veV2Inspection,
                    acceptedImageCount:
                        workflow.pilotWorkloadMetrics.acceptedImageCount,
                    fallbackCount:
                        workflow.pilotWorkloadMetrics.manualFallbackCount,
                    retakeCount: workflow.pilotWorkloadMetrics.retakeCount,
                    evidenceBundles: workflow.stationEvidenceBundles,
                    resolveFile: workflow.resolveEvidenceFile,
                    onInspect: (media) =>
                        _inspectEvidence(context, workflow, media),
                    analysisFor: workflow.veV2AnalysisFor,
                    isSaving: workflow.isSaving,
                    onEditUnit: workflow.editVeV2PlantingUnit,
                    onEditPlant: workflow.editVeV2LivingSeedling,
                    onComplete: workflow.completeVeV2PilotStation,
                    onCompleteWithoutManualConfirmation: () => _run(
                      context,
                      workflow.completeStationWithoutManualConfirmation,
                    ),
                  ),
                  Station1ViewState.veV2PilotComplete => _MessageStep(
                    key: const Key('ve_v2_pilot_complete'),
                    status: 'STATION SAVED',
                    title: 'VE–V2 station saved',
                    message:
                        'Ten planting spots and ten living plants are saved separately on this phone.',
                    actionLabel: 'Return to Scan',
                    onAction: () => Navigator.pop(context),
                  ),
                  Station1ViewState.plantSelection => PlantSelectionStep(
                    blockNumber: workflow.blockNumber,
                    stationNumber: workflow.stationNumber,
                    evidencePolicy: workflow.evidencePolicy,
                    onBegin: () =>
                        _run(context, workflow.beginTenConsecutivePlants),
                    onMarkAllHealthy: () =>
                        _run(context, workflow.markEntireStationClean),
                  ),
                  Station1ViewState.plantCapture => PlantCaptureBoardStep(
                    key: const ValueKey('plant_capture_board_step'),
                    selectedPosition: workflow.currentPlantPosition ?? 1,
                    blockNumber: workflow.blockNumber,
                    stationNumber: workflow.stationNumber,
                    evidencePolicy: workflow.currentEvidencePolicy,
                    capturedPlantCount: workflow.capturedPlantCount,
                    stationBundles: workflow.stationEvidenceBundles,
                    isSaving: workflow.isSaving,
                    resolveFile: workflow.resolveEvidenceFile,
                    cvDiagnoses: workflow.cvDiagnoses,
                    onSelectPlant: (pos) =>
                        _run(context, () => workflow.selectCapturePlant(pos)),
                    onMarkAllHealthy: () =>
                        _run(context, workflow.markEntireStationClean),
                    onCapture: (position, viewType) async {
                      await workflow.selectCapturePlant(position);
                      if (!context.mounted) return null;
                      return _captureEvidence(context, workflow, viewType);
                    },
                    onInspect: (media) =>
                        _inspectEvidence(context, workflow, media),
                    onAccept: (media) => _tryRun(context, () async {
                      await workflow.acceptEvidence(media);
                      if (workflow.currentPlantPosition != null) {
                        await workflow.analyzePlantEvidence(
                          media: media,
                          plantPosition: workflow.currentPlantPosition!,
                        );
                      }
                    }),
                    onRetake: (media) =>
                        _retakeEvidence(context, workflow, media),
                    onRemove: (media) =>
                        _run(context, () => workflow.removeEvidence(media)),
                    onManualFallback: (position, viewType, reason, note) =>
                        _tryRun(context, () async {
                          await workflow.selectCapturePlant(position);
                          await workflow.waiveEvidence(
                            viewType: viewType,
                            reasonCode: reason,
                            note: note,
                          );
                        }),
                    onCompleteStationCapture: () =>
                        _run(context, workflow.proceedToStationReview),
                    onCannotAssess: (position, reason) =>
                        _run(context, () async {
                          await workflow.selectCapturePlant(position);
                          await workflow.saveCaptureNotAssessable(
                            reason: reason,
                            activeDuration: Duration.zero,
                          );
                        }),
                  ),
                  Station1ViewState.plantEntry => PlantObservationStep(
                    key: ValueKey('plant_${workflow.currentPlantPosition}'),
                    position: workflow.currentPlantPosition!,
                    blockNumber: workflow.blockNumber,
                    stationNumber: workflow.stationNumber,
                    evidencePolicy: workflow.currentEvidencePolicy,
                    savedCount: workflow.savedPlantCount,
                    stationId: workflow.snapshot!.station!.id,
                    actorPersonId: workflow.assessment!.evaluatorPersonId,
                    existing: workflow.currentPlant,
                    initialLeavesInspectedCount: workflow
                        .capturedLeavesInspectedFor(
                          workflow.currentPlantPosition!,
                        ),
                    isSaving: workflow.isSaving,
                    onSave: workflow.savePlant,
                    onSaveReviewed: workflow.saveReviewedPlant,
                    onMarkAllHealthy: () =>
                        _run(context, workflow.markEntireStationClean),
                    cvDiagnosis:
                        workflow.cvDiagnoses[workflow.currentPlantPosition],
                    initialEvidenceReviewStatus:
                        workflow
                                .plantEvidenceReviews[workflow
                                    .currentPlantPosition!]
                                ?.isCurrent ==
                            true
                        ? workflow
                              .plantEvidenceReviews[workflow
                                  .currentPlantPosition!]
                              ?.status
                        : null,
                    onCancelEdit: () => _handleSystemBack(context, workflow),
                    evidence: workflow.currentEvidence,
                    resolveEvidenceFile: workflow.resolveEvidenceFile,
                    onCaptureEvidence: (viewType) async {
                      await _captureEvidence(context, workflow, viewType);
                    },
                    onInspectEvidence: (media) async {
                      await _inspectEvidence(context, workflow, media);
                    },
                    onAcceptEvidence: (media) => _run(context, () async {
                      await workflow.acceptEvidence(media);
                      if (workflow.currentPlantPosition != null) {
                        await workflow.analyzePlantEvidence(
                          media: media,
                          plantPosition: workflow.currentPlantPosition!,
                        );
                      }
                    }),
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
                    blockNumber: workflow.blockNumber,
                    stationNumber: workflow.stationNumber,
                    evidencePolicy: workflow.evidencePolicy,
                    evidenceReviews: workflow.plantEvidenceReviews,
                    isSaving: workflow.isSaving,
                    onEdit: (position) =>
                        _run(context, () => workflow.editPlant(position)),
                    onConfirm: () =>
                        _run(context, workflow.confirmStationReview),
                    onCompleteWithoutManualConfirmation: () => _run(
                      context,
                      workflow.completeStationWithoutManualConfirmation,
                    ),
                    onCompleteTestStation:
                        kDebugMode && debugFeaturesEnabled && testMode
                        ? () => _run(context, workflow.completeTestStation)
                        : null,
                    onMarkInsufficient: (position) => _run(
                      context,
                      () => workflow.markPlantEvidenceInsufficient(position),
                    ),
                    evidenceBundles: workflow.stationEvidenceBundles,
                    resolveEvidenceFile: workflow.resolveEvidenceFile,
                    onOpenEvidence: (media, scopeLabel) =>
                        _openReadOnlyEvidence(
                          context,
                          workflow,
                          media,
                          scopeLabel,
                        ),
                    pilotWorkloadMetrics: workflow.pilotWorkloadMetrics,
                  ),
                  Station1ViewState.stationComplete => _MessageStep(
                    key: const Key('station1_complete'),
                    status: 'STATION REVIEWED',
                    title: 'Ten plant positions saved',
                    message:
                        'Block ${workflow.blockNumber}, Station ${workflow.stationNumber} is complete and saved on this phone.',
                    actionLabel: 'Return to Scan',
                    onAction: () => Navigator.pop(context),
                  ),
                  Station1ViewState.betweenStations => _BetweenStationsStep(
                    blockNumber: workflow.blockNumber,
                    completedStation: workflow.stationNumber,
                    boundary: workflow.blockBoundary,
                    plan: workflow.routePlan,
                    completedStationLocations:
                        workflow.completedStationLocations,
                    completedStationNumbers: workflow.completedStationNumbers,
                    imageryProvider: imageryProvider,
                    isSaving: workflow.isSaving,
                    onContinue: () =>
                        _run(context, workflow.continueToNextStation),
                  ),
                  Station1ViewState.blockReview => _BlockReviewStep(
                    blockNumber: workflow.blockNumber,
                    snapshot: workflow.blockSnapshot!,
                    isSaving: workflow.isSaving,
                    onReviewStation: (station) => _run(
                      context,
                      () => workflow.openStationFromBlockReview(station),
                    ),
                    onComplete: () =>
                        _run(context, workflow.completeCurrentBlock),
                  ),
                  Station1ViewState.betweenBlocks => _MessageStep(
                    key: const Key('between_blocks_step'),
                    status: 'BLOCK SAVED',
                    title: 'Continue to Block ${workflow.blockNumber}',
                    message:
                        'The previous block is sampling complete. Continue with the next confirmed assessment block.',
                    supporting:
                        'Each block has its own saved approximate route preparation. Continue to prepare or follow that block’s guidance.',
                    actionLabel: 'Continue to next block',
                    onAction: () => _run(context, workflow.continueToNextBlock),
                  ),
                  Station1ViewState.samplingComplete => _MessageStep(
                    key: const Key('sampling_complete_step'),
                    status: 'SAMPLING COMPLETE',
                    title: 'All required blocks are complete',
                    message:
                        'Stations 1–5 and all ten plant positions per station are saved and reviewed for every required block.',
                    supporting:
                        'No assessment result or treatment recommendation has been calculated. Route guidance remains an editable approximate field aid, not proof of protocol compliance.',
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
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _exitToScan(
    BuildContext context,
    FiveStationWorkflowProvider workflow,
    Future<void> Function() exitRoute,
  ) async {
    if (workflow.isSaving) return;
    if (workflow.state == Station1ViewState.plantEntry) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Return to Scan?'),
          content: const Text(
            'Answers not yet saved on this plant form will be discarded. Accepted photographs and previously saved plant records will remain attached.',
          ),
          actions: [
            TextButton(
              key: const Key('stay_on_plant_button'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Stay here'),
            ),
            FilledButton(
              key: const Key('leave_plant_for_scan_button'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Return to Scan'),
            ),
          ],
        ),
      );
      if (leave != true || !context.mounted) return;
    }
    await exitRoute();
  }

  static Future<void> _handleSystemBack(
    BuildContext context,
    FiveStationWorkflowProvider workflow,
  ) async {
    if (workflow.isSaving) return;
    if (!workflow.canNavigateBackWithinWorkflow) {
      Navigator.maybePop(context);
      return;
    }
    if (workflow.state == Station1ViewState.plantEntry) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Return to Station Review?'),
          content: const Text(
            'Answers not yet saved on this plant form will be discarded. Accepted photographs and previously saved plant records will remain attached.',
          ),
          actions: [
            TextButton(
              key: const Key('keep_editing_plant_button'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              key: const Key('discard_plant_edits_button'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Return to review'),
            ),
          ],
        ),
      );
      if (discard != true || !context.mounted) return;
    }
    await _run(context, workflow.navigateBackWithinWorkflow);
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

  Future<void> _showTestShortcuts(
    BuildContext context,
    FiveStationWorkflowProvider workflow,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'TEST DATA shortcuts',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'These actions write clearly synthetic records only to the separate debug database.',
              ),
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('fill_remaining_test_plants_button'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _run(context, workflow.fillRemainingTestPlants);
                },
                child: const Text('Fill remaining test plants'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('complete_test_station_button'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _run(context, workflow.completeTestStation);
                },
                child: const Text('Complete test station'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('complete_all_test_stations_button'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _run(
                    context,
                    workflow.completeAllRemainingTestStations,
                  );
                },
                icon: const Icon(Icons.fast_forward_outlined),
                label: const Text('Complete all remaining test stations'),
              ),
            ],
          ),
        ),
      ),
    );
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
    FiveStationWorkflowProvider workflow,
    String viewType,
  ) async {
    final (title, viewLabel, instruction) = switch (viewType) {
      DatabaseCodes.evidenceViewStationContext => (
        'Station ${workflow.stationNumber}',
        'Station photo',
        workflow.isVeV2
            ? 'Keep the row and planting spots clearly in the frame.'
            : 'Keep the maize row and nearby crop clearly in the frame.',
      ),
      DatabaseCodes.evidenceViewWholeSeedling => (
        'Seedling ${workflow.currentPlantPosition}',
        'Whole seedling',
        'Inspect the newest leaves and stem base, then keep the whole seedling clearly in the frame.',
      ),
      DatabaseCodes.evidenceViewCloseUp => (
        'Whorl detail',
        workflow.stationNumber == 1
            ? 'Required closer view'
            : 'Optional evidence detail',
        workflow.stationNumber == 1
            ? 'Move closer to the whorl interior or inspected feeding surface. This is required even when no sign is visible.'
            : 'Move closer only when the recorded evidence benefits from additional detail.',
      ),
      DatabaseCodes.evidenceViewDiagnosticDetail => (
        'Extra evidence detail',
        'Conditional detail',
        'Frame the larva, egg mass, ambiguous feature, or other sign that needs its own detail view.',
      ),
      _ => (
        'Plant photo',
        'Newest leaves and whorl',
        'Keep the newest leaves and whorl clearly in the frame.',
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
    FiveStationWorkflowProvider workflow,
    EvidenceMediaRecord media,
  ) async {
    final bundle = media.viewType == DatabaseCodes.evidenceViewStationContext
        ? workflow.stationContextEvidence
        : (workflow.stationEvidenceBundles
                  .where((b) => b.session.id == media.captureSessionId)
                  .firstOrNull ??
              workflow.currentEvidence);
    if (bundle?.session.plantPosition != null &&
        workflow.currentPlantPosition != bundle!.session.plantPosition) {
      await workflow.selectCapturePlant(bundle.session.plantPosition!);
    }
    if (!context.mounted) return null;
    final scopeLabel = bundle?.session.plantPosition == null
        ? 'Block ${workflow.blockNumber} · Station ${workflow.stationNumber}'
        : 'Station ${workflow.stationNumber} · Plant ${bundle!.session.plantPosition}';
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
    FiveStationWorkflowProvider workflow,
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
    FiveStationWorkflowProvider workflow,
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

class _StationWorkflowBackBoundary extends StatefulWidget {
  const _StationWorkflowBackBoundary({
    required this.onSystemBack,
    required this.builder,
  });

  final Future<void> Function() onSystemBack;
  final Widget Function(Future<void> Function() exitRoute) builder;

  @override
  State<_StationWorkflowBackBoundary> createState() =>
      _StationWorkflowBackBoundaryState();
}

class _StationWorkflowBackBoundaryState
    extends State<_StationWorkflowBackBoundary> {
  bool _allowRouteExit = false;

  Future<void> _exitRoute() async {
    if (_allowRouteExit) return;
    setState(() => _allowRouteExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    // Phone Back stays inside the workflow. Only the explicit app-bar action
    // temporarily enables removal of this Navigator route.
    canPop: _allowRouteExit,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(widget.onSystemBack());
    },
    child: widget.builder(_exitRoute),
  );
}

class TestDataWorkflowActions extends StatelessWidget {
  const TestDataWorkflowActions({
    super.key,
    required this.stationNumber,
    this.isVeV2 = false,
    required this.isSaving,
    required this.onCompleteCurrent,
    required this.onCompleteAll,
  });

  final int stationNumber;
  final bool isVeV2;
  final bool isSaving;
  final VoidCallback onCompleteCurrent;
  final VoidCallback onCompleteAll;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('persistent_test_station_bypass'),
      color: const Color(0xFFFFF3CD),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'TEST DATA · Skip field workload',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'These shortcuts create isolated synthetic records. No photos or manual documentation are required.',
              style: TextStyle(fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: FilledButton.icon(
                key: const Key('complete_all_test_stations_persistent_button'),
                onPressed: isSaving ? null : onCompleteAll,
                icon: const Icon(Icons.fast_forward_outlined),
                label: Text(
                  isVeV2
                      ? 'Complete all VE–V2 Stations 1–5 synthetically'
                      : 'Complete all Stations 1–5 synthetically',
                ),
              ),
            ),
            TextButton(
              key: const Key('complete_current_test_station_persistent_button'),
              onPressed: isSaving ? null : onCompleteCurrent,
              child: Text('Complete only test Station $stationNumber'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BetweenStationsStep extends StatelessWidget {
  const _BetweenStationsStep({
    required this.blockNumber,
    required this.completedStation,
    required this.boundary,
    required this.plan,
    required this.completedStationLocations,
    required this.completedStationNumbers,
    required this.isSaving,
    required this.onContinue,
    this.imageryProvider,
  });

  final int blockNumber;
  final int completedStation;
  final List<LatLng> boundary;
  final ScoutingRoutePlan? plan;
  final Map<int, LatLng> completedStationLocations;
  final Set<int> completedStationNumbers;
  final bool isSaving;
  final VoidCallback onContinue;
  final FieldImageryProvider? imageryProvider;

  @override
  Widget build(BuildContext context) {
    final nextStation = completedStation + 1;
    return _StepList(
      children: [
        const _Eyebrow('STATION SAVED'),
        const SizedBox(height: 8),
        Text(
          'Continue to Station $nextStation',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          'Block $blockNumber, Station $completedStation is reviewed and saved on this phone.',
          style: const TextStyle(height: 1.45),
        ),
        const SizedBox(height: 14),
        _StationProgressStrip(
          completedStations: completedStationNumbers,
          activeStation: nextStation,
        ),
        const SizedBox(height: 16),
        if (plan?.isReady == true) ...[
          OfflineScoutingRouteMap(
            boundary: boundary,
            plan: plan!,
            activeStation: nextStation,
            completedStationLocations: completedStationLocations,
            completedStationNumbers: completedStationNumbers,
            imageryProvider: imageryProvider,
            height: 280,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        const _InfoCard(
          icon: Icons.info_outline,
          title: 'Approximate guidance only',
          message:
              'The target is editable and the next screen shows live phone location. It is not turn-by-turn navigation, a confirmed walking path, or proof of sampling compliance.',
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          key: Key('continue_to_station_$nextStation'),
          label: 'Continue to Station $nextStation',
          busy: isSaving,
          onPressed: onContinue,
        ),
      ],
    );
  }
}

class _StationProgressStrip extends StatelessWidget {
  const _StationProgressStrip({
    required this.completedStations,
    required this.activeStation,
  });

  final Set<int> completedStations;
  final int activeStation;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${completedStations.length} of 5 stations completed. Station $activeStation is next.',
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5DED0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            for (var station = 1; station <= 5; station++) ...[
              if (station > 1)
                Expanded(
                  child: Container(
                    height: 3,
                    color: completedStations.contains(station - 1)
                        ? AppColors.primary
                        : const Color(0xFFD5DED0),
                  ),
                ),
              _StationProgressDot(
                station: station,
                completed: completedStations.contains(station),
                active: station == activeStation,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _StationProgressDot extends StatelessWidget {
  const _StationProgressDot({
    required this.station,
    required this.completed,
    required this.active,
  });

  final int station;
  final bool completed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? AppColors.primary
        : active
        ? const Color(0xFFE98B00)
        : const Color(0xFF68766F);
    return Tooltip(
      message: completed
          ? 'Station $station completed'
          : active
          ? 'Station $station next'
          : 'Station $station upcoming',
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        alignment: Alignment.center,
        child: completed
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 21)
            : Text(
                '$station',
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

class _BlockReviewStep extends StatelessWidget {
  const _BlockReviewStep({
    required this.blockNumber,
    required this.snapshot,
    required this.isSaving,
    required this.onReviewStation,
    required this.onComplete,
  });

  final int blockNumber;
  final BlockProgressSnapshot snapshot;
  final bool isSaving;
  final ValueChanged<int> onReviewStation;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return _StepList(
      children: [
        const _Eyebrow('BLOCK REVIEW'),
        const SizedBox(height: 8),
        Text(
          'Review Block $blockNumber sampling',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'This confirms sampling completeness only. WormWise does not calculate a result or treatment recommendation here.',
          style: TextStyle(height: 1.45),
        ),
        const SizedBox(height: 14),
        for (final station in snapshot.stations)
          Card(
            key: Key('block_review_station_${station.stationNumber}'),
            elevation: 0,
            child: ListTile(
              leading: Icon(
                station.reviewIsCurrent
                    ? Icons.check_circle
                    : Icons.error_outline,
                color: station.reviewIsCurrent
                    ? AppColors.primary
                    : const Color(0xFF8A5A00),
              ),
              title: Text('Station ${station.stationNumber}'),
              subtitle: Text(
                '${station.plants.length}/10 plant positions · ${station.reviewIsCurrent ? 'review current' : 'review required'}',
              ),
              trailing: TextButton(
                key: Key('review_block_station_${station.stationNumber}'),
                onPressed: () => onReviewStation(station.stationNumber),
                child: const Text('Review'),
              ),
            ),
          ),
        const SizedBox(height: 10),
        const _InfoCard(
          icon: Icons.save_outlined,
          title: 'Raw records remain intact',
          message:
              'Completion validates required blocks, stations, plant positions, evidence associations, and reviews. It does not delete, reclassify, or calculate results.',
        ),
        const SizedBox(height: 20),
        _PrimaryButton(
          key: const Key('complete_block_sampling_button'),
          label: 'Confirm block sampling complete',
          busy: isSaving,
          onPressed: onComplete,
        ),
      ],
    );
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
        Text(
          areaHectares <= 1
              ? 'Block 1 is the whole field'
              : 'Prepare confirmed assessment blocks',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          areaHectares <= 1
              ? '$fieldName has a confirmed approximate outline of ${areaHectares.toStringAsFixed(2)} ha. A field up to one hectare is recorded as one block.'
              : '$fieldName has a confirmed approximate outline of ${areaHectares.toStringAsFixed(2)} ha. Existing evaluator-confirmed block definitions are required. WormWise will not subdivide this field automatically.',
          style: const TextStyle(height: 1.45),
        ),
        const SizedBox(height: 16),
        _InfoCard(
          icon: Icons.grid_view_outlined,
          title: 'Active block and station',
          message: areaHectares <= 1
              ? 'Block 1 · Station 1'
              : 'Each confirmed block will begin at Station 1',
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          key: const Key('prepare_block_one_button'),
          label: areaHectares <= 1
              ? 'Prepare Block 1'
              : 'Prepare confirmed blocks',
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
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String status;
  final String title;
  final String message;
  final String? supporting;
  final String actionLabel;
  final VoidCallback onAction;
  final bool warning;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

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
        if (secondaryActionLabel != null && onSecondaryAction != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: OutlinedButton(
              key: const Key('change_growth_stage_button'),
              onPressed: onSecondaryAction,
              child: Text(secondaryActionLabel!),
            ),
          ),
        ],
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
