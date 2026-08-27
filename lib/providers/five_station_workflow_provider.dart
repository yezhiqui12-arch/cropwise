import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/evidence_capture_repository.dart';
import '../data/repositories/scouting_workflow_repository.dart';
import '../data/repositories/scouting_route_repository.dart';
import '../data/services/atomic_plant_save_service.dart';
import '../data/services/atomic_ve_v2_save_service.dart';
import '../data/services/five_station_completion_service.dart';
import '../data/services/stage_plant_save_service.dart';
import '../services/computer_vision/faw_computer_vision_service.dart';
import '../services/computer_vision/tflite_faw_detector.dart';
import '../services/evidence_capture_coordinator.dart';
import '../services/phone_location_service.dart';
import '../services/scouting_route_generator.dart';
import '../services/station_evidence_policy.dart';
import '../services/ve_v2_analysis_service.dart';
import 'station1_workflow_provider.dart';

enum VeV2CaptureKind { plantingUnit, livingSeedling }

class VeV2CaptureTarget {
  const VeV2CaptureTarget._({
    required this.kind,
    this.plantingUnitPosition,
    this.livingSeedlingPosition,
    this.sourcePlantingUnitId,
    this.sourcePlantingUnitSequence,
  });

  const VeV2CaptureTarget.plantingUnit(int position)
    : this._(
        kind: VeV2CaptureKind.plantingUnit,
        plantingUnitPosition: position,
      );

  const VeV2CaptureTarget.livingSeedling({
    required int livingSeedlingPosition,
    required String? sourcePlantingUnitId,
    required int? sourcePlantingUnitSequence,
  }) : this._(
         kind: VeV2CaptureKind.livingSeedling,
         livingSeedlingPosition: livingSeedlingPosition,
         sourcePlantingUnitId: sourcePlantingUnitId,
         sourcePlantingUnitSequence: sourcePlantingUnitSequence,
       );

  final VeV2CaptureKind kind;
  final int? plantingUnitPosition;
  final int? livingSeedlingPosition;
  final String? sourcePlantingUnitId;
  final int? sourcePlantingUnitSequence;
}

/// Coordinates five-station capture and Scan-owned approximate route guidance.
class FiveStationWorkflowProvider extends ChangeNotifier {
  FiveStationWorkflowProvider({
    required this.assessmentId,
    required ScoutingWorkflowRepository workflowRepository,
    required AssessmentRepository assessmentRepository,
    required AtomicPlantSaveService plantSaveService,
    required FiveStationCompletionService completionService,
    AtomicVeV2SaveService? veV2SaveService,
    ScoutingRouteRepository? routeRepository,
    EvidenceCaptureCoordinator? evidenceCoordinator,
    VeV2AnalysisService veV2AnalysisService =
        const UnavailableVeV2AnalysisService(),
    FawComputerVisionService? computerVisionService,
    this.testMode = false,
    this.debugFeaturesEnabled = kDebugMode,
  }) : _workflow = workflowRepository,
       _assessments = assessmentRepository,
       _plantSaves = plantSaveService,
       _stageSaves = StagePlantSaveService(plantSaveService.database),
       _completion = completionService,
       _veV2 = veV2SaveService,
       _routes = routeRepository,
       _evidence = evidenceCoordinator,
       _veV2Analysis = veV2AnalysisService,
       _cvService = computerVisionService ?? TfliteFawDetector();

  final String assessmentId;
  final ScoutingWorkflowRepository _workflow;
  final AssessmentRepository _assessments;
  final AtomicPlantSaveService _plantSaves;
  final StagePlantSaveService _stageSaves;
  final FiveStationCompletionService _completion;
  final AtomicVeV2SaveService? _veV2;
  final ScoutingRouteRepository? _routes;
  final EvidenceCaptureCoordinator? _evidence;
  final VeV2AnalysisService _veV2Analysis;
  final FawComputerVisionService _cvService;
  final bool testMode;
  final bool debugFeaturesEnabled;

  Map<int, PlantDiagnosisResult> _cvDiagnoses = const {};
  Map<int, PlantDiagnosisResult> get cvDiagnoses => _cvDiagnoses;
  FawComputerVisionService get cvService => _cvService;

  Station1ViewState _state = Station1ViewState.loading;
  Station1ViewState? _resumeTarget;
  AssessmentRecord? _assessment;
  BoundaryRecord? _boundary;
  List<PreparedScoutingRun> _preparedRuns = const [];
  int _activeRunIndex = 0;
  int _stationNumber = 1;
  BlockProgressSnapshot? _blockSnapshot;
  StationSnapshot? _snapshot;
  EvidenceCaptureBundle? _stationContextEvidence;
  EvidenceCaptureBundle? _currentEvidence;
  List<EvidenceCaptureBundle> _stationEvidenceBundles = const [];
  Map<int, PlantEvidenceReview> _plantEvidenceReviews = const {};
  PilotWorkloadMetrics _pilotWorkloadMetrics = PilotWorkloadMetrics.empty;
  Map<int, int> _capturedLeavesInspected = const {};
  LateSeasonAssessmentSetupRecord? _lateSeasonSetup;
  List<EarOpeningSelectionRecord> _openingPlan = const [];
  EarOpeningSelectionRecord? _activeOpeningSelection;
  VeV2StationInspectionRecord? _veV2Inspection;
  List<PlantingUnitObservationRecord> _veV2Units = const [];
  EvidenceCaptureBundle? _veV2RowContextEvidence;
  VeV2CaptureTarget? _veV2CaptureTarget;
  Map<String, VeV2AnalysisPresentation> _veV2AnalysisPresentations = const {};
  int? _currentPlantPosition;
  Object? _error;
  bool _isSaving = false;
  bool _returnToBlockReview = false;
  bool _returnToVeV2Review = false;
  bool _returnToRouteTravel = false;
  ScoutingRoutePlan? _routePlan;

  Station1ViewState get state => _state;
  AssessmentRecord? get assessment => _assessment;
  BoundaryRecord? get boundary => _boundary;
  PreparedScoutingRun? get prepared =>
      _preparedRuns.isEmpty ? null : _preparedRuns[_activeRunIndex];
  List<PreparedScoutingRun> get preparedRuns => _preparedRuns;
  BlockProgressSnapshot? get blockSnapshot => _blockSnapshot;
  StationSnapshot? get snapshot => _snapshot;
  int get stationNumber => _stationNumber;
  int get blockNumber => prepared?.run.blockSequence ?? 1;
  int? get currentPlantPosition => _currentPlantPosition;
  bool get isVeV2 =>
      const {'ve', 'v1', 'v2'}.contains(_assessment?.growthStage);
  bool get isVtR2 => _assessment?.growthStage == 'vt_r2';
  bool get isR3R6 => _assessment?.growthStage == 'r3_r6';
  LateSeasonAssessmentSetupRecord? get lateSeasonSetup => _lateSeasonSetup;
  List<EarOpeningSelectionRecord> get openingPlan => _openingPlan;
  EarOpeningSelectionRecord? get activeOpeningSelection =>
      _activeOpeningSelection;
  List<EarOpeningSelectionRecord> get activeOpeningTargets => _openingPlan
      .where(
        (item) =>
            item.initiallySelected ||
            item.selectionStatus == 'replacement_selected' ||
            item.selectionStatus == 'opened' ||
            item.selectionStatus == 'failed',
      )
      .toList(growable: false);
  bool get openedEarSubsampleComplete =>
      !isR3R6 ||
      _lateSeasonSetup?.openingPermission !=
          DatabaseCodes.openingPermissionGranted ||
      activeOpeningTargets.every(
        (item) =>
            item.selectionStatus == 'opened' ||
            item.selectionStatus == 'failed',
      );
  String get primaryEvidenceViewType => isVtR2 || isR3R6
      ? DatabaseCodes.evidenceViewEarRegionOverview
      : DatabaseCodes.evidenceViewWhorlOverview;
  VeV2StationInspectionRecord? get veV2Inspection => _veV2Inspection;
  List<PlantingUnitObservationRecord> get veV2Units => _veV2Units;
  EvidenceCaptureBundle? get veV2RowContextEvidence => _veV2RowContextEvidence;
  VeV2CaptureTarget? get veV2CaptureTarget => _veV2CaptureTarget;
  int get veV2CapturedLivingCount => _veV2CapturedLivingPositions.length;
  int get veV2ConfirmedUnitCount =>
      _veV2Units.where((unit) => unit.primaryCondition != null).length;
  int get veV2ConfirmedLivingCount => _snapshot?.plants.length ?? 0;
  VeV2AnalysisPresentation veV2AnalysisFor(EvidenceCaptureBundle? bundle) =>
      bundle == null
      ? VeV2AnalysisPresentation.unavailable
      : _veV2AnalysisPresentations[bundle.session.id] ??
            VeV2AnalysisPresentation.unavailable;
  PlantingUnitObservationRecord? get currentVeV2Unit {
    final position = _currentPlantPosition;
    if (position == null) return null;
    for (final unit in _veV2Units) {
      if (unit.sequenceNumber == position) return unit;
    }
    return null;
  }

  List<PlantingUnitObservationRecord> get linkableVeV2Units {
    final plants = _snapshot?.plants ?? const <StationPlantRecord>[];
    return _veV2Units.where((unit) {
      final capacity = unit.observedSeedlingCount ?? 0;
      final used = plants
          .where(
            (item) =>
                item.plant.sequenceNumber != _currentPlantPosition &&
                item.plant.sourcePlantingUnitObservationId == unit.id,
          )
          .length;
      return capacity > used;
    }).toList();
  }

  EvidenceCaptureBundle? get stationContextEvidence => _stationContextEvidence;
  EvidenceCaptureBundle? get currentEvidence => _currentEvidence;
  List<EvidenceCaptureBundle> get stationEvidenceBundles =>
      _stationEvidenceBundles;
  Map<int, PlantEvidenceReview> get plantEvidenceReviews =>
      _plantEvidenceReviews;
  PilotWorkloadMetrics get pilotWorkloadMetrics => _pilotWorkloadMetrics;
  StationEvidencePolicy get evidencePolicy =>
      StationEvidencePolicy.forStation(_stationNumber);
  StationEvidencePolicy get currentEvidencePolicy {
    final bundle = _currentEvidence;
    return bundle == null ? evidencePolicy : _policyForBundle(bundle);
  }

  Object? get error => _error;
  bool get isSaving => _isSaving;
  ScoutingRoutePlan? get routePlan => _routePlan;
  List<LatLng> get blockBoundary => prepared == null
      ? const []
      : ScoutingRouteGenerator.parsePolygon(prepared!.block.geometryGeojson);
  Map<int, LatLng> get completedStationLocations => {
    for (final entry in _completedStationLocations().entries)
      if (entry.value != null) entry.key: entry.value!,
  };
  Set<int> get completedStationNumbers =>
      _completedStationLocations().keys.toSet();
  int get savedPlantCount => _snapshot?.plants.length ?? 0;
  bool get canNavigateBackWithinWorkflow => switch (_state) {
    Station1ViewState.stationTravel ||
    Station1ViewState.targetAdjustment => true,
    Station1ViewState.routePreparation =>
      _returnToRouteTravel && _routePlan?.isReady == true,
    Station1ViewState.stationLocation => _routePlan?.isReady == true,
    Station1ViewState.plantEntry ||
    Station1ViewState.plantCapture ||
    Station1ViewState.openedEarEntry ||
    Station1ViewState.stationReview ||
    Station1ViewState.veV2StationSetup ||
    Station1ViewState.veV2RowContextEvidence ||
    Station1ViewState.veV2ContinuousCapture ||
    Station1ViewState.veV2PlantingUnitEntry ||
    Station1ViewState.veV2LivingSeedlingEntry ||
    Station1ViewState.veV2StationReview ||
    Station1ViewState.betweenStations ||
    Station1ViewState.blockReview => true,
    _ => false,
  };
  int? capturedLeavesInspectedFor(int position) =>
      _capturedLeavesInspected[position];

  int get capturedPlantCount {
    final snapshot = _snapshot;
    if (snapshot == null) return 0;
    var count = 0;
    for (var position = 1; position <= 10; position++) {
      if (_isCaptureSatisfied(snapshot, position)) count++;
    }
    return count;
  }

  EvidenceCaptureBundle? bundleForPlant(int position) {
    for (final bundle in _stationEvidenceBundles) {
      if (bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
          bundle.session.plantPosition == position) {
        return bundle;
      }
    }
    return null;
  }

  bool isPlantCaptureSatisfied(int position) {
    final s = _snapshot;
    if (s == null) return false;
    return _isCaptureSatisfied(s, position);
  }

  Future<void> selectCapturePlant(int position) async {
    if (position < 1 || position > 10) return;
    _currentPlantPosition = position;
    if (isVeV2) {
      final unit = _unitAt(position);
      final bundle = bundleForPlant(position);
      _veV2CaptureTarget = VeV2CaptureTarget.livingSeedling(
        livingSeedlingPosition: position,
        sourcePlantingUnitId:
            unit?.id ?? bundle?.session.sourcePlantingUnitObservationId,
        sourcePlantingUnitSequence:
            unit?.sequenceNumber ??
            _unitSequenceForId(bundle?.session.sourcePlantingUnitObservationId),
      );
    }
    await _loadCurrentEvidence();
    notifyListeners();
  }

  Future<void> proceedToStationReview() async {
    _currentPlantPosition = null;
    _setState(
      isVeV2
          ? Station1ViewState.veV2StationReview
          : Station1ViewState.stationReview,
    );
  }

  StationPlantRecord? get currentPlant {
    final position = _currentPlantPosition;
    if (position == null) return null;
    for (final item in _snapshot?.plants ?? const <StationPlantRecord>[]) {
      if (item.plant.sequenceNumber == position) return item;
    }
    return null;
  }

  Future<void> initialize() async {
    _setState(Station1ViewState.loading);
    try {
      _assessment = await _workflow.assessmentById(assessmentId);
      final assessment = _assessment!;
      await _evidence?.reconcileAssessment(
        assessmentId: assessment.id,
        actorPersonId: assessment.evaluatorPersonId,
      );
      if (assessment.status == DatabaseCodes.safetyBlocked) {
        _setState(Station1ViewState.safetyBlocked);
        return;
      }
      if (assessment.status == DatabaseCodes.completed) {
        _preparedRuns = await _workflow.findPreparedRuns(assessment.id);
        _setState(Station1ViewState.samplingComplete);
        return;
      }
      if (assessment.status != DatabaseCodes.inProgress) {
        _setState(Station1ViewState.setupRequired);
        return;
      }
      _boundary = await _workflow.boundaryById(assessment.boundaryVersionId);
      if (_boundary!.confirmationStatus != 'user_confirmed') {
        _setState(Station1ViewState.boundaryRequired);
        return;
      }
      if (!_isPilotStage(assessment.growthStage)) {
        _setState(Station1ViewState.unsupportedStage);
        return;
      }
      if (assessment.growthStageUncertain) {
        _setState(Station1ViewState.stageConfirmation);
        return;
      }
      try {
        _preparedRuns = await _workflow.findPreparedRuns(assessment.id);
      } on PilotBlockRequiredException {
        _setState(Station1ViewState.blockPreparation);
        return;
      } on IncompleteBlockDefinitionsException {
        _setState(Station1ViewState.blockPreparation);
        return;
      }
      if (_preparedRuns.isEmpty) {
        _setState(Station1ViewState.blockPreparation);
        return;
      }
      _activeRunIndex = _firstIncompleteRunIndex();
      await _loadActiveBlock(askForResume: true);
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> confirmGrowthStage() async {
    final assessment = _requireAssessment();
    await _perform(() async {
      await _workflow.confirmPilotGrowthStage(assessment);
      _assessment = await _workflow.assessmentById(assessment.id);
      _setState(Station1ViewState.blockPreparation);
    });
  }

  Future<void> prepareBlockOne() => prepareRequiredBlocks();

  Future<void> prepareRequiredBlocks() async {
    final assessment = _requireAssessment();
    final boundary = _boundary;
    if (boundary == null) throw StateError('Field outline is unavailable.');
    await _perform(() async {
      await _ensureAssessmentActive();
      _preparedRuns = await _workflow.prepareRequiredBlocks(
        assessment,
        boundary,
      );
      _activeRunIndex = _firstIncompleteRunIndex();
      _stationNumber = 1;
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> saveLateSeasonSetup(LateSeasonSetupInput input) async {
    if (!isR3R6 || input.assessmentId != assessmentId) {
      throw StateError('Late-season setup does not match this assessment.');
    }
    final expectedRunIds = _preparedRuns.map((item) => item.run.id).toSet();
    if (!setEquals(expectedRunIds, input.blockRunIds.toSet())) {
      throw StateError(
        'Late-season opening plan does not match prepared blocks.',
      );
    }
    await _perform(() async {
      await _ensureAssessmentActive();
      _lateSeasonSetup = await _stageSaves.saveLateSeasonSetup(input);
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> beginOpenedEar(EarOpeningSelectionRecord selection) async {
    if (!isR3R6 ||
        !(selection.initiallySelected ||
            selection.selectionStatus == 'replacement_selected')) {
      throw StateError('This ear is not in the preselected opening sample.');
    }
    final plant = _snapshot?.plants
        .where((item) => item.plant.sequenceNumber == selection.plantPosition)
        .firstOrNull;
    if (plant?.ear == null || plant!.ear!.externallyAssessable != true) {
      throw StateError(
        'Record a failed selection and reason when the selected ear cannot be opened.',
      );
    }
    _activeOpeningSelection = selection;
    _currentPlantPosition = selection.plantPosition;
    await _loadCurrentEvidence();
    _setState(Station1ViewState.openedEarEntry);
  }

  Future<void> failOpenedEarSelection(
    EarOpeningSelectionRecord selection,
    String reason,
  ) async {
    await _perform(() async {
      await _stageSaves.markOpeningSelectionFailed(
        selectionId: selection.id,
        reason: reason,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _activeOpeningSelection = null;
      _currentPlantPosition = null;
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> saveOpenedEar(OpenedEarSave input) async {
    final selection = _activeOpeningSelection;
    if (selection == null || selection.id != input.selectionId) {
      throw StateError('Opened-ear save does not match the active selection.');
    }
    await _perform(() async {
      await _stageSaves.saveOpenedEar(input);
      _activeOpeningSelection = null;
      _currentPlantPosition = null;
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> saveStationCoordinates(AveragedPhoneLocation location) async {
    await _perform(() async {
      await _ensureAssessmentActive();
      await _workflow.saveStationLocation(
        prepared: _requirePrepared(),
        stationNumber: _stationNumber,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        latitude: location.latitude,
        longitude: location.longitude,
        gpsAccuracyM: location.averageAccuracyMeters,
        capturedAt: location.capturedAt,
      );
      await _clearArrivalConfirmation();
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> saveStationUnavailable({
    required String reason,
    String? note,
  }) async {
    await _perform(() async {
      await _ensureAssessmentActive();
      await _workflow.saveStationLocation(
        prepared: _requirePrepared(),
        stationNumber: _stationNumber,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        notLocatedReason: reason,
        accessibilityNotes: note?.trim().isEmpty == true ? null : note?.trim(),
      );
      await _clearArrivalConfirmation();
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> saveRoutePreparation(RoutePreparationData preparation) async {
    final repository = _requireRouteRepository();
    final plan = _requireRoutePlan();
    await _perform(() async {
      _routePlan = await repository.savePreparationDraft(
        plan,
        preparation,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _setState(Station1ViewState.routePreparation);
    });
  }

  Future<void> generateRoute() async {
    final repository = _requireRouteRepository();
    final plan = _requireRoutePlan();
    await _perform(() async {
      final generated = ScoutingRouteGenerator.generate(
        draft: plan,
        boundary: blockBoundary,
        completedStations: _completedStationLocations(),
      );
      _routePlan = await repository.saveGeneratedPlan(
        generated,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        recalculated: plan.targets.isNotEmpty,
      );
      _returnToRouteTravel = false;
      _setState(Station1ViewState.stationTravel);
    });
  }

  Future<void> editRoutePreparation() async {
    if (_routePlan == null) return;
    _returnToRouteTravel = true;
    _setState(Station1ViewState.routePreparation);
  }

  Future<void> confirmReachedActiveStation() async {
    final repository = _requireRouteRepository();
    final plan = _requireRoutePlan();
    await _perform(() async {
      _routePlan = await repository.confirmStationArrival(
        plan,
        stationNumber: _stationNumber,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _setState(Station1ViewState.stationLocation);
    });
  }

  Future<void> beginTargetAdjustment() async {
    final repository = _requireRouteRepository();
    final plan = _requireRoutePlan();
    await _perform(() async {
      _routePlan = await repository.beginTargetAdjustment(
        plan,
        stationNumber: _stationNumber,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _setState(Station1ViewState.targetAdjustment);
    });
  }

  Future<void> saveTargetAdjustmentDraft({
    required LatLng? candidate,
    required String reason,
  }) async {
    final repository = _requireRouteRepository();
    final plan = _requireRoutePlan();
    await _perform(() async {
      _routePlan = await repository.saveTargetAdjustmentDraft(
        plan,
        candidate: candidate,
        reason: reason,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _setState(Station1ViewState.targetAdjustment);
    });
  }

  Future<void> applyTargetAdjustment() async {
    final repository = _requireRouteRepository();
    final plan = _requireRoutePlan();
    await _perform(() async {
      _routePlan = await repository.applyTargetAdjustment(
        plan,
        boundary: blockBoundary,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _setState(Station1ViewState.stationTravel);
    });
  }

  Future<void> cancelTargetAdjustment() async {
    final repository = _requireRouteRepository();
    final plan = _requireRoutePlan();
    await _perform(() async {
      _routePlan = await repository.cancelTargetAdjustment(
        plan,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _setState(Station1ViewState.stationTravel);
    });
  }

  Future<void> beginTenConsecutivePlants() async {
    final snapshot = _snapshot;
    if (snapshot?.station == null) {
      throw StateError('Record the active station location step first.');
    }
    _currentPlantPosition = snapshot!.nextMissingPlantPosition;
    await _loadCurrentEvidence();
    _setState(
      _evidence == null
          ? Station1ViewState.plantEntry
          : Station1ViewState.plantCapture,
    );
  }

  Future<void> completeCurrentPlantCapture(
    Duration activeDuration,
    int newestLeavesInspectedCount,
  ) async {
    final bundle = _currentEvidence;
    if (bundle == null) throw StateError('Plant evidence is unavailable.');
    await _perform(() async {
      await _ensureAssessmentActive();
      await _requireEvidenceCoordinator().completePlantCapture(
        session: bundle.session,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        activeDuration: activeDuration,
        newestLeavesInspectedCount: newestLeavesInspectedCount,
        requiredViewTypes: isVtR2 || isR3R6
            ? {primaryEvidenceViewType}
            : _policyForBundle(bundle).captureCompletionViews(bundle),
      );
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> recordCurrentPlantInspection(int count) async {
    final bundle = _currentEvidence;
    if (bundle == null) throw StateError('Plant evidence is unavailable.');
    await _perform(() async {
      await _requireEvidenceCoordinator().recordPlantCaptureInspection(
        session: bundle.session,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        newestLeavesInspectedCount: count,
      );
      await _refreshPilotWorkloadMetrics();
    });
  }

  Future<void> saveCaptureNotAssessable({
    required String reason,
    required Duration activeDuration,
  }) async {
    final station = _snapshot?.station;
    final position = _currentPlantPosition;
    final evidence = _currentEvidence;
    if (station == null || position == null || evidence == null) {
      throw StateError('The active plant position is unavailable.');
    }
    if (isVtR2) {
      await saveReproductivePlant(
        ReproductivePlantSave(
          stationId: station.id,
          plantPosition: position,
          assessable: false,
          notAssessableReason: reason,
          classification: DatabaseCodes.reproductiveNotAssessable,
          tasselExamined: false,
          earBaseExamined: false,
          upperAxilExamined: false,
          lowerAxilExamined: false,
          freshFeedingPresent: false,
          frassPresent: false,
          earHuskPenetrationVisible: false,
          larvaPresent: false,
          larvalSize: 'none_seen',
          possibleNonFawEvidence: null,
          uncertainEvidence: null,
          naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNotAssessable,
          actorPersonId: _requireAssessment().evaluatorPersonId,
          evidenceCaptureSessionId: evidence.session.id,
          pilotActiveDurationMs: activeDuration.inMilliseconds,
        ),
        DatabaseCodes.evidenceReviewSufficient,
      );
      return;
    }
    if (isR3R6) {
      await saveExternalEar(
        EarExternalPlantSave(
          stationId: station.id,
          plantPosition: position,
          earPresent: null,
          externallyAssessable: false,
          designatedEarIdentity: null,
          exteriorEarTipExamined: false,
          baseShankSilkAxilsExamined: false,
          externalDamagePresent: null,
          activeInfestationPresent: null,
          silkDamagePresent: null,
          huskDamagePresent: null,
          entryHolePresent: null,
          frassPresent: null,
          larvaPresent: null,
          moldRotLikeSymptoms: null,
          externalClassification: DatabaseCodes.earExternalNotAssessable,
          naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNotAssessable,
          notAssessableReason: reason,
          actorPersonId: _requireAssessment().evaluatorPersonId,
          evidenceCaptureSessionId: evidence.session.id,
          pilotActiveDurationMs: activeDuration.inMilliseconds,
        ),
        DatabaseCodes.evidenceReviewSufficient,
      );
      return;
    }
    await savePlant(
      VegetativePlantSave(
        stationId: station.id,
        plantPosition: position,
        plantStatus: DatabaseCodes.plantNotAssessable,
        assessable: false,
        notAssessableReason: reason,
        newestLeavesInspectedCount: null,
        smallFreshWindowpanes: false,
        scraping: false,
        cuttingOrTearing: false,
        freshFrass: false,
        whorlFeedingSign: false,
        larvaVisible: false,
        larvalSize: 'none_seen',
        eggMassVisible: null,
        oldDamagePresent: false,
        possibleNonFawEvidence: null,
        uncertainEvidence: null,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        evidenceCaptureSessionId: evidence.session.id,
        requiredEvidenceViewTypes: const {},
        requireCameraPhaseAEvidence: true,
        pilotActiveDurationMs: activeDuration.inMilliseconds,
        manualFormUsed: false,
      ),
    );
  }

  Future<void> editPlant(int position) async {
    if (position < 1 || position > 10) {
      throw ArgumentError.value(position, 'position', 'Must be 1-10');
    }
    _currentPlantPosition = position;
    await _loadCurrentEvidence();
    _setState(Station1ViewState.plantEntry);
  }

  void returnToReview() {
    _currentPlantPosition = null;
    _setState(Station1ViewState.stationReview);
  }

  /// Moves between already-loaded workflow views without deleting or
  /// reclassifying any persisted station, plant, or evidence record.
  ///
  /// The station workflow is hosted by one Navigator route. This method keeps
  /// the phone's system Back gesture/button inside that route. The visible
  /// app-bar Back action deliberately exits to Scan.
  Future<void> navigateBackWithinWorkflow() async {
    if (_isSaving) return;
    switch (_state) {
      case Station1ViewState.routePreparation:
        if (_returnToRouteTravel) {
          _returnToRouteTravel = false;
          _setState(Station1ViewState.stationTravel);
        }
        return;
      case Station1ViewState.stationTravel:
        if (_stationNumber > 1) {
          _stationNumber--;
          _snapshot = _blockSnapshot?.station(_stationNumber);
          _setState(Station1ViewState.betweenStations);
        } else {
          _setState(Station1ViewState.routePreparation);
        }
        return;
      case Station1ViewState.targetAdjustment:
        await cancelTargetAdjustment();
        return;
      case Station1ViewState.stationLocation:
        if (_routePlan?.isReady == true) {
          _setState(Station1ViewState.stationTravel);
        }
        return;
      case Station1ViewState.plantEntry:
        _currentPlantPosition = null;
        _setState(Station1ViewState.stationReview);
        return;
      case Station1ViewState.openedEarEntry:
        _activeOpeningSelection = null;
        _currentPlantPosition = null;
        _setState(Station1ViewState.stationReview);
        return;
      case Station1ViewState.plantCapture:
        final position = _currentPlantPosition ?? 1;
        if (position <= 1) {
          _currentPlantPosition = null;
          _setState(Station1ViewState.plantSelection);
          return;
        }
        _currentPlantPosition = position - 1;
        await _loadCurrentEvidence();
        _setState(Station1ViewState.plantCapture);
        return;
      case Station1ViewState.stationReview:
        if (_returnToBlockReview) {
          _currentPlantPosition = null;
          _setState(Station1ViewState.blockReview);
          return;
        }
        _currentPlantPosition = 10;
        await _loadCurrentEvidence();
        _setState(
          _currentEvidence == null
              ? Station1ViewState.plantSelection
              : Station1ViewState.plantCapture,
        );
        return;
      case Station1ViewState.veV2StationSetup:
        _setState(Station1ViewState.stationContextEvidence);
        return;
      case Station1ViewState.veV2RowContextEvidence:
        _setState(Station1ViewState.veV2StationSetup);
        return;
      case Station1ViewState.veV2ContinuousCapture:
        if (_veV2CaptureTarget?.kind == VeV2CaptureKind.livingSeedling &&
            (_veV2CaptureTarget?.livingSeedlingPosition ?? 1) > 1) {
          _currentPlantPosition =
              _veV2CaptureTarget!.livingSeedlingPosition! - 1;
          final previousBundle = _plantEvidenceBundle(_currentPlantPosition!);
          final sourceUnitId =
              previousBundle?.session.sourcePlantingUnitObservationId;
          _veV2CaptureTarget = VeV2CaptureTarget.livingSeedling(
            livingSeedlingPosition: _currentPlantPosition!,
            sourcePlantingUnitId: sourceUnitId,
            sourcePlantingUnitSequence: _unitSequenceForId(sourceUnitId),
          );
          await _loadCurrentEvidence();
        }
        return;
      case Station1ViewState.veV2PlantingUnitEntry:
        if (_returnToVeV2Review) {
          _returnToVeV2Review = false;
          _currentPlantPosition = null;
          _setState(Station1ViewState.veV2StationReview);
          return;
        }
        final position = _currentPlantPosition ?? 1;
        if (position <= 1) {
          _setState(Station1ViewState.veV2StationSetup);
          return;
        }
        _currentPlantPosition = position - 1;
        await loadVeV2PlantingUnitEvidence();
        _setState(Station1ViewState.veV2PlantingUnitEntry);
        return;
      case Station1ViewState.veV2LivingSeedlingEntry:
        if (_returnToVeV2Review) {
          _returnToVeV2Review = false;
          _currentPlantPosition = null;
          _setState(Station1ViewState.veV2StationReview);
          return;
        }
        final position = _currentPlantPosition ?? 1;
        if (position <= 1) {
          _currentPlantPosition = 10;
          await loadVeV2PlantingUnitEvidence();
          _setState(Station1ViewState.veV2PlantingUnitEntry);
          return;
        }
        _currentPlantPosition = position - 1;
        await _loadCurrentEvidence();
        _setState(Station1ViewState.veV2LivingSeedlingEntry);
        return;
      case Station1ViewState.veV2StationReview:
        if (_returnToBlockReview) {
          _currentPlantPosition = null;
          _setState(Station1ViewState.blockReview);
          return;
        }
        await editVeV2LivingSeedling(10);
        return;
      case Station1ViewState.betweenStations:
        _currentPlantPosition = null;
        _setState(
          isVeV2
              ? Station1ViewState.veV2StationReview
              : Station1ViewState.stationReview,
        );
        return;
      case Station1ViewState.blockReview:
        _stationNumber = 5;
        _snapshot = _blockSnapshot?.station(_stationNumber);
        _currentPlantPosition = null;
        _returnToBlockReview = true;
        _setState(
          isVeV2
              ? Station1ViewState.veV2StationReview
              : Station1ViewState.stationReview,
        );
        return;
      default:
        return;
    }
  }

  Future<void> savePlant(VegetativePlantSave input) async {
    _validatePlantSave(input);
    await _perform(() async {
      await _ensureAssessmentActive();
      await _plantSaves.saveVegetativePlant(input);
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> saveReproductivePlant(
    ReproductivePlantSave input,
    String evidenceReviewStatus,
  ) async {
    _validateStagePlantIdentity(input.stationId, input.plantPosition);
    _validateExplicitEvidenceReview(evidenceReviewStatus);
    await _perform(() async {
      await _ensureAssessmentActive();
      await _stageSaves.saveReproductivePlant(input);
      await _recordStageEvidenceReview(evidenceReviewStatus);
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> saveExternalEar(
    EarExternalPlantSave input,
    String evidenceReviewStatus,
  ) async {
    _validateStagePlantIdentity(input.stationId, input.plantPosition);
    _validateExplicitEvidenceReview(evidenceReviewStatus);
    if (_lateSeasonSetup == null) {
      throw StateError('Complete late-season authorization first.');
    }
    await _perform(() async {
      await _ensureAssessmentActive();
      await _stageSaves.saveExternalEar(input);
      await _recordStageEvidenceReview(evidenceReviewStatus);
      await _loadSnapshot(askForResume: false);
    });
  }

  void _validateStagePlantIdentity(String stationId, int position) {
    final station = _snapshot?.station;
    if (station == null ||
        stationId != station.id ||
        position != _currentPlantPosition) {
      throw StateError(
        'Plant save does not match the active block, station, and position.',
      );
    }
  }

  void _validateExplicitEvidenceReview(String status) {
    if (status != DatabaseCodes.evidenceReviewSufficient) {
      throw StateError(
        'Resolve insufficient evidence before confirming observations.',
      );
    }
  }

  Future<void> _recordStageEvidenceReview(String status) async {
    final bundle = _currentEvidence;
    if (bundle == null) return;
    await _requireEvidenceCoordinator().repository.recordPlantEvidenceReview(
      bundle: await _requireEvidenceCoordinator().repository.loadBundle(
        bundle.session.id,
      ),
      status: status,
      actorPersonId: _requireAssessment().evaluatorPersonId,
    );
  }

  Future<void> saveReviewedPlant(
    VegetativePlantSave input,
    String evidenceReviewStatus,
  ) async {
    if (evidenceReviewStatus != DatabaseCodes.evidenceReviewSufficient) {
      throw StateError(
        'Resolve insufficient evidence before confirming observations.',
      );
    }
    _validatePlantSave(input);
    final sessionId = input.evidenceCaptureSessionId;
    await _perform(() async {
      await _ensureAssessmentActive();
      await _plantSaves.saveVegetativePlant(input);
      if (sessionId != null) {
        final bundle = await _requireEvidenceCoordinator().repository
            .loadBundle(sessionId);
        await _requireEvidenceCoordinator().repository
            .recordPlantEvidenceReview(
              bundle: bundle,
              status: evidenceReviewStatus,
              actorPersonId: _requireAssessment().evaluatorPersonId,
            );
      }
      await _loadSnapshot(askForResume: false);
    });
  }

  void _validatePlantSave(VegetativePlantSave input) {
    final station = _snapshot?.station;
    if (station == null ||
        input.stationId != station.id ||
        input.plantPosition != _currentPlantPosition) {
      throw StateError(
        'Plant save does not match the active block, station, and position.',
      );
    }
    final activeBundle = _currentEvidence;
    final activePolicy = activeBundle == null
        ? evidencePolicy
        : _policyForBundle(activeBundle);
    final expectedViews = _requiredViewsForInput(input, activePolicy);
    if (!setEquals(input.requiredEvidenceViewTypes, expectedViews)) {
      throw StateError(
        'Plant evidence requirements do not match ${evidencePolicy.requirementsVersion}.',
      );
    }
    if (_evidence != null) {
      final version = _currentEvidence?.session.requirementsVersion;
      if (version == null ||
          StationEvidencePolicy.fromRequirementsVersion(version) !=
              activePolicy) {
        throw StateError('The active evidence policy version does not match.');
      }
    }
  }

  Future<void> recordCurrentEvidenceReview(String status) async {
    final bundle = _currentEvidence;
    if (bundle == null) throw StateError('Plant evidence is unavailable.');
    await _perform(() async {
      await _requireEvidenceCoordinator().repository.recordPlantEvidenceReview(
        bundle: bundle,
        status: status,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> markPlantEvidenceInsufficient(int position) async {
    final matches = _stationEvidenceBundles.where(
      (bundle) =>
          bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
          bundle.session.plantPosition == position,
    );
    if (matches.length != 1) {
      throw StateError('Plant $position evidence is missing.');
    }
    await _perform(() async {
      await _requireEvidenceCoordinator().repository.recordPlantEvidenceReview(
        bundle: matches.single,
        status: DatabaseCodes.evidenceReviewInsufficient,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> fillRemainingTestPlants() async {
    _requireTestShortcuts();
    if (isVeV2) {
      await _fillRemainingVeV2TestData();
      return;
    }
    await _perform(() async {
      await _ensureAssessmentActive();
      var snapshot = await _workflow.loadStationSnapshot(
        _requirePrepared(),
        stationNumber: _stationNumber,
      );
      var station = snapshot.station;
      station ??= await _workflow.saveStationLocation(
        prepared: _requirePrepared(),
        stationNumber: _stationNumber,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        notLocatedReason: DatabaseCodes.stationNoCurrentFix,
        accessibilityNotes: '[TEST DATA] Synthetic unavailable GPS.',
      );
      final coordinator = _requireEvidenceCoordinator();
      var context = await coordinator.ensureStationContext(
        assessmentId: assessmentId,
        stationId: station.id,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      if (!context.isViewSatisfied(DatabaseCodes.evidenceViewStationContext)) {
        context = await coordinator.waive(
          session: context.session,
          viewType: DatabaseCodes.evidenceViewStationContext,
          reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
          actorPersonId: _requireAssessment().evaluatorPersonId,
          note: '[TEST DATA] Synthetic station context fallback.',
        );
      }
      if (context.session.completedAt == null) {
        await coordinator.completeStationContext(
          session: context.session,
          actorPersonId: _requireAssessment().evaluatorPersonId,
        );
      }

      snapshot = await _workflow.loadStationSnapshot(
        _requirePrepared(),
        stationNumber: _stationNumber,
      );
      final savedPositions = snapshot.plants
          .map((item) => item.plant.sequenceNumber)
          .toSet();
      for (var position = 1; position <= 10; position++) {
        if (savedPositions.contains(position)) continue;
        var bundle = await coordinator.ensurePlant(
          assessmentId: assessmentId,
          stationId: station.id,
          plantPosition: position,
          actorPersonId: _requireAssessment().evaluatorPersonId,
          requirementsVersion: evidencePolicy.requirementsVersion,
        );
        final kind = position % 5;
        final assessable = kind != 0;
        final current = kind == 2;
        final possibleNonFaw = kind == 3;
        final uncertain = kind == 4;
        final requiredViews = assessable
            ? const {DatabaseCodes.evidenceViewWhorlOverview}
            : const <String>{};
        final syntheticViews = {
          ...requiredViews,
          if (assessable && (current || possibleNonFaw || uncertain))
            DatabaseCodes.evidenceViewCloseUp,
        };
        for (final viewType in syntheticViews) {
          if (!bundle.isViewSatisfied(viewType)) {
            bundle = await coordinator.waive(
              session: bundle.session,
              viewType: viewType,
              reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
              actorPersonId: _requireAssessment().evaluatorPersonId,
              note: '[TEST DATA] Synthetic evidence fallback.',
            );
          }
        }
        await _plantSaves.saveVegetativePlant(
          VegetativePlantSave(
            stationId: station.id,
            plantPosition: position,
            plantStatus: !assessable
                ? DatabaseCodes.plantNotAssessable
                : current
                ? DatabaseCodes.plantCurrentPositive
                : possibleNonFaw
                ? DatabaseCodes.plantPossibleNonFaw
                : uncertain
                ? DatabaseCodes.plantUncertain
                : DatabaseCodes.plantNegative,
            assessable: assessable,
            notAssessableReason: assessable
                ? null
                : '[TEST DATA] Synthetic not-assessable position.',
            newestLeavesInspectedCount: assessable ? 3 : null,
            smallFreshWindowpanes: current,
            scraping: false,
            cuttingOrTearing: false,
            freshFrass: false,
            whorlFeedingSign: false,
            larvaVisible: false,
            larvalSize: 'none_seen',
            eggMassVisible: assessable ? false : null,
            oldDamagePresent: uncertain,
            possibleNonFawEvidence: assessable ? possibleNonFaw : null,
            uncertainEvidence: assessable ? uncertain : null,
            evaluatorNotes: '[TEST DATA] Synthetic Plant $position.',
            actorPersonId: _requireAssessment().evaluatorPersonId,
            evidenceCaptureSessionId: bundle.session.id,
            requiredEvidenceViewTypes: requiredViews,
            requireCameraPhaseAEvidence: true,
            manualFormUsed: true,
          ),
        );
        if (assessable) {
          bundle = await coordinator.repository.loadBundle(bundle.session.id);
          await coordinator.repository.recordPlantEvidenceReview(
            bundle: bundle,
            status: DatabaseCodes.evidenceReviewSufficient,
            actorPersonId: _requireAssessment().evaluatorPersonId,
          );
        }
      }
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> completeTestStation() async {
    _requireTestShortcuts();
    await _prepareTestBlockIfNeeded();
    await fillRemainingTestPlants();
    if (isVeV2) {
      await completeVeV2PilotStation(1);
      return;
    }
    final snapshot = _snapshot;
    if (snapshot == null) throw StateError('Test station is unavailable.');
    await _perform(() async {
      _validateReviewEvidence(snapshot);
      await _workflow.confirmStationReview(
        snapshot: snapshot,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _loadSnapshot(askForResume: false);
    });
  }

  /// Completes the current and every remaining station in the active test
  /// block without opening camera or documentation screens.
  ///
  /// Existing manually tested plants are preserved. Only missing test records
  /// are generated, using clearly synthetic observations and documented
  /// fallback evidence in the isolated test database.
  Future<void> completeAllRemainingTestStations() async {
    _requireTestShortcuts();
    await _prepareTestBlockIfNeeded();
    while (true) {
      if (_snapshot?.reviewIsCurrent != true) {
        await completeTestStation();
      }
      if (_stationNumber >= 5) return;
      await continueToNextStation();
    }
  }

  Future<void> _fillRemainingVeV2TestData() async {
    final service = _veV2;
    if (service == null) {
      throw StateError('VE-V2 test persistence is unavailable.');
    }
    await _prepareTestBlockIfNeeded();
    await _perform(() async {
      var snapshot = await _workflow.loadStationSnapshot(
        _requirePrepared(),
        stationNumber: _stationNumber,
      );
      var station = snapshot.station;
      station ??= await _workflow.saveStationLocation(
        prepared: _requirePrepared(),
        stationNumber: _stationNumber,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        notLocatedReason: DatabaseCodes.stationNoCurrentFix,
        accessibilityNotes: '[TEST DATA] Synthetic unavailable GPS.',
      );
      final coordinator = _requireEvidenceCoordinator();
      var context = await coordinator.ensureStationContext(
        assessmentId: assessmentId,
        stationId: station.id,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      if (!context.isViewSatisfied(DatabaseCodes.evidenceViewStationContext)) {
        context = await coordinator.waive(
          session: context.session,
          viewType: DatabaseCodes.evidenceViewStationContext,
          reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
          actorPersonId: _requireAssessment().evaluatorPersonId,
          note: '[TEST DATA] Synthetic station and row context fallback.',
        );
      }
      if (context.session.completedAt == null) {
        await coordinator.completeStationContext(
          session: context.session,
          actorPersonId: _requireAssessment().evaluatorPersonId,
        );
      }
      var inspection = await service.loadStationInspection(station.id);
      inspection ??= await service.saveStationSetup(
        VeV2StationSetupInput(
          stationId: station.id,
          growthStage: _requireAssessment().growthStage,
          rowDirectionCode: 'forward_from_station',
          plantingUnitSequenceAssessable: true,
          stationContextMeetsRowPurpose: true,
          emergenceContinuing: _requireAssessment().growthStage == 've'
              ? false
              : null,
          delayedEmergencePlausible: _requireAssessment().growthStage == 've'
              ? null
              : false,
          actorPersonId: _requireAssessment().evaluatorPersonId,
        ),
      );
      final units = await service.loadPlantingUnits(station.id);
      final byPosition = {for (final unit in units) unit.sequenceNumber: unit};
      for (var position = 1; position <= 10; position++) {
        byPosition[position] ??= await service.savePlantingUnit(
          VeV2PlantingUnitSave(
            stationId: station.id,
            sequenceNumber: position,
            assessable: true,
            primaryCondition: DatabaseCodes.veUnitHealthy,
            observedSeedlingCount: 1,
            recognizableRemnantPresent: true,
            visibleCutting: false,
            visibleSevering: false,
            visibleSeedlingInjury: false,
            injuryLocation: null,
            injuryFreshness: null,
            larvaVisible: null,
            larvalSize: null,
            freshFrass: null,
            rotPresent: null,
            tunnelingPresent: null,
            discolorationPresent: null,
            otherNonFawEvidence: null,
            evaluatorPrimaryInterpretation: DatabaseCodes.veInterpretationNone,
            evaluatorConfidence: 'high',
            alternativeCauseCodes: const {},
            inspectionDurationMs: 0,
            notes: '[TEST DATA] Synthetic healthy planting unit.',
            actorPersonId: _requireAssessment().evaluatorPersonId,
          ),
        );
      }
      snapshot = await _workflow.loadStationSnapshot(
        _requirePrepared(),
        stationNumber: _stationNumber,
      );
      final savedPlants = snapshot.plants
          .map((item) => item.plant.sequenceNumber)
          .toSet();
      for (var position = 1; position <= 10; position++) {
        if (savedPlants.contains(position)) continue;
        var bundle = await coordinator.ensurePlant(
          assessmentId: assessmentId,
          stationId: station.id,
          plantPosition: position,
          actorPersonId: _requireAssessment().evaluatorPersonId,
          requirementsVersion:
              DatabaseCodes.evidencePolicyVeV2ModelReadyCaptureV1,
          sourcePlantingUnitObservationId: byPosition[position]!.id,
        );
        if (!bundle.isViewSatisfied(DatabaseCodes.evidenceViewWhorlOverview)) {
          bundle = await coordinator.waive(
            session: bundle.session,
            viewType: DatabaseCodes.evidenceViewWhorlOverview,
            reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
            actorPersonId: _requireAssessment().evaluatorPersonId,
            note: '[TEST DATA] Synthetic living-plant evidence fallback.',
          );
        }
        if (bundle.session.completedAt == null) {
          await coordinator.completePlantCapture(
            session: bundle.session,
            actorPersonId: _requireAssessment().evaluatorPersonId,
            activeDuration: Duration.zero,
            newestLeavesInspectedCount: 3,
            requiredViewTypes: const {DatabaseCodes.evidenceViewWhorlOverview},
          );
        }
        await _plantSaves.saveVegetativePlant(
          VegetativePlantSave(
            stationId: station.id,
            plantPosition: position,
            plantStatus: DatabaseCodes.plantNegative,
            assessable: true,
            newestLeavesInspectedCount: 3,
            smallFreshWindowpanes: false,
            scraping: false,
            cuttingOrTearing: false,
            freshFrass: false,
            whorlFeedingSign: false,
            larvaVisible: false,
            larvalSize: 'none_seen',
            eggMassVisible: false,
            oldDamagePresent: false,
            possibleNonFawEvidence: false,
            uncertainEvidence: false,
            naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
            sourcePlantingUnitObservationId: byPosition[position]!.id,
            evaluatorNotes: '[TEST DATA] Synthetic living seedling.',
            actorPersonId: _requireAssessment().evaluatorPersonId,
            evidenceCaptureSessionId: bundle.session.id,
            requiredEvidenceViewTypes: const {
              DatabaseCodes.evidenceViewWhorlOverview,
            },
            requireCameraPhaseAEvidence: true,
            manualFormUsed: true,
            pilotActiveDurationMs: 0,
          ),
        );
      }
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> _prepareTestBlockIfNeeded() async {
    if (_preparedRuns.isNotEmpty) return;
    await prepareRequiredBlocks();
  }

  void _requireTestShortcuts() {
    if (!kDebugMode || !debugFeaturesEnabled || !testMode) {
      throw StateError('Test-data shortcuts are unavailable.');
    }
  }

  Future<void> confirmStationReview() async {
    final snapshot = _snapshot;
    if (snapshot == null) throw StateError('Station data is unavailable.');
    await _perform(() async {
      await _ensureAssessmentActive();
      _validateReviewEvidence(snapshot);
      await _workflow.confirmStationReview(
        snapshot: snapshot,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _loadSnapshot(askForResume: false);
      if (_returnToBlockReview) {
        _returnToBlockReview = false;
        _setState(Station1ViewState.blockReview);
      }
    });
  }

  Future<void> completeStationWithoutManualConfirmation() async {
    final snapshot = _snapshot;
    if (snapshot == null) throw StateError('Station data is unavailable.');
    await _perform(() async {
      await _ensureAssessmentActive();
      _validateDeferredManualConfirmationEvidence();
      await _workflow.confirmStationReview(
        snapshot: snapshot,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        manualConfirmationDeferred: true,
      );
      await _loadSnapshot(askForResume: false);
      if (_returnToBlockReview) {
        _returnToBlockReview = false;
        _setState(Station1ViewState.blockReview);
      }
    });
  }

  void _validateDeferredManualConfirmationEvidence() {
    final context = _stationEvidenceBundles.where(
      (bundle) =>
          bundle.session.scopeType == DatabaseCodes.evidenceScopeStationContext,
    );
    if (context.length != 1 ||
        context.single.session.completedAt == null ||
        !context.single.isViewSatisfied(
          DatabaseCodes.evidenceViewStationContext,
        )) {
      throw StateError(
        'Record the station context or its documented fallback first.',
      );
    }
    final requiredView = isVeV2
        ? DatabaseCodes.evidenceViewWholeSeedling
        : primaryEvidenceViewType;
    for (var position = 1; position <= 10; position++) {
      final matches = _stationEvidenceBundles.where(
        (bundle) =>
            bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
            bundle.session.plantPosition == position,
      );
      if (matches.length != 1 ||
          matches.single.session.completedAt == null ||
          !matches.single.isViewSatisfied(requiredView)) {
        throw StateError(
          '${isVeV2 ? 'Seedling' : 'Plant'} $position needs its required photo or documented fallback.',
        );
      }
    }
  }

  Future<void> openStationFromBlockReview(int stationNumber) async {
    if (stationNumber < 1 || stationNumber > 5) {
      throw ArgumentError.value(stationNumber, 'stationNumber', 'Must be 1-5');
    }
    _stationNumber = stationNumber;
    _returnToBlockReview = true;
    await _loadSnapshot(askForResume: false);
    _currentPlantPosition = null;
    _setState(
      isVeV2
          ? Station1ViewState.veV2StationReview
          : Station1ViewState.stationReview,
    );
  }

  Future<void> continueToNextStation() async {
    if (_snapshot?.reviewIsCurrent != true || _stationNumber >= 5) {
      throw StateError('The current station review is not complete.');
    }
    _stationNumber++;
    await _loadSnapshot(askForResume: false);
  }

  Future<void> completeCurrentBlock() async {
    if (_blockSnapshot?.allStationsReviewed != true) {
      throw StateError(
        'Review all five stations before completing this block.',
      );
    }
    await _perform(() async {
      await _ensureAssessmentActive();
      await _completion.completeBlock(_requirePrepared().run.id);
      _assessment = await _workflow.assessmentById(assessmentId);
      _preparedRuns = await _workflow.findPreparedRuns(assessmentId);
      if (_assessment!.status == DatabaseCodes.completed) {
        _setState(Station1ViewState.samplingComplete);
        return;
      }
      _activeRunIndex = _firstIncompleteRunIndex();
      _stationNumber = 1;
      _setState(Station1ViewState.betweenBlocks);
    });
  }

  Future<void> continueToNextBlock() async {
    await _loadSnapshot(askForResume: false);
  }

  Future<void> submitResumeCheck({
    required ResumeCondition condition,
    required bool safeToContinue,
    String? note,
  }) async {
    final assessment = _requireAssessment();
    final conditionCode = switch (condition) {
      ResumeCondition.unchanged => 'conditions_unchanged',
      ResumeCondition.rainOrMajorDelay => 'rain_or_major_delay',
      ResumeCondition.treatmentOrFieldOperation =>
        'treatment_or_field_operation',
    };
    await _perform(() async {
      if (condition == ResumeCondition.treatmentOrFieldOperation) {
        await _assessments.recordSafetyCheck(
          assessmentId: assessment.id,
          checkedByPersonId: assessment.evaluatorPersonId,
          resultStatus: DatabaseCodes.cannotConfirmSafety,
          notes: note?.trim().isEmpty == true ? null : note?.trim(),
        );
        await _workflow.recordResumeCheck(
          assessment: assessment,
          conditionCode: conditionCode,
          continuingSameAssessment: false,
          note: note,
        );
        _assessment = await _workflow.assessmentById(assessment.id);
        _setState(Station1ViewState.safetyBlocked);
        return;
      }
      final continuing =
          condition == ResumeCondition.unchanged || safeToContinue;
      await _workflow.recordResumeCheck(
        assessment: assessment,
        conditionCode: conditionCode,
        continuingSameAssessment: continuing,
        note: note,
      );
      if (!continuing) {
        _setState(Station1ViewState.pausedConditions);
        return;
      }
      _setState(_resumeTarget ?? Station1ViewState.stationLocation);
    });
  }

  Future<File> resolveEvidenceFile(String localUri) {
    return _requireEvidenceCoordinator().resolve(localUri);
  }

  Future<void> stageEvidence({
    required String viewType,
    required String sourcePath,
  }) async {
    await _perform(() async {
      await _ensureAssessmentActive();
      final activeBundle = _requireActiveEvidenceBundle();
      final existingMedia = activeBundle.mediaForView(viewType);
      if (existingMedia != null) {
        await _requireEvidenceCoordinator().remove(
          media: existingMedia,
          actorPersonId: _requireAssessment().evaluatorPersonId,
          retake: true,
        );
      }
      final updated = await _requireEvidenceCoordinator().stageCapture(
        session: activeBundle.session,
        viewType: viewType,
        sourcePath: sourcePath,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _replaceEvidenceBundle(updated);
      await _refreshPilotWorkloadMetrics();
    });
  }

  Future<void> acceptEvidence(EvidenceMediaRecord media) async {
    if (media.storageState == DatabaseCodes.evidenceStorageReady) return;
    await _perform(() async {
      final updated = await _requireEvidenceCoordinator().accept(
        media: media,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _replaceEvidenceBundle(updated);
      await _refreshPilotWorkloadMetrics();
    });
  }

  Future<void> removeEvidence(
    EvidenceMediaRecord media, {
    bool retake = false,
  }) async {
    await _perform(() async {
      final updated = await _requireEvidenceCoordinator().remove(
        media: media,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        retake: retake,
      );
      _replaceEvidenceBundle(updated);
      await _refreshPilotWorkloadMetrics();
    });
  }

  Future<void> waiveEvidence({
    required String viewType,
    required String reasonCode,
    String? note,
  }) async {
    await _perform(() async {
      final bundle = _requireActiveEvidenceBundle();
      final updated = await _requireEvidenceCoordinator().waive(
        session: bundle.session,
        viewType: viewType,
        reasonCode: reasonCode,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        note: note,
      );
      _replaceEvidenceBundle(updated);
      await _refreshPilotWorkloadMetrics();
    });
  }

  Future<void> continueAfterStationContext() async {
    final bundle = _stationContextEvidence;
    if (bundle == null) throw StateError('Station context is unavailable.');
    await _perform(() async {
      await _requireEvidenceCoordinator().completeStationContext(
        session: bundle.session,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> saveVeV2StationSetup(VeV2StationSetupInput input) async {
    final service = _veV2;
    if (!isVeV2 || service == null) {
      throw StateError('VE-V2 persistence is unavailable.');
    }
    await _perform(() async {
      _veV2Inspection = await service.saveStationSetup(input);
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> continueAfterVeV2RowContext() async {
    final bundle = _veV2RowContextEvidence;
    if (bundle == null ||
        !bundle.isViewSatisfied(DatabaseCodes.evidenceViewVeRowContext)) {
      throw StateError('Capture the row context or document manual fallback.');
    }
    await _loadSnapshot(askForResume: false);
  }

  Future<void> saveVeV2PlantingUnit(VeV2PlantingUnitSave input) async {
    final service = _veV2;
    if (!isVeV2 || service == null) {
      throw StateError('VE-V2 persistence is unavailable.');
    }
    await _perform(() async {
      await service.savePlantingUnit(input);
      await service.addEntryDuration(
        stationId: input.stationId,
        duration: Duration(milliseconds: input.inspectionDurationMs),
        plantingUnit: true,
      );
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> saveVeV2CaptureRouting(VeV2CaptureRoutingSave input) async {
    final service = _veV2;
    if (!isVeV2 || service == null) {
      throw StateError('VE-V2 persistence is unavailable.');
    }
    await _perform(() async {
      await service.saveCaptureRouting(input);
      await service.addEntryDuration(
        stationId: input.stationId,
        duration: Duration(milliseconds: input.inspectionDurationMs),
        plantingUnit: true,
      );
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> completeVeV2LivingCapture({
    required int newestLeavesInspectedCount,
    required Duration activeDuration,
  }) async {
    final bundle = _currentEvidence;
    final target = _veV2CaptureTarget;
    if (bundle == null || target?.kind != VeV2CaptureKind.livingSeedling) {
      throw StateError('The living-seedling capture is unavailable.');
    }
    // VE-V2 uses a stage-specific whole-seedling image as its canonical
    // capture. Whorl imagery belongs to the V3-V12 workflow.
    final requiredViews = <String>{DatabaseCodes.evidenceViewWholeSeedling};
    await _perform(() async {
      await _requireEvidenceCoordinator().completePlantCapture(
        session: bundle.session,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        activeDuration: activeDuration,
        newestLeavesInspectedCount: newestLeavesInspectedCount,
        requiredViewTypes: requiredViews,
      );
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> saveVeV2LivingSeedling(
    VegetativePlantSave input,
    bool repeatedPhysicalCheck,
  ) async {
    final service = _veV2;
    if (!isVeV2 || service == null) {
      throw StateError('This is not a VE-V2 assessment.');
    }
    await _perform(() async {
      final correcting = currentPlant != null;
      await _plantSaves.saveVegetativePlant(input);
      await service.addEntryDuration(
        stationId: input.stationId,
        duration: Duration(milliseconds: input.pilotActiveDurationMs),
        plantingUnit: false,
      );
      if (correcting) {
        await service.recordLivingPlantCorrection(
          stationId: input.stationId,
          repeatedPhysicalCheck: repeatedPhysicalCheck,
        );
      }
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> editVeV2PlantingUnit(int position) async {
    if (position < 1 || position > 10) throw ArgumentError('Must be 1-10');
    _currentPlantPosition = position;
    _returnToVeV2Review = true;
    await loadVeV2PlantingUnitEvidence();
    _setState(Station1ViewState.veV2PlantingUnitEntry);
  }

  Future<void> editVeV2LivingSeedling(int position) async {
    if (position < 1 || position > 10) throw ArgumentError('Must be 1-10');
    _currentPlantPosition = position;
    _returnToVeV2Review = true;
    final bundle = _plantEvidenceBundle(position);
    _veV2CaptureTarget = VeV2CaptureTarget.livingSeedling(
      livingSeedlingPosition: position,
      sourcePlantingUnitId:
          bundle?.session.sourcePlantingUnitObservationId ??
          currentPlant?.plant.sourcePlantingUnitObservationId,
      sourcePlantingUnitSequence: _unitSequenceForId(
        bundle?.session.sourcePlantingUnitObservationId ??
            currentPlant?.plant.sourcePlantingUnitObservationId,
      ),
    );
    await _loadCurrentEvidence();
    _setState(Station1ViewState.veV2LivingSeedlingEntry);
  }

  Future<void> completeVeV2PilotStation(int workloadRating) async {
    final station = _snapshot?.station;
    if (!isVeV2 || station == null || _veV2 == null) {
      throw StateError('VE-V2 station data is unavailable.');
    }
    await _perform(() async {
      _veV2Inspection = await _veV2.completePilotStation(
        stationId: station.id,
        workloadRating: workloadRating,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      final reviewedSnapshot = await _workflow.loadStationSnapshot(
        _requirePrepared(),
        stationNumber: _stationNumber,
      );
      await _workflow.confirmStationReview(
        snapshot: reviewedSnapshot,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _loadSnapshot(askForResume: false);
      if (_returnToBlockReview) {
        _returnToBlockReview = false;
        _setState(Station1ViewState.blockReview);
      }
    });
  }

  Future<PlantDiagnosisResult?> analyzePlantEvidence({
    required EvidenceMediaRecord media,
    required int plantPosition,
  }) async {
    final coordinator = _evidence;
    if (coordinator == null) return null;
    try {
      final file = await coordinator.resolve(media.localUri);
      final result = await _cvService.analyzeImage(file);
      _cvDiagnoses = {..._cvDiagnoses, plantPosition: result};
      notifyListeners();
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 1-Tap Shortcut: Records all remaining plants at the active station as healthy
  /// and automatically advances to the next station route guidance.
  Future<void> markEntireStationClean() async {
    final station = _snapshot?.station;
    if (station == null) return;
    await _perform(() async {
      final existingPositions = {
        for (final p in _snapshot!.plants) p.plant.sequenceNumber,
      };
      for (var pos = 1; pos <= 10; pos++) {
        if (!existingPositions.contains(pos)) {
          await _plantSaves.saveVegetativePlant(
            VegetativePlantSave(
              stationId: station.id,
              plantPosition: pos,
              plantStatus: DatabaseCodes.plantNegative,
              assessable: true,
              newestLeavesInspectedCount: 3,
              smallFreshWindowpanes: false,
              scraping: false,
              cuttingOrTearing: false,
              freshFrass: false,
              whorlFeedingSign: false,
              larvaVisible: false,
              larvalSize: 'none_seen',
              eggMassVisible: false,
              oldDamagePresent: false,
              possibleNonFawEvidence: false,
              uncertainEvidence: false,
              actorPersonId: _requireAssessment().evaluatorPersonId,
            ),
          );
        }
      }
      final reviewedSnapshot = await _workflow.loadStationSnapshot(
        _requirePrepared(),
        stationNumber: _stationNumber,
      );
      await _workflow.confirmStationReview(
        snapshot: reviewedSnapshot,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _loadSnapshot(askForResume: false);
      if (_stationNumber < 5) {
        _setState(Station1ViewState.betweenStations);
      } else {
        _setState(Station1ViewState.blockReview);
      }
    });
  }

  void retry() => initialize();

  Future<void> _loadActiveBlock({required bool askForResume}) async {
    _blockSnapshot = await _workflow.loadBlockSnapshot(_requirePrepared());
    _stationNumber = _blockSnapshot!.nextIncompleteStationNumber ?? 5;
    await _loadSnapshot(askForResume: askForResume);
  }

  Future<void> _loadSnapshot({required bool askForResume}) async {
    _blockSnapshot = await _workflow.loadBlockSnapshot(_requirePrepared());
    _snapshot = _blockSnapshot!.station(_stationNumber);
    if (_routes != null) {
      _routePlan = await _routes.loadOrCreateDraft(
        assessment: _requireAssessment(),
        prepared: _requirePrepared(),
      );
      await _upgradeLegacyRouteIfNeeded();
    }
    _stationContextEvidence = null;
    _currentEvidence = null;
    _stationEvidenceBundles = const [];
    _plantEvidenceReviews = const {};
    _pilotWorkloadMetrics = PilotWorkloadMetrics.empty;
    _capturedLeavesInspected = const {};
    _veV2Inspection = null;
    _veV2Units = const [];
    _veV2RowContextEvidence = null;
    _veV2CaptureTarget = null;
    _veV2AnalysisPresentations = const {};
    _lateSeasonSetup = isR3R6
        ? await _stageSaves.loadLateSeasonSetup(assessmentId)
        : null;
    _openingPlan = isR3R6 && _lateSeasonSetup != null
        ? await _stageSaves.loadOpeningPlan(
            blockRunId: _requirePrepared().run.id,
            stationNumber: _stationNumber,
          )
        : const [];
    final station = _snapshot!.station;
    if (station != null && _evidence != null) {
      _stationContextEvidence = await _evidence.ensureStationContext(
        assessmentId: assessmentId,
        stationId: station.id,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _stationEvidenceBundles = await _evidence.repository.loadStationBundles(
        station.id,
      );
      if (isVeV2) await _refreshVeV2AnalysisPresentations();
      _plantEvidenceReviews = await _evidence.repository
          .loadPlantEvidenceReviews(station.id);
      _pilotWorkloadMetrics = await _evidence.loadPilotWorkloadMetrics(
        station.id,
      );
      _capturedLeavesInspected =
          (await _evidence.repository.loadPilotWorkloadAuditSummary(
            station.id,
          )).inspectedLeavesByPlant;
    }
    if (station != null && isVeV2 && _veV2 != null) {
      _veV2Inspection = await _veV2.loadStationInspection(station.id);
      _veV2Inspection ??= await _veV2.saveStationSetup(
        VeV2StationSetupInput(
          stationId: station.id,
          growthStage: _requireAssessment().growthStage,
          rowDirectionCode: 'forward_from_station',
          plantingUnitSequenceAssessable: true,
          stationContextMeetsRowPurpose: true,
          emergenceContinuing: _requireAssessment().growthStage == 've'
              ? false
              : null,
          delayedEmergencePlausible: _requireAssessment().growthStage == 've'
              ? null
              : false,
          actorPersonId: _requireAssessment().evaluatorPersonId,
        ),
      );
      _veV2Units = await _veV2.loadPlantingUnits(station.id);
    }
    final target = _targetFor(_snapshot!);
    if (target == Station1ViewState.plantEntry ||
        target == Station1ViewState.plantCapture ||
        target == Station1ViewState.veV2LivingSeedlingEntry ||
        (target == Station1ViewState.veV2ContinuousCapture &&
            _veV2CaptureTarget?.kind == VeV2CaptureKind.livingSeedling)) {
      await _loadCurrentEvidence();
    }
    if (target == Station1ViewState.veV2PlantingUnitEntry ||
        (target == Station1ViewState.veV2ContinuousCapture &&
            _veV2CaptureTarget?.kind == VeV2CaptureKind.plantingUnit)) {
      await loadVeV2PlantingUnitEvidence();
    }
    if (askForResume &&
        target != Station1ViewState.samplingComplete &&
        target != Station1ViewState.blockPreparation) {
      _resumeTarget = target;
      _setState(Station1ViewState.resumeCheck);
      return;
    }
    _resumeTarget = null;
    _setState(target);
  }

  Future<void> _upgradeLegacyRouteIfNeeded() async {
    final repository = _routes;
    final plan = _routePlan;
    if (repository == null ||
        plan == null ||
        plan.algorithmVersion == scoutingRouteAlgorithmVersion) {
      return;
    }
    final preparation = plan.preparation;
    final hasAutomaticInputs = preparation.obstaclesReviewed;
    if (hasAutomaticInputs) {
      try {
        final generated = ScoutingRouteGenerator.generate(
          draft: plan.copyWith(
            algorithmVersion: scoutingRouteAlgorithmVersion,
            status: ScoutingRouteStatus.draft,
          ),
          boundary: blockBoundary,
          completedStations: _completedStationLocations(),
        );
        _routePlan = await repository.saveGeneratedPlan(
          generated,
          actorPersonId: _requireAssessment().evaluatorPersonId,
          recalculated: true,
        );
        return;
      } on RouteGenerationException {
        // Preserve the preparation and all completed station records. The
        // evaluator can review the inputs and explicitly generate again.
      }
    }
    _routePlan = await repository.savePreparationDraft(
      plan.copyWith(algorithmVersion: scoutingRouteAlgorithmVersion),
      preparation,
      actorPersonId: _requireAssessment().evaluatorPersonId,
    );
  }

  Station1ViewState _targetFor(StationSnapshot snapshot) {
    if (snapshot.reviewIsCurrent) {
      return _stationNumber < 5
          ? Station1ViewState.betweenStations
          : Station1ViewState.blockReview;
    }
    final route = _routePlan;
    if (_routes != null) {
      if (route?.pendingAdjustment != null) {
        return Station1ViewState.targetAdjustment;
      }
      if (route?.isReady != true) return Station1ViewState.routePreparation;
      if (snapshot.station == null) {
        return route!.arrivalConfirmedStation == _stationNumber
            ? Station1ViewState.stationLocation
            : Station1ViewState.stationTravel;
      }
    } else if (snapshot.station == null) {
      return Station1ViewState.stationLocation;
    }
    if (_evidence != null &&
        (_stationContextEvidence?.session.completedAt == null ||
            !(_stationContextEvidence?.isViewSatisfied(
                  DatabaseCodes.evidenceViewStationContext,
                ) ??
                false))) {
      return Station1ViewState.stationContextEvidence;
    }
    if (isVeV2) return _veV2TargetFor(snapshot);
    if (isR3R6 && _lateSeasonSetup == null) {
      return Station1ViewState.lateSeasonSetup;
    }
    if (_evidence == null) {
      if (snapshot.plants.isEmpty) return Station1ViewState.plantSelection;
      if (snapshot.plants.length < 10) {
        _currentPlantPosition = snapshot.nextMissingPlantPosition;
        return Station1ViewState.plantEntry;
      }
      _currentPlantPosition = null;
      return Station1ViewState.stationReview;
    }
    for (var position = 1; position <= 10; position++) {
      if (!_isCaptureSatisfied(snapshot, position)) {
        _currentPlantPosition = position;
        final started = _stationEvidenceBundles.any(
          (bundle) =>
              bundle.session.scopeType == DatabaseCodes.evidenceScopePlant,
        );
        return !started && snapshot.plants.isEmpty && _stationNumber == 1
            ? Station1ViewState.plantSelection
            : Station1ViewState.plantCapture;
      }
    }
    _currentPlantPosition = null;
    return Station1ViewState.stationReview;
  }

  Station1ViewState _veV2TargetFor(StationSnapshot snapshot) {
    if (_veV2Inspection?.completedAt != null) {
      return Station1ViewState.veV2StationReview;
    }
    for (var position = 1; position <= 10; position++) {
      if (!_isCaptureSatisfied(snapshot, position)) {
        _currentPlantPosition = position;
        final unit = _unitAt(position);
        final bundle = _plantEvidenceBundle(position);
        _veV2CaptureTarget = VeV2CaptureTarget.livingSeedling(
          livingSeedlingPosition: position,
          sourcePlantingUnitId:
              unit?.id ?? bundle?.session.sourcePlantingUnitObservationId,
          sourcePlantingUnitSequence:
              unit?.sequenceNumber ??
              _unitSequenceForId(
                bundle?.session.sourcePlantingUnitObservationId,
              ),
        );
        return Station1ViewState.veV2ContinuousCapture;
      }
    }
    _currentPlantPosition = null;
    _veV2CaptureTarget = null;
    return Station1ViewState.veV2StationReview;
  }

  bool _isCaptureSatisfied(StationSnapshot snapshot, int position) {
    StationPlantRecord? saved;
    for (final item in snapshot.plants) {
      if (item.plant.sequenceNumber == position) saved = item;
    }
    if (saved != null && !saved.plant.assessable) return true;
    if (isVeV2) {
      final unit = _unitAt(position);
      if (unit != null &&
          (unit.occupancyStatus == DatabaseCodes.veOccupancyEmpty ||
              unit.occupancyStatus == DatabaseCodes.veOccupancyRemnant ||
              unit.occupancyStatus == DatabaseCodes.veOccupancyNotAssessable)) {
        return true;
      }
    }
    final matches = _stationEvidenceBundles.where(
      (bundle) =>
          bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
          bundle.session.plantPosition == position,
    );
    if (matches.isEmpty) return false;
    final bundle = matches.first;
    if (bundle.session.completedAt != null) return true;
    final requiredView = isVeV2
        ? DatabaseCodes.evidenceViewWholeSeedling
        : primaryEvidenceViewType;
    return bundle.isViewSatisfied(requiredView);
  }

  Future<void> _loadCurrentEvidence() async {
    final position = _currentPlantPosition;
    final station = _snapshot?.station;
    if (_evidence == null || position == null || station == null) {
      _currentEvidence = null;
      return;
    }
    _currentEvidence = await _evidence.ensurePlant(
      assessmentId: assessmentId,
      stationId: station.id,
      plantPosition: position,
      actorPersonId: _requireAssessment().evaluatorPersonId,
      requirementsVersion: isVeV2
          ? DatabaseCodes.evidencePolicyVeV2ModelReadyCaptureV1
          : evidencePolicy.requirementsVersion,
      sourcePlantingUnitObservationId: isVeV2
          ? _veV2CaptureTarget?.sourcePlantingUnitId
          : null,
    );
  }

  Set<int> get _veV2CapturedLivingPositions {
    final positions = <int>{
      for (final plant in _snapshot?.plants ?? const <StationPlantRecord>[])
        plant.plant.sequenceNumber,
    };
    for (final bundle in _stationEvidenceBundles) {
      final session = bundle.session;
      if (session.scopeType == DatabaseCodes.evidenceScopePlant &&
          session.requirementsVersion ==
              DatabaseCodes.evidencePolicyVeV2ModelReadyCaptureV1 &&
          session.completedAt != null &&
          session.plantPosition != null) {
        positions.add(session.plantPosition!);
      }
    }
    return positions;
  }

  PlantingUnitObservationRecord? _unitAt(int sequence) {
    for (final unit in _veV2Units) {
      if (unit.sequenceNumber == sequence) return unit;
    }
    return null;
  }

  int? _unitSequenceForId(String? id) {
    if (id == null) return null;
    for (final unit in _veV2Units) {
      if (unit.id == id) return unit.sequenceNumber;
    }
    return null;
  }

  EvidenceCaptureBundle? _plantEvidenceBundle(int position) {
    for (final bundle in _stationEvidenceBundles) {
      if (bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
          bundle.session.plantPosition == position) {
        return bundle;
      }
    }
    return null;
  }

  Future<void> _refreshVeV2AnalysisPresentations() async {
    final presentations = <String, VeV2AnalysisPresentation>{};
    for (final bundle in _stationEvidenceBundles) {
      if (bundle.session.scopeType == DatabaseCodes.evidenceScopePlant ||
          bundle.session.scopeType == DatabaseCodes.evidenceScopePlantingUnit) {
        presentations[bundle.session.id] = await _veV2Analysis.presentationFor(
          bundle,
        );
      }
    }
    _veV2AnalysisPresentations = presentations;
  }

  Future<void> loadVeV2PlantingUnitEvidence() async {
    final position = _currentPlantPosition;
    final station = _snapshot?.station;
    if (_evidence == null || position == null || station == null) {
      _currentEvidence = null;
      return;
    }
    _currentEvidence = await _evidence.ensurePlantingUnit(
      assessmentId: assessmentId,
      stationId: station.id,
      sequenceNumber: position,
      actorPersonId: _requireAssessment().evaluatorPersonId,
    );
    notifyListeners();
  }

  Set<String> _requiredViewsForInput(
    VegetativePlantSave input,
    StationEvidencePolicy policy,
  ) {
    if (!input.assessable) return const {};
    if (policy == StationEvidencePolicy.station1TwoView) {
      return const {
        DatabaseCodes.evidenceViewWhorlOverview,
        DatabaseCodes.evidenceViewCloseUp,
      };
    }
    if (policy == StationEvidencePolicy.cameraFirstOverviewConditional) {
      return const {DatabaseCodes.evidenceViewWhorlOverview};
    }
    final supporting =
        input.smallFreshWindowpanes ||
        input.scraping ||
        input.cuttingOrTearing ||
        input.freshFrass ||
        input.whorlFeedingSign ||
        input.larvaVisible ||
        input.eggMassVisible == true ||
        input.possibleNonFawEvidence == true ||
        input.uncertainEvidence == true;
    return supporting
        ? const {DatabaseCodes.evidenceViewWhorlOverview}
        : const {};
  }

  void _validateReviewEvidence(StationSnapshot snapshot) {
    if (_evidence == null) return;
    final context = _stationEvidenceBundles.where(
      (bundle) =>
          bundle.session.scopeType == DatabaseCodes.evidenceScopeStationContext,
    );
    if (context.length != 1 ||
        !context.single.isViewSatisfied(
          DatabaseCodes.evidenceViewStationContext,
        )) {
      throw StateError(
        'Station context needs an accepted image or documented manual fallback.',
      );
    }
    for (final item in snapshot.plants) {
      final matches = _stationEvidenceBundles.where(
        (bundle) =>
            bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
            bundle.session.plantPosition == item.plant.sequenceNumber,
      );
      if (matches.length != 1) {
        throw StateError(
          'Plant ${item.plant.sequenceNumber} has no evidence capture record.',
        );
      }
      final bundle = matches.single;
      final sessionPolicy = _policyForBundle(bundle);
      if (bundle.session.plantObservationId != item.plant.id ||
          (sessionPolicy != evidencePolicy &&
              sessionPolicy != StationEvidencePolicy.station1TwoView &&
              sessionPolicy != StationEvidencePolicy.humanWorkloadSafe)) {
        throw StateError(
          'Plant ${item.plant.sequenceNumber} evidence association or policy version is invalid.',
        );
      }
      if (isVtR2 || isR3R6) {
        if (item.plant.assessable &&
            !bundle.isViewSatisfied(primaryEvidenceViewType)) {
          throw StateError(
            'Plant ${item.plant.sequenceNumber} needs its stage-specific overview or documented fallback.',
          );
        }
        final review = _plantEvidenceReviews[item.plant.sequenceNumber];
        if (item.plant.assessable &&
            (review?.isCurrent != true ||
                review?.status != DatabaseCodes.evidenceReviewSufficient)) {
          throw StateError(
            'Plant ${item.plant.sequenceNumber} requires a current sufficient evidence review.',
          );
        }
        continue;
      }
      for (final view in sessionPolicy.requiredViewsForObservation(
        plant: item.plant,
        vegetative: item.vegetative,
      )) {
        if (!bundle.isViewSatisfied(view)) {
          throw StateError(
            'Plant ${item.plant.sequenceNumber} needs supporting evidence or documented manual fallback.',
          );
        }
      }
    }
    if (isR3R6 && !openedEarSubsampleComplete) {
      throw StateError(
        'Complete or document failure for every active opened-ear selection.',
      );
    }
  }

  int _firstIncompleteRunIndex() {
    final index = _preparedRuns.indexWhere(
      (item) => item.run.status != DatabaseCodes.completed,
    );
    return index < 0 ? _preparedRuns.length - 1 : index;
  }

  Map<int, LatLng?> _completedStationLocations() {
    final result = <int, LatLng?>{};
    for (final station
        in _blockSnapshot?.stations ?? const <StationSnapshot>[]) {
      if (!station.reviewIsCurrent) continue;
      final record = station.station;
      result[station.stationNumber] =
          record?.latitude == null || record?.longitude == null
          ? null
          : LatLng(record!.latitude!, record.longitude!);
    }
    return result;
  }

  Future<void> _clearArrivalConfirmation() async {
    final repository = _routes;
    final plan = _routePlan;
    if (repository == null || plan?.arrivalConfirmedStation == null) return;
    _routePlan = await repository.clearStationArrival(
      plan!,
      actorPersonId: _requireAssessment().evaluatorPersonId,
    );
  }

  ScoutingRouteRepository _requireRouteRepository() {
    final value = _routes;
    if (value == null) throw StateError('Route guidance is unavailable.');
    return value;
  }

  ScoutingRoutePlan _requireRoutePlan() {
    final value = _routePlan;
    if (value == null) throw StateError('Route preparation is unavailable.');
    return value;
  }

  StationEvidencePolicy _policyForBundle(EvidenceCaptureBundle bundle) {
    return StationEvidencePolicy.fromRequirementsVersion(
      bundle.session.requirementsVersion,
    );
  }

  EvidenceCaptureCoordinator _requireEvidenceCoordinator() {
    final value = _evidence;
    if (value == null) throw StateError('Camera evidence is unavailable.');
    return value;
  }

  EvidenceCaptureBundle _requireActiveEvidenceBundle() {
    final value = switch (_state) {
      Station1ViewState.stationContextEvidence => _stationContextEvidence,
      Station1ViewState.veV2RowContextEvidence => _veV2RowContextEvidence,
      _ => _currentEvidence,
    };
    if (value == null) throw StateError('Evidence capture is unavailable.');
    return value;
  }

  void _replaceEvidenceBundle(EvidenceCaptureBundle value) {
    if (value.session.scopeKey == 've_v2_row_context') {
      _veV2RowContextEvidence = value;
    } else if (value.session.scopeType ==
        DatabaseCodes.evidenceScopeStationContext) {
      _stationContextEvidence = value;
    } else {
      _currentEvidence = value;
    }
    final replaced = <EvidenceCaptureBundle>[];
    var found = false;
    for (final bundle in _stationEvidenceBundles) {
      if (bundle.session.id == value.session.id) {
        replaced.add(value);
        found = true;
      } else {
        replaced.add(bundle);
      }
    }
    if (!found) replaced.add(value);
    _stationEvidenceBundles = List.unmodifiable(replaced);
    notifyListeners();
  }

  Future<void> _refreshPilotWorkloadMetrics() async {
    final stationId = _snapshot?.station?.id;
    if (_evidence == null || stationId == null) return;
    _pilotWorkloadMetrics = await _evidence.loadPilotWorkloadMetrics(stationId);
    notifyListeners();
  }

  Future<void> _perform(Future<void> Function() operation) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      await operation();
    } catch (error) {
      _error = error;
      notifyListeners();
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  AssessmentRecord _requireAssessment() {
    final value = _assessment;
    if (value == null) throw StateError('Assessment is unavailable.');
    return value;
  }

  PreparedScoutingRun _requirePrepared() {
    final value = prepared;
    if (value == null) throw StateError('No assessment block is prepared.');
    return value;
  }

  Future<void> _ensureAssessmentActive() async {
    final current = await _workflow.assessmentById(assessmentId);
    _assessment = current;
    if (current.status == DatabaseCodes.safetyBlocked) {
      _setState(Station1ViewState.safetyBlocked);
      throw StateError('Field entry needs another safety check.');
    }
    if (current.status != DatabaseCodes.inProgress) {
      _setState(Station1ViewState.setupRequired);
      throw StateError('This assessment is not ready for field observations.');
    }
    final currentBoundary = await _workflow.boundaryById(
      current.boundaryVersionId,
    );
    _boundary = currentBoundary;
    if (currentBoundary.confirmationStatus != 'user_confirmed') {
      _setState(Station1ViewState.boundaryRequired);
      throw StateError(
        'The approximate field outline must be confirmed before continuing.',
      );
    }
  }

  bool _isPilotStage(String value) =>
      DatabaseCodes.isGrowthStageImplemented(value);

  void _setState(Station1ViewState value) {
    _state = value;
    _error = null;
    notifyListeners();
  }

  void _fail(Object error) {
    _error = error;
    _state = Station1ViewState.error;
    notifyListeners();
  }
}
