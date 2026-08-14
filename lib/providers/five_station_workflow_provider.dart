import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/evidence_capture_repository.dart';
import '../data/repositories/scouting_workflow_repository.dart';
import '../data/services/atomic_plant_save_service.dart';
import '../data/services/five_station_completion_service.dart';
import '../services/evidence_capture_coordinator.dart';
import '../services/phone_location_service.dart';
import '../services/station_evidence_policy.dart';
import 'station1_workflow_provider.dart';

/// Coordinates Increment A across every existing required block.
///
/// Route generation is deliberately absent. Between-station states explicitly
/// disclose that field-orientation guidance remains unavailable until
/// Increment B.
class FiveStationWorkflowProvider extends ChangeNotifier {
  FiveStationWorkflowProvider({
    required this.assessmentId,
    required ScoutingWorkflowRepository workflowRepository,
    required AssessmentRepository assessmentRepository,
    required AtomicPlantSaveService plantSaveService,
    required FiveStationCompletionService completionService,
    EvidenceCaptureCoordinator? evidenceCoordinator,
    this.testMode = false,
    this.debugFeaturesEnabled = kDebugMode,
  }) : _workflow = workflowRepository,
       _assessments = assessmentRepository,
       _plantSaves = plantSaveService,
       _completion = completionService,
       _evidence = evidenceCoordinator;

  final String assessmentId;
  final ScoutingWorkflowRepository _workflow;
  final AssessmentRepository _assessments;
  final AtomicPlantSaveService _plantSaves;
  final FiveStationCompletionService _completion;
  final EvidenceCaptureCoordinator? _evidence;
  final bool testMode;
  final bool debugFeaturesEnabled;

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
  int? _currentPlantPosition;
  Object? _error;
  bool _isSaving = false;
  bool _returnToBlockReview = false;

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
  int get savedPlantCount => _snapshot?.plants.length ?? 0;
  bool get canNavigateBackWithinWorkflow => switch (_state) {
    Station1ViewState.plantEntry ||
    Station1ViewState.plantCapture ||
    Station1ViewState.stationReview ||
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
      await _loadSnapshot(askForResume: false);
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
        requiredViewTypes: _policyForBundle(
          bundle,
        ).captureCompletionViews(bundle),
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
  /// the system and app-bar Back actions inside that route until the evaluator
  /// reaches a genuine exit point.
  Future<void> navigateBackWithinWorkflow() async {
    if (_isSaving) return;
    switch (_state) {
      case Station1ViewState.plantEntry:
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
      case Station1ViewState.betweenStations:
        _currentPlantPosition = null;
        _setState(Station1ViewState.stationReview);
        return;
      case Station1ViewState.blockReview:
        _stationNumber = 5;
        _snapshot = _blockSnapshot?.station(_stationNumber);
        _currentPlantPosition = null;
        _returnToBlockReview = true;
        _setState(Station1ViewState.stationReview);
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

  Future<void> openStationFromBlockReview(int stationNumber) async {
    if (stationNumber < 1 || stationNumber > 5) {
      throw ArgumentError.value(stationNumber, 'stationNumber', 'Must be 1-5');
    }
    _stationNumber = stationNumber;
    _returnToBlockReview = true;
    await _loadSnapshot(askForResume: false);
    _currentPlantPosition = null;
    _setState(Station1ViewState.stationReview);
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
      final updated = await _requireEvidenceCoordinator().stageCapture(
        session: _requireActiveEvidenceBundle().session,
        viewType: viewType,
        sourcePath: sourcePath,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      _replaceEvidenceBundle(updated);
      await _refreshPilotWorkloadMetrics();
    });
  }

  Future<void> acceptEvidence(EvidenceMediaRecord media) async {
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

  void retry() => initialize();

  Future<void> _loadActiveBlock({required bool askForResume}) async {
    _blockSnapshot = await _workflow.loadBlockSnapshot(_requirePrepared());
    _stationNumber = _blockSnapshot!.nextIncompleteStationNumber ?? 5;
    await _loadSnapshot(askForResume: askForResume);
  }

  Future<void> _loadSnapshot({required bool askForResume}) async {
    _blockSnapshot = await _workflow.loadBlockSnapshot(_requirePrepared());
    _snapshot = _blockSnapshot!.station(_stationNumber);
    _stationContextEvidence = null;
    _currentEvidence = null;
    _stationEvidenceBundles = const [];
    _plantEvidenceReviews = const {};
    _pilotWorkloadMetrics = PilotWorkloadMetrics.empty;
    _capturedLeavesInspected = const {};
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
    final target = _targetFor(_snapshot!);
    if (target == Station1ViewState.plantEntry ||
        target == Station1ViewState.plantCapture) {
      await _loadCurrentEvidence();
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

  Station1ViewState _targetFor(StationSnapshot snapshot) {
    if (snapshot.station == null) return Station1ViewState.stationLocation;
    if (_evidence != null &&
        (_stationContextEvidence?.session.completedAt == null ||
            !(_stationContextEvidence?.isViewSatisfied(
                  DatabaseCodes.evidenceViewStationContext,
                ) ??
                false))) {
      return Station1ViewState.stationContextEvidence;
    }
    if (snapshot.reviewIsCurrent) {
      return _stationNumber < 5
          ? Station1ViewState.betweenStations
          : Station1ViewState.blockReview;
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
        return !started && snapshot.plants.isEmpty
            ? Station1ViewState.plantSelection
            : Station1ViewState.plantCapture;
      }
    }
    _currentPlantPosition = null;
    return Station1ViewState.stationReview;
  }

  bool _isCaptureSatisfied(StationSnapshot snapshot, int position) {
    StationPlantRecord? saved;
    for (final item in snapshot.plants) {
      if (item.plant.sequenceNumber == position) saved = item;
    }
    if (saved != null && !saved.plant.assessable) return true;
    final matches = _stationEvidenceBundles.where(
      (bundle) =>
          bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
          bundle.session.plantPosition == position,
    );
    if (matches.isEmpty || matches.first.session.completedAt == null) {
      return false;
    }
    return _policyForBundle(matches.first)
        .captureCompletionViews(matches.first)
        .every(matches.first.isViewSatisfied);
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
      requirementsVersion: evidencePolicy.requirementsVersion,
    );
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
      if (item.plant.assessable &&
          sessionPolicy ==
              StationEvidencePolicy.cameraFirstOverviewConditional) {
        final review = _plantEvidenceReviews[item.plant.sequenceNumber];
        if (review == null ||
            !review.isCurrent ||
            review.status != DatabaseCodes.evidenceReviewSufficient) {
          throw StateError(
            'Plant ${item.plant.sequenceNumber} evidence must be reviewed and sufficient before station completion.',
          );
        }
      }
    }
  }

  int _firstIncompleteRunIndex() {
    final index = _preparedRuns.indexWhere(
      (item) => item.run.status != DatabaseCodes.completed,
    );
    return index < 0 ? _preparedRuns.length - 1 : index;
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
    final value = _state == Station1ViewState.stationContextEvidence
        ? _stationContextEvidence
        : _currentEvidence;
    if (value == null) throw StateError('Evidence capture is unavailable.');
    return value;
  }

  void _replaceEvidenceBundle(EvidenceCaptureBundle value) {
    if (value.session.scopeType == DatabaseCodes.evidenceScopeStationContext) {
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

  bool _isPilotStage(String value) => value == 'v3_v6' || value == 'v7_v12';

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
