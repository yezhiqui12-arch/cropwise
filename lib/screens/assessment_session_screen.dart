import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import 'package:provider/provider.dart';

import '../data/local/app_database.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/evidence_capture_repository.dart';
import '../data/repositories/scouting_workflow_repository.dart';
import '../data/repositories/scouting_route_repository.dart';
import '../data/services/atomic_plant_save_service.dart';
import '../data/services/atomic_ve_v2_save_service.dart';
import '../data/services/scouting_completion_service.dart';
import '../providers/assessment_workspace_provider.dart';
import '../providers/app_data_mode.dart';
import '../providers/scouting_workflow_provider.dart';
import '../services/phone_location_service.dart';
import '../services/evidence_capture_coordinator.dart';
import '../services/evidence_storage_service.dart';
import '../services/field_imagery_provider.dart';
import 'station1/station1_workflow_screen.dart';

class AssessmentSessionScreen extends StatefulWidget {
  const AssessmentSessionScreen({
    super.key,
    this.assessmentId,
    this.initialBlockRunId,
    this.initialStationNumber,
    this.onExitRequested,
    this.openForReview = false,
    this.onStationRepairCompleted,
  });

  final String? assessmentId;
  final String? initialBlockRunId;
  final int? initialStationNumber;
  final Future<void> Function()? onExitRequested;
  final bool openForReview;
  final Future<void> Function()? onStationRepairCompleted;

  @override
  State<AssessmentSessionScreen> createState() =>
      _AssessmentSessionScreenState();
}

class _AssessmentSessionScreenState extends State<AssessmentSessionScreen> {
  String? _assessmentId;
  String? _fieldName;

  @override
  void initState() {
    super.initState();
    _assessmentId = widget.assessmentId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assessmentId == null) {
      final workspace = context.read<AssessmentWorkspaceProvider>();
      if (workspace.currentAssessment != null) {
        _assessmentId = workspace.currentAssessment!.id;
        _fieldName ??= workspace.fieldWorkspace?.field.name;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AssessmentSessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.assessmentId != null &&
        widget.assessmentId != oldWidget.assessmentId) {
      _assessmentId = widget.assessmentId;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_assessmentId == null) {
      final workspace = context.watch<AssessmentWorkspaceProvider>();
      if (workspace.currentAssessment != null) {
        _assessmentId = workspace.currentAssessment!.id;
        _fieldName ??= workspace.fieldWorkspace?.field.name;
      } else if (!workspace.isLoading) {
        return Scaffold(
          appBar: AppBar(title: const AppText('Assessment')),
          body: const SafeArea(
            child: Center(
              child: AppText('No unfinished assessment was found.'),
            ),
          ),
        );
      } else {
        return const Scaffold(
          body: SafeArea(child: Center(child: CircularProgressIndicator())),
        );
      }
    }

    final assessmentId = _assessmentId!;

    final database = context.read<AppDatabase>();
    final dataMode =
        context.read<AppDataMode?>() ?? const AppDataMode.production();
    final evidenceRepository = EvidenceCaptureRepository(database);
    final evidenceCoordinator = EvidenceCaptureCoordinator(
      repository: evidenceRepository,
      storage: EvidenceStorageService(
        rootDirectory: dataMode.isTestMode
            ? dataMode.evidenceRootDirectory
            : null,
      ),
    );
    const phoneLocation = PhoneLocationService();
    return ChangeNotifierProvider(
      create: (context) =>
          ScoutingWorkflowProvider(
            assessmentId: assessmentId,
            workflowRepository: ScoutingWorkflowRepository(database),
            assessmentRepository: context.read<AssessmentRepository>(),
            plantSaveService: AtomicPlantSaveService(
              database,
              evidenceRepository: evidenceRepository,
            ),
            evidenceCoordinator: evidenceCoordinator,
            completionService: ScoutingCompletionService(database),
            veV2SaveService: AtomicVeV2SaveService(
              database,
              evidenceRepository: evidenceRepository,
            ),
            routeRepository: ScoutingRouteRepository(database),
            testMode: dataMode.isTestMode,
            debugFeaturesEnabled: dataMode.debugFeaturesEnabled,
          )..initialize(
            initialBlockRunId: widget.initialBlockRunId,
            initialStationNumber: widget.initialStationNumber,
            openForReview: widget.openForReview,
          ),
      child: Station1WorkflowScreen(
        fieldName: _fieldName ?? 'Selected field',
        captureLocation: () =>
            phoneLocation.captureAverage(maximumAcceptedAccuracyMeters: null),
        capturePhotoLocation: () => phoneLocation.captureAverage(
          targetSamples: 1,
          maximumWait: const Duration(seconds: 8),
          maximumAcceptedAccuracyMeters: null,
          fallbackToCurrentPosition: false,
        ),
        watchLocation: phoneLocation.watchPosition,
        testMode: dataMode.isTestMode,
        debugFeaturesEnabled: dataMode.debugFeaturesEnabled,
        imageryProvider: PiatFieldImageryProvider(),
        onExitRequested: widget.onExitRequested,
        onStationRepairCompleted: widget.onStationRepairCompleted,
      ),
    );
  }
}
