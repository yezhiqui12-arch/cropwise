import '../services/photo_screening_checkpoint_store.dart';
import '../services/scouting_sampling_protocol.dart';
import '../models/automatic_screening.dart';
import '../models/guided_plant_details.dart';
import '../data/repositories/da_monitoring_repository.dart';
import '../models/da_monitoring.dart';
import '../data/repositories/plant_action_repository.dart';
import '../models/da_batch_import.dart';
import '../data/services/automatic_screening_save_service.dart';
import '../services/computer_vision/detection_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart' show LatLng;

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/local/local_id.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/evidence_capture_repository.dart';
import '../data/repositories/field_repository.dart';
import '../data/repositories/local_mutation_recorder.dart';
import '../data/repositories/scouting_workflow_repository.dart';
import '../data/repositories/scouting_route_repository.dart';
import '../data/services/atomic_plant_save_service.dart';
import '../data/services/atomic_ve_v2_save_service.dart';
import '../data/services/assessment_validation_types.dart';
import '../data/services/scouting_completion_service.dart';
import '../data/services/stage_plant_save_service.dart';
import '../services/computer_vision/faw_computer_vision_service.dart';
import '../services/computer_vision/two_stage_faw_cv_service.dart';
import '../services/evidence_capture_coordinator.dart';
import '../services/phone_location_service.dart';
import '../services/assessment_area_policy.dart';
import '../services/scouting_route_generator.dart';
import '../services/station_evidence_policy.dart';
import '../services/ve_v2_analysis_service.dart';
import 'scouting_workflow_state.dart';

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

/// Coordinates plant capture and approximate sampling-point guidance.
class ScoutingWorkflowProvider extends ChangeNotifier {
  ScoutingWorkflowProvider({
    required this.assessmentId,
    required ScoutingWorkflowRepository workflowRepository,
    required AssessmentRepository assessmentRepository,
    required AtomicPlantSaveService plantSaveService,
    required ScoutingCompletionService completionService,
    AtomicVeV2SaveService? veV2SaveService,
    ScoutingRouteRepository? routeRepository,
    EvidenceCaptureCoordinator? evidenceCoordinator,
    VeV2AnalysisService veV2AnalysisService =
        const UnavailableVeV2AnalysisService(),
    FawComputerVisionService? computerVisionService,
    this.testMode = false,
    this.debugFeaturesEnabled = kDebugMode,
    this.realisticTestFixture = false,
  }) : _workflow = workflowRepository,
       _assessments = assessmentRepository,
       _plantSaves = plantSaveService,
       _stageSaves = StagePlantSaveService(plantSaveService.database),
       _completion = completionService,
       _veV2 = veV2SaveService,
       _routes = routeRepository,
       _evidence = evidenceCoordinator,
       _veV2Analysis = veV2AnalysisService,
       _ownsCvService = computerVisionService == null,
       _cvService = computerVisionService ?? TwoStageFawCvService();

  final String assessmentId;
  final ScoutingWorkflowRepository _workflow;
  final AssessmentRepository _assessments;
  final AtomicPlantSaveService _plantSaves;
  final StagePlantSaveService _stageSaves;
  final ScoutingCompletionService _completion;
  final AtomicVeV2SaveService? _veV2;
  final ScoutingRouteRepository? _routes;
  final EvidenceCaptureCoordinator? _evidence;
  final VeV2AnalysisService _veV2Analysis;
  final FawComputerVisionService _cvService;
  final bool _ownsCvService;
  final bool testMode;
  final bool debugFeaturesEnabled;
  final bool realisticTestFixture;

  Map<int, PlantDiagnosisResult> _cvDiagnoses = const {};
  final Set<int> _pendingModelPositions = {};
  Map<int, PlantDiagnosisResult> get cvDiagnoses => _cvDiagnoses;
  FawComputerVisionService get cvService => _cvService;

  Station1ViewState _state = Station1ViewState.loading;
  Station1ViewState? _resumeTarget;
  AssessmentRecord? _assessment;
  BoundaryRecord? _boundary;
  List<PreparedScoutingRun> _preparedRuns = const [];
  List<FieldBlockRecord> _blockDefinitions = const [];
  int _partitionCandidateIndex = 0;
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
  bool _returnToStationReview = false;
  bool _returnToRouteTravel = false;
  ScoutingRoutePlan? _routePlan;
  EvidenceMediaRecord? _syntheticPhotoTemplate;

  bool _disposed = false;
  Future<PlantDiagnosisResult?>? _screeningInFlight;
  String? _screeningSubject;
  @override
  void dispose() {
    _disposed = true;
    final service = _cvService;
    if (_ownsCvService && service is DisposableFawComputerVisionService) {
      unawaited(
        (service as DisposableFawComputerVisionService).close().catchError((
          Object error,
          StackTrace stack,
        ) {
          debugPrint('Model cleanup failed: $error');
        }),
      );
    }
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Station1ViewState get state => _state;
  AssessmentRecord? get assessment => _assessment;
  BoundaryRecord? get boundary => _boundary;
  PreparedScoutingRun? get prepared =>
      _preparedRuns.isEmpty ? null : _preparedRuns[_activeRunIndex];
  List<PreparedScoutingRun> get preparedRuns => _preparedRuns;
  List<FieldBlockRecord> get blockDefinitions => _blockDefinitions;
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
  String get primaryEvidenceViewType => isVeV2
      ? DatabaseCodes.evidenceViewWholeSeedling
      : isVtR2 || isR3R6
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
      StationEvidencePolicy.forStation(isDaGuidedScouting ? 1 : _stationNumber);
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
  Set<int> get completedStationNumbers => {
    ..._completedStationLocations().keys,
    for (var station = 1; station < _stationNumber; station++) station,
  };
  bool get isDaGuidedScouting =>
      ScoutingSamplingProtocol.isDa(_assessment?.protocolVersion ?? '');
  int get locationsPerBlock => ScoutingSamplingProtocol.locationCount(
    _assessment?.protocolVersion ?? '',
  );
  int get plantsPerLocation => ScoutingSamplingProtocol.plantsPerLocation(
    _assessment?.protocolVersion ?? '',
  );
  Set<int> _daEvidenceNumbers = {};
  Set<int> get daEvidencePlantNumbers {
    final result = {..._daEvidenceNumbers};
    final bundle = bundleForPlant(1);
    if (bundle != null) {
      result.remove(_stationNumber);
      if (bundle.media.any(
        (m) =>
            m.deletedAt == null &&
            m.storageState == DatabaseCodes.evidenceStorageReady,
      ))
        result.add(_stationNumber);
    }
    return result;
  }

  Future<void> _refreshDaEvidenceNumbers() async {
    if (!isDaGuidedScouting) {
      _daEvidenceNumbers = {};
      return;
    }
    final stations = {
      for (final s in _blockSnapshot?.stations ?? const <StationSnapshot>[])
        if (s.station != null) s.station!.id: s.stationNumber,
    };
    if (stations.isEmpty) {
      _daEvidenceNumbers = {};
      return;
    }
    final db = _plantSaves.database;
    final photos =
        await (db.select(db.evidenceMedia)..where(
              (m) =>
                  m.stationId.isIn(stations.keys) &
                  m.storageState.equals(DatabaseCodes.evidenceStorageReady) &
                  m.deletedAt.isNull(),
            ))
            .get();
    _daEvidenceNumbers = {for (final p in photos) stations[p.stationId]!};
  }

  int get completedDaPlantCount =>
      _blockSnapshot?.stations.where((s) => s.reviewIsCurrent).length ?? 0;

  Map<int, LatLng> get daRecordedPlantLocations {
    final result = <int, LatLng>{};
    for (final snapshot
        in _blockSnapshot?.stations ?? const <StationSnapshot>[]) {
      if (!snapshot.reviewIsCurrent) continue;
      final plant = snapshot.plants.firstOrNull?.plant;
      final hasPlantFix = plant?.latitude != null && plant?.longitude != null;
      final latitude = hasPlantFix
          ? plant!.latitude
          : snapshot.station?.latitude;
      final longitude = hasPlantFix
          ? plant!.longitude
          : snapshot.station?.longitude;
      if (latitude != null && longitude != null) {
        result[snapshot.stationNumber] = LatLng(latitude, longitude);
      }
    }
    return result;
  }

  Future<void> analyzeDaActivePlantForPreview() async {
    if (!isDaGuidedScouting) throw StateError('Not a DA guided assessment.');
    await _perform(() async {
      await analyzePlantBundle(1);
    });
  }

  /// Bulk gallery intake never borrows the phone's current GPS or replaces
  /// another plant's evidence. Stable media UUIDs make interrupted retries safe.
  Future<List<int>> availableDaBatchPlants() async {
    if (!isDaGuidedScouting) throw StateError('Not a DA guided assessment.');
    final available = <int>[];
    for (var n = 1; n <= locationsPerBlock; n++) {
      final details = await loadDaPlantDetails(n);
      if (!details.snapshot.reviewIsCurrent &&
          details.plant == null &&
          !(details.evidence?.media.any((m) => m.deletedAt == null) ?? false))
        available.add(n);
    }
    return available;
  }

  Future<void> saveDaBatchPhoto({
    required String blockId,
    required int number,
    required String viewType,
    required DaBatchPhoto photo,
  }) async {
    if (!isDaGuidedScouting ||
        _requirePrepared().run.id != blockId ||
        number < 1 ||
        number > locationsPerBlock)
      throw StateError('The sampling block changed.');
    await _perform(() async {
      await _ensureAssessmentActive();
      final coordinator = _requireEvidenceCoordinator();
      final actor = _requireAssessment().evaluatorPersonId;
      final snapshot = await _workflow.loadStationSnapshot(
        _requirePrepared(),
        stationNumber: number,
      );
      final station =
          snapshot.station ??
          await _workflow.saveStationLocation(
            prepared: _requirePrepared(),
            stationNumber: number,
            actorPersonId: actor,
            notLocatedReason: DatabaseCodes.stationNoCurrentFix,
          );
      final bundle = await coordinator.ensurePlant(
        assessmentId: assessmentId,
        stationId: station.id,
        plantPosition: 1,
        actorPersonId: actor,
        requirementsVersion: evidencePolicy.requirementsVersion,
      );
      final existing = bundle.mediaForView(viewType);
      if (existing != null && existing.id != photo.id) {
        throw StateError('Plant $number already has a photo in this view.');
      }
      final rows = await (_plantSaves.database.select(
        _plantSaves.database.evidenceMedia,
      )..where((m) => m.id.equals(photo.id))).get();
      if (rows.isNotEmpty &&
          (rows.single.deletedAt != null ||
              rows.single.captureSessionId != bundle.session.id ||
              rows.single.viewType != viewType)) {
        throw StateError('This imported photo changed. Start a new import.');
      }
      if (existing == null &&
          (snapshot.reviewIsCurrent || snapshot.plants.isNotEmpty) &&
          rows.isEmpty) {
        throw StateError('Plant $number is already sampled.');
      }
      var media = existing;
      if (media == null) {
        final staged = await coordinator.stageCapture(
          session: bundle.session,
          viewType: viewType,
          sourcePath: photo.path,
          actorPersonId: actor,
          deleteSourceAfterCopy: false,
          stableMediaId: photo.id,
        );
        media = staged.mediaForView(viewType)!;
      }
      await (_plantSaves.database.update(
        _plantSaves.database.evidenceMedia,
      )..where((m) => m.id.equals(media!.id))).write(
        EvidenceMediaCompanion(
          captureSource: const Value('gallery'),
          capturedAt: const Value(null),
          latitude: const Value(null),
          longitude: const Value(null),
          gpsAccuracyM: const Value(null),
          locationCapturedAt: const Value(null),
          locationSource: const Value('unavailable'),
        ),
      );
      if (media.storageState == DatabaseCodes.evidenceStorageStaged) {
        await coordinator.accept(media: media, actorPersonId: actor);
      } else if (media.storageState != DatabaseCodes.evidenceStorageReady) {
        throw StateError('The imported photo is unavailable.');
      }
      final ready = await coordinator.repository.loadBundle(bundle.session.id);
      if (!await (await coordinator.resolve(
        ready.mediaForView(viewType)!.localUri,
      )).exists()) {
        throw StateError('An imported photo is missing from this phone.');
      }
    });
  }

  Future<bool> daBatchPhotoIsSaved(
    String blockId,
    int number,
    String viewType,
    String photoId,
  ) async {
    if (_requirePrepared().run.id != blockId) return false;
    final details = await loadDaPlantDetails(number);
    final matches = details.photos.where(
      (p) => p.id == photoId && p.viewType == viewType,
    );
    return matches.length == 1 &&
        await (await resolveEvidenceFile(matches.single.localUri)).exists();
  }

  Future<void> screenDaBatchPlant(
    String blockId,
    int number,
    Set<String> photoIds,
  ) async {
    if (!isDaGuidedScouting || number < 1 || number > locationsPerBlock) {
      throw StateError('Invalid DA plant.');
    }
    if (_requirePrepared().run.id != blockId)
      throw StateError('The sampling block changed.');
    final previousNumber = _stationNumber;
    try {
      _stationNumber = number;
      await _loadSnapshot(askForResume: false);
      final bundle = bundleForPlant(1);
      final active =
          bundle?.media
              .where(
                (m) =>
                    m.deletedAt == null &&
                    m.storageState == DatabaseCodes.evidenceStorageReady,
              )
              .toList() ??
          [];
      if (bundle == null ||
          active.length != photoIds.length ||
          !active.every((m) => photoIds.contains(m.id))) {
        throw StateError('Plant $number photos changed. Check the sample.');
      }
      await _requireEvidenceCoordinator().completePlantCapture(
        session: bundle.session,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        activeDuration: Duration.zero,
        newestLeavesInspectedCount: null,
        requiredViewTypes: {primaryEvidenceViewType},
      );
      await _loadSnapshot(askForResume: false);
      final result = await analyzePlantBundle(1);
      if (result == null || result.classificationLabel == null) {
        throw StateError('Plant $number could not be screened. Try again.');
      }
      await completeStationWithoutManualConfirmation();
      if (!await daBatchPlantIsScreened(blockId, number, photoIds)) {
        throw StateError(
          'Plant $number screening was not saved. Retry this plant.',
        );
      }
    } finally {
      _stationNumber = previousNumber;
      await _loadSnapshot(askForResume: false);
    }
  }

  Future<void> refreshAfterDaBatchImport() =>
      _loadActiveBlock(askForResume: false);

  Future<GuidedPlantDetails> loadDaPlantDetails(int number) async {
    if (!isDaGuidedScouting || number < 1 || number > locationsPerBlock) {
      throw ArgumentError.value(number, 'number', 'Not a DA sampling plant');
    }
    final snapshot = await _workflow.loadStationSnapshot(
      _requirePrepared(),
      stationNumber: number,
    );
    final station = snapshot.station;
    if (station == null) return GuidedPlantDetails(snapshot: snapshot);
    final bundles = await _requireEvidenceCoordinator().repository
        .loadStationBundles(station.id);
    final plantBundles =
        bundles
            .where(
              (b) =>
                  b.session.scopeType == DatabaseCodes.evidenceScopePlant &&
                  b.session.plantPosition == 1,
            )
            .toList()
          ..sort((a, b) => b.session.updatedAt.compareTo(a.session.updatedAt));
    final bundle = plantBundles.firstOrNull;
    final photos =
        bundle?.media
            .where(
              (m) =>
                  m.deletedAt == null &&
                  m.storageState == DatabaseCodes.evidenceStorageReady,
            )
            .toList() ??
        <EvidenceMediaRecord>[];
    PlantDiagnosisResult? diagnosis;
    if (photos.isNotEmpty) {
      final cached = await FieldRepository(
        _plantSaves.database,
      ).readPreferenceValue(_diagnosisKey(station.id, 1));
      diagnosis = AutomaticScreening.resolveSaved(
        note: snapshot.plants.firstOrNull?.plant.wholePlantContextNote,
        cache: cached,
        signature: _evidenceSignature(photos),
        hasEvidence: true,
      )?.result;
    }
    return GuidedPlantDetails(
      snapshot: snapshot,
      evidence: bundle,
      diagnosis: diagnosis,
      monitoring: await DaMonitoringRepository(
        _plantSaves.database,
      ).load(_requireAssessment().id),
    );
  }

  Future<void> saveDaPlantCorrection(
    int number,
    Map<String, bool?> values,
  ) async {
    final details = await loadDaPlantDetails(number);
    if (details.photos.isEmpty)
      throw StateError('Capture a plant photo first.');
    await DaMonitoringRepository(_plantSaves.database).saveCorrection(
      _requireAssessment().id,
      details.snapshot.prepared.run.id,
      number,
      daPhotoSignature(details.photos),
      values,
    );
    _daGuidanceRevision++;
    notifyListeners();
  }

  int _daGuidanceRevision = 0;
  int get daGuidanceRevision => _daGuidanceRevision;
  PlantActionRepository get plantActions => PlantActionRepository(
    _plantSaves.database,
    _requireAssessment().evaluatorPersonId,
  );

  Future<List<String>?> loadDaNaturalEnemies() async =>
      (await DaMonitoringRepository(
        _plantSaves.database,
      ).load(_requireAssessment().id)).enemies(_requirePrepared().run.id);
  Future<void> saveDaNaturalEnemies(List<String> choices) =>
      DaMonitoringRepository(_plantSaves.database).saveEnemies(
        _requireAssessment().id,
        _requirePrepared().run.id,
        choices,
      );

  Future<void> finishDaPlantAndContinue({
    int? newestLeavesInspectedCount,
  }) async {
    if (!isDaGuidedScouting)
      throw StateError('This is not a DA guided assessment.');
    await selectCapturePlant(1, analyzePrevious: false);
    if (!isPlantCaptureSatisfied(1))
      throw StateError('Add the plant overview before continuing.');
    // DA guided capture does not ask for a leaf count. Omit the count rather
    // than silently recording an inspection that the user never reported.
    await _perform(() async {
      final bundle = _currentEvidence!;
      await _requireEvidenceCoordinator().completePlantCapture(
        session: bundle.session,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        activeDuration: Duration.zero,
        newestLeavesInspectedCount: newestLeavesInspectedCount,
        requiredViewTypes: {primaryEvidenceViewType},
      );
      await _loadSnapshot(askForResume: false);
    });
    await analyzePlantBundle(1);
    // Screened evidence is explicitly saved as awaiting human confirmation.
    // A model result must never become a farmer/expert-confirmed diagnosis.
    await completeStationWithoutManualConfirmation();
    if (_stationNumber < locationsPerBlock) await continueToNextStation();
  }

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
    for (var position = 1; position <= plantsPerLocation; position++) {
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

  Future<void> selectCapturePlant(
    int position, {
    bool analyzePrevious = true,
  }) async {
    if (position < 1 || position > plantsPerLocation) return;
    for (var earlier = 1; earlier < position; earlier++) {
      if (!isPlantCaptureSatisfied(earlier)) {
        throw StateError('Finish Plant $earlier before Plant $position.');
      }
    }
    final previous = _currentPlantPosition;
    if (analyzePrevious &&
        previous != null &&
        previous != position &&
        isPlantCaptureSatisfied(previous) &&
        _pendingModelPositions.contains(previous)) {
      await analyzePlantBundle(previous);
    }
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
    for (var position = 1; position <= plantsPerLocation; position++) {
      final recorded =
          _snapshot?.plants.any((p) => p.plant.sequenceNumber == position) ??
          false;
      if (isPlantCaptureSatisfied(position) &&
          (!recorded || _pendingModelPositions.contains(position))) {
        await analyzePlantBundle(position);
      }
    }
    _currentPlantPosition = null;
    _returnToStationReview = false;
    _returnToVeV2Review = false;
    await _loadSnapshot(askForResume: false, preserveState: true);
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

  Future<void> initialize({
    String? initialBlockRunId,
    int? initialStationNumber,
    bool openForReview = false,
  }) async {
    _setState(Station1ViewState.loading);
    try {
      _assessment = await _workflow.assessmentById(assessmentId);
      if (!ScoutingSamplingProtocol.isDa(_assessment!.protocolVersion) ||
          _assessment!.scoutingPattern != ScoutingSamplingProtocol.daPattern) {
        throw StateError(
          'This scouting method is no longer supported. Start a new assessment with 20 plants per sampling block.',
        );
      }
      await _lockAssessmentModels();
      final assessment = _assessment!;
      await _evidence?.recoverPreparedCaptures();
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
      if (!AssessmentAreaPolicy.isWithinAssessmentLimit(
        _boundary!.areaHectares,
      )) {
        _setState(Station1ViewState.largeFieldBlocked);
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
      } on AssessmentAreaExceedsLimitException {
        _setState(Station1ViewState.largeFieldBlocked);
        return;
      } on PilotBlockRequiredException {
        _blockDefinitions = await _workflow.blockDefinitionsForAssessment(
          assessment.id,
        );
        _setState(Station1ViewState.blockPreparation);
        return;
      } on IncompleteBlockDefinitionsException {
        _blockDefinitions = await _workflow.blockDefinitionsForAssessment(
          assessment.id,
        );
        _setState(Station1ViewState.blockPreparation);
        return;
      }
      if (_preparedRuns.isEmpty) {
        _blockDefinitions = await _workflow.blockDefinitionsForAssessment(
          assessment.id,
        );
        _setState(Station1ViewState.blockPreparation);
        return;
      }
      _activeRunIndex = _firstIncompleteRunIndex();
      if (initialBlockRunId != null) {
        final target = _preparedRuns.indexWhere(
          (r) => r.run.id == initialBlockRunId,
        );
        if (target >= 0) _activeRunIndex = target;
      }
      if (initialBlockRunId == _requirePrepared().run.id &&
          initialStationNumber != null &&
          initialStationNumber >= 1 &&
          initialStationNumber <= locationsPerBlock) {
        _stationNumber = initialStationNumber;
        await _loadSnapshot(askForResume: true);
        if (openForReview && _snapshot?.station != null) {
          _currentPlantPosition = null;
          _returnToBlockReview = false;
          _setState(
            isVeV2
                ? Station1ViewState.veV2StationReview
                : Station1ViewState.stationReview,
          );
        }
      } else {
        await _loadActiveBlock(askForResume: true);
      }
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

  Future<void> generateProposedBlocks({bool nextAlternative = false}) async {
    final assessment = _requireAssessment();
    final boundary = _boundary;
    if (boundary == null) throw StateError('Field outline is unavailable.');
    await _perform(() async {
      if (nextAlternative) _partitionCandidateIndex++;
      _blockDefinitions = await _workflow.generateProposedBlocks(
        assessment,
        boundary,
        candidateIndex: _partitionCandidateIndex,
      );
      _setState(Station1ViewState.blockPreparation);
    });
  }

  Future<void> confirmProposedBlocks() async {
    final assessment = _requireAssessment();
    final boundary = _boundary;
    if (boundary == null) throw StateError('Field outline is unavailable.');
    await _perform(() async {
      _blockDefinitions = await _workflow.confirmProposedBlocks(
        assessment,
        boundary,
      );
      _preparedRuns = await _workflow.prepareRequiredBlocks(
        assessment,
        boundary,
      );
      _activeRunIndex = _firstIncompleteRunIndex();
      _stationNumber = 1;
      await _loadSnapshot(askForResume: false);
    });
  }

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

  Future<void> confirmReachedActiveStation([
    Future<AveragedPhoneLocation> Function()? captureLocation,
  ]) async {
    final repository = _requireRouteRepository();
    final plan = _requireRoutePlan();
    await _perform(() async {
      _routePlan = await repository.confirmStationArrival(
        plan,
        stationNumber: _stationNumber,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _workflow.saveStationLocation(
        prepared: _requirePrepared(),
        stationNumber: _stationNumber,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        latitude: null,
        longitude: null,
        gpsAccuracyM: null,
        capturedAt: null,
        notLocatedReason: DatabaseCodes.stationNoCurrentFix,
      );
      await _clearArrivalConfirmation();
      await _loadSnapshot(askForResume: false);
    });

    if (captureLocation != null) {
      unawaited(refineStationLocationInBackground(captureLocation));
    }
  }

  Future<void> refineStationLocationInBackground(
    Future<AveragedPhoneLocation> Function() captureLocation,
  ) async {
    final prepared = _requirePrepared();
    final stationNumber = _stationNumber;
    final station = _snapshot?.station;
    final actor = _requireAssessment().evaluatorPersonId;
    try {
      final loc = await captureLocation();
      if (station != null) {
        await _workflow.saveStationLocation(
          prepared: prepared,
          stationNumber: stationNumber,
          actorPersonId: actor,
          latitude: loc.latitude,
          longitude: loc.longitude,
          gpsAccuracyM: loc.averageAccuracyMeters,
          capturedAt: loc.capturedAt,
        );
        if (_stationNumber == stationNumber &&
            _snapshot?.station?.id == station.id) {
          await _loadSnapshot(askForResume: false, preserveState: true);
          notifyListeners();
        }
      }
    } catch (_) {
      // Non-blocking background GPS capture
    }
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
    if (isVeV2 && _unitAt(position) == null) {
      await _veV2!.saveCaptureRouting(
        VeV2CaptureRoutingSave(
          stationId: station.id,
          sequenceNumber: position,
          occupancyStatus: DatabaseCodes.veOccupancyNotAssessable,
          observedSeedlingCount: 0,
          inspectionDurationMs: 0,
          evidenceCaptureSessionId: evidence.session.id,
          requiredEvidenceViewTypes: const {},
          actorPersonId: _requireAssessment().evaluatorPersonId,
          notAssessableReason: reason,
        ),
      );
      _veV2Units = await _veV2.loadPlantingUnits(station.id);
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
        sourcePlantingUnitObservationId: isVeV2 ? _unitAt(position)?.id : null,
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
    if (position < 1 || position > plantsPerLocation) {
      throw ArgumentError.value(
        position,
        'position',
        'Must be 1-$plantsPerLocation',
      );
    }
    _currentPlantPosition = position;
    _returnToStationReview = true;
    await _loadCurrentEvidence();
    await _restorePlantDiagnosis(position);
    _setState(Station1ViewState.plantEntry);
  }

  void returnToReview() {
    _currentPlantPosition = null;
    _returnToStationReview = false;
    _returnToVeV2Review = false;
    _setState(
      isVeV2
          ? Station1ViewState.veV2StationReview
          : Station1ViewState.stationReview,
    );
  }

  Future<void> returnToStationReview() async {
    _currentPlantPosition = null;
    _returnToStationReview = false;
    _returnToVeV2Review = false;
    await _loadSnapshot(askForResume: false, preserveState: true);
    _setState(
      isVeV2
          ? Station1ViewState.veV2StationReview
          : Station1ViewState.stationReview,
    );
  }

  /// Moves between already-loaded workflow views without deleting or
  /// reclassifying any persisted station, plant, or evidence record.
  ///
  /// The station workflow is hosted by one Navigator route. This method keeps
  /// the phone's system Back gesture/button inside that route. The visible
  /// app-bar Back action deliberately exits to Scout.
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
        _returnToStationReview = false;
        _setState(
          isVeV2
              ? Station1ViewState.veV2StationReview
              : Station1ViewState.stationReview,
        );
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
          _returnToBlockReview = false;
          _setState(Station1ViewState.blockReview);
          return;
        }
        _currentPlantPosition = plantsPerLocation;
        await _loadCurrentEvidence();
        _setState(
          _currentEvidence == null
              ? Station1ViewState.plantSelection
              : Station1ViewState.plantCapture,
        );
        return;
      case Station1ViewState.veV2StationSetup:
        _setState(Station1ViewState.stationLocation);
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
          _currentPlantPosition = plantsPerLocation;
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
          _returnToBlockReview = false;
          _setState(Station1ViewState.blockReview);
          return;
        }
        _currentPlantPosition = plantsPerLocation;
        await _loadCurrentEvidence();
        _setState(Station1ViewState.veV2ContinuousCapture);
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
        _stationNumber = locationsPerBlock;
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
      final returning = _returnToStationReview;
      await _loadSnapshot(askForResume: false, preserveState: returning);
      if (returning) {
        _returnToStationReview = false;
        _currentPlantPosition = null;
        _setState(
          isVeV2
              ? Station1ViewState.veV2StationReview
              : Station1ViewState.stationReview,
        );
      }
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
      final returning = _returnToStationReview;
      await _loadSnapshot(askForResume: false, preserveState: returning);
      if (returning) {
        _returnToStationReview = false;
        _currentPlantPosition = null;
        _setState(
          isVeV2
              ? Station1ViewState.veV2StationReview
              : Station1ViewState.stationReview,
        );
      }
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
      final returning = _returnToStationReview;
      await _loadSnapshot(askForResume: false, preserveState: returning);
      if (returning) {
        _returnToStationReview = false;
        _currentPlantPosition = null;
        _setState(
          isVeV2
              ? Station1ViewState.veV2StationReview
              : Station1ViewState.stationReview,
        );
      }
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
      final returning = _returnToStationReview;
      await _loadSnapshot(askForResume: false, preserveState: returning);
      if (returning) {
        _returnToStationReview = false;
        _currentPlantPosition = null;
        _setState(
          isVeV2
              ? Station1ViewState.veV2StationReview
              : Station1ViewState.stationReview,
        );
      }
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
    } else if (isVtR2) {
      await _fillRemainingVtR2TestData();
    } else if (isR3R6) {
      await _fillRemainingR3R6TestData();
    } else if (_assessment?.growthStage == 'v7_v12') {
      await _fillRemainingVegetativeTestData(isV7V12: true);
    } else {
      await _fillRemainingVegetativeTestData(isV7V12: false);
    }
  }

  Future<void> _fillRemainingVegetativeTestData({required bool isV7V12}) async {
    await _perform(() async {
      await _ensureAssessmentActive();
      var snapshot = await _workflow.loadStationSnapshot(
        _requirePrepared(),
        stationNumber: _stationNumber,
      );
      var station = snapshot.station;
      if (realisticTestFixture &&
          (station?.latitude == null || station?.longitude == null)) {
        station = await _saveSyntheticTestStationLocation();
      } else {
        station ??= await _workflow.saveStationLocation(
          prepared: _requirePrepared(),
          stationNumber: _stationNumber,
          actorPersonId: _requireAssessment().evaluatorPersonId,
          notLocatedReason: DatabaseCodes.stationNoCurrentFix,
          accessibilityNotes: '[TEST DATA] Synthetic unavailable GPS.',
        );
      }
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
      for (var position = 1; position <= plantsPerLocation; position++) {
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
        if (realisticTestFixture) {
          if (!bundle.isViewSatisfied(
            DatabaseCodes.evidenceViewWhorlOverview,
          )) {
            bundle = await _captureSyntheticTestPlantPhoto(
              bundle: bundle,
              plantPosition: position,
            );
          }
          if (bundle.session.completedAt == null) {
            await coordinator.completePlantCapture(
              session: bundle.session,
              actorPersonId: _requireAssessment().evaluatorPersonId,
              activeDuration: const Duration(seconds: 8),
              newestLeavesInspectedCount: 3,
              requiredViewTypes: const {
                DatabaseCodes.evidenceViewWhorlOverview,
              },
            );
          }
        } else {
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
        }
        final saved = await _plantSaves.saveVegetativePlant(
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
            daBafsLeafDamageScore: isV7V12 && assessable
                ? (current ? 3 : 1)
                : null,
            damageAttribution: isV7V12 && assessable
                ? (current
                      ? DatabaseCodes.damageAttributionFawConsistent
                      : DatabaseCodes.damageAttributionLikelyNonFaw)
                : null,
            damageFreshness: isV7V12 && assessable
                ? (current
                      ? DatabaseCodes.evidenceFresh
                      : DatabaseCodes.evidenceOld)
                : null,
            naturalEnemyQuickStatus: isV7V12
                ? DatabaseCodes.naturalEnemyNoneSeen
                : DatabaseCodes.naturalEnemyNotCollected,
            evaluatorNotes: '[TEST DATA] Synthetic Plant $position.',
            actorPersonId: _requireAssessment().evaluatorPersonId,
            evidenceCaptureSessionId: bundle.session.id,
            requiredEvidenceViewTypes: requiredViews,
            requireCameraPhaseAEvidence: true,
            manualFormUsed: true,
          ),
        );
        if (realisticTestFixture) {
          await _attachSyntheticPlantLocation(
            station: station,
            plant: saved.plant,
            captureSessionId: bundle.session.id,
          );
        }
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

  Future<StationRecord> _saveSyntheticTestStationLocation() {
    final point = _syntheticStationPoint(_stationNumber);
    return _workflow.saveStationLocation(
      prepared: _requirePrepared(),
      stationNumber: _stationNumber,
      actorPersonId: _requireAssessment().evaluatorPersonId,
      latitude: point.latitude,
      longitude: point.longitude,
      gpsAccuracyM: 3.5 + _stationNumber / 10,
      capturedAt: DateTime.now().toUtc(),
      accessibilityNotes:
          '[TEST DATA] Synthetic GPS coordinate inside the test field.',
    );
  }

  ({double latitude, double longitude}) _syntheticStationPoint(
    int stationNumber,
  ) => switch (stationNumber) {
    1 => (latitude: 17.00010, longitude: 121.00010),
    2 => (latitude: 17.00067, longitude: 121.00017),
    3 => (latitude: 17.00029, longitude: 121.00043),
    4 => (latitude: 17.00067, longitude: 121.00068),
    _ => (latitude: 17.00010, longitude: 121.00075),
  };

  Future<EvidenceCaptureBundle> _captureSyntheticTestPlantPhoto({
    required EvidenceCaptureBundle bundle,
    required int plantPosition,
  }) async {
    final coordinator = _requireEvidenceCoordinator();
    var updated = bundle;
    final template = _syntheticPhotoTemplate;
    if (template == null) {
      final assetPath = _assessment?.growthStage == 'v7_v12'
          ? 'assets/images/growth_stages/maize_tall_vegetative.jpg'
          : 'assets/images/growth_stages/maize_young_vegetative.jpg';
      final data = await rootBundle.load(assetPath);
      final source = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'wormwise_test_${bundle.session.id}_$plantPosition.jpg',
      );
      await source.writeAsBytes(data.buffer.asUint8List(), flush: true);
      updated = await coordinator.stageCapture(
        session: bundle.session,
        viewType: DatabaseCodes.evidenceViewWhorlOverview,
        sourcePath: source.path,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
    } else {
      final mediaId = LocalId.generate();
      final folder = [
        _safeTestPathSegment(bundle.session.assessmentId),
        _safeTestPathSegment(bundle.session.stationId),
        _safeTestPathSegment(bundle.session.scopeKey),
        'staging',
      ].join('/');
      final localUri = '$folder/$mediaId.jpg';
      final thumbnailLocalUri = '$folder/${mediaId}_thumb.jpg';
      final templateThumbnail = template.thumbnailLocalUri;
      if (templateThumbnail == null) {
        throw StateError('The synthetic photo template has no thumbnail.');
      }
      final target = await coordinator.resolve(localUri);
      final targetThumbnail = await coordinator.resolve(thumbnailLocalUri);
      await target.parent.create(recursive: true);
      await (await coordinator.resolve(template.localUri)).copy(target.path);
      await (await coordinator.resolve(
        templateThumbnail,
      )).copy(targetThumbnail.path);
      await coordinator.repository.insertStagedMedia(
        mediaId: mediaId,
        session: bundle.session,
        viewType: DatabaseCodes.evidenceViewWhorlOverview,
        localUri: localUri,
        thumbnailLocalUri: thumbnailLocalUri,
        byteSize: template.byteSize!,
        sha256Checksum: template.sha256Checksum,
        widthPx: template.widthPx!,
        heightPx: template.heightPx!,
        capturedAt: DateTime.now().toUtc(),
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      updated = await coordinator.repository.loadBundle(bundle.session.id);
    }
    final staged = updated.mediaForView(
      DatabaseCodes.evidenceViewWhorlOverview,
    );
    if (staged == null) {
      throw StateError('The synthetic test photo was not staged.');
    }
    updated = await coordinator.accept(
      media: staged,
      actorPersonId: _requireAssessment().evaluatorPersonId,
    );
    _syntheticPhotoTemplate ??= updated.mediaForView(
      DatabaseCodes.evidenceViewWhorlOverview,
    );
    return updated;
  }

  String _safeTestPathSegment(String value) =>
      value.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');

  Future<void> _attachSyntheticPlantLocation({
    required StationRecord station,
    required PlantObservationRecord plant,
    required String captureSessionId,
  }) async {
    final stationLatitude = station.latitude;
    final stationLongitude = station.longitude;
    if (stationLatitude == null || stationLongitude == null) return;
    final offset = (plant.sequenceNumber - 5.5) * 0.000008;
    final latitude = stationLatitude + offset;
    final longitude = stationLongitude + offset / 2;
    final now = DateTime.now().toUtc();
    await (_plantSaves.database.update(
      _plantSaves.database.plantObservations,
    )..where((row) => row.id.equals(plant.id))).write(
      PlantObservationsCompanion(
        latitude: Value(latitude),
        longitude: Value(longitude),
        gpsAccuracyM: const Value(4.0),
        updatedAt: Value(now),
      ),
    );
    await (_plantSaves.database.update(
      _plantSaves.database.evidenceMedia,
    )..where((row) => row.captureSessionId.equals(captureSessionId))).write(
      EvidenceMediaCompanion(
        latitude: Value(latitude),
        longitude: Value(longitude),
        gpsAccuracyM: const Value(4.0),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _fillRemainingVtR2TestData() async {
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
      for (var position = 1; position <= plantsPerLocation; position++) {
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
        final infested = kind == 2;
        final requiredViews = assessable
            ? const {DatabaseCodes.evidenceViewWhorlOverview}
            : const <String>{};
        for (final viewType in requiredViews) {
          if (!bundle.isViewSatisfied(viewType)) {
            bundle = await coordinator.waive(
              session: bundle.session,
              viewType: viewType,
              reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
              actorPersonId: _requireAssessment().evaluatorPersonId,
              note: '[TEST DATA] Synthetic VT-R2 evidence fallback.',
            );
          }
        }
        await _stageSaves.saveReproductivePlant(
          ReproductivePlantSave(
            stationId: station.id,
            plantPosition: position,
            assessable: assessable,
            classification: !assessable
                ? DatabaseCodes.reproductiveNotAssessable
                : infested
                ? DatabaseCodes.reproductiveInfested
                : DatabaseCodes.reproductiveNotInfested,
            tasselExamined: assessable,
            earBaseExamined: assessable,
            upperAxilExamined: assessable,
            lowerAxilExamined: assessable,
            freshFeedingPresent: infested,
            frassPresent: infested,
            earHuskPenetrationVisible: false,
            larvaPresent: false,
            larvalSize: 'none_seen',
            possibleNonFawEvidence: false,
            uncertainEvidence: false,
            naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
            notAssessableReason: assessable
                ? null
                : '[TEST DATA] Synthetic not-assessable position.',
            evaluatorNotes: '[TEST DATA] Synthetic VT-R2 Plant $position.',
            actorPersonId: _requireAssessment().evaluatorPersonId,
            evidenceCaptureSessionId: bundle.session.id,
            requiredEvidenceViewTypes: requiredViews,
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

  Future<void> _fillRemainingR3R6TestData() async {
    await _perform(() async {
      await _ensureAssessmentActive();
      _lateSeasonSetup ??= await _stageSaves.saveLateSeasonSetup(
        LateSeasonSetupInput(
          assessmentId: assessmentId,
          cropUse: 'grain',
          commercialHarvestStarted: false,
          selectedEarsPartOfHarvest: true,
          openingPermission: DatabaseCodes.openingPermissionGranted,
          maximumEarsPermitted: 10,
          openingReason: 'test_subsample',
          permissionGrantedBy: 'Farm Manager',
          earDesignationRule: 'primary_top_ear',
          permissionRecordedAt: DateTime.now().toUtc(),
          blockRunIds: [_requirePrepared().run.id],
          evaluatorPersonId: _requireAssessment().evaluatorPersonId,
        ),
      );
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
      for (var position = 1; position <= plantsPerLocation; position++) {
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
        final active = kind == 2;
        final requiredViews = assessable
            ? const {DatabaseCodes.evidenceViewWhorlOverview}
            : const <String>{};
        for (final viewType in requiredViews) {
          if (!bundle.isViewSatisfied(viewType)) {
            bundle = await coordinator.waive(
              session: bundle.session,
              viewType: viewType,
              reasonCode: DatabaseCodes.evidenceFallbackNoCamera,
              actorPersonId: _requireAssessment().evaluatorPersonId,
              note: '[TEST DATA] Synthetic R3-R6 evidence fallback.',
            );
          }
        }
        await _stageSaves.saveExternalEar(
          EarExternalPlantSave(
            stationId: station.id,
            plantPosition: position,
            earPresent: assessable,
            externallyAssessable: assessable,
            designatedEarIdentity: 'primary_top_ear',
            exteriorEarTipExamined: assessable,
            baseShankSilkAxilsExamined: assessable,
            externalDamagePresent: active,
            activeInfestationPresent: active,
            silkDamagePresent: active,
            huskDamagePresent: false,
            entryHolePresent: false,
            frassPresent: active,
            larvaPresent: false,
            moldRotLikeSymptoms: false,
            externalClassification: !assessable
                ? DatabaseCodes.earExternalNotAssessable
                : active
                ? DatabaseCodes.earExternalActive
                : DatabaseCodes.earExternalNegative,
            naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
            notAssessableReason: assessable
                ? null
                : '[TEST DATA] Synthetic not-assessable position.',
            evaluatorNotes: '[TEST DATA] Synthetic R3-R6 Plant $position.',
            actorPersonId: _requireAssessment().evaluatorPersonId,
            evidenceCaptureSessionId: bundle.session.id,
            requiredEvidenceViewTypes: requiredViews,
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
      // Isolated test data must satisfy the same terminal-target rule as production.
      // Record an explicit synthetic exception instead of inventing opened-ear findings.
      while (true) {
        final plan = await _stageSaves.loadOpeningPlan(
          blockRunId: _requirePrepared().run.id,
          stationNumber: _stationNumber,
        );
        final pending = plan
            .where(
              (item) =>
                  (item.initiallySelected ||
                      item.selectionStatus == 'replacement_selected') &&
                  item.selectionStatus != 'opened' &&
                  item.selectionStatus != 'failed',
            )
            .firstOrNull;
        if (pending == null) break;
        await _stageSaves.markOpeningSelectionFailed(
          selectionId: pending.id,
          reason:
              '[TEST DATA] Synthetic opening unavailable; no internal findings recorded.',
          actorPersonId: _requireAssessment().evaluatorPersonId,
        );
      }
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> completeTestStation() async {
    _requireTestShortcuts();
    await _prepareTestBlockIfNeeded();
    await fillRemainingTestPlants();
    if (isVeV2) {
      await completeVeV2PilotStation();
    } else {
      final snapshot = _snapshot;
      if (snapshot == null) throw StateError('Test station is unavailable.');
      await _perform(() async {
        await _workflow.confirmStationReview(
          snapshot: snapshot,
          actorPersonId: _requireAssessment().evaluatorPersonId,
        );
        await _loadSnapshot(askForResume: false);
      });
    }
    if (_stationNumber < locationsPerBlock) {
      _setState(Station1ViewState.betweenStations);
    } else {
      _setState(Station1ViewState.blockReview);
    }
  }

  /// Completes the current and every remaining station in the active test
  /// block without opening camera or documentation screens, then redirects
  /// directly to the Block Review screen.
  Future<void> completeAllRemainingTestStations() async {
    _requireTestShortcuts();
    await _prepareTestBlockIfNeeded();
    for (var sn = 1; sn <= locationsPerBlock; sn++) {
      _stationNumber = sn;
      await _loadSnapshot(askForResume: false);
      await fillRemainingTestPlants();
      if (isVeV2) {
        await completeVeV2PilotStation();
      } else {
        final snapshot = _snapshot;
        if (snapshot != null) {
          await _workflow.confirmStationReview(
            snapshot: snapshot,
            actorPersonId: _requireAssessment().evaluatorPersonId,
          );
          await _loadSnapshot(askForResume: false);
        }
      }
    }
    _stationNumber = locationsPerBlock;
    await _loadSnapshot(askForResume: false);
    _setState(Station1ViewState.blockReview);
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
      for (var position = 1; position <= plantsPerLocation; position++) {
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
      for (var position = 1; position <= plantsPerLocation; position++) {
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

  Future<void> confirmStationReview({bool remainOnReview = false}) async {
    final snapshot = _snapshot;
    if (snapshot == null) throw StateError('Station data is unavailable.');
    await _perform(() async {
      await _ensureAssessmentActive();
      await _repairLegacyPlantEvidenceAssociations(snapshot);
      _validateReviewEvidence(snapshot);
      await _workflow.confirmStationReview(
        snapshot: snapshot,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _loadSnapshot(askForResume: false, preserveState: remainOnReview);
      if (_returnToBlockReview) {
        _returnToBlockReview = false;
        _setState(Station1ViewState.blockReview);
      }
    });
  }

  Future<void> completeStationWithoutManualConfirmation({
    bool remainOnReview = false,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) throw StateError('Station data is unavailable.');
    await _perform(() async {
      await _ensureAssessmentActive();
      await _repairLegacyPlantEvidenceAssociations(snapshot);
      _validateDeferredManualConfirmationEvidence();
      await _workflow.confirmStationReview(
        snapshot: snapshot,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        manualConfirmationDeferred: true,
      );
      await _loadSnapshot(askForResume: false, preserveState: remainOnReview);
      if (_returnToBlockReview) {
        _returnToBlockReview = false;
        _setState(Station1ViewState.blockReview);
      }
    });
  }

  Future<List<ValidationIssue>> currentStationValidationIssues() async {
    final station = _snapshot?.station;
    if (station == null) {
      return const [
        ValidationIssue(
          'station_missing',
          'This station has not been recorded yet.',
        ),
      ];
    }
    final result = await _completion.validateBlock(_requirePrepared().run.id);
    return result.issues
        .where(
          (issue) =>
              issue.stationId == station.id ||
              issue.stationNumber == _stationNumber,
        )
        .toList(growable: false);
  }

  void _validateDeferredManualConfirmationEvidence() {
    final requiredView = isVeV2
        ? DatabaseCodes.evidenceViewWholeSeedling
        : primaryEvidenceViewType;
    for (var position = 1; position <= plantsPerLocation; position++) {
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
    if (stationNumber < 1 || stationNumber > locationsPerBlock) {
      throw ArgumentError.value(
        stationNumber,
        'stationNumber',
        'Must be 1-$locationsPerBlock',
      );
    }
    if (_stationNumber != stationNumber) _cvDiagnoses = const {};
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
    if (_snapshot?.reviewIsCurrent != true ||
        _stationNumber >= locationsPerBlock) {
      throw StateError('The current station review is not complete.');
    }
    _cvDiagnoses = const {};
    _stationNumber++;
    await _loadSnapshot(askForResume: false);
  }

  Future<void> completeCurrentBlock() async {
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

  Future<EvidenceMediaRecord> stageEvidence({
    required String viewType,
    required String sourcePath,
    bool deleteSourceAfterCopy = true,
    AveragedPhoneLocation? photoLocation,
    bool fromCamera = true,
  }) async {
    EvidenceMediaRecord? stagedMedia;
    await _perform(() async {
      await _ensureAssessmentActive();
      final activeBundle = _requireActiveEvidenceBundle();
      // Replacement is registered transactionally before the previous evidence
      // is discarded. A failed retake must leave the accepted photo intact.
      final updated = await _requireEvidenceCoordinator().stageCapture(
        session: activeBundle.session,
        viewType: viewType,
        sourcePath: sourcePath,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        deleteSourceAfterCopy: deleteSourceAfterCopy,
      );
      stagedMedia = updated.mediaForView(viewType);
      final media = stagedMedia;
      if (media != null) {
        final db = _plantSaves.database;
        await (db.update(
          db.evidenceMedia,
        )..where((row) => row.id.equals(media.id))).write(
          EvidenceMediaCompanion(
            latitude: Value(photoLocation?.latitude),
            longitude: Value(photoLocation?.longitude),
            gpsAccuracyM: Value(photoLocation?.averageAccuracyMeters),
            locationCapturedAt: Value(photoLocation?.capturedAt.toUtc()),
            locationSource: Value(
              photoLocation == null ? 'unavailable' : 'phone_gps',
            ),
            capturedAt: fromCamera
                ? Value(DateTime.now().toUtc())
                : const Value(null),
            captureSource: Value(
              fromCamera
                  ? DatabaseCodes.evidenceCaptureSourceCamera
                  : 'gallery',
            ),
          ),
        );
        final refreshed = await _requireEvidenceCoordinator().repository
            .loadBundle(activeBundle.session.id);
        stagedMedia = refreshed.mediaForView(viewType);
        _replaceEvidenceBundle(refreshed);
      } else {
        _replaceEvidenceBundle(updated);
      }
      if (_currentPlantPosition != null) {
        _cvDiagnoses = {..._cvDiagnoses}..remove(_currentPlantPosition);
      }
      await _refreshPilotWorkloadMetrics();
    });
    final result = stagedMedia;
    if (result == null) {
      throw StateError('The newly uploaded photo could not be loaded.');
    }
    return result;
  }

  Future<void> acceptEvidence(EvidenceMediaRecord media) async {
    if (media.storageState == DatabaseCodes.evidenceStorageReady) return;
    await _perform(() async {
      final updated = await _requireEvidenceCoordinator().accept(
        media: media,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _requireEvidenceCoordinator().repository
          .savePlantLocationFromEvidence(updated);
      _replaceEvidenceBundle(updated);
      if (_currentPlantPosition != null) {
        _cvDiagnoses = {..._cvDiagnoses}..remove(_currentPlantPosition);
      }
      await _refreshPilotWorkloadMetrics();
    });
    final position = _currentPlantPosition;
    if (position != null &&
        media.captureSessionId == bundleForPlant(position)?.session.id) {
      _pendingModelPositions.add(position);
    }
    if (isVeV2 &&
        position != null &&
        media.viewType == DatabaseCodes.evidenceViewWholeSeedling &&
        _unitAt(position) == null) {
      final bundle = bundleForPlant(position);
      final station = _snapshot?.station;
      if (bundle != null && station != null) {
        await _veV2!.saveCaptureRouting(
          VeV2CaptureRoutingSave(
            stationId: station.id,
            sequenceNumber: position,
            occupancyStatus: DatabaseCodes.veOccupancySeedling,
            observedSeedlingCount: 1,
            inspectionDurationMs: 0,
            evidenceCaptureSessionId: bundle.session.id,
            requiredEvidenceViewTypes: const {},
            actorPersonId: _requireAssessment().evaluatorPersonId,
          ),
        );
        _veV2Units = await _veV2.loadPlantingUnits(station.id);
        notifyListeners();
      }
    }
    // Inference runs when leaving the completed plant or opening station review.
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
      if (_currentPlantPosition != null) {
        _cvDiagnoses = {..._cvDiagnoses}..remove(_currentPlantPosition);
      }
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
      final returning = _returnToVeV2Review;
      await _loadSnapshot(askForResume: false, preserveState: returning);
      if (returning) {
        _returnToVeV2Review = false;
        _currentPlantPosition = null;
        _setState(Station1ViewState.veV2StationReview);
      }
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
      final returning = _returnToVeV2Review;
      await _loadSnapshot(askForResume: false, preserveState: returning);
      if (returning) {
        _returnToVeV2Review = false;
        _currentPlantPosition = null;
        _setState(Station1ViewState.veV2StationReview);
      }
    });
  }

  Future<void> editVeV2PlantingUnit(int position) async {
    if (position < 1 || position > plantsPerLocation)
      throw ArgumentError('Must be 1-$plantsPerLocation');
    _currentPlantPosition = position;
    _returnToVeV2Review = true;
    await loadVeV2PlantingUnitEvidence();
    _setState(Station1ViewState.veV2PlantingUnitEntry);
  }

  Future<void> editVeV2LivingSeedling(int position) async {
    if (position < 1 || position > plantsPerLocation)
      throw ArgumentError('Must be 1-$plantsPerLocation');
    _currentPlantPosition = position;
    final bundle = _plantEvidenceBundle(position);
    final station = _snapshot?.station;
    if (bundle != null &&
        station != null &&
        _unitAt(position) == null &&
        bundle.isViewSatisfied(DatabaseCodes.evidenceViewWholeSeedling)) {
      await _veV2!.saveCaptureRouting(
        VeV2CaptureRoutingSave(
          stationId: station.id,
          sequenceNumber: position,
          occupancyStatus: DatabaseCodes.veOccupancySeedling,
          observedSeedlingCount: 1,
          inspectionDurationMs: 0,
          evidenceCaptureSessionId: bundle.session.id,
          requiredEvidenceViewTypes: const {},
          actorPersonId: _requireAssessment().evaluatorPersonId,
        ),
      );
      _veV2Units = await _veV2.loadPlantingUnits(station.id);
    }
    _veV2CaptureTarget = VeV2CaptureTarget.livingSeedling(
      livingSeedlingPosition: position,
      sourcePlantingUnitId:
          _unitAt(position)?.id ??
          bundle?.session.sourcePlantingUnitObservationId ??
          currentPlant?.plant.sourcePlantingUnitObservationId,
      sourcePlantingUnitSequence: _unitSequenceForId(
        bundle?.session.sourcePlantingUnitObservationId ??
            currentPlant?.plant.sourcePlantingUnitObservationId,
      ),
    );
    await _loadCurrentEvidence();
    await _restorePlantDiagnosis(position);
    _setState(
      bundle?.isViewSatisfied(DatabaseCodes.evidenceViewWholeSeedling) == true
          ? Station1ViewState.plantEntry
          : Station1ViewState.veV2ContinuousCapture,
    );
  }

  Future<void> completeVeV2PilotStation() async {
    final station = _snapshot?.station;
    if (!isVeV2 || station == null || _veV2 == null) {
      throw StateError('VE-V2 station data is unavailable.');
    }
    await _perform(() async {
      _veV2Inspection = await _veV2.completePilotStation(
        stationId: station.id,
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
    return analyzePlantBundle(plantPosition);
  }

  /// Analyzes all captured images (1-3 photos) for a plant, fuses their results,
  /// and automatically persists the plant observation.
  Future<void> _lockAssessmentModels() async {
    final enabled = await DetectionPreferences.forAssessment(
      _plantSaves.database,
      assessmentId,
    );
    final service = _cvService;
    if (service is TwoStageFawCvService) {
      service.useAssessmentHighlighting(enabled);
    }
  }

  Future<PlantDiagnosisResult?> analyzePlantBundle(
    int plantPosition, {
    bool saveResult = true,
  }) async {
    final subject = '${_snapshot?.station?.id}:$plantPosition:$saveResult';
    if (_screeningInFlight != null) {
      if (_screeningSubject == subject) return _screeningInFlight;
      throw StateError('Screening is still running. Please wait.');
    }
    _screeningSubject = subject;
    final operation = _analyzePlantBundle(
      plantPosition,
      saveResult: saveResult,
    );
    _screeningInFlight = operation;
    try {
      return await operation;
    } finally {
      _screeningInFlight = null;
      _screeningSubject = null;
    }
  }

  Future<PlantDiagnosisResult?> _analyzePlantBundle(
    int plantPosition, {
    required bool saveResult,
  }) async {
    await _lockAssessmentModels();
    final coordinator = _evidence;
    final station = _snapshot?.station;
    if (coordinator == null || station == null) return null;
    final bundle = bundleForPlant(plantPosition);
    if (bundle == null) return null;

    final mediaList = bundle.media
        .where(
          (m) =>
              m.deletedAt == null &&
              m.storageState == DatabaseCodes.evidenceStorageReady,
        )
        .toList();

    if (mediaList.isEmpty) return null;

    final signature = _evidenceSignature(mediaList);
    final restored = await _restorePlantDiagnosis(
      plantPosition,
      signature: signature,
    );
    if (restored != null) {
      if (_disposed || _snapshot?.station?.id != station.id) {
        throw StateError('The active plant changed. Retry screening.');
      }
      if (saveResult) {
        await _autoSavePlantDiagnosis(
          plantPosition: plantPosition,
          diagnosis: restored,
          sessionId: bundle.session.id,
          evidenceSignature: signature,
          expectedStationId: station.id,
        );
      }
      _pendingModelPositions.remove(plantPosition);
      return restored;
    }

    final checkpoints = PhotoScreeningCheckpointStore(_plantSaves.database);
    final repository = checkpoints.repository;
    final pipeline = _cvService.modelIdentifier;
    final results = <PlantDiagnosisResult>[];
    for (final media in mediaList) {
      if (_disposed) throw StateError('Screening paused. Resume this sample.');
      // A completed photo is a durable checkpoint. Restart only failed/missing
      // photos, not every photo in a plant after an interrupted batch.
      var res = await _restorePhotoDiagnosis(media, pipeline);
      if (res == null) {
        final file = await coordinator.resolve(media.localUri);
        res = await _cvService.analyzeImage(file);
        if (_disposed ||
            _snapshot?.station?.id != station.id ||
            _evidenceSignature(
                  bundleForPlant(plantPosition)?.media
                          .where(
                            (m) =>
                                m.deletedAt == null &&
                                m.storageState ==
                                    DatabaseCodes.evidenceStorageReady,
                          )
                          .toList() ??
                      [],
                ) !=
                signature) {
          throw StateError('The plant photos changed. Retry screening.');
        }
        await checkpoints.save(media, res, pipeline);
      }
      if (res.modelName.startsWith('WormWise-AutoScreen-v1:') &&
          !AutomaticScreening(res).screeningSucceeded) {
        throw StateError('A photo could not be screened. Retry this plant.');
      }
      results.add(res);
    }
    // Never associate an old inference with a newly selected plant/photo set.
    if (_disposed ||
        _snapshot?.station?.id != station.id ||
        _evidenceSignature(
              bundleForPlant(plantPosition)?.media
                      .where(
                        (m) =>
                            m.deletedAt == null &&
                            m.storageState ==
                                DatabaseCodes.evidenceStorageReady,
                      )
                      .toList() ??
                  [],
            ) !=
            signature) {
      throw StateError('The plant photos changed. Retry screening.');
    }
    final merged = PlantDiagnosisResult.merge(results);
    await _plantSaves.database.transaction(() async {
      await repository.savePreferenceValue(
        _diagnosisKey(station.id, plantPosition),
        jsonEncode({
          'signature': signature,
          'pipelineVersion': pipeline,
          'result': merged.toJson(),
        }),
      );
      if (saveResult)
        await _autoSavePlantDiagnosis(
          plantPosition: plantPosition,
          diagnosis: merged,
          sessionId: bundle.session.id,
          evidenceSignature: signature,
          refreshSnapshot: false,
          expectedStationId: station.id,
        );
    });
    if (saveResult)
      await _loadSnapshot(askForResume: false, preserveState: true);
    _cvDiagnoses = {..._cvDiagnoses, plantPosition: merged};
    if (merged.modelName.startsWith('WormWise-AutoScreen-v1:') &&
        !AutomaticScreening(merged).processingComplete) {
      throw StateError('Photo detection was interrupted. Retry this plant.');
    }
    _pendingModelPositions.remove(plantPosition);
    notifyListeners();
    return merged;
  }

  Future<PlantDiagnosisResult?> _restorePhotoDiagnosis(
    EvidenceMediaRecord media,
    String pipeline,
  ) =>
      PhotoScreeningCheckpointStore(_plantSaves.database).read(media, pipeline);

  Future<bool> daBatchPlantIsScreened(
    String blockId,
    int number,
    Set<String> photoIds,
  ) async {
    if (_requirePrepared().run.id != blockId) return false;
    final details = await loadDaPlantDetails(number);
    if (!details.snapshot.reviewIsCurrent ||
        details.photos.length != photoIds.length ||
        !details.photos.every((m) => photoIds.contains(m.id)))
      return false;
    final saved = AutomaticScreening.parse(
      details.plant?.wholePlantContextNote,
    );
    if (saved == null ||
        !saved.processingComplete ||
        !saved.matchesEvidence(
          _evidenceSignature(details.photos),
          hasEvidence: details.photos.isNotEmpty,
          allowLegacy: false,
        ))
      return false;
    for (final photo in details.photos) {
      if (await _restorePhotoDiagnosis(photo, saved.result.modelName) == null)
        return false;
    }
    return true;
  }

  String _diagnosisKey(String stationId, int position) =>
      'plant_model_${stationId}_$position';

  String _evidenceSignature(List<EvidenceMediaRecord> media) {
    final checksums = media.map((item) => item.sha256Checksum).toList()..sort();
    return checksums.join(':');
  }

  Future<PlantDiagnosisResult?> _restorePlantDiagnosis(
    int position, {
    String? signature,
  }) async {
    await DetectionPreferences.load();
    final station = _snapshot?.station;
    if (station == null) return null;
    final bundle = bundleForPlant(position);
    if (bundle == null) return null;
    final currentSignature =
        signature ??
        _evidenceSignature(
          bundle.media
              .where(
                (item) =>
                    item.deletedAt == null &&
                    item.storageState == DatabaseCodes.evidenceStorageReady,
              )
              .toList(),
        );
    final stored = await FieldRepository(
      _plantSaves.database,
    ).readPreferenceValue(_diagnosisKey(station.id, position));
    final plants = _snapshot?.plants.where(
      (p) => p.plant.sequenceNumber == position,
    );
    final restored = AutomaticScreening.resolveSaved(
      note: plants?.firstOrNull?.plant.wholePlantContextNote,
      cache: stored,
      signature: currentSignature,
      hasEvidence: bundle.media.any(
        (m) =>
            m.deletedAt == null &&
            m.storageState == DatabaseCodes.evidenceStorageReady,
      ),
      pipelineVersion: signature == null ? null : _cvService.modelIdentifier,
      allowLegacy: signature == null,
    );
    if (restored == null ||
        (signature != null &&
            restored.result.modelName.startsWith('WormWise-AutoScreen-v1:') &&
            !restored.processingComplete))
      return null;
    if (signature != null) {
      for (final photo in bundle.media.where(
        (m) =>
            m.deletedAt == null &&
            m.storageState == DatabaseCodes.evidenceStorageReady,
      )) {
        if (await _restorePhotoDiagnosis(photo, _cvService.modelIdentifier) ==
            null)
          return null;
      }
    }
    _cvDiagnoses = {..._cvDiagnoses, position: restored.result};
    return restored.result;
  }

  Future<void> _autoSavePlantDiagnosis({
    required int plantPosition,
    required PlantDiagnosisResult diagnosis,
    String? sessionId,
    String? notes,
    bool refreshSnapshot = true,
    String? evidenceSignature,
    String? expectedStationId,
  }) async {
    final station = _snapshot?.station;
    if (expectedStationId != null && station?.id != expectedStationId) {
      throw StateError('The active plant changed. Retry screening.');
    }
    if (station == null) return;
    if (evidenceSignature != null &&
        _evidenceSignature(
              bundleForPlant(plantPosition)?.media
                      .where(
                        (m) =>
                            m.deletedAt == null &&
                            m.storageState ==
                                DatabaseCodes.evidenceStorageReady,
                      )
                      .toList() ??
                  [],
            ) !=
            evidenceSignature) {
      throw StateError('The plant photos changed. Retry screening.');
    }
    final actorId = _requireAssessment().evaluatorPersonId;
    if (diagnosis.modelName.startsWith('WormWise-AutoScreen-v1:')) {
      await AutomaticScreeningSaveService(_plantSaves.database).save(
        stationId: station.id,
        position: plantPosition,
        growthStage: _requireAssessment().growthStage,
        screening: AutomaticScreening(
          diagnosis,
          evidenceSignature:
              evidenceSignature ??
              (bundleForPlant(plantPosition) == null
                  ? null
                  : _evidenceSignature(
                      bundleForPlant(plantPosition)!.media
                          .where(
                            (m) =>
                                m.deletedAt == null &&
                                m.storageState ==
                                    DatabaseCodes.evidenceStorageReady,
                          )
                          .toList(),
                    )),
        ),
        actorId: actorId,
        sessionId: sessionId,
        unitId: isVeV2 ? _unitAt(plantPosition)?.id : null,
        primaryView: primaryEvidenceViewType,
      );
      if (refreshSnapshot)
        await _loadSnapshot(askForResume: false, preserveState: true);
      return;
    }

    if (isVtR2) {
      await _stageSaves.saveReproductivePlant(
        ReproductivePlantSave(
          stationId: station.id,
          plantPosition: plantPosition,
          assessable: true,
          classification: diagnosis.isInfested
              ? DatabaseCodes.reproductiveInfested
              : DatabaseCodes.reproductiveNotInfested,
          tasselExamined: true,
          earBaseExamined: true,
          upperAxilExamined: true,
          lowerAxilExamined: true,
          freshFeedingPresent: diagnosis.isInfested,
          frassPresent: diagnosis.frass,
          earHuskPenetrationVisible: false,
          larvaPresent: diagnosis.larvaVisible,
          larvalSize: diagnosis.larvalSize,
          possibleNonFawEvidence:
              diagnosis.suggestedPlantStatus ==
              DatabaseCodes.plantPossibleNonFaw,
          uncertainEvidence: false,
          naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
          evaluatorNotes: notes,
          actorPersonId: actorId,
          evidenceCaptureSessionId: sessionId,
          requiredEvidenceViewTypes: {primaryEvidenceViewType},
        ),
      );
    } else if (isR3R6) {
      await _stageSaves.saveExternalEar(
        EarExternalPlantSave(
          stationId: station.id,
          plantPosition: plantPosition,
          earPresent: true,
          externallyAssessable: true,
          designatedEarIdentity: 'primary_top_ear',
          exteriorEarTipExamined: true,
          baseShankSilkAxilsExamined: true,
          externalDamagePresent: diagnosis.isInfested,
          activeInfestationPresent: diagnosis.isInfested,
          silkDamagePresent: diagnosis.whorlFeeding,
          huskDamagePresent: diagnosis.cutting || diagnosis.windowpanes,
          entryHolePresent: false,
          frassPresent: diagnosis.frass,
          frassFreshness: diagnosis.frass ? 'fresh' : null,
          larvaPresent: diagnosis.larvaVisible,
          larvalSize: diagnosis.larvalSize,
          moldRotLikeSymptoms: false,
          externalClassification: diagnosis.isInfested
              ? DatabaseCodes.earExternalActive
              : DatabaseCodes.earExternalNegative,
          naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
          evaluatorNotes: notes,
          actorPersonId: actorId,
          evidenceCaptureSessionId: sessionId,
          requiredEvidenceViewTypes: {primaryEvidenceViewType},
        ),
      );
    } else if (isVeV2) {
      final unit = _unitAt(plantPosition);
      await _plantSaves.saveVegetativePlant(
        VegetativePlantSave(
          stationId: station.id,
          plantPosition: plantPosition,
          plantStatus: diagnosis.suggestedPlantStatus,
          assessable: true,
          newestLeavesInspectedCount: 3,
          smallFreshWindowpanes: diagnosis.windowpanes,
          scraping: diagnosis.scraping,
          cuttingOrTearing: diagnosis.cutting,
          freshFrass: diagnosis.frass,
          whorlFeedingSign: diagnosis.whorlFeeding,
          larvaVisible: diagnosis.larvaVisible,
          larvalSize: diagnosis.larvalSize,
          eggMassVisible: false,
          oldDamagePresent:
              diagnosis.suggestedPlantStatus ==
              DatabaseCodes.plantOldDamageOnly,
          possibleNonFawEvidence:
              diagnosis.suggestedPlantStatus ==
              DatabaseCodes.plantPossibleNonFaw,
          uncertainEvidence: false,
          naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
          sourcePlantingUnitObservationId: unit?.id,
          evaluatorNotes: notes,
          actorPersonId: actorId,
          evidenceCaptureSessionId: sessionId,
          requiredEvidenceViewTypes: {primaryEvidenceViewType},
          requireCameraPhaseAEvidence: sessionId != null,
        ),
      );
    } else {
      await _plantSaves.saveVegetativePlant(
        VegetativePlantSave(
          stationId: station.id,
          plantPosition: plantPosition,
          plantStatus: diagnosis.suggestedPlantStatus,
          assessable: true,
          newestLeavesInspectedCount: 3,
          smallFreshWindowpanes: diagnosis.windowpanes,
          scraping: diagnosis.scraping,
          cuttingOrTearing: diagnosis.cutting,
          freshFrass: diagnosis.frass,
          whorlFeedingSign: diagnosis.whorlFeeding,
          larvaVisible: diagnosis.larvaVisible,
          larvalSize: diagnosis.larvalSize,
          eggMassVisible: false,
          oldDamagePresent:
              diagnosis.suggestedPlantStatus ==
              DatabaseCodes.plantOldDamageOnly,
          possibleNonFawEvidence:
              diagnosis.suggestedPlantStatus ==
              DatabaseCodes.plantPossibleNonFaw,
          uncertainEvidence: false,
          naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
          evaluatorNotes: notes,
          actorPersonId: actorId,
          evidenceCaptureSessionId: sessionId,
          requiredEvidenceViewTypes: {primaryEvidenceViewType},
          requireCameraPhaseAEvidence: sessionId != null,
        ),
      );
    }

    if (sessionId != null && _evidence != null) {
      final updatedBundle = await _evidence.repository.loadBundle(sessionId);
      await _evidence.repository.recordPlantEvidenceReview(
        bundle: updatedBundle,
        status: DatabaseCodes.evidenceReviewSufficient,
        actorPersonId: actorId,
      );
    }

    await _loadSnapshot(askForResume: false, preserveState: true);
  }

  /// 1-Tap Quick Action: Overrides the diagnosis/status of a specific plant.
  Future<void> quickOverridePlantStatus({
    required int plantPosition,
    required String status,
    String? notes,
  }) async {
    final isPositive =
        status == DatabaseCodes.plantCurrentPositive ||
        status == DatabaseCodes.reproductiveInfested ||
        status == DatabaseCodes.earExternalActive;
    final isOldDamage = status == DatabaseCodes.plantOldDamageOnly;
    final isNonFaw = status == DatabaseCodes.plantPossibleNonFaw;

    final updatedDiagnosis = isPositive
        ? PlantDiagnosisResult.fawInfested()
        : isOldDamage
        ? PlantDiagnosisResult.oldDamagePlant()
        : isNonFaw
        ? PlantDiagnosisResult.nonFawPlant()
        : PlantDiagnosisResult.cleanPlant;

    _cvDiagnoses = {..._cvDiagnoses, plantPosition: updatedDiagnosis};
    notifyListeners();

    final bundle = bundleForPlant(plantPosition);
    await _autoSavePlantDiagnosis(
      plantPosition: plantPosition,
      diagnosis: updatedDiagnosis,
      sessionId: bundle?.session.id,
      notes: notes,
    );
  }

  /// Field notes do not finalize, replace, or reinterpret an automatic result.
  Future<void> saveDaPlantNotesAndReturn(String? notes) async {
    await saveDaPlantFieldNotes(_stationNumber, notes);
    _setState(Station1ViewState.plantCapture);
  }

  Future<void> saveDaPlantFieldNotes(int number, String? notes) async {
    final details = await loadDaPlantDetails(number);
    final plant = details.plant;
    if (plant == null)
      throw StateError('Capture and process a plant photo first.');
    final db = _plantSaves.database;
    final value = notes?.trim();
    final normalized = value == null || value.isEmpty ? null : value;
    await _perform(() async {
      await db.transaction(() async {
        await (db.update(
          db.plantObservations,
        )..where((p) => p.id.equals(plant.id))).write(
          PlantObservationsCompanion(
            evaluatorNotes: Value(normalized),
            updatedAt: Value(DateTime.now().toUtc()),
            syncState: const Value(DatabaseCodes.queued),
          ),
        );
        await LocalMutationRecorder(db).record(
          entityType: 'plant_observation',
          entityId: plant.id,
          action: 'save_da_field_notes',
          actorPersonId: _assessment!.evaluatorPersonId,
          before: {'evaluator_notes': plant.evaluatorNotes},
          after: {'evaluator_notes': normalized},
        );
      });
      await _loadSnapshot(askForResume: false);
    });
  }

  /// Saves plant diagnosis and notes from the plant inspector and returns cleanly to Station Review.
  Future<void> savePlantDiagnosisAndReturnToReview({
    required int plantPosition,
    required String status,
    String? notes,
  }) async {
    final isPositive =
        status == DatabaseCodes.plantCurrentPositive ||
        status == DatabaseCodes.reproductiveInfested ||
        status == DatabaseCodes.earExternalActive;
    final isOldDamage = status == DatabaseCodes.plantOldDamageOnly;
    final isNonFaw = status == DatabaseCodes.plantPossibleNonFaw;
    final isNotAssessable = status == DatabaseCodes.plantNotAssessable;

    final updatedDiagnosis = isNotAssessable
        ? PlantDiagnosisResult.cleanPlant
        : isPositive
        ? PlantDiagnosisResult.fawInfested()
        : isOldDamage
        ? PlantDiagnosisResult.oldDamagePlant()
        : isNonFaw
        ? PlantDiagnosisResult.nonFawPlant()
        : PlantDiagnosisResult.cleanPlant;

    _cvDiagnoses = {..._cvDiagnoses, plantPosition: updatedDiagnosis};
    notifyListeners();

    final station = _snapshot?.station;
    if (station != null) {
      final actorId = _requireAssessment().evaluatorPersonId;
      final bundle = bundleForPlant(plantPosition);
      final sessionId = bundle?.session.id;

      if (isVtR2) {
        await _stageSaves.saveReproductivePlant(
          ReproductivePlantSave(
            stationId: station.id,
            plantPosition: plantPosition,
            assessable: !isNotAssessable,
            classification: isNotAssessable
                ? DatabaseCodes.reproductiveNotAssessable
                : isPositive
                ? DatabaseCodes.reproductiveInfested
                : DatabaseCodes.reproductiveNotInfested,
            tasselExamined: !isNotAssessable,
            earBaseExamined: !isNotAssessable,
            upperAxilExamined: !isNotAssessable,
            lowerAxilExamined: !isNotAssessable,
            freshFeedingPresent: isPositive,
            frassPresent: isPositive,
            earHuskPenetrationVisible: false,
            larvaPresent: false,
            larvalSize: 'none_seen',
            possibleNonFawEvidence: isNonFaw,
            uncertainEvidence: false,
            naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
            notAssessableReason: isNotAssessable ? 'Cannot assess' : null,
            evaluatorNotes: notes,
            actorPersonId: actorId,
            evidenceCaptureSessionId: sessionId,
            requiredEvidenceViewTypes: {primaryEvidenceViewType},
          ),
        );
      } else if (isR3R6) {
        await _stageSaves.saveExternalEar(
          EarExternalPlantSave(
            stationId: station.id,
            plantPosition: plantPosition,
            earPresent: true,
            externallyAssessable: !isNotAssessable,
            designatedEarIdentity: 'primary_top_ear',
            exteriorEarTipExamined: !isNotAssessable,
            baseShankSilkAxilsExamined: !isNotAssessable,
            externalDamagePresent: isPositive,
            activeInfestationPresent: isPositive,
            silkDamagePresent: false,
            huskDamagePresent: false,
            entryHolePresent: false,
            frassPresent: isPositive,
            frassFreshness: isPositive ? 'fresh' : null,
            larvaPresent: false,
            larvalSize: 'none_seen',
            moldRotLikeSymptoms: false,
            externalClassification: isNotAssessable
                ? DatabaseCodes.earExternalNotAssessable
                : isPositive
                ? DatabaseCodes.earExternalActive
                : DatabaseCodes.earExternalNegative,
            naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
            notAssessableReason: isNotAssessable ? 'Cannot assess' : null,
            evaluatorNotes: notes,
            actorPersonId: actorId,
            evidenceCaptureSessionId: sessionId,
            requiredEvidenceViewTypes: {primaryEvidenceViewType},
          ),
        );
      } else if (isVeV2) {
        final unit = _unitAt(plantPosition);
        await _plantSaves.saveVegetativePlant(
          VegetativePlantSave(
            stationId: station.id,
            plantPosition: plantPosition,
            plantStatus: status,
            assessable: !isNotAssessable,
            notAssessableReason: isNotAssessable ? 'Cannot assess' : null,
            newestLeavesInspectedCount: 3,
            smallFreshWindowpanes: false,
            scraping: false,
            cuttingOrTearing: false,
            freshFrass: isPositive,
            whorlFeedingSign: isPositive,
            larvaVisible: false,
            larvalSize: 'none_seen',
            eggMassVisible: false,
            oldDamagePresent: isOldDamage,
            possibleNonFawEvidence: isNonFaw,
            uncertainEvidence: false,
            naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
            sourcePlantingUnitObservationId: unit?.id,
            evaluatorNotes: notes,
            actorPersonId: actorId,
            evidenceCaptureSessionId: sessionId,
            requiredEvidenceViewTypes: {primaryEvidenceViewType},
            requireCameraPhaseAEvidence: sessionId != null,
          ),
        );
      } else {
        await _plantSaves.saveVegetativePlant(
          VegetativePlantSave(
            stationId: station.id,
            plantPosition: plantPosition,
            plantStatus: status,
            assessable: !isNotAssessable,
            notAssessableReason: isNotAssessable ? 'Cannot assess' : null,
            newestLeavesInspectedCount: 3,
            smallFreshWindowpanes: false,
            scraping: false,
            cuttingOrTearing: false,
            freshFrass: isPositive,
            whorlFeedingSign: isPositive,
            larvaVisible: false,
            larvalSize: 'none_seen',
            eggMassVisible: false,
            oldDamagePresent: isOldDamage,
            possibleNonFawEvidence: isNonFaw,
            uncertainEvidence: false,
            naturalEnemyQuickStatus: DatabaseCodes.naturalEnemyNoneSeen,
            evaluatorNotes: notes,
            actorPersonId: actorId,
            evidenceCaptureSessionId: sessionId,
            requiredEvidenceViewTypes: {primaryEvidenceViewType},
            requireCameraPhaseAEvidence: sessionId != null,
          ),
        );
      }

      if (sessionId != null && _evidence != null) {
        final updatedBundle = await _evidence.repository.loadBundle(sessionId);
        await _evidence.repository.recordPlantEvidenceReview(
          bundle: updatedBundle,
          status: DatabaseCodes.evidenceReviewSufficient,
          actorPersonId: actorId,
        );
      }
    }

    _currentPlantPosition = null;
    _returnToStationReview = false;
    _returnToVeV2Review = false;
    await _loadSnapshot(askForResume: false, preserveState: true);
    _setState(
      isVeV2
          ? Station1ViewState.veV2StationReview
          : Station1ViewState.stationReview,
    );
  }

  void retry() => initialize();

  Future<void> _loadActiveBlock({required bool askForResume}) async {
    _blockSnapshot = await _workflow.loadBlockSnapshot(_requirePrepared());
    await _refreshDaEvidenceNumbers();
    _stationNumber =
        _blockSnapshot!.nextIncompleteStationNumber ?? locationsPerBlock;
    await _loadSnapshot(askForResume: askForResume);
  }

  Future<void> _loadSnapshot({
    required bool askForResume,
    bool preserveState = false,
  }) async {
    final preservedEvidenceSessionId = preserveState
        ? _currentEvidence?.session.id
        : null;
    _blockSnapshot = await _workflow.loadBlockSnapshot(_requirePrepared());
    await _refreshDaEvidenceNumbers();
    _snapshot = _blockSnapshot!.station(_stationNumber);
    final locationStation = _snapshot?.station;
    if (locationStation != null && _evidence != null) {
      final bundles = await _evidence.repository.loadStationBundles(
        locationStation.id,
      );
      for (final bundle in bundles) {
        await _evidence.repository.savePlantLocationFromEvidence(bundle);
      }
      _blockSnapshot = await _workflow.loadBlockSnapshot(_requirePrepared());
      await _refreshDaEvidenceNumbers();
      _snapshot = _blockSnapshot!.station(_stationNumber);
    }

    if (_routes != null) {
      _routePlan = await _routes.loadOrCreateDraft(
        assessment: _requireAssessment(),
        prepared: _requirePrepared(),
      );
      if (isDaGuidedScouting &&
          _routePlan?.isReady != true &&
          _routePlan?.pendingAdjustment == null) {
        _routePlan = await _routes.saveGeneratedPlan(
          ScoutingRouteGenerator.generate(
            draft: _routePlan!,
            boundary: blockBoundary,
            completedStations: _completedStationLocations(),
          ),
          actorPersonId: _requireAssessment().evaluatorPersonId,
        );
      } else if (isDaGuidedScouting &&
          _routePlan?.algorithmVersion !=
              ScoutingSamplingProtocol.daAlgorithm &&
          _routePlan?.pendingAdjustment == null) {
        var fixedThrough = 0;
        for (final snapshot in _blockSnapshot!.stations) {
          if (snapshot.station != null) {
            if (snapshot.stationNumber > fixedThrough) {
              fixedThrough = snapshot.stationNumber;
            }
          }
        }
        _routePlan = await _routes.saveGeneratedPlan(
          ScoutingRouteGenerator.orderDaTargetsForWalk(
            _routePlan!,
            fixedThrough: fixedThrough,
          ),
          actorPersonId: _requireAssessment().evaluatorPersonId,
          recalculated: true,
        );
      } else {
        await _upgradeLegacyRouteIfNeeded();
      }
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
    var station = _snapshot!.station;
    if (station == null &&
        (_routes == null ||
            _routePlan?.arrivalConfirmedStation == _stationNumber)) {
      station = await _workflow.saveStationLocation(
        prepared: _requirePrepared(),
        stationNumber: _stationNumber,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        latitude: null,
        longitude: null,
        gpsAccuracyM: null,
        capturedAt: null,
        notLocatedReason: DatabaseCodes.stationNoCurrentFix,
      );
      _blockSnapshot = await _workflow.loadBlockSnapshot(_requirePrepared());
      await _refreshDaEvidenceNumbers();
      _snapshot = _blockSnapshot!.station(_stationNumber);
    }
    if (station != null && _evidence != null) {
      _stationEvidenceBundles = await _evidence.repository.loadStationBundles(
        station.id,
      );
      _cvDiagnoses = const {};
      for (var position = 1; position <= plantsPerLocation; position++) {
        await _restorePlantDiagnosis(position);
      }
      _stationContextEvidence = _existingStationContext(
        _stationEvidenceBundles,
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
    if (preserveState) {
      // Snapshot refreshes rebuild every evidence bundle from the database.
      // Keep the inspector attached to the same plant session; otherwise an
      // analysis/save refresh makes its already accepted photos appear to
      // vanish until the screen is reopened.
      if (_currentPlantPosition != null) {
        EvidenceCaptureBundle? restored;
        if (preservedEvidenceSessionId != null) {
          for (final bundle in _stationEvidenceBundles) {
            if (bundle.session.id == preservedEvidenceSessionId) {
              restored = bundle;
              break;
            }
          }
        }
        _currentEvidence =
            restored ?? _plantEvidenceBundle(_currentPlantPosition!);
      }
      notifyListeners();
      return;
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
    if (isDaGuidedScouting) return;
    if (repository == null ||
        plan == null ||
        plan.algorithmVersion == scoutingRouteAlgorithmVersion) {
      return;
    }
    final preparation = plan.preparation;
    final hasAutomaticInputs =
        preparation.entrance != null && preparation.rowBearingDegrees != null;
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
      return _stationNumber < locationsPerBlock
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
    if (isVeV2) return _veV2TargetFor(snapshot);
    if (isR3R6 && !isDaGuidedScouting && _lateSeasonSetup == null) {
      return Station1ViewState.lateSeasonSetup;
    }
    if (_evidence == null) {
      if (snapshot.plants.isEmpty) return Station1ViewState.plantSelection;
      if (snapshot.plants.length < plantsPerLocation) {
        _currentPlantPosition = snapshot.nextMissingPlantPosition;
        return Station1ViewState.plantEntry;
      }
      _currentPlantPosition = null;
      return Station1ViewState.stationReview;
    }
    for (var position = 1; position <= plantsPerLocation; position++) {
      if (!_isCaptureSatisfied(snapshot, position)) {
        _currentPlantPosition = position;
        final started = _stationEvidenceBundles.any(
          (bundle) =>
              bundle.session.scopeType == DatabaseCodes.evidenceScopePlant,
        );
        return !isDaGuidedScouting &&
                !started &&
                snapshot.plants.isEmpty &&
                _stationNumber == 1
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
    for (var position = 1; position <= plantsPerLocation; position++) {
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

    // Station Review already holds the authoritative bundle for this plant.
    // Reuse it when entering the inspector; calling ensurePlant with a newer
    // requirements version can otherwise create/select a different empty
    // session and make the accepted photos appear to disappear.
    final existingBundle = _plantEvidenceBundle(position);
    if (existingBundle != null) {
      _currentEvidence = existingBundle;
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

  Future<void> _repairLegacyPlantEvidenceAssociations(
    StationSnapshot snapshot,
  ) async {
    final coordinator = _evidence;
    final station = snapshot.station;
    if (coordinator == null || station == null) return;

    final bundles = [..._stationEvidenceBundles];
    var repairedAny = false;
    for (final item in snapshot.plants) {
      final position = item.plant.sequenceNumber;
      final matches = bundles.where(
        (bundle) =>
            bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
            bundle.session.plantPosition == position,
      );
      if (matches.length != 1) continue;

      final bundle = matches.single;
      if (bundle.session.plantObservationId == item.plant.id) continue;

      final policy = _policyForBundle(bundle);
      final requiredViews = isVtR2 || isR3R6
          ? {primaryEvidenceViewType}
          : policy.requiredViewsForObservation(
              plant: item.plant,
              vegetative: item.vegetative,
            );
      final previousReview = _plantEvidenceReviews[position];
      final reviewCanCarryForward =
          previousReview?.isCurrent == true &&
          previousReview?.status == DatabaseCodes.evidenceReviewSufficient;

      // The repository still verifies station, position, planting-unit link,
      // and required views. This repairs only a stale observation ID; it cannot
      // attach evidence belonging to another plant or station.
      await coordinator.repository.attachPlantEvidenceInCurrentTransaction(
        sessionId: bundle.session.id,
        stationId: station.id,
        plantPosition: position,
        plantObservationId: item.plant.id,
        sourcePlantingUnitObservationId:
            item.plant.sourcePlantingUnitObservationId,
        requiredViewTypes: requiredViews,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        pilotActiveDurationMs: 0,
        manualFormUsed: false,
      );
      final repaired = await coordinator.repository.loadBundle(
        bundle.session.id,
      );
      final index = bundles.indexWhere(
        (candidate) => candidate.session.id == repaired.session.id,
      );
      if (index >= 0) bundles[index] = repaired;
      if (reviewCanCarryForward) {
        await coordinator.repository.recordPlantEvidenceReview(
          bundle: repaired,
          status: DatabaseCodes.evidenceReviewSufficient,
          actorPersonId: _requireAssessment().evaluatorPersonId,
        );
      }
      repairedAny = true;
    }

    if (!repairedAny) return;
    _stationEvidenceBundles = List.unmodifiable(bundles);
    _plantEvidenceReviews = await coordinator.repository
        .loadPlantEvidenceReviews(station.id);
  }

  void _validateReviewEvidence(StationSnapshot snapshot) {
    if (_evidence == null) return;
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
    if (isDaGuidedScouting) return;
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

  EvidenceCaptureBundle? _existingStationContext(
    List<EvidenceCaptureBundle> bundles,
  ) {
    for (final bundle in bundles) {
      if (bundle.session.scopeType ==
          DatabaseCodes.evidenceScopeStationContext) {
        return bundle;
      }
    }
    return null;
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
