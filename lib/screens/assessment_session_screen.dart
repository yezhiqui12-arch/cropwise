import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/local/app_database.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/evidence_capture_repository.dart';
import '../data/repositories/scouting_workflow_repository.dart';
import '../data/repositories/scouting_route_repository.dart';
import '../data/services/atomic_plant_save_service.dart';
import '../data/services/atomic_ve_v2_save_service.dart';
import '../data/services/five_station_completion_service.dart';
import '../providers/assessment_workspace_provider.dart';
import '../providers/app_data_mode.dart';
import '../providers/five_station_workflow_provider.dart';
import '../services/phone_location_service.dart';
import '../services/evidence_capture_coordinator.dart';
import '../services/evidence_storage_service.dart';
import '../services/field_imagery_provider.dart';
import 'station1/station1_workflow_screen.dart';

class AssessmentSessionScreen extends StatelessWidget {
  const AssessmentSessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<AssessmentWorkspaceProvider>();
    final assessment = workspace.currentAssessment;
    if (assessment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Assessment')),
        body: const SafeArea(
          child: Center(child: Text('No unfinished assessment was found.')),
        ),
      );
    }

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
      create: (context) => FiveStationWorkflowProvider(
        assessmentId: assessment.id,
        workflowRepository: ScoutingWorkflowRepository(database),
        assessmentRepository: context.read<AssessmentRepository>(),
        plantSaveService: AtomicPlantSaveService(
          database,
          evidenceRepository: evidenceRepository,
        ),
        evidenceCoordinator: evidenceCoordinator,
        completionService: FiveStationCompletionService(database),
        veV2SaveService: AtomicVeV2SaveService(
          database,
          evidenceRepository: evidenceRepository,
        ),
        routeRepository: ScoutingRouteRepository(database),
        testMode: dataMode.isTestMode,
        debugFeaturesEnabled: dataMode.debugFeaturesEnabled,
      )..initialize(),
      child: Station1WorkflowScreen(
        fieldName: workspace.fieldWorkspace?.field.name ?? 'Selected field',
        captureLocation: () =>
            phoneLocation.captureAverage(maximumAcceptedAccuracyMeters: null),
        watchLocation: phoneLocation.watchPosition,
        testMode: dataMode.isTestMode,
        debugFeaturesEnabled: dataMode.debugFeaturesEnabled,
        imageryProvider: PiatFieldImageryProvider(),
      ),
    );
  }
}
