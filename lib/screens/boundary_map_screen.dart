import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/repositories/field_repository.dart';
import '../providers/field_workspace_provider.dart';
import '../services/phone_location_service.dart';
import '../services/polygon_calculator.dart';
import '../services/walk_boundary_recorder.dart';
import '../theme/app_colors.dart';
import 'fields_screen.dart';

class FieldBoundarySetupScreen extends StatelessWidget {
  const FieldBoundarySetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Boundary'),
        actions: [
          TextButton(
            key: const Key('finish_boundary_setup_button'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const _BoundaryManagementBody(),
    );
  }
}

class BoundaryMapScreen extends StatelessWidget {
  const BoundaryMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldWorkspaceProvider>();

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final workspace = provider.activeWorkspace;
    if (workspace == null) {
      return _NoActiveField(
        onOpenFields: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FieldsScreen()),
        ),
      );
    }

    return _FieldMapOverview(
      key: ValueKey('${workspace.field.id}:${workspace.boundary?.id}:overview'),
      workspace: workspace,
    );
  }
}

class ManageFieldBoundaryScreen extends StatelessWidget {
  const ManageFieldBoundaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Field Boundary')),
      body: const _BoundaryManagementBody(),
    );
  }
}

class _BoundaryManagementBody extends StatelessWidget {
  const _BoundaryManagementBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldWorkspaceProvider>();
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final workspace = provider.activeWorkspace;
    if (workspace == null) {
      return _NoActiveField(
        onOpenFields: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FieldsScreen()),
        ),
      );
    }
    return _BoundaryMethodSelection(workspace: workspace);
  }
}

class _FieldMapOverview extends StatefulWidget {
  const _FieldMapOverview({super.key, required this.workspace});

  final FieldWorkspaceRecord workspace;

  @override
  State<_FieldMapOverview> createState() => _FieldMapOverviewState();
}

class _FieldMapOverviewState extends State<_FieldMapOverview> {
  final MapController _mapController = MapController();
  late final List<LatLng> _outline;
  late final LatLng _initialCenter;
  late double _zoom;

  bool get _hasOutline =>
      _outline.length >= 3 &&
      widget.workspace.boundary?.confirmationStatus == 'user_confirmed';

  @override
  void initState() {
    super.initState();
    final boundary = widget.workspace.boundary;
    _outline = PolygonCalculator.fromGeoJson(
      boundary?.geometryGeojson ?? '',
    ).toList();
    _initialCenter = _outline.isNotEmpty
        ? PolygonCalculator.calculateCenter(_outline)
        : boundary?.centroidLatitude != null &&
              boundary?.centroidLongitude != null
        ? LatLng(boundary!.centroidLatitude!, boundary.centroidLongitude!)
        : const LatLng(17.7905, 121.4781);
    _zoom = _outline.isNotEmpty ? 17 : 15;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _centerField() {
    if (_outline.length >= 2) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: _outline,
          padding: const EdgeInsets.fromLTRB(50, 90, 50, 230),
        ),
      );
      return;
    }
    _mapController.move(_initialCenter, _zoom);
  }

  void _openBoundaryManagement() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const ManageFieldBoundaryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boundary = widget.workspace.boundary;
    return Stack(
      key: const Key('field_map_overview'),
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _initialCenter,
            initialZoom: _zoom,
            onMapReady: _centerField,
            onPositionChanged: (camera, _) => _zoom = camera.zoom,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.wormwise.app.wormwise',
            ),
            if (_hasOutline)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _outline,
                    color: AppColors.primary.withValues(alpha: 0.24),
                    borderColor: AppColors.primary,
                    borderStrokeWidth: 4,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (!_hasOutline &&
                    boundary?.centroidLatitude != null &&
                    boundary?.centroidLongitude != null)
                  Marker(
                    point: _initialCenter,
                    width: 46,
                    height: 46,
                    child: const Icon(
                      Icons.location_pin,
                      size: 42,
                      color: Color(0xFF1565C0),
                    ),
                  ),
              ],
            ),
            const RichAttributionWidget(
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              _MapControlButton(
                tooltip: 'Zoom in',
                icon: Icons.add,
                onPressed: () {
                  _zoom = (_zoom + 1).clamp(3.0, 20.0);
                  _mapController.move(_mapController.camera.center, _zoom);
                },
              ),
              const SizedBox(height: 8),
              _MapControlButton(
                tooltip: 'Zoom out',
                icon: Icons.remove,
                onPressed: () {
                  _zoom = (_zoom - 1).clamp(3.0, 20.0);
                  _mapController.move(_mapController.camera.center, _zoom);
                },
              ),
              const SizedBox(height: 8),
              _MapControlButton(
                key: const Key('center_active_field_button'),
                tooltip: 'Center active field',
                icon: Icons.center_focus_strong,
                onPressed: _centerField,
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 14,
          child: _MapFieldCard(
            fieldName: widget.workspace.field.name,
            hasOutline: _hasOutline,
            areaHectares: _hasOutline ? boundary!.areaHectares : null,
            onOpenFields: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const FieldsScreen()),
            ),
            onManageBoundary: _openBoundaryManagement,
          ),
        ),
      ],
    );
  }
}

class _MapFieldCard extends StatelessWidget {
  const _MapFieldCard({
    required this.fieldName,
    required this.hasOutline,
    required this.areaHectares,
    required this.onOpenFields,
    required this.onManageBoundary,
  });

  final String fieldName;
  final bool hasOutline;
  final double? areaHectares;
  final VoidCallback onOpenFields;
  final VoidCallback onManageBoundary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      elevation: 7,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.landscape_outlined, color: AppColors.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    fieldName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: hasOutline
                        ? AppColors.primaryLight
                        : const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hasOutline ? 'BOUNDARY SAVED' : 'NO BOUNDARY',
                    style: TextStyle(
                      color: hasOutline
                          ? AppColors.primary
                          : const Color(0xFF805500),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              hasOutline
                  ? '${areaHectares!.toStringAsFixed(3)} ha calculated outline'
                  : 'Add the field outline to prepare its scouting map.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onOpenFields,
                  child: const Text('Field details'),
                ),
                const SizedBox(width: 5),
                FilledButton.icon(
                  key: const Key('manage_boundary_button'),
                  onPressed: onManageBoundary,
                  icon: Icon(
                    hasOutline
                        ? Icons.edit_location_alt_outlined
                        : Icons.add_location_alt_outlined,
                  ),
                  label: Text(hasOutline ? 'Manage boundary' : 'Add boundary'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum BoundaryEditorMode { manual, walk }

class ManualFieldBoundaryScreen extends StatelessWidget {
  const ManualFieldBoundaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Draw Field Boundary')),
      body: const _BoundaryEditorHost(mode: BoundaryEditorMode.manual),
    );
  }
}

class WalkFieldBoundaryScreen extends StatelessWidget {
  const WalkFieldBoundaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Walk Field Boundary')),
      body: const _BoundaryEditorHost(mode: BoundaryEditorMode.walk),
    );
  }
}

class _BoundaryEditorHost extends StatelessWidget {
  const _BoundaryEditorHost({required this.mode});

  final BoundaryEditorMode mode;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldWorkspaceProvider>();
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final workspace = provider.activeWorkspace;
    if (workspace == null) {
      return _NoActiveField(
        onOpenFields: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FieldsScreen()),
        ),
      );
    }
    return _BoundaryEditor(
      key: ValueKey(
        '${workspace.field.id}:${workspace.boundary?.id}:${mode.name}',
      ),
      workspace: workspace,
      mode: mode,
    );
  }
}

class _BoundaryMethodSelection extends StatelessWidget {
  const _BoundaryMethodSelection({required this.workspace});

  final FieldWorkspaceRecord workspace;

  @override
  Widget build(BuildContext context) {
    final boundary = workspace.boundary;
    final savedPoints = PolygonCalculator.fromGeoJson(
      boundary?.geometryGeojson ?? '',
    );
    final hasSavedOutline =
        savedPoints.length >= 3 &&
        boundary?.confirmationStatus == 'user_confirmed';
    final sourceLabel = switch (boundary?.sourceMethod) {
      'walked_phone_gnss' => 'Walked with phone GPS',
      'walked_phone_gnss_adjusted' => 'Walked and manually adjusted',
      'phone_gnss_corners' => 'Phone GPS corners',
      'mixed_draw_phone_gnss' => 'Map and phone GPS',
      'manual_draw' => 'Drawn on map',
      _ => 'Reported area only',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hasSavedOutline
                ? AppColors.primaryLight
                : const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasSavedOutline
                  ? AppColors.primary.withValues(alpha: 0.28)
                  : const Color(0xFF90CAF9),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasSavedOutline
                    ? Icons.check_circle_outline
                    : Icons.landscape_outlined,
                color: hasSavedOutline
                    ? AppColors.primary
                    : const Color(0xFF1565C0),
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.field.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasSavedOutline
                          ? 'Approximate boundary saved'
                          : 'No complete boundary saved',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasSavedOutline
                          ? '${boundary!.areaHectares.toStringAsFixed(3)} ha • $sourceLabel'
                          : 'Reported area: ${boundary?.areaHectares.toStringAsFixed(2) ?? '--'} ha',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          hasSavedOutline
              ? 'Manage field boundary'
              : 'Choose how to add the boundary',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose one method. Each opens a focused workflow and returns here when finished.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 16),
        _BoundaryMethodCard(
          key: const Key('choose_manual_boundary_method'),
          icon: Icons.edit_location_alt_outlined,
          title: hasSavedOutline ? 'Review or draw on map' : 'Draw on map',
          description:
              'Tap field corners, add averaged GPS corners, and manually correct the outline.',
          badge: hasSavedOutline ? 'EDITABLE' : 'QUICK',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => const ManualFieldBoundaryScreen(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _BoundaryMethodCard(
          key: const Key('choose_walk_boundary_method'),
          icon: Icons.directions_walk,
          title: 'Walk the field edge',
          description:
              'Follow the boundary outdoors while WormWise records a filtered phone-GPS path.',
          badge: 'OUTDOOR',
          emphasized: true,
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const WalkFieldBoundaryScreen()),
          ),
        ),
        const SizedBox(height: 12),
        const _BoundaryMethodCard(
          icon: Icons.satellite_alt_outlined,
          title: 'Satellite reference',
          description:
              'Use agricultural imagery as a visual reference while drawing. This method will be added later.',
          badge: 'PLANNED',
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Color(0xFF8A5A00)),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Phone GPS and map drawing create approximate scouting outlines, not survey-grade property boundaries.',
                  style: TextStyle(height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BoundaryMethodCard extends StatelessWidget {
  const _BoundaryMethodCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    this.emphasized = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Card(
      margin: EdgeInsets.zero,
      elevation: emphasized ? 2 : 0,
      color: enabled ? Colors.white : AppColors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: emphasized ? AppColors.primary : AppColors.outlineVariant,
          width: emphasized ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: enabled
                      ? AppColors.primaryLight
                      : AppColors.outlineVariant.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: enabled ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: enabled
                                ? AppColors.primaryLight
                                : AppColors.outlineVariant,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: enabled
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Icon(Icons.chevron_right),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BoundarySnapshot {
  const _BoundarySnapshot(this.points, this.accuracies);

  final List<LatLng> points;
  final List<double?> accuracies;
}

enum _WalkTrackingStatus { idle, starting, active, paused, review }

class _BoundaryEditor extends StatefulWidget {
  const _BoundaryEditor({
    super.key,
    required this.workspace,
    required this.mode,
  });

  final FieldWorkspaceRecord workspace;
  final BoundaryEditorMode mode;

  @override
  State<_BoundaryEditor> createState() => _BoundaryEditorState();
}

class _BoundaryEditorState extends State<_BoundaryEditor> {
  final MapController _mapController = MapController();
  final PhoneLocationService _locationService = const PhoneLocationService();
  final WalkBoundaryRecorder _walkRecorder = WalkBoundaryRecorder();
  final List<_BoundarySnapshot> _history = [];
  late List<LatLng> _points;
  late List<double?> _pointAccuracies;
  late LatLng _referenceCenter;
  late LatLng _cameraCenter;
  late double _cameraZoom;
  bool _isCapturingGpsCorner = false;
  int? _selectedPointIndex;
  bool _isDirty = false;
  int? _tapCandidatePointer;
  Offset? _tapDownPosition;
  bool _tapCandidateMoved = false;
  StreamSubscription<PhoneLocationReading>? _walkSubscription;
  _WalkTrackingStatus _walkStatus = _WalkTrackingStatus.idle;
  bool _isMarkingWalkCorner = false;
  bool _walkBoundaryWasCaptured = false;
  bool _walkBoundaryWasAdjusted = false;
  bool _walkPreviousDirty = false;
  WalkSampleDecision? _latestWalkDecision;
  WalkBoundarySample? _displayedWalkSample;
  bool _hasLiveWalkReading = false;

  @override
  void initState() {
    super.initState();
    _points = PolygonCalculator.fromGeoJson(
      widget.workspace.boundary?.geometryGeojson ?? '',
    ).toList();
    _pointAccuracies = List<double?>.filled(
      _points.length,
      null,
      growable: true,
    );
    final boundary = widget.workspace.boundary;
    _referenceCenter =
        boundary?.centroidLatitude != null &&
            boundary?.centroidLongitude != null
        ? LatLng(boundary!.centroidLatitude!, boundary.centroidLongitude!)
        : PolygonCalculator.calculateCenter(_points);
    _cameraCenter = _points.isEmpty
        ? _referenceCenter
        : PolygonCalculator.calculateCenter(_points);
    _cameraZoom = _points.isEmpty ? 15 : 17;
  }

  @override
  void dispose() {
    unawaited(_walkSubscription?.cancel());
    _mapController.dispose();
    super.dispose();
  }

  bool get _walkIsRecording =>
      _walkStatus == _WalkTrackingStatus.active ||
      _walkStatus == _WalkTrackingStatus.starting;

  bool get _walkSessionOpen =>
      _walkIsRecording || _walkStatus == _WalkTrackingStatus.paused;

  bool get _manualEditingEnabled =>
      widget.mode == BoundaryEditorMode.manual ||
      (widget.mode == BoundaryEditorMode.walk &&
          _walkStatus == _WalkTrackingStatus.review);

  void _saveHistory() {
    _history.add(
      _BoundarySnapshot(
        List<LatLng>.of(_points),
        List<double?>.of(_pointAccuracies),
      ),
    );
  }

  void _handleMapPointerDown(PointerDownEvent event) {
    if (!_manualEditingEnabled || _walkSessionOpen) return;
    if (_tapCandidatePointer != null) {
      _tapCandidateMoved = true;
      return;
    }
    _tapCandidatePointer = event.pointer;
    _tapDownPosition = event.localPosition;
    _tapCandidateMoved = false;
  }

  void _handleMapPointerMove(PointerMoveEvent event) {
    if (!_manualEditingEnabled || _walkSessionOpen) return;
    if (event.pointer != _tapCandidatePointer || _tapDownPosition == null) {
      return;
    }
    if ((event.localPosition - _tapDownPosition!).distance > 12) {
      _tapCandidateMoved = true;
    }
  }

  void _handleMapPointerUp(PointerUpEvent event) {
    if (!_manualEditingEnabled || _walkSessionOpen) return;
    if (event.pointer != _tapCandidatePointer) return;
    final shouldPlacePoint = !_tapCandidateMoved;
    _resetTapCandidate();
    if (!shouldPlacePoint) return;

    final tapOffset = event.localPosition;
    final tappedExistingPoint = _points.any(
      (point) =>
          (_mapController.camera.latLngToScreenOffset(point) - tapOffset)
              .distance <=
          32,
    );
    if (tappedExistingPoint) return;

    final position = _mapController.camera.screenOffsetToLatLng(tapOffset);
    _addOrMovePoint(position);
    Feedback.forTap(context);
  }

  void _handleMapPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _tapCandidatePointer) _resetTapCandidate();
  }

  void _resetTapCandidate() {
    _tapCandidatePointer = null;
    _tapDownPosition = null;
    _tapCandidateMoved = false;
  }

  void _addOrMovePoint(LatLng position, {double? accuracyMeters}) {
    var automaticallyAdjusted = false;
    setState(() {
      _saveHistory();
      final selectedIndex = _selectedPointIndex;
      if (selectedIndex == null) {
        _points.add(position);
        _pointAccuracies.add(accuracyMeters);
      } else {
        _points[selectedIndex] = position;
        _pointAccuracies[selectedIndex] = accuracyMeters;
        _selectedPointIndex = null;
      }
      automaticallyAdjusted = _untangleBoundaryPoints();
      if (_walkBoundaryWasCaptured) _walkBoundaryWasAdjusted = true;
      _isDirty = true;
    });
    if (automaticallyAdjusted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Point order adjusted automatically to prevent crossing edges.',
            ),
          ),
        );
    }
  }

  bool _untangleBoundaryPoints() {
    final order = PolygonCalculator.untangledOrder(_points);
    final changed = order.indexed.any((entry) => entry.$1 != entry.$2);
    if (!changed) return false;

    final originalPoints = List<LatLng>.of(_points);
    final originalAccuracies = List<double?>.of(_pointAccuracies);
    _points = [for (final index in order) originalPoints[index]];
    _pointAccuracies = [for (final index in order) originalAccuracies[index]];
    return true;
  }

  void _selectPoint(int index) {
    setState(() {
      _selectedPointIndex = _selectedPointIndex == index ? null : index;
    });
  }

  void _deleteSelectedPoint() {
    final selectedIndex = _selectedPointIndex;
    if (selectedIndex == null) return;
    setState(() {
      _saveHistory();
      _points.removeAt(selectedIndex);
      _pointAccuracies.removeAt(selectedIndex);
      _selectedPointIndex = null;
      if (_walkBoundaryWasCaptured) _walkBoundaryWasAdjusted = true;
      _isDirty = true;
    });
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      final previous = _history.removeLast();
      _points = previous.points;
      _pointAccuracies = previous.accuracies;
      _selectedPointIndex = null;
      if (_walkBoundaryWasCaptured) _walkBoundaryWasAdjusted = true;
      _isDirty = true;
    });
  }

  void _clear() {
    if (_points.isEmpty) return;
    setState(() {
      _saveHistory();
      _points.clear();
      _pointAccuracies.clear();
      _selectedPointIndex = null;
      _walkBoundaryWasCaptured = false;
      _walkBoundaryWasAdjusted = false;
      _walkStatus = _WalkTrackingStatus.idle;
      _isDirty = true;
    });
  }

  Future<void> _centerBoundary() async {
    final center = _points.isEmpty
        ? _referenceCenter
        : PolygonCalculator.calculateCenter(_points);
    if (_points.isEmpty) {
      await _moveCamera(center, 15);
      return;
    }

    if (_points.length == 1) {
      await _moveCamera(center, 18);
      return;
    }

    _cameraCenter = center;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _points,
        padding: const EdgeInsets.all(56),
      ),
    );
  }

  Future<void> _zoomBy(double amount) async {
    final targetZoom = (_cameraZoom + amount).clamp(3.0, 20.0).toDouble();
    await _moveCamera(_cameraCenter, targetZoom);
  }

  Future<void> _moveCamera(LatLng center, double zoom) async {
    _cameraCenter = center;
    _cameraZoom = zoom;
    _mapController.move(center, zoom);
  }

  Future<void> _captureGpsCorner() async {
    setState(() => _isCapturingGpsCorner = true);
    try {
      final location = await _locationService.captureAverage();
      if (!mounted) return;
      final point = LatLng(location.latitude, location.longitude);
      _addOrMovePoint(point, accuracyMeters: location.averageAccuracyMeters);
      await _moveCamera(point, mathMax(_cameraZoom, 18));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'GPS point added from ${location.sampleCount} reading(s), '
            'about ${location.averageAccuracyMeters.toStringAsFixed(1)} m accuracy.',
          ),
        ),
      );
    } on PhoneLocationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add a GPS point: $error')),
      );
    } finally {
      if (mounted) setState(() => _isCapturingGpsCorner = false);
    }
  }

  Future<void> _startWalkBoundary() async {
    if (widget.mode != BoundaryEditorMode.walk) return;
    if (_walkSessionOpen || _walkStatus == _WalkTrackingStatus.starting) return;

    if (_points.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Start a new walked boundary?'),
          content: const Text(
            'Walking will temporarily replace the points currently on the map. '
            'You can discard the walk to restore them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep current outline'),
            ),
            FilledButton(
              key: const Key('confirm_start_walk_boundary_button'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start walking'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }

    setState(() => _walkStatus = _WalkTrackingStatus.starting);
    try {
      final stream = await _locationService.watchPosition();
      if (!mounted) return;
      _walkPreviousDirty = _isDirty;
      _saveHistory();
      _walkRecorder.reset();
      _latestWalkDecision = null;
      _displayedWalkSample = null;
      _hasLiveWalkReading = false;
      _resetTapCandidate();
      setState(() {
        _points.clear();
        _pointAccuracies.clear();
        _selectedPointIndex = null;
        _walkBoundaryWasCaptured = false;
        _walkBoundaryWasAdjusted = false;
        _walkStatus = _WalkTrackingStatus.active;
        _isDirty = true;
      });
      _listenToWalkStream(stream);
    } on PhoneLocationException catch (error) {
      if (!mounted) return;
      setState(() => _walkStatus = _WalkTrackingStatus.idle);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _walkStatus = _WalkTrackingStatus.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start boundary walking: $error')),
      );
    }
  }

  void _listenToWalkStream(Stream<PhoneLocationReading> stream) {
    unawaited(_walkSubscription?.cancel());
    _walkSubscription = stream.listen(
      _handleWalkReading,
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _walkStatus = _WalkTrackingStatus.paused);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'GPS tracking paused because location updates stopped: $error',
            ),
          ),
        );
      },
    );
  }

  void _handleWalkReading(PhoneLocationReading reading) {
    if (!mounted || _walkStatus != _WalkTrackingStatus.active) return;
    final sample = WalkBoundarySample(
      position: LatLng(reading.latitude, reading.longitude),
      accuracyMeters: reading.accuracyMeters,
      capturedAt: reading.capturedAt,
    );
    if (reading.isCached) {
      setState(() => _displayedWalkSample = sample);
      unawaited(_moveCamera(sample.position, mathMax(_cameraZoom, 18)));
      return;
    }

    final decision = _walkRecorder.addSample(sample);
    final accepted =
        decision == WalkSampleDecision.accepted ||
        decision == WalkSampleDecision.acceptedCorner ||
        decision == WalkSampleDecision.replacedWithCorner;
    setState(() {
      _displayedWalkSample = sample;
      _hasLiveWalkReading = true;
      _latestWalkDecision = decision;
      if (accepted) _copyWalkPointsToEditor();
    });
    unawaited(_moveCamera(sample.position, mathMax(_cameraZoom, 18)));
  }

  void _copyWalkPointsToEditor({List<WalkBoundaryPoint>? points}) {
    final source = points ?? _walkRecorder.points;
    _points = [for (final point in source) point.position];
    _pointAccuracies = [for (final point in source) point.accuracyMeters];
    _selectedPointIndex = null;
    _isDirty = true;
  }

  Future<void> _pauseWalkBoundary() async {
    if (_walkStatus != _WalkTrackingStatus.active) return;
    await _walkSubscription?.cancel();
    _walkSubscription = null;
    if (mounted) setState(() => _walkStatus = _WalkTrackingStatus.paused);
  }

  Future<void> _resumeWalkBoundary() async {
    if (_walkStatus != _WalkTrackingStatus.paused) return;
    setState(() => _walkStatus = _WalkTrackingStatus.starting);
    try {
      final stream = await _locationService.watchPosition();
      if (!mounted) return;
      setState(() => _walkStatus = _WalkTrackingStatus.active);
      _listenToWalkStream(stream);
    } on PhoneLocationException catch (error) {
      if (!mounted) return;
      setState(() => _walkStatus = _WalkTrackingStatus.paused);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _walkStatus = _WalkTrackingStatus.paused);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resume GPS tracking: $error')),
      );
    }
  }

  Future<void> _markWalkCorner() async {
    if (_walkStatus != _WalkTrackingStatus.active || _isMarkingWalkCorner) {
      return;
    }
    setState(() => _isMarkingWalkCorner = true);
    try {
      final latest = _displayedWalkSample;
      if (latest == null || !_hasLiveWalkReading) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Current location is not available yet. Keep the phone outdoors with Location on.',
            ),
          ),
        );
        return;
      }
      final decision = _walkRecorder.addSample(latest, markedCorner: true);
      final accepted =
          decision == WalkSampleDecision.acceptedCorner ||
          decision == WalkSampleDecision.replacedWithCorner;
      if (accepted) {
        setState(() {
          _latestWalkDecision = decision;
          _copyWalkPointsToEditor();
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Turn marked at the current location '
              '(about ${latest.accuracyMeters.toStringAsFixed(1)} m accuracy).',
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == WalkSampleDecision.poorAccuracy
                  ? 'Corner not marked. GPS accuracy is currently too weak.'
                  : 'Move closer to the actual corner and try marking it again.',
            ),
          ),
        );
      }
    } on PhoneLocationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _isMarkingWalkCorner = false);
    }
  }

  Future<void> _finishWalkBoundary() async {
    if (!_walkSessionOpen) return;
    await _walkSubscription?.cancel();
    _walkSubscription = null;
    if (!mounted) return;
    setState(() => _walkStatus = _WalkTrackingStatus.paused);

    if (_walkRecorder.points.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Keep walking until at least three filtered boundary points are recorded.',
          ),
        ),
      );
      return;
    }

    final distanceToStart = _walkRecorder.distanceToStartMeters;
    if (distanceToStart != null && distanceToStart > 20) {
      final finishAnyway = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('You are not near the starting point'),
          content: Text(
            'The phone is about ${distanceToStart.toStringAsFixed(0)} m from the '
            'start. Finishing now will connect the last point to the start with '
            'a straight line.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Continue walking'),
            ),
            FilledButton(
              key: const Key('finish_walk_away_from_start_button'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Finish anyway'),
            ),
          ],
        ),
      );
      if (finishAnyway != true) {
        if (mounted) await _resumeWalkBoundary();
        return;
      }
    }

    final simplified = _walkRecorder.simplified(toleranceMeters: 2);
    setState(() {
      _copyWalkPointsToEditor(points: simplified);
      _walkBoundaryWasCaptured = true;
      _walkBoundaryWasAdjusted = false;
      _walkStatus = _WalkTrackingStatus.review;
      _untangleBoundaryPoints();
    });
    await _centerBoundary();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Walk finished. ${_walkRecorder.points.length} filtered points were '
          'simplified to ${_points.length}. Review and adjust the outline before saving.',
        ),
      ),
    );
  }

  Future<void> _discardWalkBoundary() async {
    if (!_walkSessionOpen) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this walk?'),
        content: const Text(
          'The current walked route will be removed and the previous outline '
          'will be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep walking'),
          ),
          FilledButton(
            key: const Key('confirm_discard_walk_button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard walk'),
          ),
        ],
      ),
    );
    if (discard != true) return;
    await _walkSubscription?.cancel();
    _walkSubscription = null;
    if (!mounted) return;
    setState(() {
      _walkRecorder.reset();
      _latestWalkDecision = null;
      _displayedWalkSample = null;
      _hasLiveWalkReading = false;
      if (_history.isNotEmpty) {
        final previous = _history.removeLast();
        _points = previous.points;
        _pointAccuracies = previous.accuracies;
      } else {
        _points.clear();
        _pointAccuracies.clear();
      }
      _walkStatus = _WalkTrackingStatus.idle;
      _selectedPointIndex = null;
      _isDirty = _walkPreviousDirty;
    });
  }

  double mathMax(double first, double second) =>
      first > second ? first : second;

  Widget _buildMap() {
    return Listener(
      key: const Key('boundary_map_tap_area'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handleMapPointerDown,
      onPointerMove: _handleMapPointerMove,
      onPointerUp: _handleMapPointerUp,
      onPointerCancel: _handleMapPointerCancel,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _cameraCenter,
          initialZoom: _cameraZoom,
          onPositionChanged: (camera, _) {
            _cameraCenter = camera.center;
            _cameraZoom = camera.zoom;
          },
          interactionOptions: const InteractionOptions(
            flags: ~InteractiveFlag.doubleTapZoom,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.wormwise.app.wormwise',
          ),
          if (_walkSessionOpen && _displayedWalkSample != null)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: _displayedWalkSample!.position,
                  radius: mathMax(_displayedWalkSample!.accuracyMeters, 3),
                  useRadiusInMeter: true,
                  color:
                      (_displayedWalkSample?.accuracyMeters ??
                              double.infinity) <=
                          15
                      ? AppColors.primary.withValues(alpha: 0.14)
                      : const Color(0xFFF57C00).withValues(alpha: 0.16),
                  borderColor:
                      (_displayedWalkSample?.accuracyMeters ??
                              double.infinity) <=
                          15
                      ? AppColors.primary.withValues(alpha: 0.55)
                      : const Color(0xFFF57C00),
                  borderStrokeWidth: 2,
                ),
              ],
            ),
          if (widget.mode == BoundaryEditorMode.walk &&
              _walkStatus == _WalkTrackingStatus.review &&
              _walkRecorder.points.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [
                    for (final point in _walkRecorder.points) point.position,
                  ],
                  color: AppColors.textSecondary.withValues(alpha: 0.45),
                  strokeWidth: 5,
                ),
              ],
            ),
          if (!_walkSessionOpen && _points.length >= 3)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: _points,
                  color: AppColors.primary.withValues(alpha: 0.22),
                  borderColor: AppColors.primary,
                  borderStrokeWidth: 3,
                ),
              ],
            )
          else if (_points.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _points,
                  color: AppColors.primary,
                  strokeWidth: 3,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              if (widget.workspace.hasEntranceLocation)
                Marker(
                  point: _referenceCenter,
                  width: 42,
                  height: 42,
                  child: Semantics(
                    label: 'Recorded field entrance',
                    child: const Icon(
                      Icons.location_pin,
                      size: 38,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
              if (_walkSessionOpen && _points.isNotEmpty)
                Marker(
                  point: _points.first,
                  width: 42,
                  height: 42,
                  child: const _WalkMapMarker(
                    icon: Icons.flag,
                    color: Color(0xFF1565C0),
                    label: 'Walk starting point',
                  ),
                ),
              if (_walkSessionOpen && _displayedWalkSample != null)
                Marker(
                  point: _displayedWalkSample!.position,
                  width: 44,
                  height: 44,
                  child: const _WalkMapMarker(
                    icon: Icons.navigation,
                    color: Color(0xFFF57C00),
                    label: 'Current phone location',
                  ),
                ),
              if (_manualEditingEnabled)
                for (var index = 0; index < _points.length; index++)
                  Marker(
                    point: _points[index],
                    width: 52,
                    height: 52,
                    child: Semantics(
                      button: true,
                      label: 'Boundary point ${index + 1}',
                      child: GestureDetector(
                        onTap: () => _selectPoint(index),
                        child: _BoundaryPointMarker(
                          number: index + 1,
                          isSelected: _selectedPointIndex == index,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
          const RichAttributionWidget(
            showFlutterMapAttribution: false,
            attributions: [TextSourceAttribution('OpenStreetMap contributors')],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBoundary() async {
    final validation = PolygonCalculator.validate(_points);
    if (!validation.isValid) return;

    final areaHectares = PolygonCalculator.calculateHectares(_points);
    final perimeterMeters = PolygonCalculator.calculatePerimeterMeters(_points);
    final knownAccuracies = _pointAccuracies.whereType<double>().toList();
    final averageAccuracyM = knownAccuracies.isEmpty
        ? null
        : knownAccuracies.reduce((first, second) => first + second) /
              knownAccuracies.length;
    final worstAccuracyM = knownAccuracies.isEmpty
        ? null
        : knownAccuracies.reduce(mathMax);
    final confidenceCode = _walkBoundaryWasCaptured
        ? averageAccuracyM != null && averageAccuracyM <= 5
              ? 'high_walked_phone_gnss_outline'
              : averageAccuracyM != null && averageAccuracyM <= 10
              ? 'moderate_walked_phone_gnss_outline'
              : 'low_walked_phone_gnss_outline'
        : knownAccuracies.isEmpty
        ? 'manual_visual_outline'
        : knownAccuracies.length == _points.length && averageAccuracyM! <= 5
        ? 'high_phone_gnss_outline'
        : averageAccuracyM! <= 10
        ? 'mixed_phone_gnss_outline'
        : 'low_phone_gnss_outline';
    final sourceMethod = _walkBoundaryWasCaptured
        ? _walkBoundaryWasAdjusted
              ? 'walked_phone_gnss_adjusted'
              : 'walked_phone_gnss'
        : knownAccuracies.isEmpty
        ? 'manual_draw'
        : knownAccuracies.length == _points.length
        ? 'phone_gnss_corners'
        : 'mixed_draw_phone_gnss';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _BoundaryConfirmationDialog(
        fieldName: widget.workspace.field.name,
        pointCount: _points.length,
        areaHectares: areaHectares,
        perimeterMeters: perimeterMeters,
      ),
    );
    if (confirmed != true || !mounted) return;

    final center = PolygonCalculator.calculateCenter(_points);
    try {
      await context.read<FieldWorkspaceProvider>().confirmDrawnBoundary(
        geometryGeoJson: PolygonCalculator.toGeoJson(_points),
        areaHectares: areaHectares,
        perimeterMeters: perimeterMeters,
        centroidLatitude: center.latitude,
        centroidLongitude: center.longitude,
        sourceMethod: sourceMethod,
        averageAccuracyM: averageAccuracyM,
        worstAccuracyM: worstAccuracyM,
        confidenceCode: confidenceCode,
      );
      if (!mounted) return;
      setState(() => _isDirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Approximate outline confirmed and saved offline.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Boundary could not be saved: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final validation = PolygonCalculator.validate(_points);
    final areaHectares = PolygonCalculator.calculateHectares(_points);
    final perimeterMeters = PolygonCalculator.calculatePerimeterMeters(_points);
    final isConfirmed =
        widget.workspace.boundary?.confirmationStatus == 'user_confirmed';

    return Column(
      children: [
        _FieldBoundaryHeader(
          fieldName: widget.workspace.field.name,
          isConfirmed: isConfirmed,
          mode: widget.mode,
          isReview: _walkStatus == _WalkTrackingStatus.review,
        ),
        Expanded(
          child: Stack(
            children: [
              _buildMap(),
              if (_manualEditingEnabled || _walkSessionOpen)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 76,
                  child: _MapInstruction(
                    selectedPointNumber: _selectedPointIndex == null
                        ? null
                        : _selectedPointIndex! + 1,
                    walkStatus: _walkStatus,
                    mode: widget.mode,
                  ),
                ),
              Positioned(
                top: 12,
                right: 12,
                child: Column(
                  children: [
                    _MapControlButton(
                      key: const Key('boundary_zoom_in_button'),
                      tooltip: 'Zoom in',
                      icon: Icons.add,
                      onPressed: () => _zoomBy(1),
                    ),
                    const SizedBox(height: 8),
                    _MapControlButton(
                      key: const Key('boundary_zoom_out_button'),
                      tooltip: 'Zoom out',
                      icon: Icons.remove,
                      onPressed: () => _zoomBy(-1),
                    ),
                    const SizedBox(height: 8),
                    _MapControlButton(
                      tooltip: 'Center boundary',
                      icon: Icons.center_focus_strong,
                      onPressed: _centerBoundary,
                    ),
                    if (_manualEditingEnabled) ...[
                      const SizedBox(height: 8),
                      _MapControlButton(
                        key: const Key('add_gps_boundary_point_button'),
                        tooltip: 'Add averaged GPS corner',
                        icon: _isCapturingGpsCorner
                            ? Icons.gps_fixed
                            : Icons.add_location_alt_outlined,
                        onPressed: _isCapturingGpsCorner
                            ? null
                            : () => unawaited(_captureGpsCorner()),
                      ),
                      const SizedBox(height: 8),
                      _MapControlButton(
                        tooltip: 'Undo',
                        icon: Icons.undo,
                        onPressed: _history.isEmpty ? null : _undo,
                      ),
                      const SizedBox(height: 8),
                      _MapControlButton(
                        tooltip: 'Delete selected point',
                        icon: Icons.delete_outline,
                        onPressed: _selectedPointIndex == null
                            ? null
                            : _deleteSelectedPoint,
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.mode == BoundaryEditorMode.walk)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _WalkBoundaryPanel(
                    status: _walkStatus,
                    acceptedPointCount: _walkRecorder.points.length,
                    latestAccuracyMeters: _displayedWalkSample?.accuracyMeters,
                    hasLiveLocation: _hasLiveWalkReading,
                    acceptedPathMeters: _walkRecorder.acceptedPathMeters,
                    distanceToStartMeters: _walkRecorder.distanceToStartMeters,
                    rejectedAccuracyCount: _walkRecorder.rejectedAccuracyCount,
                    latestDecision: _latestWalkDecision,
                    isMarkingCorner: _isMarkingWalkCorner,
                    onStart: () => unawaited(_startWalkBoundary()),
                    onPause: () => unawaited(_pauseWalkBoundary()),
                    onResume: () => unawaited(_resumeWalkBoundary()),
                    onMarkCorner: () => unawaited(_markWalkCorner()),
                    onFinish: () => unawaited(_finishWalkBoundary()),
                    onDiscard: () => unawaited(_discardWalkBoundary()),
                  ),
                ),
            ],
          ),
        ),
        if (_manualEditingEnabled)
          _BoundarySummaryPanel(
            pointCount: _points.length,
            areaHectares: areaHectares,
            perimeterMeters: perimeterMeters,
            validation: validation,
            isSaving: context.watch<FieldWorkspaceProvider>().isSaving,
            canConfirm: validation.isValid && _isDirty && !_walkSessionOpen,
            onClear: _points.isEmpty || _walkSessionOpen ? null : _clear,
            onConfirm: _confirmBoundary,
          ),
      ],
    );
  }
}

class _FieldBoundaryHeader extends StatelessWidget {
  const _FieldBoundaryHeader({
    required this.fieldName,
    required this.isConfirmed,
    required this.mode,
    required this.isReview,
  });

  final String fieldName;
  final bool isConfirmed;
  final BoundaryEditorMode mode;
  final bool isReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: Colors.white,
      child: Row(
        children: [
          const Icon(Icons.landscape_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fieldName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  mode == BoundaryEditorMode.manual
                      ? 'Draw and adjust an approximate outline'
                      : isReview
                      ? 'Review the simplified walked outline'
                      : 'Filtered phone-GPS boundary walk',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: isConfirmed
                  ? AppColors.primaryLight
                  : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isConfirmed ? 'Outline saved' : 'Not saved',
              style: TextStyle(
                color: isConfirmed
                    ? AppColors.primary
                    : const Color(0xFF1565C0),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapInstruction extends StatelessWidget {
  const _MapInstruction({
    this.selectedPointNumber,
    required this.walkStatus,
    required this.mode,
  });

  final int? selectedPointNumber;
  final _WalkTrackingStatus walkStatus;
  final BoundaryEditorMode mode;

  @override
  Widget build(BuildContext context) {
    final isWalking =
        walkStatus == _WalkTrackingStatus.active ||
        walkStatus == _WalkTrackingStatus.starting;
    final isPaused = walkStatus == _WalkTrackingStatus.paused;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWalking
                ? Icons.directions_walk
                : isPaused
                ? Icons.pause_circle_outline
                : selectedPointNumber == null
                ? Icons.touch_app_outlined
                : Icons.open_with,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWalking
                      ? 'Walk along the field edge.'
                      : isPaused
                      ? 'Boundary walking is paused.'
                      : selectedPointNumber == null
                      ? 'Tap the map to place a numbered boundary point.'
                      : 'Point $selectedPointNumber selected. Tap its new location.',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!isWalking && !isPaused) ...[
                  const SizedBox(height: 2),
                  Text(
                    mode == BoundaryEditorMode.walk
                        ? 'Adjust only obvious GPS errors, then review and save.'
                        : 'Use the GPS-pin control at an accessible corner.',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WalkBoundaryPanel extends StatelessWidget {
  const _WalkBoundaryPanel({
    required this.status,
    required this.acceptedPointCount,
    required this.latestAccuracyMeters,
    required this.hasLiveLocation,
    required this.acceptedPathMeters,
    required this.distanceToStartMeters,
    required this.rejectedAccuracyCount,
    required this.latestDecision,
    required this.isMarkingCorner,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onMarkCorner,
    required this.onFinish,
    required this.onDiscard,
  });

  final _WalkTrackingStatus status;
  final int acceptedPointCount;
  final double? latestAccuracyMeters;
  final bool hasLiveLocation;
  final double acceptedPathMeters;
  final double? distanceToStartMeters;
  final int rejectedAccuracyCount;
  final WalkSampleDecision? latestDecision;
  final bool isMarkingCorner;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onMarkCorner;
  final VoidCallback onFinish;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    if (status == _WalkTrackingStatus.idle) {
      return Material(
        color: Colors.white.withValues(alpha: 0.96),
        elevation: 4,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.directions_walk, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Before you start',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const _WalkPrepLine(
                icon: Icons.flag_outlined,
                text: 'Stand at an accessible field corner or edge.',
              ),
              const _WalkPrepLine(
                icon: Icons.phone_android,
                text: 'Keep WormWise open while you walk the boundary.',
              ),
              const _WalkPrepLine(
                icon: Icons.health_and_safety_outlined,
                text: 'Walk only where it is safe and accessible.',
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('start_walk_boundary_button'),
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text("I'm at the starting edge - Begin"),
              ),
            ],
          ),
        ),
      );
    }

    if (status == _WalkTrackingStatus.review) {
      return Material(
        color: Colors.white.withValues(alpha: 0.96),
        elevation: 4,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppColors.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Walk captured - review it',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'The raw path is grey; the saved outline is green.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('start_walk_boundary_button'),
                onPressed: onStart,
                icon: const Icon(Icons.replay),
                label: const Text('Walk again'),
              ),
            ],
          ),
        ),
      );
    }

    if (status == _WalkTrackingStatus.starting) {
      return Material(
        color: Colors.white.withValues(alpha: 0.96),
        elevation: 4,
        borderRadius: BorderRadius.circular(14),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Finding your location... Move outdoors and keep this screen open.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final paused = status == _WalkTrackingStatus.paused;
    final closeEnough =
        acceptedPointCount >= 3 &&
        distanceToStartMeters != null &&
        distanceToStartMeters! <= 15;
    final locationStatus = latestAccuracyMeters == null
        ? 'Waiting for a phone location'
        : !hasLiveLocation
        ? 'Showing last location - waiting for live GPS'
        : latestAccuracyMeters! > 25
        ? 'Location found, but accuracy is too weak for the path'
        : latestDecision == WalkSampleDecision.tooClose
        ? 'Location found - walk about 5 m for the next path point'
        : latestDecision == WalkSampleDecision.implausibleJump
        ? 'Location found - a sudden GPS jump was ignored'
        : 'Location found and tracking';
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      elevation: 5,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  paused ? Icons.pause_circle : Icons.gps_fixed,
                  color: paused ? const Color(0xFFF57C00) : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    paused
                        ? 'Boundary walk paused'
                        : closeEnough
                        ? 'Near the start — ready to finish'
                        : 'Recording filtered boundary walk',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const Key('discard_walk_boundary_button'),
                  tooltip: 'Discard walk',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDiscard,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              locationStatus,
              key: const Key('walk_location_status'),
              style: TextStyle(
                color:
                    latestAccuracyMeters != null &&
                        (!hasLiveLocation || latestAccuracyMeters! > 25)
                    ? const Color(0xFF9A6700)
                    : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _WalkMetricChip(
                  icon: Icons.location_searching,
                  text: latestAccuracyMeters == null
                      ? 'Accuracy: waiting'
                      : '±${latestAccuracyMeters!.toStringAsFixed(0)} m',
                  warning:
                      latestAccuracyMeters != null &&
                      latestAccuracyMeters! > 25,
                ),
                _WalkMetricChip(
                  icon: Icons.route,
                  text: '$acceptedPointCount points',
                ),
                _WalkMetricChip(
                  icon: Icons.straighten,
                  text: '${acceptedPathMeters.toStringAsFixed(0)} m walked',
                ),
                if (distanceToStartMeters != null)
                  _WalkMetricChip(
                    icon: Icons.flag_outlined,
                    text:
                        '${distanceToStartMeters!.toStringAsFixed(0)} m from start',
                    positive: closeEnough,
                  ),
                if (rejectedAccuracyCount > 0)
                  _WalkMetricChip(
                    icon: Icons.signal_cellular_connected_no_internet_0_bar,
                    text: '$rejectedAccuracyCount weak skipped',
                    warning: true,
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('pause_resume_walk_boundary_button'),
                  onPressed: paused ? onResume : onPause,
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                  label: Text(paused ? 'Resume' : 'Pause'),
                ),
                if (!paused)
                  OutlinedButton.icon(
                    key: const Key('mark_walk_corner_button'),
                    onPressed: isMarkingCorner ? null : onMarkCorner,
                    icon: isMarkingCorner
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Mark turn'),
                  ),
                FilledButton.icon(
                  key: const Key('finish_walk_boundary_button'),
                  onPressed: acceptedPointCount >= 3 ? onFinish : null,
                  icon: const Icon(Icons.flag),
                  label: const Text('Finish'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WalkPrepLine extends StatelessWidget {
  const _WalkPrepLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalkMetricChip extends StatelessWidget {
  const _WalkMetricChip({
    required this.icon,
    required this.text,
    this.warning = false,
    this.positive = false,
  });

  final IconData icon;
  final String text;
  final bool warning;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? const Color(0xFF9A6700)
        : positive
        ? AppColors.primary
        : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _WalkMapMarker extends StatelessWidget {
  const _WalkMapMarker({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Center(
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: AppColors.primary,
        disabledColor: AppColors.outlineVariant,
      ),
    );
  }
}

class _BoundaryPointMarker extends StatelessWidget {
  const _BoundaryPointMarker({required this.number, required this.isSelected});

  final int number;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: isSelected ? 36 : 30,
        height: isSelected ? 36 : 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? const Color(0xFFF57C00) : AppColors.primary,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _BoundarySummaryPanel extends StatelessWidget {
  const _BoundarySummaryPanel({
    required this.pointCount,
    required this.areaHectares,
    required this.perimeterMeters,
    required this.validation,
    required this.isSaving,
    required this.canConfirm,
    required this.onClear,
    required this.onConfirm,
  });

  final int pointCount;
  final double areaHectares;
  final double perimeterMeters;
  final PolygonValidationResult validation;
  final bool isSaving;
  final bool canConfirm;
  final VoidCallback? onClear;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final issue = validation.issues.isEmpty ? null : validation.issues.first;
    return Material(
      elevation: 8,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    key: const Key('boundary_point_count'),
                    label: 'Points',
                    value: '$pointCount',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Area',
                    value: '${areaHectares.toStringAsFixed(3)} ha',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Perimeter',
                    value: '${perimeterMeters.toStringAsFixed(0)} m',
                  ),
                ),
              ],
            ),
            if (issue != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF9A6700),
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      issue,
                      style: const TextStyle(
                        color: Color(0xFF805500),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Clear'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('confirm_boundary_button'),
                    onPressed: canConfirm && !isSaving ? onConfirm : null,
                    icon: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      isSaving ? 'Saving...' : 'Review & save outline',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _BoundaryConfirmationDialog extends StatefulWidget {
  const _BoundaryConfirmationDialog({
    required this.fieldName,
    required this.pointCount,
    required this.areaHectares,
    required this.perimeterMeters,
  });

  final String fieldName;
  final int pointCount;
  final double areaHectares;
  final double perimeterMeters;

  @override
  State<_BoundaryConfirmationDialog> createState() =>
      _BoundaryConfirmationDialogState();
}

class _BoundaryConfirmationDialogState
    extends State<_BoundaryConfirmationDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review field outline'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.fieldName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Boundary points: ${widget.pointCount}'),
            Text(
              'Calculated area: ${widget.areaHectares.toStringAsFixed(3)} ha',
            ),
            Text(
              'Calculated perimeter: '
              '${widget.perimeterMeters.toStringAsFixed(0)} m',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Use this outline for scouting and approximate area only. It is not '
                'survey-grade and remains optional for an assessment.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() => _acknowledged = !_acknowledged);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _acknowledged,
                      onChanged: (value) {
                        setState(() => _acknowledged = value ?? false);
                      },
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 11),
                        child: Text(
                          'I checked the point order and shape. It reasonably '
                          'represents this maize field.',
                          textAlign: TextAlign.start,
                          style: TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Continue editing'),
        ),
        FilledButton(
          key: const Key('save_confirmed_boundary_button'),
          onPressed: _acknowledged ? () => Navigator.pop(context, true) : null,
          child: const Text('Save outline'),
        ),
      ],
      actionsOverflowButtonSpacing: 8,
    );
  }
}

class _NoActiveField extends StatelessWidget {
  const _NoActiveField({required this.onOpenFields});

  final VoidCallback onOpenFields;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.add_location_alt_outlined,
              color: AppColors.primary,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Select a maize field first',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'A field outline must belong to a registered field so it can be '
              'linked to the correct assessment and report.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onOpenFields,
              icon: const Icon(Icons.landscape_outlined),
              label: const Text('Open My Fields'),
            ),
          ],
        ),
      ),
    );
  }
}
