import 'dart:convert';
import '../../models/automatic_screening.dart';
import '../../services/computer_vision/detection_preferences.dart';
import 'dart:async';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:provider/provider.dart';

import '../../providers/scouting_workflow_provider.dart';
import '../../providers/scouting_workflow_state.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/scouting_workflow_repository.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../services/evidence_camera_service.dart';
import '../../services/field_imagery_provider.dart';
import '../../services/assessment_protocol_selector.dart';
import '../../services/phone_location_service.dart';
import '../../services/scouting_route_generator.dart';
import '../../services/assessment_area_policy.dart';
import '../../services/station_evidence_policy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/offline_scouting_route_map.dart';
import '../assess/assessment_results_screen.dart';
import '../scan/route_preparation_step.dart';
import '../scan/station_route_guidance_step.dart';
import '../scan/guided_plant_walk_step.dart';
import '../scan/scouting_ui.dart';
import '../scan/guided_plant_details_sheet.dart';
import '../scan/plant_action_guidance_panel.dart';
import '../scan/plant_action_notice_host.dart';
import '../../models/da_monitoring.dart';
import '../scan/da_monitoring_controls.dart';
import '../scan/da_batch_import_screen.dart';
import '../../services/da_batch_import_store.dart';
import '../scan/station_target_adjustment_step.dart';
import '../../data/services/atomic_ve_v2_save_service.dart';
import '../growth_stage_correction_screen.dart';
import '../ve_v2/ve_v2_pilot_steps.dart';
import 'plant_capture_board_step.dart';
import 'station_batch_upload_screen.dart';
import 'plant_analysis_inspector_step.dart';
import '../../services/map_view_policy.dart';
import 'late_season_workflow_steps.dart';
import 'model_detection_image.dart';
import 'stage_station_review_step.dart';
import 'evidence_capture_panel.dart';
import 'evidence_photo_viewer.dart';
import 'guided_camera_screen.dart';
import 'plant_selection_step.dart';
import 'resume_assessment_step.dart';
import 'station_location_step.dart';
import 'station_context_evidence_step.dart';
import 'station_review_step.dart';

enum _EvidenceImageSource { camera, gallery }

class Station1WorkflowScreen extends StatelessWidget {
  static final _startingPlantAssessments = <String>{};
  const Station1WorkflowScreen({
    super.key,
    required this.fieldName,
    required this.captureLocation,
    this.capturePhotoLocation,
    required this.watchLocation,
    this.cameraFactory = const PluginEvidenceCameraFactory(),
    this.testMode = false,
    this.debugFeaturesEnabled = kDebugMode,
    this.imageryProvider,
    this.onExitRequested,
    this.onStationRepairCompleted,
  });

  final String fieldName;
  final Future<AveragedPhoneLocation> Function() captureLocation;
  final Future<AveragedPhoneLocation> Function()? capturePhotoLocation;
  final Future<Stream<PhoneLocationReading>> Function() watchLocation;
  final EvidenceCameraFactory cameraFactory;
  final bool testMode;
  final bool debugFeaturesEnabled;
  final FieldImageryProvider? imageryProvider;
  final Future<void> Function()? onExitRequested;
  final Future<void> Function()? onStationRepairCompleted;

  @override
  Widget build(BuildContext context) {
    final workflow = context.watch<ScoutingWorkflowProvider>();
    final showTestTools = kDebugMode && debugFeaturesEnabled && testMode;

    return _StationWorkflowBackBoundary(
      onSystemBack: () => _handleSystemBack(context, workflow),
      builder: (exitRoute) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('station_workflow_back_button'),
            tooltip: AppWords.of(context).translate(
              workflow.state == Station1ViewState.plantEntry ||
                      workflow.state == Station1ViewState.openedEarEntry
                  ? 'Return to station review'
                  : 'Return to Assess',
            ),
            onPressed: workflow.isSaving
                ? null
                : workflow.state == Station1ViewState.plantEntry ||
                      workflow.state == Station1ViewState.openedEarEntry
                ? () => _run(context, workflow.navigateBackWithinWorkflow)
                : () => _exitToScan(
                    context,
                    workflow,
                    onExitRequested ?? exitRoute,
                  ),
            icon: const Icon(Icons.arrow_back),
          ),
          title: AppText(
            workflow.isDaGuidedScouting
                ? 'Guided scouting'
                : 'Block ${workflow.blockNumber} · Station ${workflow.stationNumber}',
          ),
          actions: [
            if (workflow.isDaGuidedScouting)
              IconButton(
                tooltip: 'Scouting guide',
                icon: const Icon(Icons.help_outline),
                onPressed: () => showScoutingGuide(
                  context,
                  instruction: workflow.isVeV2
                      ? 'Inspect the newest leaves and stem base.'
                      : 'Inspect the upper 3–4 leaves.',
                ),
              ),
            if (kDebugMode && debugFeaturesEnabled && testMode)
              IconButton(
                key: const Key('test_station_shortcuts_button'),
                tooltip: AppWords.of(context).translate('TEST DATA shortcuts'),
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
                child:
                    workflow.isDaGuidedScouting &&
                        _showsGuidedWalk(workflow.state)
                    ? _buildGuidedWalk(context, workflow)
                    : switch (workflow.state) {
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
                          actionLabel: 'Return to Assess',
                          onAction: () => Navigator.pop(context),
                        ),
                        Station1ViewState.setupRequired => _MessageStep(
                          status: 'SETUP REQUIRED',
                          title: 'Finish assessment setup',
                          message:
                              'This assessment is not ready for field observations. Return to Assess and complete setup.',
                          actionLabel: 'Return to Assess',
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
                          actionLabel: 'Return to Assess',
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
                          actionLabel: 'Return to Assess',
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
                          onAction: () =>
                              _run(context, workflow.confirmGrowthStage),
                          secondaryActionLabel: 'Change growth stage',
                          onSecondaryAction: () async {
                            final changed = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const GrowthStageCorrectionScreen(),
                              ),
                            );
                            if (changed == true) workflow.retry();
                          },
                        ),
                        Station1ViewState.largeFieldBlocked => _MessageStep(
                          key: const Key('station1_large_field_blocked'),
                          warning: true,
                          status: 'ASSESSMENT LIMIT',
                          title: 'This field is above the current limit',
                          message:
                              'The confirmed outline is ${workflow.boundary!.areaHectares.toStringAsFixed(2)} ha. Formal assessment currently supports up to ${AssessmentAreaPolicy.maxAssessmentAreaHectares.toStringAsFixed(0)} ha.',
                          supporting:
                              'The field remains saved. No block or station was created.',
                          actionLabel: 'Return to Assess',
                          onAction: () => Navigator.pop(context),
                        ),
                        Station1ViewState.blockPreparation =>
                          _BlockPreparationStep(
                            fieldName: fieldName,
                            areaHectares: workflow.boundary!.areaHectares,
                            locationsPerBlock: workflow.locationsPerBlock,
                            plantsPerLocation: workflow.plantsPerLocation,
                            blocks: workflow.blockDefinitions,
                            isSaving: workflow.isSaving,
                            onPrepareSingle: () =>
                                _run(context, workflow.prepareRequiredBlocks),
                            onGenerate: () =>
                                _run(context, workflow.generateProposedBlocks),
                            onGenerateAlternative: () => _run(
                              context,
                              () => workflow.generateProposedBlocks(
                                nextAlternative: true,
                              ),
                            ),
                            onConfirm: () =>
                                _run(context, workflow.confirmProposedBlocks),
                          ),
                        Station1ViewState.resumeCheck => ResumeAssessmentStep(
                          isSaving: workflow.isSaving,
                          onSubmit: workflow.submitResumeCheck,
                        ),
                        Station1ViewState.routePreparation =>
                          RoutePreparationStep(
                            blockNumber: workflow.blockNumber,
                            boundary: workflow.blockBoundary,
                            plan: workflow.routePlan!,
                            completedStationLocations:
                                workflow.completedStationLocations,
                            completedStationNumbers:
                                workflow.completedStationNumbers,
                            captureLocation: captureLocation,
                            watchLocation: watchLocation,
                            isSaving: workflow.isSaving,
                            onSavePreparation: workflow.saveRoutePreparation,
                            onGenerate: workflow.generateRoute,
                            imageryProvider: imageryProvider,
                          ),
                        Station1ViewState.stationTravel =>
                          StationRouteGuidanceStep(
                            blockNumber: workflow.blockNumber,
                            stationNumber: workflow.stationNumber,
                            boundary: workflow.blockBoundary,
                            plan: workflow.routePlan!,
                            completedStationLocations:
                                workflow.completedStationLocations,
                            completedStationNumbers:
                                workflow.completedStationNumbers,
                            watchLocation: watchLocation,
                            isSaving: workflow.isSaving,
                            onConfirmReached: () => workflow
                                .confirmReachedActiveStation(captureLocation),
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
                            completedStationNumbers:
                                workflow.completedStationNumbers,
                            isSaving: workflow.isSaving,
                            onSaveDraft: workflow.saveTargetAdjustmentDraft,
                            onApply: workflow.applyTargetAdjustment,
                            onCancel: workflow.cancelTargetAdjustment,
                            imageryProvider: imageryProvider,
                          ),
                        Station1ViewState.stationLocation =>
                          StationLocationStep(
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
                              await _acceptEvidence(context, workflow, media);
                              await workflow.continueAfterStationContext();
                            }),
                            onRetake: (media) async {
                              await _retakeEvidence(context, workflow, media);
                            },
                            onRemove: (media) => _run(
                              context,
                              () => workflow.removeEvidence(media),
                            ),
                            onManualFallback: (reason, note) => _run(
                              context,
                              () async {
                                await workflow.waiveEvidence(
                                  viewType:
                                      DatabaseCodes.evidenceViewStationContext,
                                  reasonCode: reason,
                                  note: note,
                                );
                                await workflow.continueAfterStationContext();
                              },
                            ),
                            onContinue: workflow.continueAfterStationContext,
                          ),
                        Station1ViewState.veV2StationSetup =>
                          VeV2StationSetupStep(
                            stationNumber: workflow.stationNumber,
                            stationId: workflow.snapshot!.station!.id,
                            growthStage: workflow.assessment!.growthStage,
                            actorPersonId:
                                workflow.assessment!.evaluatorPersonId,
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
                            onAccept: (media) => _run(
                              context,
                              () => _acceptEvidence(context, workflow, media),
                            ),
                            onRetake: (media) =>
                                _retakeEvidence(context, workflow, media),
                            onRemove: (media) => _run(
                              context,
                              () => workflow.removeEvidence(media),
                            ),
                            onFallback: (reason, note) => _run(
                              context,
                              () => workflow.waiveEvidence(
                                viewType:
                                    DatabaseCodes.evidenceViewVeRowContext,
                                reasonCode: reason,
                                note: note,
                              ),
                            ),
                            onContinue: workflow.continueAfterVeV2RowContext,
                          ),
                        Station1ViewState.veV2ContinuousCapture =>
                          PlantCaptureBoardStep(
                            key: const ValueKey(
                              've_v2_plant_capture_board_step',
                            ),
                            isVeV2: true,
                            selectedPosition:
                                workflow.currentPlantPosition ?? 1,
                            boundary: workflow.blockBoundary,
                            plan: workflow.routePlan!,
                            watchLocation: watchLocation,
                            completedStationLocations:
                                workflow.completedStationLocations,
                            completedStationNumbers:
                                workflow.completedStationNumbers,
                            imageryProvider: imageryProvider,
                            blockNumber: workflow.blockNumber,
                            stationNumber: workflow.stationNumber,
                            evidencePolicy: workflow.currentEvidencePolicy,
                            capturedPlantCount: workflow.capturedPlantCount,
                            stationBundles: workflow.stationEvidenceBundles,
                            veV2Units: workflow.veV2Units,
                            isSaving: workflow.isSaving,
                            resolveFile: workflow.resolveEvidenceFile,
                            cvDiagnoses: workflow.cvDiagnoses,
                            onSelectPlant: (pos) => _run(
                              context,
                              () => workflow.selectCapturePlant(pos),
                            ),
                            onCapture: (position, viewType) async {
                              await workflow.selectCapturePlant(position);
                              if (!context.mounted) return null;
                              return _captureEvidence(
                                context,
                                workflow,
                                viewType,
                                offerPlantSession: true,
                              );
                            },
                            onInspect: (media) =>
                                _inspectEvidence(context, workflow, media),
                            onAccept: (media) => _tryRun(
                              context,
                              () => _acceptEvidence(context, workflow, media),
                            ),
                            onRetake: (media) =>
                                _retakeEvidence(context, workflow, media),
                            onRemove: (media) => _run(
                              context,
                              () => workflow.removeEvidence(media),
                            ),
                            onManualFallback:
                                (position, viewType, reason, note) => _tryRun(
                                  context,
                                  () async {
                                    await workflow.selectCapturePlant(position);
                                    await workflow.waiveEvidence(
                                      viewType: viewType,
                                      reasonCode: reason,
                                      note: note,
                                    );
                                  },
                                ),
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
                            onSaveVeV2UnitException:
                                (
                                  position,
                                  occupancy,
                                  reason,
                                ) => _run(context, () async {
                                  await workflow.selectCapturePlant(position);
                                  if (occupancy ==
                                      DatabaseCodes.veOccupancyRemnant) {
                                    if (!context.mounted) return;
                                    final accepted = await _captureEvidence(
                                      context,
                                      workflow,
                                      DatabaseCodes.evidenceViewStemBase,
                                    );
                                    if (accepted == null) return;
                                  }
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
                                      requiredEvidenceViewTypes:
                                          occupancy ==
                                              DatabaseCodes.veOccupancyRemnant
                                          ? {DatabaseCodes.evidenceViewStemBase}
                                          : const {},
                                      actorPersonId: workflow
                                          .assessment!
                                          .evaluatorPersonId,
                                      notAssessableReason: reason,
                                    ),
                                  );
                                }),
                          ),
                        Station1ViewState.veV2PlantingUnitEntry =>
                          VeV2PlantingUnitStep(
                            key: ValueKey(
                              've_unit_${workflow.currentPlantPosition}',
                            ),
                            position: workflow.currentPlantPosition!,
                            stationId: workflow.snapshot!.station!.id,
                            actorPersonId:
                                workflow.assessment!.evaluatorPersonId,
                            existing: workflow.currentVeV2Unit,
                            bundle: workflow.currentEvidence!,
                            isSaving: workflow.isSaving,
                            resolveFile: workflow.resolveEvidenceFile,
                            onCapture: (view) =>
                                _captureEvidence(context, workflow, view),
                            onInspect: (media) =>
                                _inspectEvidence(context, workflow, media),
                            onAccept: (media) => _run(
                              context,
                              () => _acceptEvidence(context, workflow, media),
                            ),
                            onRetake: (media) =>
                                _retakeEvidence(context, workflow, media),
                            onRemove: (media) => _run(
                              context,
                              () => workflow.removeEvidence(media),
                            ),
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
                            blockNumber: workflow.blockNumber,
                            stationNumber: workflow.stationNumber,
                            stationId: workflow.snapshot!.station!.id,
                            actorPersonId:
                                workflow.assessment!.evaluatorPersonId,
                            existing: workflow.currentPlant,
                            suggestedSourceUnitId: workflow
                                .veV2CaptureTarget
                                ?.sourcePlantingUnitId,
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
                            onAccept: (media) => _run(
                              context,
                              () => _acceptEvidence(context, workflow, media),
                            ),
                            onRetake: (media) =>
                                _retakeEvidence(context, workflow, media),
                            onRemove: (media) => _run(
                              context,
                              () => workflow.removeEvidence(media),
                            ),
                            onFallback: (view, reason, note) => _run(
                              context,
                              () => workflow.waiveEvidence(
                                viewType: view,
                                reasonCode: reason,
                                note: note,
                              ),
                            ),
                            onSave: workflow.saveVeV2LivingSeedling,
                            onCancel: workflow.returnToReview,
                          ),
                        Station1ViewState.veV2StationReview =>
                          VeV2StationReviewStep(
                            blockNumber: workflow.blockNumber,
                            stationNumber: workflow.stationNumber,
                            units: workflow.veV2Units,
                            plants: workflow.snapshot?.plants ?? const [],
                            inspection: workflow.veV2Inspection,
                            acceptedImageCount: workflow
                                .pilotWorkloadMetrics
                                .acceptedImageCount,
                            fallbackCount: workflow
                                .pilotWorkloadMetrics
                                .manualFallbackCount,
                            retakeCount:
                                workflow.pilotWorkloadMetrics.retakeCount,
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
                          actionLabel: 'Return to Assess',
                          onAction: () => Navigator.pop(context),
                        ),
                        Station1ViewState.lateSeasonSetup =>
                          LateSeasonSetupStep(
                            assessmentId: workflow.assessment!.id,
                            evaluatorPersonId:
                                workflow.assessment!.evaluatorPersonId,
                            blockRunIds: workflow.preparedRuns
                                .map((item) => item.run.id)
                                .toList(growable: false),
                            isSaving: workflow.isSaving,
                            onSave: workflow.saveLateSeasonSetup,
                          ),
                        Station1ViewState.openedEarEntry => OpenedEarEntryStep(
                          selection: workflow.activeOpeningSelection!,
                          plant: workflow.currentPlant!,
                          evidence: workflow.currentEvidence!,
                          actorPersonId: workflow.assessment!.evaluatorPersonId,
                          isSaving: workflow.isSaving,
                          resolveFile: workflow.resolveEvidenceFile,
                          onCapture: (viewType) async {
                            await _captureEvidence(context, workflow, viewType);
                          },
                          onInspect: (media) async {
                            await _inspectEvidence(context, workflow, media);
                          },
                          onAccept: (media) => _run(
                            context,
                            () => _acceptEvidence(context, workflow, media),
                          ),
                          onRetake: (media) async {
                            await _retakeEvidence(context, workflow, media);
                          },
                          onRemove: (media) => _run(
                            context,
                            () => workflow.removeEvidence(media),
                          ),
                          onManualFallback: (viewType, reason, note) => _run(
                            context,
                            () => workflow.waiveEvidence(
                              viewType: viewType,
                              reasonCode: reason,
                              note: note,
                            ),
                          ),
                          onSave: (input) => _run(
                            context,
                            () => workflow.saveOpenedEar(input),
                          ),
                        ),
                        Station1ViewState.plantSelection => PlantSelectionStep(
                          blockNumber: workflow.blockNumber,
                          stationNumber: workflow.stationNumber,
                          evidencePolicy: workflow.evidencePolicy,
                          onBegin: () => _run(context, () async {
                            if (!_startingPlantAssessments.add(
                              workflow.assessmentId,
                            )) {
                              return;
                            }
                            try {
                              final database = context.read<AppDatabase>();
                              if (await DetectionPreferences.needsIntroduction(
                                database,
                                workflow.assessmentId,
                              )) {
                                if (!context.mounted) return;
                                final choice = await showDialog<bool>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const AppText(
                                      'Enable evidence detection?',
                                    ),
                                    content: const AppText(
                                      'Highlight possible larvae and feeding damage in your photos. Damage screening already runs automatically.\n\n'
                                      '• Uses more RAM and may slow photo processing.\n\n'
                                      '• Detected evidence may be incorrect. Do not assume it is real or confirmed; verify it on the actual plant.\n\n'
                                      'This setting cannot change during an ongoing assessment. Choose now, before taking the first plant photo. Future changes are available in More → Models.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, false),
                                        child: const AppText('Keep off'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, true),
                                        child: const AppText(
                                          'Enable and proceed',
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (choice == null || !context.mounted) return;
                                await DetectionPreferences.chooseInitialDetection(
                                  choice,
                                  database: database,
                                  assessmentId: workflow.assessmentId,
                                );
                              }
                              if (!context.mounted) return;
                              await workflow.beginTenConsecutivePlants();
                            } finally {
                              _startingPlantAssessments.remove(
                                workflow.assessmentId,
                              );
                            }
                          }),
                        ),
                        Station1ViewState.plantCapture => PlantCaptureBoardStep(
                          key: const ValueKey('plant_capture_board_step'),
                          selectedPosition: workflow.currentPlantPosition ?? 1,
                          boundary: workflow.blockBoundary,
                          plan: workflow.routePlan!,
                          watchLocation: watchLocation,
                          completedStationLocations:
                              workflow.completedStationLocations,
                          completedStationNumbers:
                              workflow.completedStationNumbers,
                          imageryProvider: imageryProvider,
                          blockNumber: workflow.blockNumber,
                          stationNumber: workflow.stationNumber,
                          evidencePolicy: workflow.currentEvidencePolicy,
                          capturedPlantCount: workflow.capturedPlantCount,
                          stationBundles: workflow.stationEvidenceBundles,
                          isSaving: workflow.isSaving,
                          resolveFile: workflow.resolveEvidenceFile,
                          cvDiagnoses: workflow.cvDiagnoses,
                          primaryViewType: workflow.primaryEvidenceViewType,
                          onSelectPlant: (pos) => _run(
                            context,
                            () => workflow.selectCapturePlant(pos),
                          ),
                          onQuickOverride: (pos, status) => _run(
                            context,
                            () => workflow.quickOverridePlantStatus(
                              plantPosition: pos,
                              status: status,
                            ),
                          ),
                          onCapture: (position, viewType) async {
                            await workflow.selectCapturePlant(position);
                            if (!context.mounted) return null;
                            return _captureEvidence(
                              context,
                              workflow,
                              viewType,
                              offerPlantSession: true,
                            );
                          },
                          onBatchUpload: () =>
                              _openStationBatchUpload(context, workflow),
                          onInspect: (media) =>
                              _inspectEvidence(context, workflow, media),
                          onAccept: (media) => _tryRun(
                            context,
                            () => _acceptEvidence(context, workflow, media),
                          ),
                          onRetake: (media) =>
                              _retakeEvidence(context, workflow, media),
                          onRemove: (media) => _run(
                            context,
                            () => workflow.removeEvidence(media),
                          ),
                          onManualFallback:
                              (position, viewType, reason, note) =>
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
                        Station1ViewState.plantEntry =>
                          PlantAnalysisInspectorStep(
                            key: ValueKey(
                              'plant_inspector_${workflow.currentPlantPosition}',
                            ),
                            position: workflow.isDaGuidedScouting
                                ? workflow.stationNumber
                                : workflow.currentPlantPosition!,
                            isDaGuidedScouting: workflow.isDaGuidedScouting,
                            onSaveNotes: workflow.isDaGuidedScouting
                                ? (notes) => _run(
                                    context,
                                    () => workflow.saveDaPlantNotesAndReturn(
                                      notes,
                                    ),
                                  )
                                : null,
                            stationNumber: workflow.stationNumber,
                            blockNumber: workflow.blockNumber,
                            growthStage: workflow.assessment!.growthStage,
                            cvDiagnosis: workflow
                                .cvDiagnoses[workflow.currentPlantPosition],
                            screeningOnly:
                                workflow.isDaGuidedScouting ||
                                AutomaticScreening.parse(
                                      workflow
                                          .currentPlant
                                          ?.plant
                                          .wholePlantContextNote,
                                    ) !=
                                    null,
                            plantRecord: workflow.currentPlant?.plant,
                            initialStatus:
                                workflow.currentPlant?.plant.plantStatus,
                            initialNotes:
                                workflow.currentPlant?.plant.evaluatorNotes,
                            evidence: workflow.currentEvidence,
                            resolveEvidenceFile: workflow.resolveEvidenceFile,
                            onInspectEvidence: (media) =>
                                _inspectEvidence(context, workflow, media),
                            onRetakeEvidence: (media) =>
                                _retakeEvidence(context, workflow, media),
                            onCaptureEvidence: (viewType) =>
                                _captureEvidence(context, workflow, viewType),
                            isSaving: workflow.isSaving,
                            onSaveDiagnosis: ({required status, notes}) =>
                                _run(context, () async {
                                  await workflow
                                      .savePlantDiagnosisAndReturnToReview(
                                        plantPosition:
                                            workflow.currentPlantPosition!,
                                        status: status,
                                        notes: notes,
                                      );
                                }),
                            onCancel: () =>
                                _run(context, workflow.returnToStationReview),
                          ),
                        Station1ViewState.stationReview =>
                          workflow.isVtR2 || workflow.isR3R6
                              ? StageStationReviewStep(
                                  growthStage: workflow.assessment!.growthStage,
                                  blockNumber: workflow.blockNumber,
                                  snapshot: workflow.snapshot!,
                                  evidenceReviews:
                                      workflow.plantEvidenceReviews,
                                  openingPlan: workflow.openingPlan,
                                  openedEarSubsampleComplete:
                                      workflow.openedEarSubsampleComplete,
                                  isSaving: workflow.isSaving,
                                  onEditPlant: (position) => _run(
                                    context,
                                    () => workflow.editPlant(position),
                                  ),
                                  onBeginOpenedEar: (selection) => _run(
                                    context,
                                    () => workflow.beginOpenedEar(selection),
                                  ),
                                  onFailOpenedEar: (selection, reason) => _run(
                                    context,
                                    () => workflow.failOpenedEarSelection(
                                      selection,
                                      reason,
                                    ),
                                  ),
                                  onConfirm: () => _run(
                                    context,
                                    () => _confirmStationRepair(
                                      context,
                                      workflow,
                                    ),
                                  ),
                                )
                              : StationReviewStep(
                                  snapshot: workflow.snapshot!,
                                  blockNumber: workflow.blockNumber,
                                  stationNumber: workflow.stationNumber,
                                  growthStage: workflow.assessment!.growthStage,
                                  evidencePolicy: workflow.evidencePolicy,
                                  evidenceReviews:
                                      workflow.plantEvidenceReviews,
                                  isSaving: workflow.isSaving,
                                  onEdit: (position) => _run(
                                    context,
                                    () => workflow.editPlant(position),
                                  ),
                                  onConfirm: () => _run(
                                    context,
                                    () => _confirmStationRepair(
                                      context,
                                      workflow,
                                    ),
                                  ),
                                  onCompleteWithoutManualConfirmation: () =>
                                      _run(
                                        context,
                                        () => _confirmStationRepair(
                                          context,
                                          workflow,
                                          withoutManualConfirmation: true,
                                        ),
                                      ),
                                  onCompleteTestStation:
                                      kDebugMode &&
                                          debugFeaturesEnabled &&
                                          testMode
                                      ? () => _run(
                                          context,
                                          workflow.completeTestStation,
                                        )
                                      : null,
                                  onMarkInsufficient: (position) => _run(
                                    context,
                                    () =>
                                        workflow.markPlantEvidenceInsufficient(
                                          position,
                                        ),
                                  ),
                                  evidenceBundles:
                                      workflow.stationEvidenceBundles,
                                  resolveEvidenceFile:
                                      workflow.resolveEvidenceFile,
                                  evidenceThumbnailBuilder: (media) =>
                                      _buildDetectionThumbnail(workflow, media),
                                  onOpenEvidence: (media, scopeLabel) =>
                                      _openReadOnlyEvidence(
                                        context,
                                        workflow,
                                        media,
                                        scopeLabel,
                                      ),
                                  pilotWorkloadMetrics:
                                      workflow.pilotWorkloadMetrics,
                                ),
                        Station1ViewState.stationComplete => _MessageStep(
                          key: const Key('station1_complete'),
                          status: 'STATION REVIEWED',
                          title: 'Ten plant positions saved',
                          message:
                              'Block ${workflow.blockNumber}, Station ${workflow.stationNumber} is complete and saved on this phone.',
                          actionLabel: 'Return to Assess',
                          onAction: () => Navigator.pop(context),
                        ),
                        Station1ViewState.betweenStations =>
                          _BetweenStationsStep(
                            blockNumber: workflow.blockNumber,
                            completedStation: workflow.stationNumber,
                            boundary: workflow.blockBoundary,
                            plan: workflow.routePlan,
                            completedStationLocations:
                                workflow.completedStationLocations,
                            completedStationNumbers:
                                workflow.completedStationNumbers,
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
                          onComplete: () async {
                            if (workflow.isDaGuidedScouting &&
                                !await _confirmDaNaturalEnemies(
                                  context,
                                  workflow,
                                ))
                              return;
                            final targetAssessmentId = workflow.assessmentId;
                            if (!context.mounted) return;
                            final completed = await _tryRun(
                              context,
                              workflow.completeCurrentBlock,
                            );
                            if (!completed ||
                                !context.mounted ||
                                workflow.state !=
                                    Station1ViewState.samplingComplete) {
                              return;
                            }
                            await Navigator.pushReplacement<void, void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AssessmentResultsScreen(
                                  assessmentId: targetAssessmentId,
                                ),
                              ),
                            );
                          },
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
                          onAction: () =>
                              _run(context, workflow.continueToNextBlock),
                        ),
                        Station1ViewState.samplingComplete => _MessageStep(
                          key: const Key('sampling_complete_step'),
                          status: 'SAMPLING COMPLETE',
                          title: 'All required blocks are complete',
                          message: workflow.isDaGuidedScouting
                              ? 'All 20 sampled plants are saved for every required block. Expert confirmation remains separate.'
                              : 'Stations 1–5 and all ten plant positions per station are saved and reviewed for every required block.',
                          supporting:
                              'Formula-versioned assessment metrics are saved. They are descriptive field results, not a diagnosis or treatment recommendation.',
                          actionLabel: 'View assessment results',
                          onAction: () => Navigator.pushReplacement<void, void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AssessmentResultsScreen(
                                assessmentId: workflow.assessmentId,
                              ),
                            ),
                          ),
                          secondaryActionLabel: 'Return to Assess',
                          onSecondaryAction: () => Navigator.pop(context),
                        ),
                        Station1ViewState.pausedConditions => _MessageStep(
                          key: const Key('station1_conditions_paused'),
                          warning: true,
                          status: 'PAUSED',
                          title: 'Conditions changed',
                          message:
                              'Do not add new observations until you can confirm the assessment is still comparable and safe to continue.',
                          supporting:
                              'Previous answers and timestamps remain saved.',
                          actionLabel: 'Return to Assess',
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
    ScoutingWorkflowProvider workflow,
    Future<void> Function() exitRoute,
  ) async {
    if (workflow.isSaving) return;
    if (workflow.state == Station1ViewState.plantEntry) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const AppText('Return to Assess?'),
          content: const AppText(
            'Answers not yet saved on this plant form will be discarded. Accepted photographs and previously saved plant records will remain attached.',
          ),
          actions: [
            TextButton(
              key: const Key('stay_on_plant_button'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const AppText('Stay here'),
            ),
            FilledButton(
              key: const Key('leave_plant_for_scan_button'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const AppText('Return to Assess'),
            ),
          ],
        ),
      );
      if (leave != true || !context.mounted) return;
    }
    await exitRoute();
  }

  Future<void> _confirmStationRepair(
    BuildContext context,
    ScoutingWorkflowProvider workflow, {
    bool withoutManualConfirmation = false,
  }) async {
    if (withoutManualConfirmation) {
      await workflow.completeStationWithoutManualConfirmation(
        remainOnReview: onStationRepairCompleted != null,
      );
    } else {
      await workflow.confirmStationReview(
        remainOnReview: onStationRepairCompleted != null,
      );
    }
    if (onStationRepairCompleted == null) return;
    final remaining = await workflow.currentStationValidationIssues();
    if (remaining.isEmpty) {
      await onStationRepairCompleted?.call();
      return;
    }
    if (!context.mounted) return;
    final message = remaining.first.message.replaceFirst(
      RegExp(r'^Block \d+:\s*'),
      '',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: AppText('Station still needs attention: $message')),
    );
    if (workflow.isVeV2) {
      await workflow.proceedToStationReview();
    } else {
      await workflow.returnToStationReview();
    }
  }

  static Future<void> _handleSystemBack(
    BuildContext context,
    ScoutingWorkflowProvider workflow,
  ) async {
    if (workflow.isSaving) return;
    if (!workflow.canNavigateBackWithinWorkflow) {
      Navigator.maybePop(context);
      return;
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
    ScoutingWorkflowProvider workflow,
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
              const AppText(
                'TEST DATA shortcuts',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const AppText(
                'These actions write clearly synthetic records only to the separate debug database. The V3–V12 full-assessment shortcut also creates stored plant photos and GPS coordinates.',
              ),
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('fill_remaining_test_plants_button'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _run(context, workflow.fillRemainingTestPlants);
                },
                child: const AppText('Fill remaining test plants'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('complete_test_station_button'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _run(context, workflow.completeTestStation);
                },
                child: const AppText('Complete test station'),
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
                label: const AppText('Create full 20-plant test assessment'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _showsGuidedWalk(Station1ViewState state) => const {
    Station1ViewState.stationTravel,
    Station1ViewState.plantSelection,
    Station1ViewState.plantCapture,
    Station1ViewState.veV2ContinuousCapture,
    Station1ViewState.stationReview,
    Station1ViewState.veV2StationReview,
    Station1ViewState.betweenStations,
  }.contains(state);

  Widget _buildGuidedWalk(
    BuildContext context,
    ScoutingWorkflowProvider workflow,
  ) {
    final bundle = workflow.bundleForPlant(1);
    final photos = bundle?.media ?? const <EvidenceMediaRecord>[];
    final diagnosis = workflow.cvDiagnoses[1];
    final activePlant = workflow.stationNumber;
    final actionRevision =
        '${workflow.daGuidanceRevision}:${daPhotoSignature(photos)}:${identityHashCode(diagnosis)}';
    final guidedWalk = GuidedPlantWalkStep(
      key: ValueKey('guided_walk_${workflow.prepared?.run.id}'),
      fieldName: fieldName,
      areaHectares: workflow.prepared!.block.areaHectares,
      plantNumber: workflow.stationNumber,
      completedPlants: workflow.completedDaPlantCount,
      boundary: workflow.blockBoundary,
      plan: workflow.routePlan!,
      completedLocations: workflow.daRecordedPlantLocations,
      completedNumbers: workflow.completedStationNumbers,
      evidenceNumbers: workflow.daEvidencePlantNumbers,
      watchLocation: watchLocation,
      imageryProvider: imageryProvider,
      arrived: workflow.snapshot?.station != null,
      photos: photos,
      resolveFile: workflow.resolveEvidenceFile,
      resultLabel: diagnosis == null
          ? null
          : AutomaticScreening(diagnosis).label,
      resultConfidence: diagnosis?.classificationLabel == null
          ? null
          : diagnosis!.confidenceScore,
      actionGuidance: PlantActionGuidancePanel(
        key: ValueKey(
          'plant_actions_${workflow.prepared!.run.id}_${workflow.stationNumber}',
        ),
        repository: workflow.plantActions,
        assessmentId: workflow.assessment!.id,
        blockRunId: workflow.prepared!.run.id,
        number: workflow.stationNumber,
        revision: actionRevision,
        atPlant: workflow.snapshot?.reviewIsCurrent != true,
        initiallyExpanded: false,
        loadDetails: () => workflow.loadDaPlantDetails(activePlant),
        resolveFile: workflow.resolveEvidenceFile,
      ),
      onScreen: workflow.analyzeDaActivePlantForPreview,
      isSaving: workflow.isSaving,
      onOpenPlant: (number) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.background,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: (_) => FractionallySizedBox(
          heightFactor: .96,
          child: GuidedPlantDetailsSheet(
            number: number,
            blockNumber: workflow.blockNumber,
            growthStage: workflow.assessment!.growthStage,
            resolveFile: workflow.resolveEvidenceFile,
            actionRepository: workflow.plantActions,
            onSaveNotes: (notes) =>
                workflow.saveDaPlantFieldNotes(number, notes),
            onSaveCorrection: (values) =>
                workflow.saveDaPlantCorrection(number, values),
            loadDetails: () async {
              // Analyze only the active plant when explicitly opening results.
              // Browsing previous/future pins never switches the workflow.
              if (number == workflow.stationNumber &&
                  (workflow
                          .bundleForPlant(1)
                          ?.media
                          .any(
                            (m) =>
                                m.deletedAt == null &&
                                m.storageState ==
                                    DatabaseCodes.evidenceStorageReady,
                          ) ??
                      false)) {
                await workflow.analyzeDaActivePlantForPreview();
              }
              return workflow.loadDaPlantDetails(number);
            },
          ),
        ),
      ),
      onArrive: () => workflow.confirmReachedActiveStation(captureLocation),
      onAdjust: workflow.beginTargetAdjustment,
      onCapture: () async {
        await workflow.selectCapturePlant(1, analyzePrevious: false);
        if (!context.mounted) return;
        final active =
            workflow.currentEvidence?.media
                .where(
                  (p) =>
                      p.deletedAt == null &&
                      (p.storageState == DatabaseCodes.evidenceStorageReady ||
                          p.storageState ==
                              DatabaseCodes.evidenceStorageStaged),
                )
                .map((p) => p.viewType)
                .toSet() ??
            <String>{};
        final views = [
          workflow.primaryEvidenceViewType,
          DatabaseCodes.evidenceViewCloseUp,
          DatabaseCodes.evidenceViewDiagnosticDetail,
        ].where((v) => !active.contains(v)).toList();
        if (views.isEmpty) return;
        await _capturePlantPhotoSession(
          context,
          workflow,
          views,
          active.length,
          active,
        );
        if (workflow
                .bundleForPlant(1)
                ?.media
                .any(
                  (m) =>
                      m.deletedAt == null &&
                      m.storageState == DatabaseCodes.evidenceStorageReady,
                ) ??
            false) {
          await workflow.analyzeDaActivePlantForPreview();
        }
      },
      onImport: () async {
        await _importDaPlantPhotos(context, workflow);
        if (workflow
                .bundleForPlant(1)
                ?.media
                .any(
                  (m) =>
                      m.deletedAt == null &&
                      m.storageState == DatabaseCodes.evidenceStorageReady,
                ) ??
            false) {
          await workflow.analyzeDaActivePlantForPreview();
        }
      },
      onImportSample: () => _openDaBatchImport(context, workflow),
      instruction: workflow.isVeV2
          ? 'Inspect the available newest leaves and stem base.'
          : 'Inspect the upper 3–4 leaves.',
      onContinue: () async {
        if (workflow.stationNumber == workflow.locationsPerBlock &&
            (workflow.snapshot?.reviewIsCurrent == true ||
                workflow.isPlantCaptureSatisfied(1)) &&
            !await _confirmDaNaturalEnemies(context, workflow))
          return;
        if (workflow.snapshot?.reviewIsCurrent == true) {
          if (workflow.stationNumber < workflow.locationsPerBlock)
            await workflow.continueToNextStation();
          return;
        }
        await workflow.finishDaPlantAndContinue();
      },
      onReview: () async {
        await workflow.selectCapturePlant(1, analyzePrevious: false);
        await workflow.analyzePlantBundle(1);
        await workflow.editPlant(1);
      },
    );
    return PlantActionNoticeHost(
      key: ValueKey('plant_action_notices_${workflow.assessment!.id}'),
      repository: workflow.plantActions,
      assessmentId: workflow.assessment!.id,
      blockRunId: workflow.prepared!.run.id,
      number: activePlant,
      revision: actionRevision,
      enabled:
          !workflow.isSaving &&
          diagnosis != null &&
          workflow.snapshot?.reviewIsCurrent != true,
      loadDetails: () => workflow.loadDaPlantDetails(activePlant),
      resolveFile: workflow.resolveEvidenceFile,
      child: guidedWalk,
    );
  }

  Future<bool> _confirmDaNaturalEnemies(
    BuildContext context,
    ScoutingWorkflowProvider workflow,
  ) async {
    if (await workflow.loadDaNaturalEnemies() != null) return true;
    if (!context.mounted) return false;
    final selection = await showDaNaturalEnemiesDialog(context);
    if (selection == null) return false;
    await workflow.saveDaNaturalEnemies(selection);
    return true;
  }

  Future<void> _openDaBatchImport(
    BuildContext context,
    ScoutingWorkflowProvider workflow,
  ) async {
    final assessmentId = workflow.assessmentId;
    final blockId = workflow.prepared!.run.id;
    final blockNumber = workflow.blockNumber;
    final store = DaBatchImportStore(context.read<AppDatabase>());
    final available = await workflow.availableDaBatchPlants();
    final existingDraft = await store.load(assessmentId, blockId);
    if (!context.mounted) return;
    if (available.isEmpty && existingDraft == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('All plants already have photos.')),
      );
      return;
    }
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DaBatchImportScreen(
          store: store,
          assessmentId: assessmentId,
          blockId: blockId,
          blockNumber: blockNumber,
          plantNumbers: available,
          primaryViewType: workflow.primaryEvidenceViewType,
          supportViewTypes: const [
            DatabaseCodes.evidenceViewCloseUp,
            DatabaseCodes.evidenceViewDiagnosticDetail,
          ],
          onSavePhoto: (number, view, photo) => workflow.saveDaBatchPhoto(
            blockId: blockId,
            number: number,
            viewType: view,
            photo: photo,
          ),
          onScreenPlant: (number, ids) =>
              workflow.screenDaBatchPlant(blockId, number, ids),
          onValidatePhoto: (number, view, id) =>
              workflow.daBatchPhotoIsSaved(blockId, number, view, id),
          onValidateScreening: (number, ids) =>
              workflow.daBatchPlantIsScreened(blockId, number, ids),
          onFinish: () async {
            await workflow.refreshAfterDaBatchImport();
            if (!context.mounted) return false;
            if (workflow.completedDaPlantCount == workflow.locationsPerBlock &&
                !await _confirmDaNaturalEnemies(context, workflow))
              return false;
            return true;
          },
        ),
      ),
    );
    await workflow.refreshAfterDaBatchImport();
  }

  Future<void> _importDaPlantPhotos(
    BuildContext context,
    ScoutingWorkflowProvider workflow,
  ) async {
    // Import refers only to the active plant. Multiple views must not be counted
    // as separate plants, nor assigned the phone's present GPS as capture GPS.
    final selected = await ImagePicker().pickMultiImage(
      requestFullMetadata: false,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (selected.isEmpty || !context.mounted) return;
    final active =
        workflow
            .bundleForPlant(1)
            ?.media
            .where(
              (p) =>
                  p.deletedAt == null &&
                  p.storageState == DatabaseCodes.evidenceStorageReady,
            )
            .map((p) => p.viewType)
            .toSet() ??
        <String>{};
    final slots = [
      workflow.primaryEvidenceViewType,
      DatabaseCodes.evidenceViewCloseUp,
      DatabaseCodes.evidenceViewDiagnosticDetail,
    ].where((v) => !active.contains(v)).toList();
    if (selected.length > slots.length) {
      throw StateError(
        'Choose up to ${slots.length} photo(s) of this same plant. Each plant allows 3 photos.',
      );
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppText('Import for Plant ${workflow.stationNumber}?'),
        content: AppText(
          'Choose photos of this same plant: one overview and up to two closer views.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (workflow.snapshot?.station == null)
      await workflow.confirmReachedActiveStation();
    await workflow.selectCapturePlant(1, analyzePrevious: false);
    for (var index = 0; index < selected.length; index++) {
      final media = await workflow.stageEvidence(
        viewType: slots[index],
        sourcePath: selected[index].path,
        deleteSourceAfterCopy: false,
        fromCamera: false,
      );
      await _acceptEvidence(context, workflow, media);
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

  Future<void> _openStationBatchUpload(
    BuildContext context,
    ScoutingWorkflowProvider workflow,
  ) async {
    final missingPositions = [
      for (var position = 1; position <= 10; position++)
        if (!workflow.isPlantCaptureSatisfied(position) &&
            !(workflow
                    .bundleForPlant(position)
                    ?.isViewSatisfied(workflow.primaryEvidenceViewType) ??
                false))
          position,
    ];
    if (missingPositions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('All plant overviews are already saved.'),
        ),
      );
      return;
    }
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StationBatchUploadScreen(
          stationNumber: workflow.stationNumber,
          plantPositions: missingPositions,
          primaryViewType: workflow.primaryEvidenceViewType,
          onSavePhoto: (position, viewType, sourcePath) async {
            await workflow.selectCapturePlant(position, analyzePrevious: false);
            final media = await workflow.stageEvidence(
              viewType: viewType,
              sourcePath: sourcePath,
              deleteSourceAfterCopy: false,
              fromCamera: false,
            );
            await _acceptEvidence(context, workflow, media);
          },
          onAnalyzePlant: (position) async {
            final result = await workflow.analyzePlantBundle(position);
            if (result == null) {
              throw StateError('Screening did not return a plant result.');
            }
          },
        ),
      ),
    );
  }

  Future<String?> _captureEvidence(
    BuildContext context,
    ScoutingWorkflowProvider workflow,
    String viewType, {
    bool offerPlantSession = false,
  }) async {
    final plantViews = [
      workflow.primaryEvidenceViewType,
      DatabaseCodes.evidenceViewCloseUp,
      DatabaseCodes.evidenceViewDiagnosticDetail,
    ];
    if (plantViews.contains(viewType)) {
      final activePhotos =
          workflow.currentEvidence?.media
              .where(
                (m) =>
                    m.deletedAt == null &&
                    (m.storageState == DatabaseCodes.evidenceStorageReady ||
                        m.storageState == DatabaseCodes.evidenceStorageStaged),
              )
              .toList() ??
          <EvidenceMediaRecord>[];
      final usedViews = activePhotos.map((m) => m.viewType).toSet();
      if (activePhotos.length >= 3) return null;
      if (usedViews.contains(viewType)) {
        final freeViews = plantViews.where((view) => !usedViews.contains(view));
        if (freeViews.isEmpty) return null;
        viewType = freeViews.first;
      }
    }
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
    final source = await showModalBottomSheet<_EvidenceImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText(
                'Add $viewLabel',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const AppText(
                'Take a new field photo or upload one already saved on this phone.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('capture_from_camera'),
                onPressed: () =>
                    Navigator.pop(sheetContext, _EvidenceImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const AppText('Take photo'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('capture_from_gallery'),
                onPressed: () =>
                    Navigator.pop(sheetContext, _EvidenceImageSource.gallery),
                icon: const Icon(Icons.upload_file_outlined),
                label: const AppText('Upload from gallery'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || source == null) return null;

    if (source == _EvidenceImageSource.camera &&
        offerPlantSession &&
        plantViews.contains(viewType)) {
      final activeViews =
          workflow.currentEvidence?.media
              .where(
                (m) =>
                    m.deletedAt == null &&
                    (m.storageState == DatabaseCodes.evidenceStorageReady ||
                        m.storageState == DatabaseCodes.evidenceStorageStaged),
              )
              .map((m) => m.viewType)
              .toSet() ??
          <String?>{};
      final remainingViews = [
        viewType,
        ...plantViews.where(
          (view) => view != viewType && !activeViews.contains(view),
        ),
      ].take(3 - activeViews.length).toList();
      return _capturePlantPhotoSession(
        context,
        workflow,
        remainingViews,
        activeViews.length,
        activeViews,
      );
    }

    GuidedCameraResult? result;
    var deleteSourceAfterCopy = true;
    if (source == _EvidenceImageSource.gallery) {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (selected == null || !context.mounted) return null;
      AveragedPhoneLocation? uploadLocation;
      final recent = const PhoneLocationService().recentLiveReading();
      if (recent != null) {
        uploadLocation = AveragedPhoneLocation(
          latitude: recent.latitude,
          longitude: recent.longitude,
          averageAccuracyMeters: recent.accuracyMeters,
          worstAccuracyMeters: recent.accuracyMeters,
          sampleCount: 1,
          capturedAt: recent.capturedAt,
        );
      }
      if (uploadLocation == null) {
        try {
          uploadLocation = await (capturePhotoLocation ?? captureLocation)();
        } catch (_) {
          // Saved with location marked unavailable; no prompt needed.
        }
        if (!context.mounted) return null;
      }
      result = GuidedCameraResult.captured(
        selected.path,
        location: uploadLocation,
      );
      deleteSourceAfterCopy = false;
    } else {
      result = await Navigator.push<GuidedCameraResult>(
        context,
        MaterialPageRoute(
          builder: (_) => GuidedCameraScreen(
            title: title,
            viewLabel: viewLabel,
            instruction: instruction,
            cameraFactory: cameraFactory,
            captureLocation: capturePhotoLocation ?? captureLocation,
          ),
        ),
      );
    }
    if (!context.mounted || result == null) return null;
    final sourcePath = result.sourcePath;
    if (sourcePath != null) {
      EvidenceMediaRecord? stagedMedia;
      final staged = await _tryRun(context, () async {
        stagedMedia = await workflow.stageEvidence(
          viewType: viewType,
          sourcePath: sourcePath,
          deleteSourceAfterCopy: deleteSourceAfterCopy,
          photoLocation: result?.location,
          fromCamera: source == _EvidenceImageSource.camera,
        );
      });
      if (!staged || !context.mounted) return null;
      final media = stagedMedia;
      if (media != null &&
          media.storageState == DatabaseCodes.evidenceStorageStaged) {
        final accepted = await _tryRun(context, () async {
          await _acceptEvidence(context, workflow, media);
        });
        return accepted ? viewType : null;
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

  Future<String?> _capturePlantPhotoSession(
    BuildContext context,
    ScoutingWorkflowProvider workflow,
    List<String> views,
    int initialPhotoCount,
    Set<String?> activeViews,
  ) async {
    if (views.isEmpty) return null;
    final cameraViews = views
        .map(
          (view) => switch (view) {
            DatabaseCodes.evidenceViewCloseUp => const GuidedCameraView(
              title: 'Whorl detail',
              viewLabel: 'Close-up',
              instruction:
                  'Move closer to the whorl or damaged area. Keep the detail clearly in frame.',
            ),
            DatabaseCodes.evidenceViewDiagnosticDetail => const GuidedCameraView(
              title: 'Extra evidence detail',
              viewLabel: 'Detail',
              instruction:
                  'Frame the larva, egg mass, or other sign that needs its own view.',
            ),
            DatabaseCodes.evidenceViewWholeSeedling => const GuidedCameraView(
              title: 'Seedling photo',
              viewLabel: 'Whole seedling',
              instruction:
                  'Keep the whole seedling, newest leaves, and stem base in frame.',
            ),
            _ => const GuidedCameraView(
              title: 'Plant photo',
              viewLabel: 'Overview',
              instruction: 'Keep the newest leaves and whorl clearly in frame.',
            ),
          },
        )
        .toList();
    final requiredViews =
        workflow.currentEvidencePolicy == StationEvidencePolicy.station1TwoView
        ? <String>{
            DatabaseCodes.evidenceViewWhorlOverview,
            DatabaseCodes.evidenceViewCloseUp,
          }
        : <String>{workflow.primaryEvidenceViewType};
    var minimumCaptures = 1;
    for (var i = 0; i < views.length; i++) {
      if (requiredViews.contains(views[i]) && !activeViews.contains(views[i])) {
        minimumCaptures = i + 1;
      }
    }
    String? lastAccepted;
    var acceptedCount = 0;
    final result = await Navigator.push<GuidedCameraResult>(
      context,
      MaterialPageRoute(
        builder: (_) => GuidedCameraScreen(
          title: cameraViews.first.title,
          viewLabel: cameraViews.first.viewLabel,
          instruction: cameraViews.first.instruction,
          cameraFactory: cameraFactory,
          captureLocation: capturePhotoLocation ?? captureLocation,
          sessionViews: cameraViews,
          initialPhotoCount: initialPhotoCount,
          minimumSessionCaptures: minimumCaptures,
          onSessionCapture: (photo, index) async {
            final path = photo.sourcePath;
            if (path == null) return false;
            final view = views[index];
            final accepted = await _tryRun(context, () async {
              final media = await workflow.stageEvidence(
                viewType: view,
                sourcePath: path,
                deleteSourceAfterCopy: true,
                photoLocation: photo.location,
                fromCamera: true,
              );
              if (media.storageState != DatabaseCodes.evidenceStorageStaged) {
                throw StateError('The photo was not staged for review.');
              }
              await _acceptEvidence(context, workflow, media);
            });
            if (accepted) {
              lastAccepted = view;
              acceptedCount++;
            }
            return accepted;
          },
        ),
      ),
    );
    if (!context.mounted || result == null || result.sourcePath != null) {
      return lastAccepted;
    }
    final fallbackView = views[acceptedCount];
    final fallback = await showEvidenceFallbackDialog(
      context,
      suggestedReasonCode: result.fallbackReasonCode,
    );
    if (!context.mounted || fallback == null) return lastAccepted;
    final saved = await _tryRun(
      context,
      () => workflow.waiveEvidence(
        viewType: fallbackView,
        reasonCode: fallback.reasonCode,
        note: fallback.note,
      ),
    );
    return saved ? fallbackView : lastAccepted;
  }

  Widget _buildDetectionThumbnail(
    ScoutingWorkflowProvider workflow,
    EvidenceMediaRecord media,
  ) {
    EvidenceCaptureBundle? bundle;
    for (final candidate in workflow.stationEvidenceBundles) {
      if (candidate.session.id == media.captureSessionId) {
        bundle = candidate;
        break;
      }
    }
    final diagnosis = bundle?.session.plantPosition == null
        ? null
        : workflow.cvDiagnoses[bundle!.session.plantPosition];
    return FutureBuilder<File>(
      future: workflow.resolveEvidenceFile(media.localUri),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null || !file.existsSync()) {
          return const ColoredBox(
            color: Color(0xFFE6E6E6),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ModelDetectionImage(
          file: file,
          boxes: ModelDetectionImage.boxesForFile(diagnosis, file),
        );
      },
    );
  }

  Future<void> _acceptEvidence(
    BuildContext context,
    ScoutingWorkflowProvider workflow,
    EvidenceMediaRecord media,
  ) async {
    await workflow.acceptEvidence(media);
  }

  Future<String?> _inspectEvidence(
    BuildContext context,
    ScoutingWorkflowProvider workflow,
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
    final scopeLabel = workflow.isDaGuidedScouting
        ? 'Block ${workflow.blockNumber} · Plant ${workflow.stationNumber}'
        : bundle?.session.plantPosition == null
        ? 'Block ${workflow.blockNumber} · Station ${workflow.stationNumber}'
        : 'Station ${workflow.stationNumber} · Plant ${bundle!.session.plantPosition}';
    final plantPosition = bundle?.session.plantPosition;
    final cvDiagnosis = plantPosition == null
        ? null
        : workflow.cvDiagnoses[plantPosition];
    final action = await Navigator.push<EvidencePhotoAction>(
      context,
      MaterialPageRoute(
        builder: (_) => EvidencePhotoViewer(
          media: media,
          scopeLabel: scopeLabel,
          resolveFile: workflow.resolveEvidenceFile,
          cvDiagnosis: cvDiagnosis,
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
        final accepted = await _tryRun(context, () async {
          await _acceptEvidence(context, workflow, media);
        });
        return accepted ? media.viewType : null;
      case EvidencePhotoAction.retake:
        return _retakeEvidence(context, workflow, media);
      case EvidencePhotoAction.addCloseUp:
        if (media.storageState == DatabaseCodes.evidenceStorageStaged) {
          final accepted = await _tryRun(
            context,
            () => _acceptEvidence(context, workflow, media),
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
            () => _acceptEvidence(context, workflow, media),
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
    ScoutingWorkflowProvider workflow,
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
          content: const AppText(
            'The image file will be deleted. WormWise keeps only an audited metadata tombstone and checksum.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const AppText('Cancel'),
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
    ScoutingWorkflowProvider workflow,
    EvidenceMediaRecord media,
    String scopeLabel,
  ) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => EvidencePhotoViewer(
        media: media,
        scopeLabel: scopeLabel,
        resolveFile: workflow.resolveEvidenceFile,
        scoutingStyle: workflow.isDaGuidedScouting,
        cvDiagnosis: workflow.isDaGuidedScouting
            ? workflow.cvDiagnoses[1]
            : null,
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
            const AppText(
              'TEST DATA · Skip field workload',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const AppText(
              'These shortcuts create isolated synthetic records. V3–V12 test plants include stored photos and GPS coordinates; no manual capture is required.',
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
                      : 'Create 50-plant assessment with photos and GPS',
                ),
              ),
            ),
            TextButton(
              key: const Key('complete_current_test_station_persistent_button'),
              onPressed: isSaving ? null : onCompleteCurrent,
              child: AppText('Complete only test Station $stationNumber'),
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
        AppText(
          'Continue to Station $nextStation',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        AppText(
          'Station $completedStation saved.',
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
            height: math.min(
              390,
              math.max(340, MediaQuery.sizeOf(context).height * .40),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        const _InfoCard(
          icon: Icons.info_outline,
          title: 'Approximate guidance only',
          message: 'Follow the route where safe. You can adjust the target.',
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
            : AppText(
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
        AppText(
          'Review Block $blockNumber sampling',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const AppText(
          'This confirms sampling completeness. Completing the final block calculates and saves the assessment metrics; it does not create a diagnosis or treatment recommendation.',
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
              title: AppText(
                '${station.requiredPlantCount == 1 ? 'Plant' : 'Station'} ${station.stationNumber}',
              ),
              subtitle: AppText(
                station.requiredPlantCount == 1
                    ? '${station.reviewIsCurrent ? 'Saved' : 'Needs review'} · Expert confirmation separate'
                    : '${station.plants.length}/10 plant positions · ${station.reviewIsCurrent ? 'review current' : 'review required'}',
              ),
              trailing: TextButton(
                key: Key('review_block_station_${station.stationNumber}'),
                onPressed: () => onReviewStation(station.stationNumber),
                child: const AppText('Review'),
              ),
            ),
          ),
        const SizedBox(height: 10),
        const _InfoCard(
          icon: Icons.save_outlined,
          title: 'Raw records remain intact',
          message:
              'Completion validates required blocks, stations, plant positions, evidence associations, and reviews. It does not delete or reclassify observations.',
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
    required this.locationsPerBlock,
    required this.plantsPerLocation,
    required this.blocks,
    required this.isSaving,
    required this.onPrepareSingle,
    required this.onGenerate,
    required this.onGenerateAlternative,
    required this.onConfirm,
  });

  final String fieldName;
  final double areaHectares;
  final int locationsPerBlock;
  final int plantsPerLocation;
  final List<FieldBlockRecord> blocks;
  final bool isSaving;
  final VoidCallback onPrepareSingle;
  final VoidCallback onGenerate;
  final VoidCallback onGenerateAlternative;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final requiredBlocks = AssessmentAreaPolicy.requiredBlockCount(
      areaHectares,
    );
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
        AppText(
          '$fieldName · ${areaHectares.toStringAsFixed(2)} ha · $requiredBlocks ${requiredBlocks == 1 ? 'block' : 'blocks'}',
          style: const TextStyle(height: 1.45),
        ),
        const SizedBox(height: 16),
        _InfoCard(
          icon: Icons.assignment_outlined,
          title: 'Calculated workload',
          message:
              '$requiredBlocks ${requiredBlocks == 1 ? 'block' : 'blocks'} · '
              '${requiredBlocks * locationsPerBlock * plantsPerLocation} plants',
        ),
        const SizedBox(height: 24),
        if (requiredBlocks == 1)
          _PrimaryButton(
            key: const Key('prepare_block_one_button'),
            label: 'Prepare Block 1',
            busy: isSaving,
            onPressed: onPrepareSingle,
          )
        else if (blocks.isEmpty)
          _PrimaryButton(
            key: const Key('generate_block_proposal_button'),
            label: 'Generate proposed blocks',
            busy: isSaving,
            onPressed: onGenerate,
          )
        else ...[
          _BlockPlanPreview(blocks: blocks),
          const SizedBox(height: 14),
          for (final block in blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppText(
                'Block ${block.blockNumber} · ${block.areaHectares.toStringAsFixed(2)} ha',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 10),
          _PrimaryButton(
            key: const Key('confirm_block_proposal_button'),
            label: 'Confirm proposed blocks',
            busy: isSaving,
            onPressed: onConfirm,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('regenerate_block_proposal_button'),
            onPressed: isSaving ? null : onGenerateAlternative,
            child: const AppText('Try another safe layout'),
          ),
        ],
        if (requiredBlocks > 1 && blocks.isEmpty) ...[
          const SizedBox(height: 10),
          const AppText(
            'Check each proposed block before confirming.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _BlockPlanPreview extends StatefulWidget {
  const _BlockPlanPreview({required this.blocks});

  final List<FieldBlockRecord> blocks;

  @override
  State<_BlockPlanPreview> createState() => _BlockPlanPreviewState();
}

class _BlockPlanPreviewState extends State<_BlockPlanPreview> {
  bool _imageryFailed = false;

  @override
  void didUpdateWidget(covariant _BlockPlanPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blocks != widget.blocks) _imageryFailed = false;
  }

  @override
  Widget build(BuildContext context) {
    final rings = <List<LatLng>>[];
    final blockNumbers = <int>[];
    for (final block in widget.blocks) {
      try {
        final decoded = jsonDecode(block.geometryGeojson);
        final coordinates = decoded['coordinates']?[0];
        if (coordinates is! List) continue;
        final ring = <LatLng>[];
        for (final coordinate in coordinates) {
          if (coordinate is List &&
              coordinate.length >= 2 &&
              coordinate[0] is num &&
              coordinate[1] is num) {
            ring.add(
              LatLng(
                (coordinate[1] as num).toDouble(),
                (coordinate[0] as num).toDouble(),
              ),
            );
          }
        }
        if (ring.length >= 3) {
          rings.add(ring);
          blockNumbers.add(block.blockNumber);
        }
      } catch (_) {
        // Keep the saved geometry diagram available if map parsing fails.
      }
    }
    final points = rings.expand((ring) => ring).toList();
    return Container(
      key: const Key('block_proposal_preview'),
      height: 230,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: _imageryFailed || points.isEmpty
          ? CustomPaint(painter: _BlockPlanPainter(widget.blocks))
          : Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: MapViewPolicy.initialCenter(points.first),
                    initialZoom: 15,
                    minZoom: MapViewPolicy.minZoom,
                    maxZoom: MapViewPolicy.maxZoom,
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(points),
                      padding: const EdgeInsets.all(28),
                    ),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      tileUpdateTransformer: TileUpdateTransformers.debounce(
                        const Duration(milliseconds: 160),
                      ),
                      panBuffer: 0,
                      keepBuffer: 3,
                      urlTemplate:
                          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                      maxNativeZoom: 17,
                      userAgentPackageName: 'com.wormwise.app.wormwise',
                      errorTileCallback: (_, _, _) {
                        if (_imageryFailed) return;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _imageryFailed = true);
                        });
                      },
                    ),
                    PolygonLayer(
                      polygons: [
                        for (var index = 0; index < rings.length; index++)
                          Polygon(
                            points: rings[index],
                            color:
                                _BlockPlanPainter.colors[index %
                                    _BlockPlanPainter.colors.length],
                            borderColor: const Color(0xFF244D27),
                            borderStrokeWidth: 3,
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        for (var index = 0; index < rings.length; index++)
                          Marker(
                            point: LatLng(
                              rings[index]
                                      .map((p) => p.latitude)
                                      .reduce((a, b) => a + b) /
                                  rings[index].length,
                              rings[index]
                                      .map((p) => p.longitude)
                                      .reduce((a, b) => a + b) /
                                  rings[index].length,
                            ),
                            width: 32,
                            height: 32,
                            child: CircleAvatar(
                              backgroundColor: const Color(0xFF244D27),
                              child: AppText(
                                '${blockNumbers[index]}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const Positioned(
                  right: 8,
                  bottom: 6,
                  child: AppText(
                    'Esri World Imagery',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      shadows: [Shadow(blurRadius: 3, color: Colors.black)],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _BlockPlanPainter extends CustomPainter {
  _BlockPlanPainter(this.blocks);

  final List<FieldBlockRecord> blocks;
  static const colors = <Color>[
    Color(0x883B7A3A),
    Color(0x8870A95F),
    Color(0x88D7A93B),
    Color(0x888B6DB0),
    Color(0x884A90A4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rings = <List<Offset>>[];
    for (final block in blocks) {
      try {
        final decoded = jsonDecode(block.geometryGeojson);
        final coordinates = decoded['coordinates']?[0];
        if (coordinates is! List) continue;
        final ring = <Offset>[];
        for (final coordinate in coordinates) {
          if (coordinate is List &&
              coordinate.length >= 2 &&
              coordinate[0] is num &&
              coordinate[1] is num) {
            ring.add(
              Offset(
                (coordinate[0] as num).toDouble(),
                (coordinate[1] as num).toDouble(),
              ),
            );
          }
        }
        if (ring.length >= 3) rings.add(ring);
      } catch (_) {
        // Repository validation reports malformed geometry before confirmation.
      }
    }
    if (rings.isEmpty) return;
    final all = rings.expand((ring) => ring).toList();
    final minX = all.map((p) => p.dx).reduce(math.min);
    final maxX = all.map((p) => p.dx).reduce(math.max);
    final minY = all.map((p) => p.dy).reduce(math.min);
    final maxY = all.map((p) => p.dy).reduce(math.max);
    final width = math.max(maxX - minX, 1e-12);
    final height = math.max(maxY - minY, 1e-12);
    const padding = 18.0;
    final scale = math.min(
      (size.width - padding * 2) / width,
      (size.height - padding * 2) / height,
    );
    Offset transform(Offset point) => Offset(
      padding + (point.dx - minX) * scale,
      size.height - padding - (point.dy - minY) * scale,
    );

    for (var index = 0; index < rings.length; index++) {
      final path = Path()
        ..moveTo(
          transform(rings[index].first).dx,
          transform(rings[index].first).dy,
        );
      for (final point in rings[index].skip(1)) {
        final mapped = transform(point);
        path.lineTo(mapped.dx, mapped.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[index % colors.length]
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF244D27)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
      final bounds = path.getBounds();
      final label = TextPainter(
        text: TextSpan(
          text: '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final center = bounds.center;
      canvas.drawCircle(center, 14, Paint()..color = const Color(0xFF244D27));
      label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BlockPlanPainter oldDelegate) =>
      oldDelegate.blocks != blocks;
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
                    AppWords.of(context).translate(title),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppWords.of(context).translate(message),
                    style: const TextStyle(height: 1.35),
                  ),
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
  final VoidCallback? onPressed;
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
            : Text(AppWords.of(context).translate(label)),
      ),
    );
  }
}
