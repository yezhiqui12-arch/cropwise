import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/field_repository.dart';

class FieldWorkspaceProvider extends ChangeNotifier {
  FieldWorkspaceProvider(this._repository) {
    _initialize();
  }

  final FieldRepository _repository;
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

    final selectionStillExists = workspaces.any(
      (workspace) => workspace.field.id == _activeFieldId,
    );
    if (!selectionStillExists) {
      _activeFieldId = workspaces.isEmpty ? null : workspaces.first.field.id;
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
    unawaited(
      _repository.savePreferredFieldId(fieldId).catchError((Object error) {
        _error = error;
        notifyListeners();
      }),
    );
  }

  Future<void> createField({
    required String name,
    required double estimatedAreaHectares,
    String? barangay,
    String? municipalityCity,
    String? province,
    String? locationDescription,
    String? varietyName,
    String? intendedUse,
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
        locationDescription: _nullIfBlank(locationDescription),
        varietyName: _nullIfBlank(varietyName),
        intendedUse: _nullIfBlank(intendedUse),
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
            'User confirmed as a WormWise scouting boundary; not a cadastral survey.',
      );
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
