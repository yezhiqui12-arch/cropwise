import 'dart:async';
import '../localization/app_text.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../services/field_imagery_provider.dart';
import '../services/illustrated_field_geometry.dart';
import '../services/phone_location_service.dart';
import '../services/polygon_calculator.dart';
import '../services/map_view_policy.dart';
import '../services/scouting_route_generator.dart';
import '../services/scouting_sampling_protocol.dart';
import '../theme/app_colors.dart';
import 'available_satellite_layer.dart';

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

/// Scout-owned field guidance with an online basemap when available and a
/// deterministic field-geometry illustration always ready underneath it.
class OfflineScoutingRouteMap extends StatefulWidget {
  const OfflineScoutingRouteMap({
    super.key,
    required this.boundary,
    required this.plan,
    this.activeStation,
    this.completedStationLocations = const {},
    this.completedStationNumbers = const {},
    this.evidenceStationNumbers,
    this.currentLocation,
    this.candidate,
    this.animateFromCompletedStation,
    this.animateAssessmentStation,
    this.assessmentStation,
    this.onTap,
    this.height = 340,
    this.imageryProvider,
    this.recenterFieldRevision = 0,
    this.recenterLocationRevision = 0,
    this.showMapChrome = true,
    this.minimalChrome = false,
    this.viewportBottomInset = 0,
    this.onTargetTap,
  });

  final List<LatLng> boundary;
  final ScoutingRoutePlan plan;
  final int? activeStation;
  final Map<int, LatLng> completedStationLocations;
  final Set<int> completedStationNumbers;

  /// Explicit photo coverage; null retains the older completed-station fallback.
  final Set<int>? evidenceStationNumbers;
  final PhoneLocationReading? currentLocation;
  final LatLng? candidate;
  final int? animateFromCompletedStation;

  /// Animates only the generated sampling leg for the active station.
  final int? animateAssessmentStation;

  /// Identifies the sampling leg to highlight without starting an animation.
  final int? assessmentStation;
  final ValueChanged<LatLng>? onTap;
  final double height;
  final FieldImageryProvider? imageryProvider;

  /// Increment to ask the map to fit the full field boundary again.
  final int recenterFieldRevision;

  /// Increment to center the map on the latest phone location.
  final int recenterLocationRevision;

  /// Hides labels, compass, scale, and attribution in embedded previews.
  final bool showMapChrome;
  final bool minimalChrome;

  /// Space covered by an overlaid action sheet, in logical pixels.
  final double viewportBottomInset;
  final ValueChanged<int>? onTargetTap;

  @override
  State<OfflineScoutingRouteMap> createState() =>
      _OfflineScoutingRouteMapState();
}

class _OfflineScoutingRouteMapState extends State<OfflineScoutingRouteMap>
    with SingleTickerProviderStateMixin {
  FieldImagerySource? _imagery;
  bool _resolvingImagery = true;
  bool _imageryFailed = false;
  double _zoom = 17;
  final _scaleCamera = ValueNotifier<({double latitude, double zoom})>((
    latitude: 17.7905,
    zoom: 17,
  ));
  late LatLng _mapCenter;
  final MapController _mapController = MapController();
  late final AnimationController _stationTransitionController;
  late Set<int> _knownCompletedStations;
  List<LatLng> _stationTransitionPath = const [];
  bool _mapReady = false;
  int _transitionGeneration = 0;
  LatLng? _cameraAnimationStart;
  LatLng? _cameraAnimationTarget;
  double? _cameraZoomStart;
  double? _cameraZoomTarget;

  @override
  void initState() {
    super.initState();
    _mapCenter = _fieldCenter;
    _scaleCamera.value = (latitude: _mapCenter.latitude, zoom: _zoom);
    _knownCompletedStations = _completedStationsFor(widget);
    _stationTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addListener(_animateTransitionCamera);
    if (widget.animateFromCompletedStation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startStationTransition(widget.animateFromCompletedStation!);
        }
      });
    }
    unawaited(_resolveImagery());
  }

  @override
  void didUpdateWidget(OfflineScoutingRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isDaWalk && oldWidget.activeStation != widget.activeStation) {
      _cancelAutomaticCameraMovement();
      _stationTransitionPath = const [];
    }
    final completedNow = _completedStationsFor(widget);
    final newlyCompleted = completedNow.difference(_knownCompletedStations);
    _knownCompletedStations = completedNow;
    if (newlyCompleted.isNotEmpty && !_isDaWalk) {
      _startStationTransition(newlyCompleted.reduce(math.max));
    } else if (oldWidget.animateFromCompletedStation !=
            widget.animateFromCompletedStation &&
        widget.animateFromCompletedStation != null) {
      _startStationTransition(widget.animateFromCompletedStation!);
    }
    if (oldWidget.plan.boundaryVersionId != widget.plan.boundaryVersionId ||
        oldWidget.imageryProvider != widget.imageryProvider) {
      _mapCenter = _fieldCenter;
      unawaited(_resolveImagery());
    }
    if (oldWidget.recenterFieldRevision != widget.recenterFieldRevision ||
        (oldWidget.viewportBottomInset != widget.viewportBottomInset &&
            oldWidget.animateFromCompletedStation ==
                widget.animateFromCompletedStation)) {
      final generation = _transitionGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // A newer handoff or user camera choice supersedes a queued resize fit.
        if (generation == _transitionGeneration) _fitField();
      });
    }
    if (oldWidget.recenterLocationRevision != widget.recenterLocationRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusLocation());
    }
  }

  void _fitField() {
    if (!mounted || !_mapReady) return;
    // Wait for the panel to collapse before fitting into a nearly hidden map.
    if (_mapController.camera.nonRotatedSize.height -
            widget.viewportBottomInset <
        120) {
      return;
    }
    _cancelAutomaticCameraMovement();
    if (widget.boundary.length >= 3) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(widget.boundary),
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            widget.minimalChrome ? 78 : 24,
            24 + widget.viewportBottomInset,
          ),
        ),
      );
      return;
    }
    _mapController.move(_fieldCenter, _zoom);
  }

  void _focusLocation() {
    if (!mounted || !_mapReady || widget.currentLocation == null) return;
    final reading = widget.currentLocation!;
    final position = LatLng(reading.latitude, reading.longitude);
    if (!PolygonCalculator.isValidCoordinate(position)) return;
    _cancelAutomaticCameraMovement();
    _mapController.move(
      position,
      math.max(_zoom, 18),
      offset: Offset(0, -widget.viewportBottomInset / 2),
    );
  }

  void _cancelAutomaticCameraMovement() {
    // A user's camera choice takes precedence over route presentation.
    ++_transitionGeneration;
    _cameraAnimationStart = null;
    _cameraAnimationTarget = null;
    _cameraZoomStart = null;
    _cameraZoomTarget = null;
    _stationTransitionController.stop();
    if (_isDaWalk) _stationTransitionController.value = 1;
  }

  bool get _isDaWalk =>
      widget.plan.pattern == ScoutingSamplingProtocol.daPattern;

  void _startStationTransition(int completedStation) {
    final candidates = widget.plan.targets
        .where((target) => target.stationNumber > completedStation)
        .map((target) => target.stationNumber)
        .toList(growable: false);
    final next =
        widget.activeStation ?? (candidates.isEmpty ? null : candidates.first);
    if (next == null) return;
    if (!_isDaWalk || next != completedStation + 1) return;
    final start = widget.plan.targetFor(completedStation).location;
    final end = widget.plan.targetFor(next).location;
    _beginDaPlantTransition([start, end]);
  }

  void _beginDaPlantTransition(List<LatLng> path) {
    _cancelAutomaticCameraMovement();
    final generation = _transitionGeneration;
    _stationTransitionController.duration = const Duration(milliseconds: 900);
    _stationTransitionController.reset();
    setState(() => _stationTransitionPath = path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady || generation != _transitionGeneration) return;
      final camera = _mapController.camera;
      if (camera.nonRotatedSize.height - widget.viewportBottomInset < 120) {
        return;
      }
      final focused = CameraFit.coordinates(
        coordinates: path,
        padding: EdgeInsets.fromLTRB(
          48,
          54,
          widget.minimalChrome ? 88 : 48,
          60 + widget.viewportBottomInset,
        ),
        maxZoom: math.min(camera.zoom + .65, 19),
      ).fit(camera);
      _cameraAnimationStart = camera.center;
      _cameraAnimationTarget = focused.center;
      _cameraZoomStart = camera.zoom;
      _cameraZoomTarget = focused.zoom;
      if (MediaQuery.disableAnimationsOf(context)) {
        _mapController.move(focused.center, focused.zoom);
        _stationTransitionController.value = 1;
      } else {
        _stationTransitionController.forward(from: 0);
      }
    });
  }

  void _animateTransitionCamera() {
    if (!_mapReady ||
        _cameraAnimationStart == null ||
        _cameraAnimationTarget == null ||
        _cameraZoomStart == null ||
        _cameraZoomTarget == null) {
      return;
    }
    final progress = Curves.easeInOutCubic.transform(
      (_stationTransitionController.value / (_isDaWalk ? 1 : .30)).clamp(
        0.0,
        1.0,
      ),
    );
    final start = _cameraAnimationStart!;
    final target = _cameraAnimationTarget!;
    _mapController.move(
      LatLng(
        start.latitude + (target.latitude - start.latitude) * progress,
        start.longitude + (target.longitude - start.longitude) * progress,
      ),
      _cameraZoomStart! + (_cameraZoomTarget! - _cameraZoomStart!) * progress,
      id: 'station_transition_camera',
    );
  }

  @override
  void dispose() {
    _scaleCamera.dispose();
    _mapController.dispose();
    _stationTransitionController.dispose();
    super.dispose();
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
    if (!_isDaWalk) {
      return const Center(
        child: AppText('This scouting method is no longer supported.'),
      );
    }

    final completedStations = _completedStationsFor(widget);
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
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: MapViewPolicy.initialCenter(_fieldCenter),
                    initialZoom: 17,
                    minZoom: MapViewPolicy.minZoom,
                    maxZoom: MapViewPolicy.maxZoom,
                    initialCameraFit: widget.boundary.length >= 3
                        ? CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(widget.boundary),
                            padding: EdgeInsets.fromLTRB(
                              34,
                              34,
                              widget.minimalChrome ? 78 : 34,
                              34 + widget.viewportBottomInset,
                            ),
                          )
                        : null,
                    onMapReady: () => _mapReady = true,
                    onTap: widget.onTap == null
                        ? null
                        : (_, location) => widget.onTap!(location),
                    onPositionChanged: (camera, hasGesture) {
                      if (hasGesture) _cancelAutomaticCameraMovement();
                      if ((_zoom - camera.zoom).abs() < 0.001 &&
                          _mapCenter == camera.center) {
                        return;
                      }
                      _zoom = camera.zoom;
                      _mapCenter = camera.center;
                      _scaleCamera.value = (
                        latitude: camera.center.latitude,
                        zoom: camera.zoom,
                      );
                    },
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
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
                      if (_imagery!.tileUrlTemplate!.contains(
                        '/World_Imagery/MapServer/',
                      ))
                        AvailableSatelliteLayer(
                          onError: _markOnlineImageryFailed,
                        )
                      else
                        TileLayer(
                          tileUpdateTransformer:
                              TileUpdateTransformers.debounce(
                                const Duration(milliseconds: 160),
                              ),
                          panBuffer: 0,
                          keepBuffer: 3,
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
                            color: const Color(0x2419C85A),
                            borderColor: const Color(0xAA8DFF63),
                            borderStrokeWidth:
                                widget.plan.pattern ==
                                    ScoutingSamplingProtocol.daPattern
                                ? 3
                                : 9,
                          ),
                          Polygon(
                            points: widget.boundary,
                            color: Colors.transparent,
                            borderColor: const Color(0xFF064D2B),
                            borderStrokeWidth:
                                widget.plan.pattern ==
                                    ScoutingSamplingProtocol.daPattern
                                ? 1.5
                                : 4,
                            pattern:
                                widget.plan.pattern ==
                                    ScoutingSamplingProtocol.daPattern
                                ? const StrokePattern.solid()
                                : StrokePattern.dashed(segments: const [11, 7]),
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
                        if (_isDaWalk)
                          ...daPlantConnectionLines(
                            widget.plan,
                            widget.evidenceStationNumbers ??
                                widget.completedStationNumbers,
                          ),
                        for (final segment in widget.plan.segments)
                          if (segment.points.length >= 2)
                            _routePolyline(
                              segment,
                              _routeStateForSegment(segment, completedStations),
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
                    if (_stationTransitionPath.length >= 2)
                      AnimatedBuilder(
                        animation: _stationTransitionController,
                        builder: (context, _) {
                          final progress = Curves.easeInOutCubic.transform(
                            (_isDaWalk
                                    ? _stationTransitionController.value
                                    : (_stationTransitionController.value -
                                              .20) /
                                          .65)
                                .clamp(0.0, 1.0),
                          );
                          return PolylineLayer(
                            key: _isDaWalk
                                ? const Key('da_next_plant_leg')
                                : null,
                            polylines: [
                              Polyline(
                                points: _partialRoutePoints(
                                  _stationTransitionPath,
                                  progress,
                                ),
                                color: const Color(0xFF27A966),
                                strokeWidth: _isDaWalk ? 3.5 : 7,
                                borderColor: Colors.white,
                                borderStrokeWidth: _isDaWalk ? 1 : 2.5,
                                pattern:
                                    _isDaWalk &&
                                        !(widget.evidenceStationNumbers ??
                                                widget.completedStationNumbers)
                                            .contains(widget.activeStation)
                                    ? StrokePattern.dashed(
                                        segments: const [9, 6],
                                      )
                                    : const StrokePattern.solid(),
                              ),
                            ],
                          );
                        },
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
                    Builder(
                      builder: (context) => MarkerLayer(
                        markers: _markers(
                          completedStations,
                          MapCamera.of(context),
                        ),
                      ),
                    ),
                    if (_stationTransitionPath.length >= 2)
                      AnimatedBuilder(
                        animation: _stationTransitionController,
                        builder: (context, _) {
                          final raw = _stationTransitionController.value;
                          final travel = Curves.easeInOutCubic.transform(
                            ((raw - .20) / .65).clamp(0.0, 1.0),
                          );
                          final pulse = raw < .85
                              ? 1.0
                              : 1.0 +
                                    math.sin((raw - .85) / .15 * math.pi) * .45;
                          return MarkerLayer(
                            markers: [
                              if (!_isDaWalk || raw < 1)
                                Marker(
                                  point: _isDaWalk
                                      ? _stationTransitionPath.last
                                      : _pointAlongPath(
                                          _stationTransitionPath,
                                          travel,
                                        ),
                                  width: _isDaWalk ? 66 : 38 * pulse,
                                  height: _isDaWalk ? 66 : 38 * pulse,
                                  child: _isDaWalk
                                      ? IgnorePointer(
                                          child: Opacity(
                                            opacity: math
                                                .sin(raw * math.pi)
                                                .clamp(0.0, 1.0),
                                            child: Container(
                                              key: const Key(
                                                'da_next_plant_highlight',
                                              ),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: AppColors.primary,
                                                  width: 2,
                                                ),
                                                color: AppColors.primary
                                                    .withValues(alpha: .10),
                                              ),
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
              if (widget.showMapChrome && !widget.minimalChrome)
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
              if (widget.showMapChrome && !widget.minimalChrome)
                const Positioned(right: 10, top: 10, child: _NorthArrow()),
              if (widget.showMapChrome && !widget.minimalChrome)
                Positioned(
                  left: 10,
                  bottom: 52,
                  child:
                      ValueListenableBuilder<({double latitude, double zoom})>(
                        valueListenable: _scaleCamera,
                        builder: (context, camera, _) => _ScaleBar(
                          definition: scaleBarFor(
                            latitude: camera.latitude,
                            zoom: camera.zoom,
                          ),
                        ),
                      ),
                ),
              if (widget.showMapChrome)
                Positioned(
                  left: 8,
                  right: widget.minimalChrome ? null : 8,
                  bottom: 8 + widget.viewportBottomInset,
                  child: _MapAttribution(
                    compact: widget.minimalChrome,
                    text: showImagery
                        ? _imagery!.attribution
                        : widget.minimalChrome
                        ? 'Offline field illustration'
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

  RouteProgressState _routeStateForSegment(
    ScoutingRouteSegment segment,
    Set<int> completedStations,
  ) {
    return routeProgressStateFor(
      segment: segment,
      activeStation: widget.activeStation,
      completedStations: completedStations,
    );
  }

  List<Marker> _markers(Set<int> completedStations, MapCamera camera) => [
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
    if (widget.plan.pattern == ScoutingSamplingProtocol.daPattern)
      ..._plantMarkers(completedStations, camera)
    else
      for (final target in widget.plan.targets)
        Marker(
          point: target.location,
          width: 48,
          height: 48,
          child: KeyedSubtree(
            key: Key('route_station_marker_${target.stationNumber}'),
            child: _StationTargetMarker(
              stationNumber: target.stationNumber,
              isPlant:
                  widget.plan.pattern == ScoutingSamplingProtocol.daPattern,
              upcoming:
                  widget.activeStation != null &&
                  target.stationNumber > widget.activeStation! &&
                  target.stationNumber <= widget.activeStation! + 2,
              active: target.stationNumber == widget.activeStation,
              completed:
                  target.lockedCompleted ||
                  completedStations.contains(target.stationNumber),
            ),
          ),
        ),
    if (widget.plan.pattern != ScoutingSamplingProtocol.daPattern)
      for (final entry in widget.completedStationLocations.entries)
        Marker(
          point: entry.value,
          width: 38,
          height: 38,
          child: _RouteMarker(
            icon: Icons.check_circle,
            color: AppColors.primary,
            label:
                'Recorded completed ${widget.plan.pattern == ScoutingSamplingProtocol.daPattern ? 'Plant' : 'Station'} ${entry.key} location',
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
        child: widget.plan.pattern == ScoutingSamplingProtocol.daPattern
            ? Semantics(
                label: 'Current phone location',
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              )
            : const _RouteMarker(
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

  List<Marker> _plantMarkers(Set<int> completed, MapCamera camera) {
    // Keep numbered map anchors stable. Capture GPS remains in plant details;
    // a noisy fix must not move a saved pin out of the field.
    final targets = widget.plan.targets;
    final separate = camera.zoom >= 17.5
        ? targets
        : const <ScoutingStationTarget>[];
    final groups = [
      ...groupScoutingPlantPins(
        targets.where((t) => !separate.contains(t)).toList(),
        camera.latLngToScreenOffset,
      ),
      for (final target in separate) ScoutingPlantPinGroup([target]),
    ];
    return [
      for (final group in groups)
        Marker(
          point: group.location,
          width: 44,
          height: 44,
          child: GestureDetector(
            key: Key(
              group.targets.length == 1
                  ? 'route_station_marker_${group.targets.single.stationNumber}'
                  : 'route_plant_cluster_${group.targets.map((t) => t.stationNumber).join('_')}',
            ),
            behavior: HitTestBehavior.opaque,
            onTap: () => group.targets.length == 1
                ? _openPlant(group.targets.single.stationNumber)
                : _openPlantGroup(group),
            child: group.targets.length == 1
                ? _StationTargetMarker(
                    stationNumber: group.targets.single.stationNumber,
                    isPlant: true,
                    active:
                        group.targets.single.stationNumber ==
                        widget.activeStation,
                    completed: completed.contains(
                      group.targets.single.stationNumber,
                    ),
                    upcoming:
                        widget.activeStation != null &&
                        group.targets.single.stationNumber >
                            widget.activeStation! &&
                        group.targets.single.stationNumber <=
                            widget.activeStation! + 2,
                    compact: camera.zoom < 17.5,
                  )
                : Semantics(
                    button: true,
                    label:
                        '${group.targets.length} sampling plants. Tap to see plants.',
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color:
                              group.targets.any(
                                (t) => t.stationNumber == widget.activeStation,
                              )
                              ? AppColors.primary
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.layers_outlined,
                              size: 12,
                              color:
                                  group.targets.any(
                                    (t) =>
                                        t.stationNumber == widget.activeStation,
                                  )
                                  ? Colors.white
                                  : AppColors.primary,
                            ),
                            Text(
                              '${group.targets.length}',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color:
                                    group.targets.any(
                                      (t) =>
                                          t.stationNumber ==
                                          widget.activeStation,
                                    )
                                    ? Colors.white
                                    : AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
    ];
  }

  void _openPlant(int number) {
    if (widget.onTargetTap != null) {
      widget.onTargetTap!(number);
      return;
    }
    final target = widget.plan.targetFor(number);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppText('Plant $number'),
        content: Text(
          '${target.location.latitude.toStringAsFixed(6)}, ${target.location.longitude.toStringAsFixed(6)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('Close'),
          ),
        ],
      ),
    );
  }

  void _openPlantGroup(ScoutingPlantPinGroup group) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(
              '${group.targets.length} nearby plants',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            TextButton.icon(
              icon: const Icon(Icons.zoom_in),
              label: const AppText('Zoom to these plants'),
              onPressed: () {
                Navigator.pop(sheetContext);
                _cancelAutomaticCameraMovement();
                _mapController.fitCamera(
                  CameraFit.coordinates(
                    coordinates: group.targets.map((t) => t.location).toList(),
                    padding: EdgeInsets.fromLTRB(
                      44,
                      60,
                      44,
                      44 + widget.viewportBottomInset,
                    ),
                    maxZoom: 20,
                  ),
                );
              },
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final target in group.targets)
                    ListTile(
                      title: AppText('Plant ${target.stationNumber}'),
                      subtitle: AppText(
                        _completedStationsFor(
                              widget,
                            ).contains(target.stationNumber)
                            ? 'Sampled'
                            : target.stationNumber == widget.activeStation
                            ? 'Current plant'
                            : 'Not sampled',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _openPlant(target.stationNumber);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScoutingPlantPinGroup {
  const ScoutingPlantPinGroup(this.targets);
  final List<ScoutingStationTarget> targets;
  LatLng get location => LatLng(
    targets.fold<double>(0, (sum, t) => sum + t.location.latitude) /
        targets.length,
    targets.fold<double>(0, (sum, t) => sum + t.location.longitude) /
        targets.length,
  );
}

/// Group by actual screen distance, so zoom, pan and rotation stay in sync.
/// Stable plant numbers are retained in each group; no sampling data is merged.
List<ScoutingPlantPinGroup> groupScoutingPlantPins(
  List<ScoutingStationTarget> targets,
  Offset Function(LatLng) project, {
  double spacing = 44,
}) {
  final pixels = targets.map((t) => project(t.location)).toList();
  // Bounded groups avoid chaining a spread-out field into one badge.
  final groups = <List<int>>[];
  for (var i = 0; i < targets.length; i++) {
    final nearby = groups
        .where(
          (group) =>
              group.every((j) => (pixels[i] - pixels[j]).distance < spacing),
        )
        .firstOrNull;
    if (nearby == null) {
      groups.add([i]);
    } else {
      nearby.add(i);
    }
  }
  return [
    for (final group in groups)
      ScoutingPlantPinGroup(
        List.unmodifiable(
          group.map((i) => targets[i]).toList()
            ..sort((a, b) => a.stationNumber.compareTo(b.stationNumber)),
        ),
      ),
  ];
}

Set<int> _completedStationsFor(OfflineScoutingRouteMap map) => {
  ...map.completedStationNumbers,
  ...map.completedStationLocations.keys,
  for (final target in map.plan.targets)
    if (target.lockedCompleted ||
        (map.activeStation != null &&
            target.stationNumber < map.activeStation!))
      target.stationNumber,
};

List<LatLng> _partialRoutePoints(List<LatLng> points, double progress) {
  if (points.length < 2 || progress <= 0) return [points.first, points.first];
  if (progress >= 1) return points;
  final scaled = progress * (points.length - 1);
  final completedSegments = scaled.floor();
  final result = points.take(completedSegments + 1).toList();
  final fraction = scaled - completedSegments;
  final first = points[completedSegments];
  final second = points[completedSegments + 1];
  result.add(
    LatLng(
      first.latitude + (second.latitude - first.latitude) * fraction,
      first.longitude + (second.longitude - first.longitude) * fraction,
    ),
  );
  return result;
}

LatLng _pointAlongPath(List<LatLng> points, double progress) =>
    _partialRoutePoints(points, progress).last;

LatLngBounds _latLngBounds(FieldImageryBounds bounds) => LatLngBounds(
  LatLng(bounds.south, bounds.west),
  LatLng(bounds.north, bounds.east),
);

List<Polyline> daPlantConnectionLines(
  ScoutingRoutePlan plan,
  Set<int> evidence,
) {
  final targets = [...plan.targets]
    ..sort((a, b) => a.stationNumber.compareTo(b.stationNumber));
  return [
    for (var i = 1; i < targets.length; i++)
      Polyline(
        points: [targets[i - 1].location, targets[i].location],
        color:
            evidence.contains(targets[i - 1].stationNumber) &&
                evidence.contains(targets[i].stationNumber)
            ? const Color(0xFF27A966)
            : const Color(0xFF8DE0B3),
        strokeWidth: 3.5,
        borderColor: const Color(0xDDFFFFFF),
        borderStrokeWidth: 1,
        pattern:
            evidence.contains(targets[i - 1].stationNumber) &&
                evidence.contains(targets[i].stationNumber)
            ? const StrokePattern.solid()
            : StrokePattern.dashed(segments: const [9, 6]),
      ),
  ];
}

Polyline _routePolyline(
  ScoutingRouteSegment segment,
  RouteProgressState state,
) => Polyline(
  points: segment.points,
  color: routeProgressColor(state),
  strokeWidth: state == RouteProgressState.active ? 6 : 4.5,
  borderColor: Colors.white,
  borderStrokeWidth: 2,
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
    this.isPlant = false,
    this.upcoming = false,
    this.compact = false,
  });

  final int stationNumber;
  final bool active;
  final bool completed;
  final bool isPlant;
  final bool upcoming;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = isPlant
        ? completed || active
              ? AppColors.primary
              : upcoming
              ? const Color(0xFFBBDFB7)
              : const Color(0xFF607A5A)
        : completed
        ? AppColors.primary
        : active
        ? const Color(0xFFE98B00)
        : const Color(0xFF68766F);
    return Semantics(
      label:
          '${isPlant ? 'Plant' : 'Station'} $stationNumber${completed
              ? ', completed'
              : active
              ? ', active'
              : ', future'}',
      child: Center(
        child: SizedBox(
          width: isPlant
              ? (active
                    ? 32
                    : upcoming
                    ? (compact ? 20 : 28)
                    : (compact ? 14 : 24))
              : 44,
          height: isPlant
              ? (active
                    ? 32
                    : upcoming
                    ? (compact ? 20 : 28)
                    : (compact ? 14 : 24))
              : 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white, width: isPlant ? 2 : 3),
              boxShadow: const [
                BoxShadow(blurRadius: 3, color: Colors.black38),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (completed && !isPlant)
                  Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: isPlant ? 17 : 23,
                  )
                else if (active && !isPlant)
                  const Icon(Icons.flag_rounded, color: Colors.white, size: 21)
                else if (!isPlant || active || !compact)
                  AppText(
                    '$stationNumber',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: isPlant ? (active ? 14 : 11) : 14,
                      color: isPlant && upcoming
                          ? AppColors.primary
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (!isPlant && (completed || active))
                  Positioned(
                    right: 5,
                    bottom: 3,
                    child: AppText(
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
            AppText(
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
  const _MapAttribution({
    required this.text,
    required this.illustrated,
    this.compact = false,
  });

  final String text;
  final bool illustrated;
  final bool compact;

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
          illustrated && !compact
              ? '$text · illustrative rows, not remote observations'
              : text,
          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}
