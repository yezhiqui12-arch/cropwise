import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/field_repository.dart';
import '../services/field_retention_service.dart';

class FieldWorkspaceProvider extends ChangeNotifier {
  FieldWorkspaceProvider(
    this._repository, {
    FieldRetentionService? retentionService,
  }) : _retention = retentionService ?? FieldRetentionService(_repository) {
    _initialize();
  }

  /// A route-local field/cycle snapshot. Does not change saved field selection
  /// or run retention cleanup while resuming a historical assessment.
  FieldWorkspaceProvider.forAssessment(
    this._repository,
    FieldWorkspaceRecord workspace,
  ) : _retention = FieldRetentionService(_repository) {
    _workspaces = [workspace];
    _activeFieldId = workspace.field.id;
    _isLoading = false;
  }
  final FieldRepository _repository;
  final FieldRetentionService _retention;
  StreamSubscription<List<FieldWorkspaceRecord>>? _subscription;

  List<FieldWorkspaceRecord> _workspaces = const [];
  String? _activeFieldId;
  Object? _error;
  bool _isLoading = true;
  bool _isSaving = false;

  List<FieldWorkspaceRecord> get workspaces => _workspaces;
  String? get activeFieldId => _activeFieldId;
  Object? get error => _error;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;

  FieldWorkspaceRecord? get activeWorkspace {
    final activeId = _activeFieldId;
    if (activeId == null) return null;

    for (final workspace in _workspaces) {
      if (workspace.field.id == activeId) return workspace;
    }
    return null;
  }

  Future<void> _initialize() async {
    try {
      try {
        await _retention.purgeExpired();
      } catch (_) {
        // A failed cleanup must not prevent the farmer from opening saved
        // fields. The expired item remains queued and is retried next launch.
      }
      _activeFieldId = await _repository.readPreferredFieldId();
      _subscription = _repository.watchFieldWorkspaces().listen(
        _handleWorkspaces,
        onError: _handleError,
      );
    } catch (error, stackTrace) {
      _handleError(error, stackTrace);
    }
  }

  void _handleWorkspaces(List<FieldWorkspaceRecord> workspaces) {
    _workspaces = workspaces;
    _isLoading = false;
    _error = null;

    final previousSelection = _activeFieldId;
    final selectionStillExists = workspaces.any(
      (workspace) => workspace.field.id == _activeFieldId,
    );
    if (!selectionStillExists) {
      _activeFieldId = workspaces.isEmpty ? null : workspaces.first.field.id;
      if (_activeFieldId != previousSelection) {
        if (_activeFieldId == null) {
          unawaited(_persistClearedSelection());
        } else {
          unawaited(_persistSelection(_activeFieldId!));
        }
      }
    }
    notifyListeners();
  }

  void _handleError(Object error, StackTrace stackTrace) {
    _error = error;
    _isLoading = false;
    notifyListeners();
  }

  void selectField(String fieldId) {
    if (_activeFieldId == fieldId) return;
    if (!_workspaces.any((workspace) => workspace.field.id == fieldId)) {
      throw ArgumentError.value(fieldId, 'fieldId', 'Field does not exist');
    }
    _activeFieldId = fieldId;
    notifyListeners();
    unawaited(_persistSelection(fieldId));
  }

  Future<void> _persistSelection(String fieldId) async {
    try {
      await _repository.savePreferredFieldId(fieldId);
    } catch (error) {
      _error = error;
      notifyListeners();
    }
  }

  Future<void> _persistClearedSelection() async {
    try {
      await _repository.clearPreferredFieldId();
    } catch (error) {
      _error = error;
      notifyListeners();
    }
  }

  Future<void> createField({
    required String name,
    double? estimatedAreaHectares,
    String? barangay,
    String? municipalityCity,
    String? province,
    String? varietyName,
    DateTime? plantingDate,
    String? waterRegime,
    double? entranceLatitude,
    double? entranceLongitude,
    double? entranceAverageAccuracyM,
    double? entranceWorstAccuracyM,
    String? entranceConfidenceCode,
  }) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final hasEntrance = entranceLatitude != null && entranceLongitude != null;
      final created = await _repository.createFieldWithBoundaryAndCycle(
        name: name.trim(),
        geometryGeojson: '{"type":"Polygon","coordinates":[]}',
        areaHectares: estimatedAreaHectares,
        boundarySourceMethod: hasEntrance
            ? 'entrance_gps'
            : 'reported_area_only',
        boundaryConfirmationStatus: hasEntrance
            ? 'location_only'
            : 'location_pending',
        centroidLatitude: entranceLatitude,
        centroidLongitude: entranceLongitude,
        averageAccuracyM: entranceAverageAccuracyM,
        worstAccuracyM: entranceWorstAccuracyM,
        confidenceCode: entranceConfidenceCode,
        boundaryNotes: hasEntrance
            ? 'Field entrance recorded using phone GNSS. The reported area is '
                  'not a surveyed or satellite-derived boundary.'
            : 'Farmer-reported area only. Entrance GPS and outline were not recorded.',
        barangay: _nullIfBlank(barangay),
        municipalityCity: _nullIfBlank(municipalityCity),
        province: _nullIfBlank(province),
        varietyName: _nullIfBlank(varietyName),
        plantingDate: plantingDate,
        plantingDatePrecision: plantingDate == null ? 'unknown' : 'exact_day',
        waterRegime: _nullIfBlank(waterRegime),
      );
      _activeFieldId = created.field.id;
      final createdWorkspace = FieldWorkspaceRecord(
        field: created.field,
        boundary: created.boundary,
        cropCycle: created.cropCycle,
      );
      _workspaces = [
        ..._workspaces.where(
          (workspace) => workspace.field.id != created.field.id,
        ),
        createdWorkspace,
      ]..sort((first, second) => first.field.name.compareTo(second.field.name));
      await _repository.savePreferredFieldId(created.field.id);
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> confirmDrawnBoundary({
    required String geometryGeoJson,
    required double areaHectares,
    required double perimeterMeters,
    required double centroidLatitude,
    required double centroidLongitude,
    required String sourceMethod,
    double? averageAccuracyM,
    double? worstAccuracyM,
    String? confidenceCode,
  }) async {
    final fieldId = activeFieldId;
    if (fieldId == null) {
      throw StateError('Select a field before confirming its boundary.');
    }

    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      await _repository.addBoundaryVersion(
        fieldId: fieldId,
        geometryGeojson: geometryGeoJson,
        areaHectares: areaHectares,
        sourceMethod: sourceMethod,
        centroidLatitude: centroidLatitude,
        centroidLongitude: centroidLongitude,
        averageAccuracyM: averageAccuracyM,
        worstAccuracyM: worstAccuracyM,
        confidenceCode: confidenceCode,
        notes:
            'Calculated perimeter: ${perimeterMeters.toStringAsFixed(2)} m. '
            'User confirmed as a Cropwise scouting boundary; not a cadastral survey.',
      );
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> updateFieldDetails({
    required String fieldId,
    required String name,
    double? areaHectares,
    String? barangay,
    String? varietyName,
    DateTime? plantingDate,
  }) async {
    final workspace = _workspaces
        .where((item) => item.field.id == fieldId)
        .firstOrNull;
    if (workspace == null) {
      throw ArgumentError.value(fieldId, 'fieldId', 'Field does not exist');
    }
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      final boundary = workspace.boundary;
      if (boundary == null && areaHectares != null) {
        await _repository.addBoundaryVersion(
          fieldId: fieldId,
          geometryGeojson: '{"type":"Polygon","coordinates":[]}',
          areaHectares: areaHectares,
          sourceMethod: 'reported_area_only',
          confirmationStatus: 'location_pending',
          notes: 'Farmer-reported estimate; boundary has not been drawn.',
        );
      }
      if (!workspace.hasApproximateOutline &&
          boundary != null &&
          areaHectares != null) {
        final areaChanged =
            (boundary.areaHectares - areaHectares).abs() > 0.000001;
        if (areaChanged) {
          await _repository.addBoundaryVersion(
            fieldId: fieldId,
            geometryGeojson: boundary.geometryGeojson,
            areaHectares: areaHectares,
            sourceMethod: boundary.sourceMethod,
            centroidLatitude: boundary.centroidLatitude,
            centroidLongitude: boundary.centroidLongitude,
            averageAccuracyM: boundary.averageAccuracyM,
            worstAccuracyM: boundary.worstAccuracyM,
            confidenceCode: boundary.confidenceCode,
            confirmationStatus: boundary.confirmationStatus,
            notes: 'Farmer-reported area updated; confirmed location retained.',
          );
        }
      }
      await _repository.updateFieldDetails(
        fieldId: fieldId,
        name: name,
        barangay: _nullIfBlank(barangay),
        varietyName: _nullIfBlank(varietyName),
        plantingDate: plantingDate,
      );
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> renameField(String fieldId, String name) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.renameField(fieldId: fieldId, name: name);
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> archiveField(String fieldId) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      final alternatives = _workspaces
          .where((workspace) => workspace.field.id != fieldId)
          .toList(growable: false);
      await _repository.setFieldArchived(fieldId: fieldId, archived: true);
      if (_activeFieldId == fieldId) {
        _activeFieldId = alternatives.isEmpty
            ? null
            : alternatives.first.field.id;
        if (_activeFieldId == null) {
          await _repository.clearPreferredFieldId();
        } else {
          await _repository.savePreferredFieldId(_activeFieldId!);
        }
      }
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> deleteField(String fieldId) => archiveField(fieldId);

  Future<void> restoreField(String fieldId) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.setFieldArchived(fieldId: fieldId, archived: false);
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
