import '../services/scouting_sampling_protocol.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/field_repository.dart';
import '../data/repositories/people_repository.dart';
import '../services/assessment_protocol_selector.dart';
import '../services/treatment_entry_safety.dart';

class AssessmentWorkspaceProvider extends ChangeNotifier {
  AssessmentWorkspaceProvider(this._assessments, this._people);

  /// Watch the requested assessment by ID, including older crop cycles. This
  /// provider is route-local and never selects a different open assessment.
  AssessmentWorkspaceProvider.forAssessment(
    this._assessments,
    this._people,
    FieldWorkspaceRecord workspace,
    AssessmentRecord assessment,
  ) {
    if (workspace.cropCycle?.id != assessment.cropCycleId ||
        workspace.boundary?.id != assessment.boundaryVersionId) {
      throw ArgumentError(
        'Assessment context does not match the selected record.',
      );
    }
    _fieldWorkspace = workspace;
    _currentAssessment = assessment;
    _subscription = _assessments
        .watchAssessmentById(assessment.id)
        .listen(_handleAssessment, onError: _handleError);
  }
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
    TreatmentEntrySafety? treatment,
  }) async {
    if (_currentAssessment != null) {
      throw StateError(
        'This field already has an unfinished assessment. Resume it instead.',
      );
    }
    final workspace = _fieldWorkspace;
    final cropCycle = workspace?.cropCycle;
    final boundary = workspace?.boundary;
    if (workspace == null || cropCycle == null) {
      throw StateError('The selected field is missing its local crop record.');
    }
    if (boundary == null || !workspace.hasApproximateOutline) {
      throw StateError(
        'Complete and confirm the approximate field outline before setting up an assessment.',
      );
    }

    _setSaving(true);
    try {
      final evaluator = await _people.findOrCreateEvaluator(evaluatorName);
      final draft = await _assessments.createDraft(
        cropCycleId: cropCycle.id,
        boundaryVersionId: boundary.id,
        evaluatorPersonId: evaluator.id,
        assessmentMode: assessmentMode,
        scoutingPattern: ScoutingSamplingProtocol.daPattern,
        patternReason: patternReason,
        growthStage: growthStage,
        growthStageUncertain: growthStageUncertain,
        growthStageBestEstimate: growthStageUncertain ? growthStage : null,
        protocolVersion: ScoutingSamplingProtocol.daVersion,
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
        treatment: treatment,
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
    TreatmentEntrySafety? treatment,
    String? weatherContext,
  }) async {
    final assessment = _currentAssessment;
    if (assessment == null) {
      throw StateError('There is no assessment awaiting a safety check.');
    }
    final workspace = _fieldWorkspace;
    if (workspace?.boundary == null || !workspace!.hasApproximateOutline) {
      throw StateError(
        'Complete and confirm the approximate field outline before continuing this assessment.',
      );
    }
    if (assessment.status == DatabaseCodes.inProgress) return assessment;

    _setSaving(true);
    try {
      if (weatherContext != null) {
        await _assessments.updateWeatherContext(
          assessmentId: assessment.id,
          weatherContext: weatherContext,
        );
      }
      await _recordSafetyAndStartWhenAllowed(
        assessment: assessment,
        safetyStatus: safetyStatus,
        safetySource: safetySource,
        safetyNotes: safetyNotes,
        safetyInputsVerified: safetyInputsVerified,
        treatment: treatment,
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

  Future<AssessmentRecord> correctGrowthStage(String growthStage) async {
    final assessment = _currentAssessment;
    if (assessment == null) {
      throw StateError('There is no assessment to correct.');
    }
    _setSaving(true);
    try {
      _currentAssessment = await _assessments
          .correctGrowthStageBeforeObservations(
            assessmentId: assessment.id,
            growthStage: growthStage,
            assessmentMode: AssessmentProtocolSelector.assessmentModeFor(
              growthStage,
            ),
            scoutingPattern:
                ScoutingSamplingProtocol.isDa(assessment.protocolVersion)
                ? ScoutingSamplingProtocol.daPattern
                : AssessmentProtocolSelector.recommendedPatternFor(growthStage),
          );
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
    TreatmentEntrySafety? treatment,
  }) async {
    final resolvedStatus = treatment?.statusAt(DateTime.now()) ?? safetyStatus;
    await _assessments.recordSafetyCheck(
      assessmentId: assessment.id,
      checkedByPersonId: assessment.evaluatorPersonId,
      resultStatus: resolvedStatus,
      applicationEndAtUsed: treatment?.applicationEndedAt,
      reiTextUsed: treatment?.reentryText,
      reiSource: treatment?.source ?? safetySource,
      calculatedSafeEntryAt: treatment?.safeEntryAt,
      // Selecting a source records provenance, but is not independent verification.
      calculationInputsVerified: treatment == null && safetyInputsVerified,
      notes: treatment?.safetyNote ?? safetyNotes,
    );
    if (resolvedStatus == DatabaseCodes.noRecentTreatment ||
        resolvedStatus == DatabaseCodes.safeIntervalCompleted) {
      if (DatabaseCodes.isGrowthStageImplemented(assessment.growthStage)) {
        await _assessments.startAssessment(assessment.id);
      }
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
