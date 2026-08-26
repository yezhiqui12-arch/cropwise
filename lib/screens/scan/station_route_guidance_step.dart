import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../services/phone_location_service.dart';
import '../../services/field_imagery_provider.dart';
import '../../services/scouting_route_generator.dart';
import '../../theme/app_colors.dart';
import '../../widgets/offline_scouting_route_map.dart';

class StationRouteGuidanceStep extends StatefulWidget {
  const StationRouteGuidanceStep({
    super.key,
    required this.blockNumber,
    required this.stationNumber,
    required this.boundary,
    required this.plan,
    required this.completedStationLocations,
    required this.completedStationNumbers,
    required this.watchLocation,
    required this.isSaving,
    required this.onConfirmReached,
    required this.onAdjustTarget,
    required this.onEditRoute,
    this.imageryProvider,
  });

  final int blockNumber;
  final int stationNumber;
  final List<LatLng> boundary;
  final ScoutingRoutePlan plan;
  final Map<int, LatLng> completedStationLocations;
  final Set<int> completedStationNumbers;
  final Future<Stream<PhoneLocationReading>> Function() watchLocation;
  final bool isSaving;
  final Future<void> Function() onConfirmReached;
  final Future<void> Function() onAdjustTarget;
  final Future<void> Function() onEditRoute;
  final FieldImageryProvider? imageryProvider;

  @override
  State<StationRouteGuidanceStep> createState() =>
      _StationRouteGuidanceStepState();
}

class _StationRouteGuidanceStepState extends State<StationRouteGuidanceStep> {
  StreamSubscription<PhoneLocationReading>? _subscription;
  PhoneLocationReading? _location;
  Object? _locationError;

  @override
  void initState() {
    super.initState();
    _startLocation();
  }

  Future<void> _startLocation() async {
    await _subscription?.cancel();
    if (mounted) {
      setState(() => _locationError = null);
    }
    try {
      final stream = await widget.watchLocation();
      _subscription = stream.listen(
        (reading) {
          if (mounted) setState(() => _location = reading);
        },
        onError: (Object error) {
          if (mounted) setState(() => _locationError = error);
        },
      );
    } catch (error) {
      if (mounted) setState(() => _locationError = error);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.plan.targetFor(widget.stationNumber);
    final location = _location;
    final current = location == null
        ? null
        : LatLng(location.latitude, location.longitude);
    final distance = current == null
        ? null
        : ScoutingRouteGenerator.distanceMeters(current, target.location);
    final bearing = current == null
        ? null
        : ScoutingRouteGenerator.bearingDegrees(current, target.location);
    return ListView(
      key: const Key('station_route_guidance_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Text(
          'BLOCK ${widget.blockNumber} · STATION ${widget.stationNumber}',
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Go toward Station ${widget.stationNumber}',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          widget.plan.pattern == 'w'
              ? 'Use the W orientation only while crossing remains practical and safe.'
              : 'Follow the approximate generated spine and alternating branch guidance only where access remains practical and safe.',
          style: const TextStyle(height: 1.4),
        ),
        if (target.sideHint != null) ...[
          const SizedBox(height: 6),
          Text(
            target.sideHint == 'right_when_accessible'
                ? 'Suggested sampling side: right, when accessible.'
                : 'Suggested sampling side: left, when accessible.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 14),
        OfflineScoutingRouteMap(
          boundary: widget.boundary,
          plan: widget.plan,
          activeStation: widget.stationNumber,
          completedStationLocations: widget.completedStationLocations,
          completedStationNumbers: widget.completedStationNumbers,
          imageryProvider: widget.imageryProvider,
          currentLocation: location,
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: location == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _locationError == null
                            ? 'Waiting for phone location…'
                            : _friendlyLocationError(_locationError!),
                        key: const Key('route_location_status'),
                      ),
                      if (_locationError != null)
                        TextButton.icon(
                          key: const Key('retry_route_location'),
                          onPressed: _startLocation,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry phone location'),
                        ),
                    ],
                  )
                : Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      _Metric(
                        label: 'Straight-line distance',
                        value: _distanceLabel(distance!),
                        key: const Key('route_distance_metric'),
                      ),
                      _Metric(
                        label: 'Approximate direction',
                        value:
                            '${ScoutingRouteGenerator.approximateDirection(bearing!)} · ${bearing.toStringAsFixed(0)}°',
                        key: const Key('route_direction_metric'),
                      ),
                      _Metric(
                        label: 'Reported GPS accuracy',
                        value:
                            '±${location.accuracyMeters.toStringAsFixed(1)} m',
                        key: const Key('route_accuracy_metric'),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'The app will not infer that you arrived. Confirm only after you physically reach a safe, suitable station location.',
          style: TextStyle(height: 1.4),
        ),
        if (widget.plan.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            key: const Key('route_warning_help'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Route limitations'),
            children: [
              for (final warning in widget.plan.warnings)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.warning_amber),
                  title: Text(warning),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton.icon(
            key: const Key('confirm_station_reached_button'),
            onPressed: widget.isSaving ? null : widget.onConfirmReached,
            icon: const Icon(Icons.flag),
            label: Text('I reached Station ${widget.stationNumber}'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('adjust_active_station_target'),
          onPressed: widget.isSaving ? null : widget.onAdjustTarget,
          icon: const Icon(Icons.edit_location_alt),
          label: const Text('Target is inaccessible or unsafe'),
        ),
        TextButton.icon(
          key: const Key('edit_route_preparation'),
          onPressed: widget.isSaving ? null : widget.onEditRoute,
          icon: const Icon(Icons.tune),
          label: const Text('Edit route preparation'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Approximate guidance only—not turn-by-turn navigation, validated station placement, proof of protocol compliance, or a legal/survey-grade boundary.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 130),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

String _distanceLabel(double meters) => meters >= 1000
    ? '${(meters / 1000).toStringAsFixed(2)} km'
    : '${meters.toStringAsFixed(meters < 100 ? 1 : 0)} m';

String _friendlyLocationError(Object error) => error
    .toString()
    .replaceFirst('PhoneLocationException: ', '')
    .replaceFirst('Exception: ', '');
