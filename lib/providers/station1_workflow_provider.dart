import 'package:flutter/foundation.dart';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/station1_workflow_repository.dart';
import '../data/services/atomic_plant_save_service.dart';
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
  stationLocation,
  plantSelection,
  plantEntry,
  stationReview,
  stationComplete,
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
  }) : _workflow = workflowRepository,
       _assessments = assessmentRepository,
       _plantSaves = plantSaveService;

  final String assessmentId;
  final Station1WorkflowRepository _workflow;
  final AssessmentRepository _assessments;
  final AtomicPlantSaveService _plantSaves;

  Station1ViewState _state = Station1ViewState.loading;
  Station1ViewState? _resumeTarget;
  AssessmentRecord? _assessment;
  BoundaryRecord? _boundary;
  PreparedStation1Run? _prepared;
  Station1Snapshot? _snapshot;
  int? _currentPlantPosition;
  Object? _error;
  bool _isSaving = false;

  Station1ViewState get state => _state;
  AssessmentRecord? get assessment => _assessment;
  BoundaryRecord? get boundary => _boundary;
  PreparedStation1Run? get prepared => _prepared;
  Station1Snapshot? get snapshot => _snapshot;
  int? get currentPlantPosition => _currentPlantPosition;
  Object? get error => _error;
  bool get isSaving => _isSaving;
  int get savedPlantCount => _snapshot?.plants.length ?? 0;

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

  void beginTenConsecutivePlants() {
    final snapshot = _snapshot;
    if (snapshot?.station == null) {
      throw StateError('Record the Station 1 location step first.');
    }
    _currentPlantPosition = snapshot!.nextMissingPlantPosition;
    _setState(Station1ViewState.plantEntry);
  }

  void editPlant(int position) {
    if (position < 1 || position > 10) {
      throw ArgumentError.value(position, 'position', 'Must be 1-10');
    }
    _currentPlantPosition = position;
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
      await _workflow.confirmStationReview(
        snapshot: snapshot,
        actorPersonId: _requireAssessment().evaluatorPersonId,
      );
      await _loadSnapshot(askForResume: false);
    });
  }

  void retry() => initialize();

  Future<void> _loadSnapshot({required bool askForResume}) async {
    _snapshot = await _workflow.loadSnapshot(_requirePrepared());
    final target = _targetFor(_snapshot!);
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
    if (snapshot.reviewIsCurrent) return Station1ViewState.stationComplete;
    if (snapshot.plants.isEmpty) return Station1ViewState.plantSelection;
    if (snapshot.plants.length < 10) {
      _currentPlantPosition = snapshot.nextMissingPlantPosition;
      return Station1ViewState.plantEntry;
    }
    _currentPlantPosition = null;
    return Station1ViewState.stationReview;
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
