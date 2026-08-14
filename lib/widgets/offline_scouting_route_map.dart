import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../services/phone_location_service.dart';
import '../services/scouting_route_generator.dart';
import '../theme/app_colors.dart';

/// A deliberately tile-free field map owned by the active Scan workflow.
///
/// It renders only locally persisted geometry. Route lines are orientation
/// guides; hidden/non-drawable segments never imply a safe walking path.
class OfflineScoutingRouteMap extends StatelessWidget {
  const OfflineScoutingRouteMap({
    super.key,
    required this.boundary,
    required this.plan,
    this.activeStation,
    this.completedStationLocations = const {},
    this.currentLocation,
    this.candidate,
    this.onTap,
    this.height = 340,
  });

  final List<LatLng> boundary;
  final ScoutingRoutePlan plan;
  final int? activeStation;
  final Map<int, LatLng> completedStationLocations;
  final PhoneLocationReading? currentLocation;
  final LatLng? candidate;
  final ValueChanged<LatLng>? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final center = boundary.isEmpty
        ? const LatLng(0, 0)
        : ScoutingRouteGenerator.polygonCenter(boundary);
    return Semantics(
      label:
          'Offline approximate assessment route map. It is not turn-by-turn navigation or proof of sampling compliance.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          key: const Key('offline_scouting_route_map'),
          height: height,
          child: ColoredBox(
            color: const Color(0xFFEAF1E5),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 17,
                initialCameraFit: boundary.length >= 3
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(boundary),
                        padding: const EdgeInsets.all(28),
                      )
                    : null,
                onTap: onTap == null ? null : (_, location) => onTap!(location),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                if (boundary.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: boundary,
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderColor: AppColors.primary,
                        borderStrokeWidth: 3,
                      ),
                      for (final obstacle in plan.preparation.obstacles)
                        if (obstacle.length >= 3)
                          Polygon(
                            points: obstacle,
                            color: const Color(
                              0xFFB3261E,
                            ).withValues(alpha: 0.18),
                            borderColor: const Color(0xFFB3261E),
                            borderStrokeWidth: 2,
                          ),
                    ],
                  ),
                PolylineLayer(
                  polylines: [
                    for (final segment in plan.segments)
                      if (segment.drawable && segment.points.length >= 2)
                        Polyline(
                          points: segment.points,
                          color:
                              segment.kind ==
                                  'evaluator_confirmed_accessible_path'
                              ? const Color(0xFF1565C0)
                              : const Color(0xFF6A4C00),
                          strokeWidth: 4,
                          pattern: segment.kind == 'suggested_orientation_only'
                              ? StrokePattern.dashed(segments: const [10, 8])
                              : const StrokePattern.solid(),
                        ),
                    if (plan.preparation.draftPoints.length >= 2)
                      Polyline(
                        points: plan.preparation.draftPoints,
                        color: const Color(0xFF7A3E00),
                        strokeWidth: 4,
                        pattern: StrokePattern.dashed(segments: const [8, 6]),
                      ),
                  ],
                ),
                if (currentLocation != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(
                          currentLocation!.latitude,
                          currentLocation!.longitude,
                        ),
                        radius: currentLocation!.accuracyMeters.clamp(2, 250),
                        useRadiusInMeter: true,
                        color: const Color(0xFF1565C0).withValues(alpha: 0.13),
                        borderColor: const Color(0xFF1565C0),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (plan.preparation.entrance != null)
                      Marker(
                        point: plan.preparation.entrance!,
                        width: 46,
                        height: 46,
                        child: const _RouteMarker(
                          icon: Icons.login,
                          color: Color(0xFF6A4C00),
                          label: 'Evaluator-confirmed field entrance',
                        ),
                      ),
                    for (final target in plan.targets)
                      Marker(
                        point: target.location,
                        width: 48,
                        height: 48,
                        child: _StationTargetMarker(
                          stationNumber: target.stationNumber,
                          active: target.stationNumber == activeStation,
                          completed:
                              target.lockedCompleted ||
                              completedStationLocations.containsKey(
                                target.stationNumber,
                              ),
                        ),
                      ),
                    for (final entry in completedStationLocations.entries)
                      Marker(
                        point: entry.value,
                        width: 38,
                        height: 38,
                        child: _RouteMarker(
                          icon: Icons.check_circle,
                          color: AppColors.primary,
                          label:
                              'Recorded completed Station ${entry.key} location',
                        ),
                      ),
                    if (currentLocation != null)
                      Marker(
                        point: LatLng(
                          currentLocation!.latitude,
                          currentLocation!.longitude,
                        ),
                        width: 46,
                        height: 46,
                        child: const _RouteMarker(
                          icon: Icons.my_location,
                          color: Color(0xFF1565C0),
                          label: 'Current phone location',
                        ),
                      ),
                    if (candidate != null)
                      Marker(
                        point: candidate!,
                        width: 48,
                        height: 48,
                        child: const _RouteMarker(
                          icon: Icons.edit_location_alt,
                          color: Color(0xFFB3261E),
                          label: 'Proposed adjusted station target',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
        ? const Color(0xFFF57C00)
        : const Color(0xFF455A64);
    return Semantics(
      label:
          'Station $stationNumber approximate target${completed
              ? ', completed station'
              : active
              ? ', active'
              : ''}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
        ),
        child: Center(
          child: Text(
            '$stationNumber',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
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
    child: Icon(icon, color: color, size: 34),
  );
}
