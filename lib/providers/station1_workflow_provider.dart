import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/evidence_capture_repository.dart';
import '../data/repositories/station1_workflow_repository.dart';
import '../data/services/atomic_plant_save_service.dart';
import '../services/evidence_capture_coordinator.dart';
import '../services/phone_location_service.dart';

enum Station1ViewState {
  loading,
  boundaryRequired,
  setupRequired,
  safetyBlocked,
  unsupportedStage,
  stageConfirmation,
  largeFieldBlocked,
  blockPreparation,
  resumeCheck,
  routePreparation,
  stationTravel,
  targetAdjustment,
  stationLocation,
  stationContextEvidence,
  plantSelection,
  plantCapture,
  plantEntry,
  stationReview,
  stationComplete,
  betweenStations,
  blockReview,
  betweenBlocks,
  samplingComplete,
  pausedConditions,
  error,
}

enum ResumeCondition { unchanged, rainOrMajorDelay, treatmentOrFieldOperation }

class Station1WorkflowProvider extends ChangeNotifier {
  Station1WorkflowProvider({
    required this.assessmentId,
    required Station1WorkflowRepository workflowRepository,
    required AssessmentRepository assessmentRepository,
    required AtomicPlantSaveService plantSaveService,
    EvidenceCaptureCoordinator? evidenceCoordinator,
  }) : _workflow = workflowRepository,
       _assessments = assessmentRepository,
       _plantSaves = plantSaveService,
       _evidence = evidenceCoordinator;

  final String assessmentId;
  final Station1WorkflowRepository _workflow;
  final AssessmentRepository _assessments;
  final AtomicPlantSaveService _plantSaves;
  final EvidenceCaptureCoordinator? _evidence;

  Station1ViewState _state = Station1ViewState.loading;
  Station1ViewState? _resumeTarget;
  AssessmentRecord? _assessment;
  BoundaryRecord? _boundary;
  PreparedStation1Run? _prepared;
  Station1Snapshot? _snapshot;
  EvidenceCaptureBundle? _stationContextEvidence;
  EvidenceCaptureBundle? _currentEvidence;
  List<EvidenceCaptureBundle> _stationEvidenceBundles = const [];
  PilotWorkloadMetrics _pilotWorkloadMetrics = PilotWorkloadMetrics.empty;
  Map<int, int> _capturedLeavesInspected = const {};
  int? _currentPlantPosition;
  Object? _error;
  bool _isSaving = false;

  Station1ViewState get state => _state;
  AssessmentRecord? get assessment => _assessment;
  BoundaryRecord? get boundary => _boundary;
  PreparedStation1Run? get prepared => _prepared;
  Station1Snapshot? get snapshot => _snapshot;
  int? get currentPlantPosition => _currentPlantPosition;
  EvidenceCaptureBundle? get stationContextEvidence => _stationContextEvidence;
  EvidenceCaptureBundle? get currentEvidence => _currentEvidence;
  List<EvidenceCaptureBundle> get stationEvidenceBundles =>
      _stationEvidenceBundles;
  PilotWorkloadMetrics get pilotWorkloadMetrics => _pilotWorkloadMetrics;
  Object? get error => _error;
  bool get isSaving => _isSaving;
  int get savedPlantCount => _snapshot?.plants.length ?? 0;
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

  Station1PlantRecord? get currentPlant {
    final position = _currentPlantPosition;
    if (position == null) return null;
    for (final item in _snapshot?.plants ?? const <Station1PlantRecord>[]) {
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
      if (assessment.status != DatabaseCodes.inProgress) {
        _setState(Station1ViewState.setupRequired);
        return;
      }

      _boundary = await _workflow.boundaryById(assessment.boundaryVersionId);
      final boundary = _boundary!;
      if (boundary.confirmationStatus != 'user_confirmed') {
        _setState(Station1ViewState.boundaryRequired);
        return;
      }

      if (!_isPilotStage(assessment.growthStage)) {
        _setState(Station1ViewState.unsupportedStage);
        return;
      }
      if (boundary.areaHectares > 1) {
        _setState(Station1ViewState.largeFieldBlocked);
        return;
      }
      if (assessment.growthStageUncertain) {
        _setState(Station1ViewState.stageConfirmation);
        return;
      }

      _prepared = await _workflow.findPreparedRun(assessment.id);
      if (_prepared == null) {
        _setState(Station1ViewState.blockPreparation);
        return;
      }
      await _loadSnapshot(askForResume: true);
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

  Future<void> prepareBlockOne() async {
    final assessment = _requireAssessment();
    final boundary = _boundary;
    if (boundary == null) throw StateError('Field outline is unavailable.');

    await _perform(() async {
      await _ensureAssessmentActive();
      _prepared = await _workflow.prepareBlockOne(assessment, boundary);
      _snapshot = await _workflow.loadSnapshot(_prepared!);
      _setState(Station1ViewState.stationLocation);
    });
  }

  Future<void> saveStationCoordinates(AveragedPhoneLocation location) async {
    await _perform(() async {
      await _ensureAssessmentActive();
      await _workflow.saveStationLocation(
        prepared: _requirePrepared(),
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
      throw StateError('Record the Station 1 location step first.');
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
      );
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<void> recordCurrentPlantInspection(int newestLeavesInspectedCount) {
    final bundle = _currentEvidence;
    if (bundle == null) throw StateError('Plant evidence is unavailable.');
    return _perform(() async {
      await _requireEvidenceCoordinator().recordPlantCaptureInspection(
        session: bundle.session,
        actorPersonId: _requireAssessment().evaluatorPersonId,
        newestLeavesInspectedCount: newestLeavesInspectedCount,
      );
      await _refreshPilotWorkloadMetrics();
    });
  }

  Future<void> saveCaptureNotAssessable({
    required String reason,
    required Duration activeDuration,
  }) async {
    final snapshot = _snapshot;
    final position = _currentPlantPosition;
    final evidence = _currentEvidence;
    if (snapshot?.station == null || position == null || evidence == null) {
      throw StateError('The active plant position is unavailable.');
    }
    await savePlant(
      VegetativePlantSave(
        stationId: snapshot!.station!.id,
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

  Future<void> savePlant(VegetativePlantSave input) async {
    final snapshot = _snapshot;
    if (snapshot?.station == null ||
        input.stationId != snapshot!.station!.id ||
        input.plantPosition != _currentPlantPosition) {
      throw StateError('Plant save does not match the active Station 1 plant.');
    }
    await _perform(() async {
      await _ensureAssessmentActive();
      await _plantSaves.saveVegetativePlant(input);
      await _loadSnapshot(askForResume: false);
    });
  }

  Future<File> resolveEvidenceFile(String localUri) {
    final evidence = _evidence;
    if (evidence == null) {
      throw StateError('Camera evidence is unavailable.');
    }
    return evidence.resolve(localUri);
  }

  Future<void> stageEvidence({
    required String viewType,
    required String sourcePath,
  }) async {
    await _perform(() async {
      await _ensureAssessmentActive();
      final evidence = _requireEvidenceCoordinator();
      final bundle = _requireActiveEvidenceBundle();
      final updated = await evidence.stageCapture(
        session: bundle.session,
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
      _stationContextEvidence = await _requireEvidenceCoordinator().repository
          .loadBundle(bundle.session.id);
      await _loadSnapshot(askForResume: false);
    });
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
    });
  }

  void _validateReviewEvidence(Station1Snapshot snapshot) {
    if (_evidence == null) return;
    final context = _stationEvidenceBundles.where(
      (bundle) =>
          bundle.session.scopeType == DatabaseCodes.evidenceScopeStationContext,
    );
    if (context.isEmpty ||
        !context.first.isViewSatisfied(
          DatabaseCodes.evidenceViewStationContext,
        )) {
      throw StateError(
        'Station context needs an accepted image or documented manual fallback.',
      );
    }
    for (final plant in snapshot.plants) {
      final matches = _stationEvidenceBundles.where(
        (bundle) =>
            bundle.session.scopeType == DatabaseCodes.evidenceScopePlant &&
            bundle.session.plantPosition == plant.plant.sequenceNumber,
      );
      if (matches.isEmpty) {
        throw StateError(
          'Plant ${plant.plant.sequenceNumber} has no evidence capture record.',
        );
      }
      if (!plant.plant.assessable) continue;
      final bundle = matches.first;
      if (!bundle.isViewSatisfied(DatabaseCodes.evidenceViewWhorlOverview)) {
        throw StateError(
          'Plant ${plant.plant.sequenceNumber} needs a whorl overview or documented manual fallback.',
        );
      }
      if (!bundle.isViewSatisfied(DatabaseCodes.evidenceViewCloseUp)) {
        throw StateError(
          'Plant ${plant.plant.sequenceNumber} needs its evidence close-up or documented manual fallback.',
        );
      }
    }
  }

  void retry() => initialize();

  Future<void> _loadSnapshot({required bool askForResume}) async {
    _snapshot = await _workflow.loadSnapshot(_requirePrepared());
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
    if (askForResume && target != Station1ViewState.stationComplete) {
      _resumeTarget = target;
      _setState(Station1ViewState.resumeCheck);
      return;
    }
    _resumeTarget = null;
    _setState(target);
  }

  Station1ViewState _targetFor(Station1Snapshot snapshot) {
    if (snapshot.station == null) return Station1ViewState.stationLocation;
    if (_evidence != null &&
        (_stationContextEvidence?.session.completedAt == null ||
            !(_stationContextEvidence?.isViewSatisfied(
                  DatabaseCodes.evidenceViewStationContext,
                ) ??
                false))) {
      return Station1ViewState.stationContextEvidence;
    }
    if (snapshot.reviewIsCurrent) return Station1ViewState.stationComplete;
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
        final hasStartedPlantCapture = _stationEvidenceBundles.any(
          (bundle) =>
              bundle.session.scopeType == DatabaseCodes.evidenceScopePlant,
        );
        return !hasStartedPlantCapture && snapshot.plants.isEmpty
            ? Station1ViewState.plantSelection
            : Station1ViewState.plantCapture;
      }
    }
    _currentPlantPosition = null;
    return Station1ViewState.stationReview;
  }

  bool _isCaptureSatisfied(Station1Snapshot snapshot, int position) {
    Station1PlantRecord? saved;
    for (final plant in snapshot.plants) {
      if (plant.plant.sequenceNumber == position) {
        saved = plant;
        break;
      }
    }
    if (saved != null && !saved.plant.assessable) return true;
    EvidenceCaptureBundle? bundle;
    for (final candidate in _stationEvidenceBundles) {
      if (candidate.session.scopeType == DatabaseCodes.evidenceScopePlant &&
          candidate.session.plantPosition == position) {
        bundle = candidate;
        break;
      }
    }
    if (bundle == null || bundle.session.completedAt == null) return false;
    return bundle.isViewSatisfied(DatabaseCodes.evidenceViewWhorlOverview) &&
        bundle.isViewSatisfied(DatabaseCodes.evidenceViewCloseUp);
  }

  Future<void> _loadCurrentEvidence() async {
    final evidence = _evidence;
    final position = _currentPlantPosition;
    final station = _snapshot?.station;
    if (evidence == null || position == null || station == null) {
      _currentEvidence = null;
      return;
    }
    _currentEvidence = await evidence.ensurePlant(
      assessmentId: assessmentId,
      stationId: station.id,
      plantPosition: position,
      actorPersonId: _requireAssessment().evaluatorPersonId,
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
    final evidence = _evidence;
    final stationId = _snapshot?.station?.id;
    if (evidence == null || stationId == null) return;
    _pilotWorkloadMetrics = await evidence.loadPilotWorkloadMetrics(stationId);
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

  PreparedStation1Run _requirePrepared() {
    final value = _prepared;
    if (value == null) throw StateError('Block 1 is not prepared.');
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
