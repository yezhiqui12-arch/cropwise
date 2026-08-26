import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../services/field_imagery_provider.dart';
import '../services/illustrated_field_geometry.dart';
import '../services/phone_location_service.dart';
import '../services/scouting_route_generator.dart';
import '../theme/app_colors.dart';

enum RouteProgressState { completed, active, future, invalid }

Color routeProgressColor(RouteProgressState state) => switch (state) {
  RouteProgressState.completed => AppColors.primary,
  RouteProgressState.active => const Color(0xFFF57C00),
  RouteProgressState.future => const Color(0xFF60727A),
  RouteProgressState.invalid => const Color(0xFFB3261E),
};

IconData routeProgressIcon(RouteProgressState state) => switch (state) {
  RouteProgressState.completed => Icons.check_circle,
  RouteProgressState.active => Icons.arrow_circle_right,
  RouteProgressState.future => Icons.more_horiz,
  RouteProgressState.invalid => Icons.warning,
};

RouteProgressState routeProgressStateFor({
  required ScoutingRouteSegment segment,
  required int? activeStation,
  required Set<int> completedStations,
}) {
  if (!segment.drawable) return RouteProgressState.invalid;
  final station = segment.stationNumber;
  if (station != null && completedStations.contains(station)) {
    return RouteProgressState.completed;
  }
  if (station != null && station == activeStation) {
    return RouteProgressState.active;
  }
  return RouteProgressState.future;
}

/// Scan-owned field guidance with an online basemap when available and a
/// deterministic field-geometry illustration always ready underneath it.
class OfflineScoutingRouteMap extends StatefulWidget {
  const OfflineScoutingRouteMap({
    super.key,
    required this.boundary,
    required this.plan,
    this.activeStation,
    this.completedStationLocations = const {},
    this.completedStationNumbers = const {},
    this.currentLocation,
    this.candidate,
    this.onTap,
    this.height = 340,
    this.imageryProvider,
  });

  final List<LatLng> boundary;
  final ScoutingRoutePlan plan;
  final int? activeStation;
  final Map<int, LatLng> completedStationLocations;
  final Set<int> completedStationNumbers;
  final PhoneLocationReading? currentLocation;
  final LatLng? candidate;
  final ValueChanged<LatLng>? onTap;
  final double height;
  final FieldImageryProvider? imageryProvider;

  @override
  State<OfflineScoutingRouteMap> createState() =>
      _OfflineScoutingRouteMapState();
}

class _OfflineScoutingRouteMapState extends State<OfflineScoutingRouteMap> {
  FieldImagerySource? _imagery;
  bool _resolvingImagery = true;
  bool _imageryFailed = false;
  double _zoom = 17;
  late LatLng _mapCenter;

  @override
  void initState() {
    super.initState();
    _mapCenter = _fieldCenter;
    unawaited(_resolveImagery());
  }

  @override
  void didUpdateWidget(OfflineScoutingRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.boundaryVersionId != widget.plan.boundaryVersionId ||
        oldWidget.imageryProvider != widget.imageryProvider) {
      _mapCenter = _fieldCenter;
      unawaited(_resolveImagery());
    }
  }

  LatLng get _fieldCenter => widget.boundary.isEmpty
      ? const LatLng(0, 0)
      : ScoutingRouteGenerator.polygonCenter(widget.boundary);

  Future<void> _resolveImagery() async {
    if (mounted) {
      setState(() {
        _resolvingImagery = true;
        _imageryFailed = false;
        _imagery = null;
      });
    }
    try {
      final provider = widget.imageryProvider;
      final source = provider == null
          ? null
          : await provider.resolve(
              FieldImageryRequest(
                assessmentId: widget.plan.assessmentId,
                boundaryVersionId: widget.plan.boundaryVersionId,
                boundary: widget.boundary,
              ),
            );
      if (!mounted) return;
      setState(() {
        _imagery = source;
        _resolvingImagery = false;
      });
      if (source?.isPackaged == true) {
        unawaited(_monitorPackagedImage(source!));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _imagery = null;
        _resolvingImagery = false;
        _imageryFailed = true;
      });
    }
  }

  Future<void> _verifyImage(ImageProvider provider) {
    final completer = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  Future<void> _monitorPackagedImage(FieldImagerySource source) async {
    try {
      await _verifyImage(source.imageProvider!);
    } catch (_) {
      if (!mounted || !identical(_imagery, source)) return;
      setState(() => _imageryFailed = true);
    }
  }

  void _markOnlineImageryFailed() {
    if (_imageryFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _imageryFailed) return;
      setState(() => _imageryFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final completedStations = {
      ...widget.completedStationNumbers,
      ...widget.completedStationLocations.keys,
      for (final target in widget.plan.targets)
        if (target.lockedCompleted) target.stationNumber,
    };
    final illustrated = widget.boundary.length >= 3
        ? IllustratedFieldGeometryGenerator.generate(
            boundary: widget.boundary,
            rowBearingDegrees: widget.plan.preparation.rowBearingDegrees ?? 0,
          )
        : null;
    final showImagery = _imagery != null && !_imageryFailed;

    return Semantics(
      label:
          'Approximate assessment route map with online field imagery when available and an offline illustrated field view as fallback. It is not turn-by-turn navigation or proof of sampling compliance.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          key: const Key('offline_scouting_route_map'),
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: const Color(0xFFD8C9AD),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: _fieldCenter,
                    initialZoom: 17,
                    initialCameraFit: widget.boundary.length >= 3
                        ? CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(widget.boundary),
                            padding: const EdgeInsets.all(34),
                          )
                        : null,
                    onTap: widget.onTap == null
                        ? null
                        : (_, location) => widget.onTap!(location),
                    onPositionChanged: (camera, _) {
                      if ((_zoom - camera.zoom).abs() < 0.001 &&
                          _mapCenter == camera.center) {
                        return;
                      }
                      setState(() {
                        _zoom = camera.zoom;
                        _mapCenter = camera.center;
                      });
                    },
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    if (illustrated != null) ...[
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: widget.boundary,
                            color: const Color(0xFFB89B6B),
                            borderColor: const Color(0xFF6D5635),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                      PolylineLayer(
                        polylines: [
                          for (final line in illustrated.textureSegments)
                            Polyline(
                              points: line,
                              color: const Color(
                                0xFF6D5635,
                              ).withValues(alpha: 0.18),
                              strokeWidth: 1,
                            ),
                          for (final line in illustrated.rowSegments)
                            Polyline(
                              points: line,
                              color: const Color(
                                0xFF315C35,
                              ).withValues(alpha: 0.30),
                              strokeWidth: 1.4,
                            ),
                        ],
                      ),
                    ],
                    if (showImagery && _imagery!.isOnline)
                      TileLayer(
                        urlTemplate: _imagery!.tileUrlTemplate!,
                        maxNativeZoom: _imagery!.tileMaxNativeZoom,
                        userAgentPackageName: 'com.wormwise.app.wormwise',
                        errorTileCallback: (_, _, _) =>
                            _markOnlineImageryFailed(),
                      ),
                    if (showImagery && _imagery!.isPackaged)
                      OverlayImageLayer(
                        overlayImages: [
                          OverlayImage(
                            imageProvider: _imagery!.imageProvider!,
                            bounds: _latLngBounds(_imagery!.imageBounds!),
                            filterQuality: FilterQuality.high,
                          ),
                        ],
                      ),
                    if (widget.boundary.length >= 3)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: widget.boundary,
                            color: Colors.transparent,
                            borderColor: AppColors.primary,
                            borderStrokeWidth: 3,
                          ),
                          for (final obstacle
                              in widget.plan.preparation.obstacles)
                            if (obstacle.length >= 3)
                              Polygon(
                                points: obstacle,
                                color: const Color(
                                  0xFFB3261E,
                                ).withValues(alpha: 0.22),
                                borderColor: const Color(0xFFB3261E),
                                borderStrokeWidth: 2,
                              ),
                        ],
                      ),
                    PolylineLayer(
                      polylines: [
                        for (final segment in widget.plan.segments)
                          if (segment.points.length >= 2)
                            _routePolyline(
                              segment,
                              routeProgressStateFor(
                                segment: segment,
                                activeStation: widget.activeStation,
                                completedStations: completedStations,
                              ),
                            ),
                        if (widget.plan.preparation.draftPoints.length >= 2)
                          Polyline(
                            points: widget.plan.preparation.draftPoints,
                            color: const Color(0xFF7A3E00),
                            strokeWidth: 4,
                            pattern: StrokePattern.dashed(
                              segments: const [8, 6],
                            ),
                          ),
                      ],
                    ),
                    if (widget.currentLocation != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: LatLng(
                              widget.currentLocation!.latitude,
                              widget.currentLocation!.longitude,
                            ),
                            radius: widget.currentLocation!.accuracyMeters
                                .clamp(2, 250),
                            useRadiusInMeter: true,
                            color: const Color(
                              0xFF1565C0,
                            ).withValues(alpha: 0.13),
                            borderColor: const Color(0xFF1565C0),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: _markers(completedStations)),
                  ],
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                right: 58,
                child: _MapLabel(
                  key: const Key('field_imagery_state'),
                  icon: showImagery
                      ? _imagery!.kind == FieldImageryKind.onlineBasemap
                            ? Icons.map_outlined
                            : Icons.satellite_alt
                      : Icons.layers,
                  text: _imageryState(showImagery),
                ),
              ),
              const Positioned(right: 10, top: 10, child: _NorthArrow()),
              Positioned(
                left: 10,
                bottom: 52,
                child: _ScaleBar(
                  definition: scaleBarFor(
                    latitude: _mapCenter.latitude,
                    zoom: _zoom,
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: _MapAttribution(
                  text: showImagery
                      ? _imagery!.attribution
                      : 'Offline illustrated field view · generated from saved field geometry',
                  illustrated: !showImagery,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _imageryState(bool showImagery) {
    if (_resolvingImagery) {
      return 'Loading map · Offline field view ready';
    }
    if (!showImagery) {
      return 'Online map unavailable · Offline field view';
    }
    final resolution = _imagery!.resolutionLabel;
    return resolution == null || resolution.isEmpty
        ? _imagery!.displayName
        : '${_imagery!.displayName} · $resolution';
  }

  List<Marker> _markers(Set<int> completedStations) => [
    if (widget.plan.preparation.entrance != null)
      Marker(
        point: widget.plan.preparation.entrance!,
        width: 46,
        height: 46,
        child: const _RouteMarker(
          icon: Icons.login,
          color: Color(0xFF6A4C00),
          label: 'Evaluator-confirmed field entrance',
        ),
      ),
    for (final target in widget.plan.targets)
      Marker(
        point: target.location,
        width: 48,
        height: 48,
        child: KeyedSubtree(
          key: Key('route_station_marker_${target.stationNumber}'),
          child: _StationTargetMarker(
            stationNumber: target.stationNumber,
            active: target.stationNumber == widget.activeStation,
            completed:
                target.lockedCompleted ||
                completedStations.contains(target.stationNumber),
          ),
        ),
      ),
    for (final entry in widget.completedStationLocations.entries)
      Marker(
        point: entry.value,
        width: 38,
        height: 38,
        child: _RouteMarker(
          icon: Icons.check_circle,
          color: AppColors.primary,
          label: 'Recorded completed Station ${entry.key} location',
        ),
      ),
    if (widget.currentLocation != null)
      Marker(
        point: LatLng(
          widget.currentLocation!.latitude,
          widget.currentLocation!.longitude,
        ),
        width: 46,
        height: 46,
        child: const _RouteMarker(
          icon: Icons.my_location,
          color: Color(0xFF1565C0),
          label: 'Current phone location',
        ),
      ),
    if (widget.candidate != null)
      Marker(
        point: widget.candidate!,
        width: 48,
        height: 48,
        child: const _RouteMarker(
          icon: Icons.edit_location_alt,
          color: Color(0xFFB3261E),
          label: 'Proposed adjusted station target',
        ),
      ),
  ];
}

LatLngBounds _latLngBounds(FieldImageryBounds bounds) => LatLngBounds(
  LatLng(bounds.south, bounds.west),
  LatLng(bounds.north, bounds.east),
);

Polyline _routePolyline(
  ScoutingRouteSegment segment,
  RouteProgressState state,
) => Polyline(
  points: segment.points,
  color: routeProgressColor(state),
  strokeWidth: state == RouteProgressState.active ? 6 : 4,
  pattern: switch (state) {
    RouteProgressState.completed ||
    RouteProgressState.active => const StrokePattern.solid(),
    RouteProgressState.future => StrokePattern.dashed(segments: const [10, 7]),
    RouteProgressState.invalid => StrokePattern.dashed(segments: const [3, 6]),
  },
);

class ScaleBarDefinition {
  const ScaleBarDefinition({required this.meters, required this.widthPixels});

  final double meters;
  final double widthPixels;

  String get label => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)} km'
      : '${meters.toStringAsFixed(0)} m';
}

ScaleBarDefinition scaleBarFor({
  required double latitude,
  required double zoom,
  double targetPixels = 82,
}) {
  final metersPerPixel =
      156543.03392 *
      math.cos(latitude * math.pi / 180).abs().clamp(0.01, 1.0) /
      math.pow(2, zoom);
  final desiredMeters = metersPerPixel * targetPixels;
  final exponent = math.pow(10, (math.log(desiredMeters) / math.ln10).floor());
  final normalized = desiredMeters / exponent;
  final selected = normalized >= 5
      ? 5
      : normalized >= 2
      ? 2
      : 1;
  final meters = selected * exponent;
  return ScaleBarDefinition(
    meters: meters.toDouble(),
    widthPixels: (meters / metersPerPixel).clamp(28, targetPixels).toDouble(),
  );
}

class _StationTargetMarker extends StatelessWidget {
  const _StationTargetMarker({
    required this.stationNumber,
    required this.active,
    required this.completed,
  });

  final int stationNumber;
  final bool active;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? AppColors.primary
        : active
        ? const Color(0xFFE98B00)
        : const Color(0xFF68766F);
    return Semantics(
      label:
          'Station $stationNumber approximate target${completed
              ? ', completed station'
              : active
              ? ', active'
              : ', future'}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (completed)
              const Icon(Icons.check_rounded, color: Colors.white, size: 23)
            else if (active)
              const Icon(Icons.flag_rounded, color: Colors.white, size: 21)
            else
              Text(
                '$stationNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (completed || active)
              Positioned(
                right: 5,
                bottom: 3,
                child: Text(
                  '$stationNumber',
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Icon(icon, color: color, size: 30),
  );
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xEEFFFFFF),
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

class _NorthArrow extends StatelessWidget {
  const _NorthArrow();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'North arrow',
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xEEFFFFFF),
        shape: BoxShape.circle,
      ),
      child: const SizedBox(
        width: 42,
        height: 42,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'N',
              textScaler: TextScaler.noScaling,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            Icon(Icons.navigation, size: 21),
          ],
        ),
      ),
    ),
  );
}

class _ScaleBar extends StatelessWidget {
  const _ScaleBar({required this.definition});

  final ScaleBarDefinition definition;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Scale ${definition.label}',
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEEFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 4, 7, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              definition.label,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            Container(
              width: definition.widthPixels,
              height: 4,
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(width: 2),
                  right: BorderSide(width: 2),
                  bottom: BorderSide(width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MapAttribution extends StatelessWidget {
  const _MapAttribution({required this.text, required this.illustrated});

  final String text;
  final bool illustrated;

  @override
  Widget build(BuildContext context) => Semantics(
    label: illustrated
        ? '$text. Illustrated rows and texture are orientation aids, not remotely observed crop condition or obstacles.'
        : 'Map attribution: $text',
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Text(
          illustrated
              ? '$text · illustrative rows, not remote observations'
              : text,
          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}
