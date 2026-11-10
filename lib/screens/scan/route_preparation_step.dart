import 'dart:async';
import '../../localization/app_text.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

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
    required this.watchLocation,
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
  final Future<Stream<PhoneLocationReading>> Function() watchLocation;
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
  bool _automaticInputsReady = false;
  bool _savingPreparation = false;
  StreamSubscription<PhoneLocationReading>? _locationSubscription;
  PhoneLocationReading? _location;

  bool get _busy => widget.isSaving || _savingPreparation;

  @override
  void initState() {
    super.initState();
    _preparation = _withoutDrawing(widget.plan.preparation);
    _automaticInputsReady =
        _preparation.entrance != null && _preparation.rowBearingDegrees != null;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _resolveAutomaticInputs(),
    );
    _startLocation();
  }

  Future<void> _startLocation() async {
    try {
      final stream = await widget.watchLocation();
      if (!mounted) return;
      _locationSubscription = stream.listen((reading) {
        if (mounted) setState(() => _location = reading);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(RoutePreparationStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.updatedAt != widget.plan.updatedAt &&
        !_savingPreparation &&
        _preparation.draftGeometry == RouteDraftGeometry.none) {
      _preparation = _withoutDrawing(widget.plan.preparation);
    }
  }

  Future<bool> _save(RoutePreparationData value) async {
    if (!mounted || _busy) return false;
    final previous = _preparation;
    setState(() {
      _savingPreparation = true;
      _preparation = value;
      _localError = null;
    });
    try {
      await widget.onSavePreparation(value);
      return mounted;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _preparation = previous;
        _localError = _message(error);
      });
      return false;
    } finally {
      if (mounted) setState(() => _savingPreparation = false);
    }
  }

  Future<void> _resolveAutomaticInputs() async {
    if (!mounted) return;
    setState(() {
      _automaticInputsReady = true;
      _automaticStartMessage =
          'Twenty suggested sampling points use the saved field outline. Select a nearby plant at each point, at least 3 m from the edge.';
    });
  }

  Future<void> _generate() async {
    if (!await _save(_preparation) || !mounted) return;
    try {
      await widget.onGenerate();
    } catch (error) {
      if (!mounted) return;
      setState(() => _localError = _message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapPlan = widget.plan.copyWith(preparation: _preparation);
    return ListView(
      key: const Key('route_preparation_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        AppText(
          'BLOCK ${widget.blockNumber} · ROUTE PREPARATION',
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Prepare 20 sampling points',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        AppText(
          'Review the suggested plant locations before starting.',
          style: const TextStyle(height: 1.4),
        ),
        const SizedBox(height: 14),
        OfflineScoutingRouteMap(
          height: 400,
          boundary: widget.boundary,
          plan: mapPlan,
          completedStationLocations: widget.completedStationLocations,
          completedStationNumbers: widget.completedStationNumbers,
          currentLocation: _location,
          imageryProvider: widget.imageryProvider,
        ),
        const SizedBox(height: 8),
        const AppText(
          'Pan and zoom to review the automatically prepared pattern area.',
          key: Key('route_drawing_instruction'),
          style: TextStyle(fontWeight: FontWeight.w600),
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
              Text(
                _automaticStartMessage ??
                    'Review the suggested plant locations.',
                key: const Key('automatic_route_start_status'),
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 8),
              const AppText(
                'Check the suggested points against the actual field.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          key: const Key('route_guidance_limitations_help'),
          tilePadding: EdgeInsets.zero,
          title: const AppText('What this guidance means'),
          children: const [
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: AppText(
                'Targets and lines are editable approximate field guidance. They are not turn-by-turn navigation, validated station-placement geometry, proof that the protocol was followed, or a legal or survey-grade boundary. For an irregular or concave field, Cropwise may omit a connecting line rather than claim it is a safe walking path.',
                style: TextStyle(height: 1.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (!_automaticInputsReady)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: AppText('Retry automatic setup before generating targets.'),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton.icon(
            key: const Key('generate_route_targets_button'),
            onPressed: _busy || !_automaticInputsReady ? null : _generate,
            icon: const Icon(Icons.route),
            label: Text(
              widget.plan.targets.isEmpty
                  ? 'Generate 20 plant locations'
                  : 'Recalculate remaining targets',
            ),
          ),
        ),
      ],
    );
  }

  RoutePreparationData _withoutDrawing(RoutePreparationData preparation) =>
      preparation.copyWith(
        draftGeometry: RouteDraftGeometry.none,
        draftPoints: const [],
      );
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
