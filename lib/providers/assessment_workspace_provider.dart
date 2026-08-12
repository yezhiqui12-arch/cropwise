import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/field_repository.dart';
import '../data/repositories/people_repository.dart';

class AssessmentWorkspaceProvider extends ChangeNotifier {
  AssessmentWorkspaceProvider(this._assessments, this._people);

  final AssessmentRepository _assessments;
  final PeopleRepository _people;
  StreamSubscription<AssessmentRecord?>? _subscription;

  FieldWorkspaceRecord? _fieldWorkspace;
  AssessmentRecord? _currentAssessment;
  Object? _error;
  bool _isLoading = false;
  bool _isSaving = false;

  FieldWorkspaceRecord? get fieldWorkspace => _fieldWorkspace;
  AssessmentRecord? get currentAssessment => _currentAssessment;
  Object? get error => _error;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get hasOpenAssessment => _currentAssessment != null;
  bool get isInProgress =>
      _currentAssessment?.status == DatabaseCodes.inProgress;
  bool get isSafetyBlocked =>
      _currentAssessment?.status == DatabaseCodes.safetyBlocked;

  void bindFieldWorkspace(FieldWorkspaceRecord? workspace) {
    final previousCycleId = _fieldWorkspace?.cropCycle?.id;
    final nextCycleId = workspace?.cropCycle?.id;
    final spatialReferenceChanged =
        _fieldWorkspace?.boundary?.id != workspace?.boundary?.id;
    _fieldWorkspace = workspace;

    if (previousCycleId == nextCycleId) {
      if (spatialReferenceChanged) {
        scheduleMicrotask(notifyListeners);
      }
      return;
    }

    unawaited(_subscription?.cancel());
    _subscription = null;
    _currentAssessment = null;
    _error = null;

    if (nextCycleId == null) {
      _isLoading = false;
      scheduleMicrotask(notifyListeners);
      return;
    }

    _isLoading = true;
    scheduleMicrotask(notifyListeners);
    _subscription = _assessments
        .watchOpenAssessmentForCropCycle(nextCycleId)
        .listen(_handleAssessment, onError: _handleError);
  }

  Future<AssessmentRecord> createAssessment({
    required String evaluatorName,
    required String assessmentMode,
    required String scoutingPattern,
    required String growthStage,
    required String safetyStatus,
    required String interventionHistoryStatus,
    required String preferredLanguage,
    bool growthStageUncertain = false,
    String? patternReason,
    String? weatherContext,
    String? safetySource,
    String? safetyNotes,
    bool safetyInputsVerified = false,
  }) async {
    if (_currentAssessment != null) {
      throw StateError(
        'This field already has an unfinished assessment. Resume it instead.',
      );
    }
    final workspace = _fieldWorkspace;
    final cropCycle = workspace?.cropCycle;
    final boundary = workspace?.boundary;
    if (workspace == null || cropCycle == null || boundary == null) {
      throw StateError('The selected field is missing its local crop record.');
    }

    _setSaving(true);
    try {
      final evaluator = await _people.findOrCreateEvaluator(evaluatorName);
      final draft = await _assessments.createDraft(
        cropCycleId: cropCycle.id,
        boundaryVersionId: boundary.id,
        evaluatorPersonId: evaluator.id,
        assessmentMode: assessmentMode,
        scoutingPattern: scoutingPattern,
        patternReason: patternReason,
        growthStage: growthStage,
        growthStageUncertain: growthStageUncertain,
        growthStageBestEstimate: growthStageUncertain ? growthStage : null,
        protocolVersion: 'wormwise-maize-faw-2026.1-draft',
        formulaVersion: '1.0-draft',
        interventionHistoryStatus: interventionHistoryStatus,
        preferredLanguage: preferredLanguage,
        weatherContext: weatherContext,
        localUtcOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
      );
      await _recordSafetyAndStartWhenAllowed(
        assessment: draft,
        safetyStatus: safetyStatus,
        safetySource: safetySource,
        safetyNotes: safetyNotes,
        safetyInputsVerified: safetyInputsVerified,
      );
      _currentAssessment = await _assessments.assessmentById(draft.id);
      return _currentAssessment!;
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _setSaving(false);
    }
  }

  Future<AssessmentRecord> recheckSafety({
    required String safetyStatus,
    String? safetySource,
    String? safetyNotes,
    bool safetyInputsVerified = false,
  }) async {
    final assessment = _currentAssessment;
    if (assessment == null) {
      throw StateError('There is no assessment awaiting a safety check.');
    }
    if (assessment.status == DatabaseCodes.inProgress) return assessment;

    _setSaving(true);
    try {
      await _recordSafetyAndStartWhenAllowed(
        assessment: assessment,
        safetyStatus: safetyStatus,
        safetySource: safetySource,
        safetyNotes: safetyNotes,
        safetyInputsVerified: safetyInputsVerified,
      );
      _currentAssessment = await _assessments.assessmentById(assessment.id);
      return _currentAssessment!;
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _setSaving(false);
    }
  }

  Future<void> _recordSafetyAndStartWhenAllowed({
    required AssessmentRecord assessment,
    required String safetyStatus,
    required bool safetyInputsVerified,
    String? safetySource,
    String? safetyNotes,
  }) async {
    await _assessments.recordSafetyCheck(
      assessmentId: assessment.id,
      checkedByPersonId: assessment.evaluatorPersonId,
      resultStatus: safetyStatus,
      reiSource: safetySource,
      calculationInputsVerified: safetyInputsVerified,
      notes: safetyNotes,
    );
    if (safetyStatus == DatabaseCodes.noRecentTreatment ||
        safetyStatus == DatabaseCodes.safeIntervalCompleted) {
      await _assessments.startAssessment(assessment.id);
    }
  }

  void _handleAssessment(AssessmentRecord? assessment) {
    _currentAssessment = assessment;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  void _handleError(Object error, StackTrace stackTrace) {
    _error = error;
    _isLoading = false;
    notifyListeners();
  }

  void _setSaving(bool value) {
    _isSaving = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
