import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../data/local/database_codes.dart';
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
    required this.captureLocation,
    required this.isSaving,
    required this.onSavePreparation,
    required this.onGenerate,
  });

  final int blockNumber;
  final List<LatLng> boundary;
  final ScoutingRoutePlan plan;
  final Map<int, LatLng> completedStationLocations;
  final Future<AveragedPhoneLocation> Function() captureLocation;
  final bool isSaving;
  final Future<void> Function(RoutePreparationData) onSavePreparation;
  final Future<void> Function() onGenerate;

  @override
  State<RoutePreparationStep> createState() => _RoutePreparationStepState();
}

class _RoutePreparationStepState extends State<RoutePreparationStep> {
  late RoutePreparationData _preparation;
  String? _localError;

  bool get _isW => widget.plan.pattern == DatabaseCodes.patternW;

  @override
  void initState() {
    super.initState();
    _preparation = widget.plan.preparation;
  }

  @override
  void didUpdateWidget(RoutePreparationStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.updatedAt != widget.plan.updatedAt) {
      _preparation = widget.plan.preparation;
    }
  }

  Future<void> _save(RoutePreparationData value) async {
    setState(() {
      _preparation = value;
      _localError = null;
    });
    try {
      await widget.onSavePreparation(value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _localError = _message(error));
    }
  }

  Future<void> _usePhoneEntrance() async {
    try {
      final location = await widget.captureLocation();
      await _save(
        _preparation.copyWith(
          entrance: LatLng(location.latitude, location.longitude),
          draftGeometry: RouteDraftGeometry.none,
          draftPoints: const [],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _localError = _message(error));
    }
  }

  Future<void> _tapMap(LatLng point) async {
    final mode = _preparation.draftGeometry;
    if (mode == RouteDraftGeometry.none) return;
    if (mode == RouteDraftGeometry.entrance) {
      await _save(
        _preparation.copyWith(
          entrance: point,
          draftGeometry: RouteDraftGeometry.none,
          draftPoints: const [],
        ),
      );
      return;
    }
    final points = [..._preparation.draftPoints, point];
    if (mode == RouteDraftGeometry.rowDirection && points.length == 2) {
      await _save(
        _preparation.copyWith(
          rowBearingDegrees: ScoutingRouteGenerator.bearingDegrees(
            points.first,
            points.last,
          ),
          draftGeometry: RouteDraftGeometry.none,
          draftPoints: const [],
        ),
      );
      return;
    }
    await _save(_preparation.copyWith(draftPoints: points));
  }

  Future<void> _startDrawing(RouteDraftGeometry mode) =>
      _save(_preparation.copyWith(draftGeometry: mode, draftPoints: const []));

  Future<void> _finishPath() async {
    if (_preparation.draftPoints.length < 2) {
      setState(() => _localError = 'Add at least two points for a pass.');
      return;
    }
    await _save(
      _preparation.copyWith(
        accessiblePaths: [
          ..._preparation.accessiblePaths,
          List.unmodifiable(_preparation.draftPoints),
        ],
        draftGeometry: RouteDraftGeometry.none,
        draftPoints: const [],
      ),
    );
  }

  Future<void> _finishObstacle() async {
    if (_preparation.draftPoints.length < 3) {
      setState(
        () => _localError = 'Add at least three points around the obstacle.',
      );
      return;
    }
    await _save(
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
              ? 'Use W guidance only where younger maize can be crossed safely and accessibly.'
              : 'For taller or dense maize, confirm the entrance, row or pass direction, accessible paths, and known obstacles.',
          style: const TextStyle(height: 1.4),
        ),
        const SizedBox(height: 14),
        OfflineScoutingRouteMap(
          boundary: widget.boundary,
          plan: mapPlan,
          completedStationLocations: widget.completedStationLocations,
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
          title: '1. Confirm the accessible entrance',
          complete: _preparation.entrance != null,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                key: const Key('use_phone_as_route_entrance'),
                onPressed: widget.isSaving ? null : _usePhoneEntrance,
                icon: const Icon(Icons.my_location),
                label: const Text('Use phone location'),
              ),
              OutlinedButton.icon(
                key: const Key('place_route_entrance_on_map'),
                onPressed: widget.isSaving
                    ? null
                    : () => _startDrawing(RouteDraftGeometry.entrance),
                icon: const Icon(Icons.touch_app),
                label: const Text('Place on map'),
              ),
            ],
          ),
        ),
        if (_isW)
          _PreparationCard(
            title: '2. Confirm W-pattern access',
            complete: _preparation.wCrossingConfirmed,
            child: CheckboxListTile(
              key: const Key('confirm_w_crossing_accessible'),
              contentPadding: EdgeInsets.zero,
              value: _preparation.wCrossingConfirmed,
              onChanged: widget.isSaving
                  ? null
                  : (value) => _save(
                      _preparation.copyWith(wCrossingConfirmed: value == true),
                    ),
              title: const Text(
                'I confirmed that crossing rows for this W pattern is practical, accessible, and safe today.',
              ),
            ),
          )
        else ...[
          _PreparationCard(
            title: '2. Confirm row or pass direction',
            complete: _preparation.rowBearingDegrees != null,
            child: OutlinedButton.icon(
              key: const Key('draw_row_direction'),
              onPressed: widget.isSaving
                  ? null
                  : () => _startDrawing(RouteDraftGeometry.rowDirection),
              icon: const Icon(Icons.swap_calls),
              label: Text(
                _preparation.rowBearingDegrees == null
                    ? 'Tap two points on the map'
                    : 'Direction ${_preparation.rowBearingDegrees!.toStringAsFixed(0)}° · change',
              ),
            ),
          ),
          _PreparationCard(
            title: '3. Confirm accessible pass or path',
            complete: _preparation.accessiblePaths.isNotEmpty,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  key: const Key('draw_accessible_path'),
                  onPressed: widget.isSaving
                      ? null
                      : () => _startDrawing(RouteDraftGeometry.accessiblePath),
                  icon: const Icon(Icons.route),
                  label: const Text('Draw accessible pass'),
                ),
                if (drawing == RouteDraftGeometry.accessiblePath)
                  FilledButton(
                    key: const Key('finish_accessible_path'),
                    onPressed: widget.isSaving ? null : _finishPath,
                    child: const Text('Save this pass'),
                  ),
              ],
            ),
          ),
        ],
        _PreparationCard(
          title: _isW ? '3. Review obstacles' : '4. Review obstacles',
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
            onPressed: widget.isSaving ? null : _generate,
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
      'Pan and zoom to inspect the local field outline.',
    RouteDraftGeometry.entrance => 'Tap the confirmed accessible entrance.',
    RouteDraftGeometry.rowDirection =>
      'Tap two points along the row or pass direction.',
    RouteDraftGeometry.accessiblePath =>
      'Tap along a known accessible pass, then save it.',
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
