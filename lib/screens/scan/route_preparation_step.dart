import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../data/local/database_codes.dart';
import '../../services/field_imagery_provider.dart';
import '../../services/phone_location_service.dart';
import '../../services/scouting_route_generator.dart';
import '../../theme/app_colors.dart';
import '../../widgets/offline_scouting_route_map.dart';

class RoutePreparationStep extends StatefulWidget {
  const RoutePreparationStep({
    super.key,
    required this.blockNumber,
    required this.boundary,
    required this.plan,
    required this.completedStationLocations,
    required this.completedStationNumbers,
    required this.captureLocation,
    required this.isSaving,
    required this.onSavePreparation,
    required this.onGenerate,
    this.imageryProvider,
  });

  final int blockNumber;
  final List<LatLng> boundary;
  final ScoutingRoutePlan plan;
  final Map<int, LatLng> completedStationLocations;
  final Set<int> completedStationNumbers;
  final Future<AveragedPhoneLocation> Function() captureLocation;
  final bool isSaving;
  final Future<void> Function(RoutePreparationData) onSavePreparation;
  final Future<void> Function() onGenerate;
  final FieldImageryProvider? imageryProvider;

  @override
  State<RoutePreparationStep> createState() => _RoutePreparationStepState();
}

class _RoutePreparationStepState extends State<RoutePreparationStep> {
  late RoutePreparationData _preparation;
  String? _localError;
  String? _automaticStartMessage;
  bool _resolvingAutomaticInputs = false;
  bool _automaticInputsReady = false;

  bool get _isW => widget.plan.pattern == DatabaseCodes.patternW;

  @override
  void initState() {
    super.initState();
    _preparation = widget.plan.preparation;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _resolveAutomaticInputs(),
    );
  }

  @override
  void didUpdateWidget(RoutePreparationStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.updatedAt != widget.plan.updatedAt) {
      _preparation = widget.plan.preparation;
    }
  }

  Future<bool> _save(RoutePreparationData value) async {
    setState(() {
      _preparation = value;
      _localError = null;
    });
    try {
      await widget.onSavePreparation(value);
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _localError = _message(error));
      return false;
    }
  }

  Future<void> _resolveAutomaticInputs({bool retry = false}) async {
    if (_resolvingAutomaticInputs || (_automaticInputsReady && !retry)) return;
    setState(() {
      _resolvingAutomaticInputs = true;
      _localError = null;
      _automaticStartMessage = null;
    });
    late final LatLng start;
    late final String startSource;
    double? accuracyMeters;
    try {
      final location = await widget.captureLocation();
      start = LatLng(location.latitude, location.longitude);
      startSource = routeStartSourcePhoneLocation;
      accuracyMeters = location.averageAccuracyMeters;
    } catch (_) {
      start = ScoutingRouteGenerator.automaticBoundaryStart(
        widget.boundary,
        obstacles: _preparation.obstacles,
      );
      startSource = routeStartSourceFieldOutlineFallback;
    }
    final updated = _preparation.copyWith(
      entrance: start,
      startSource: startSource,
      startAccuracyMeters: accuracyMeters,
      rowBearingDegrees: ScoutingRouteGenerator.automaticRouteBearingDegrees(
        widget.boundary,
      ),
      orientationSource: routeOrientationSourceFieldShape,
      draftGeometry: RouteDraftGeometry.none,
      draftPoints: const [],
    );
    final saved = await _save(updated);
    if (!mounted) return;
    setState(() {
      _resolvingAutomaticInputs = false;
      _automaticInputsReady = saved;
      _automaticStartMessage = startSource == routeStartSourcePhoneLocation
          ? 'Starting position taken automatically from this phone${accuracyMeters == null ? '' : ' · reported accuracy ${accuracyMeters.toStringAsFixed(0)} m'}.'
          : 'Phone location was unavailable. WormWise used a generated field-edge reference; it is not your measured position.';
    });
  }

  Future<void> _removeObstacle(int index) async {
    final obstacles = [..._preparation.obstacles]..removeAt(index);
    await _save(
      _preparation.copyWith(
        obstacles: obstacles,
        obstaclesReviewed: false,
        draftGeometry: RouteDraftGeometry.none,
        draftPoints: const [],
      ),
    );
    if (mounted) {
      setState(() => _automaticInputsReady = false);
      await _resolveAutomaticInputs(retry: true);
    }
  }

  Future<void> _tapMap(LatLng point) async {
    final mode = _preparation.draftGeometry;
    if (mode != RouteDraftGeometry.obstacle) return;
    final points = [..._preparation.draftPoints, point];
    await _save(_preparation.copyWith(draftPoints: points));
  }

  Future<void> _startDrawing(RouteDraftGeometry mode) =>
      _save(_preparation.copyWith(draftGeometry: mode, draftPoints: const []));

  Future<void> _finishObstacle() async {
    if (_preparation.draftPoints.length < 3) {
      setState(
        () => _localError = 'Add at least three points around the obstacle.',
      );
      return;
    }
    final saved = await _save(
      _preparation.copyWith(
        obstacles: [
          ..._preparation.obstacles,
          List.unmodifiable(_preparation.draftPoints),
        ],
        obstaclesReviewed: true,
        draftGeometry: RouteDraftGeometry.none,
        draftPoints: const [],
      ),
    );
    if (saved && mounted) {
      setState(() => _automaticInputsReady = false);
      await _resolveAutomaticInputs(retry: true);
    }
  }

  Future<void> _generate() async {
    try {
      await widget.onGenerate();
    } catch (error) {
      if (!mounted) return;
      setState(() => _localError = _message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawing = _preparation.draftGeometry;
    final mapPlan = widget.plan.copyWith(preparation: _preparation);
    return ListView(
      key: const Key('route_preparation_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Text(
          'BLOCK ${widget.blockNumber} · ROUTE PREPARATION',
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isW ? 'Prepare W-pattern guidance' : 'Prepare ladder guidance',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _isW
              ? 'WormWise places five stations across the confirmed block. Use this pattern only where younger maize can be crossed safely.'
              : 'WormWise generates the central spine and five alternating sampling branches from the confirmed block shape.',
          style: const TextStyle(height: 1.4),
        ),
        const SizedBox(height: 14),
        OfflineScoutingRouteMap(
          boundary: widget.boundary,
          plan: mapPlan,
          completedStationLocations: widget.completedStationLocations,
          completedStationNumbers: widget.completedStationNumbers,
          imageryProvider: widget.imageryProvider,
          onTap: drawing == RouteDraftGeometry.none ? null : _tapMap,
        ),
        const SizedBox(height: 8),
        Text(
          _drawingInstruction(drawing),
          key: const Key('route_drawing_instruction'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (_localError != null) ...[
          const SizedBox(height: 8),
          Text(
            _localError!,
            key: const Key('route_preparation_error'),
            style: const TextStyle(color: Color(0xFFB3261E)),
          ),
        ],
        const SizedBox(height: 16),
        _PreparationCard(
          title: 'Automatic pattern setup',
          complete: _automaticInputsReady,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_resolvingAutomaticInputs)
                const Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 10),
                    Expanded(child: Text('Finding your starting position…')),
                  ],
                )
              else ...[
                Text(
                  _automaticStartMessage ??
                      'WormWise prepares the start and orientation automatically.',
                  key: const Key('automatic_route_start_status'),
                  style: const TextStyle(height: 1.4),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pattern direction is estimated from the saved field shape. It does not claim to detect actual maize rows.',
                  style: TextStyle(height: 1.4),
                ),
                if (_preparation.startSource ==
                    routeStartSourceFieldOutlineFallback) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('retry_automatic_route_location'),
                    onPressed: widget.isSaving
                        ? null
                        : () => _resolveAutomaticInputs(retry: true),
                    icon: const Icon(Icons.my_location),
                    label: const Text('Retry phone location'),
                  ),
                ],
              ],
            ],
          ),
        ),
        _PreparationCard(
          title: 'Check obstacles and unsafe areas',
          complete: _preparation.obstaclesReviewed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                key: const Key('confirm_route_obstacles_reviewed'),
                contentPadding: EdgeInsets.zero,
                value: _preparation.obstaclesReviewed,
                onChanged: widget.isSaving
                    ? null
                    : (value) => _save(
                        _preparation.copyWith(obstaclesReviewed: value == true),
                      ),
                title: const Text(
                  'I reviewed known obstacles and unsafe areas. None are unmarked.',
                ),
              ),
              OutlinedButton.icon(
                key: const Key('draw_route_obstacle'),
                onPressed: widget.isSaving
                    ? null
                    : () => _startDrawing(RouteDraftGeometry.obstacle),
                icon: const Icon(Icons.warning_amber),
                label: const Text('Mark an obstacle or unsafe area'),
              ),
              if (drawing == RouteDraftGeometry.obstacle)
                FilledButton(
                  key: const Key('finish_route_obstacle'),
                  onPressed: widget.isSaving ? null : _finishObstacle,
                  child: const Text('Save this obstacle'),
                ),
              if (_preparation.obstacles.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (
                      var index = 0;
                      index < _preparation.obstacles.length;
                      index++
                    )
                      InputChip(
                        label: Text('Obstacle ${index + 1}'),
                        avatar: const Icon(Icons.warning_amber, size: 18),
                        onDeleted: widget.isSaving
                            ? null
                            : () => _removeObstacle(index),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          key: const Key('route_guidance_limitations_help'),
          tilePadding: EdgeInsets.zero,
          title: const Text('What this guidance means'),
          children: const [
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Targets and lines are editable approximate field guidance. They are not turn-by-turn navigation, validated station-placement geometry, proof that the protocol was followed, or a legal or survey-grade boundary. For an irregular or concave field, WormWise may omit a connecting line rather than claim it is a safe walking path.',
                style: TextStyle(height: 1.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton.icon(
            key: const Key('generate_route_targets_button'),
            onPressed:
                widget.isSaving ||
                    !_automaticInputsReady ||
                    !_preparation.obstaclesReviewed
                ? null
                : _generate,
            icon: const Icon(Icons.route),
            label: Text(
              widget.plan.targets.isEmpty
                  ? 'Generate five station targets'
                  : 'Recalculate remaining targets',
            ),
          ),
        ),
      ],
    );
  }

  String _drawingInstruction(RouteDraftGeometry mode) => switch (mode) {
    RouteDraftGeometry.none =>
      'Pan and zoom to review the automatically prepared pattern area.',
    RouteDraftGeometry.entrance => 'Legacy entrance drawing is no longer used.',
    RouteDraftGeometry.rowDirection =>
      'Legacy row-direction drawing is no longer used.',
    RouteDraftGeometry.accessiblePath =>
      'This legacy drawing mode is not used by automatic ladder guidance.',
    RouteDraftGeometry.obstacle => 'Tap around the unsafe area, then save it.',
  };
}

class _PreparationCard extends StatelessWidget {
  const _PreparationCard({
    required this.title,
    required this.complete,
    required this.child,
  });

  final String title;
  final bool complete;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                complete ? Icons.check_circle : Icons.radio_button_unchecked,
                color: complete ? AppColors.primary : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );
}

String _message(Object error) => error
    .toString()
    .replaceFirst('StateError: ', '')
    .replaceFirst('RouteGenerationException: ', '');
