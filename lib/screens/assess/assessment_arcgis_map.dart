import '../../services/map_view_policy.dart';
import 'dart:math' as math;
import '../../localization/app_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

/// ArcGIS World Imagery only. No alternate basemap or illustrated fallback.
class AssessmentArcgisMap extends StatefulWidget {
  const AssessmentArcgisMap({
    super.key,
    required this.boundary,
    required this.stations,
    required this.reviewed,
    this.compact = false,
  });
  final List<LatLng> boundary;
  final Map<int, LatLng> stations;
  final Set<int> reviewed;
  final bool compact;
  @override
  State<AssessmentArcgisMap> createState() => _AssessmentArcgisMapState();
}

class _AssessmentArcgisMapState extends State<AssessmentArcgisMap> {
  bool _failed = false;
  bool _errorQueued = false;
  int _attempt = 0;
  void _onError() {
    if (_failed || _errorQueued || !mounted) return;
    _errorQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _errorQueued = false;
      if (mounted) setState(() => _failed = true);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    final points = [...widget.boundary, ...widget.stations.values];
    final ordered = widget.stations.keys.toList()..sort();
    final unique = points.map((p) => '${p.latitude},${p.longitude}').toSet();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: widget.compact ? 112 : 210,
        child: points.isEmpty || _failed
            ? ColoredBox(
                color: const Color(0xFFEDF1F3),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.satellite_alt_outlined,
                          color: Color(0xFF60717B),
                        ),
                        if (!widget.compact) ...[
                          const SizedBox(height: 8),
                          Text(
                            points.isEmpty
                                ? 'No saved map coordinates'
                                : 'ArcGIS imagery unavailable',
                            textAlign: TextAlign.center,
                          ),
                          if (_failed)
                            TextButton(
                              onPressed: () => setState(() {
                                _failed = false;
                                _attempt++;
                              }),
                              child: const AppText('Retry imagery'),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            : Stack(
                children: [
                  FlutterMap(
                    key: ValueKey(_attempt),
                    options: MapOptions(
                      minZoom: MapViewPolicy.minZoom,
                      maxZoom: MapViewPolicy.maxZoom,
                      initialCenter: MapViewPolicy.initialCenter(points.first),
                      initialZoom: widget.compact ? 18 : 17,
                      initialCameraFit: !widget.compact && unique.length > 1
                          ? CameraFit.bounds(
                              bounds: LatLngBounds.fromPoints(points),
                              padding: const EdgeInsets.fromLTRB(
                                30,
                                48,
                                30,
                                30,
                              ),
                              maxZoom: 18,
                            )
                          : null,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                      backgroundColor: const Color(0xFFEDF1F3),
                    ),
                    children: [
                      TileLayer(
                        tileUpdateTransformer: TileUpdateTransformers.debounce(
                          const Duration(milliseconds: 160),
                        ),
                        panBuffer: 0,
                        keepBuffer: 3,
                        urlTemplate:
                            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                        userAgentPackageName: 'com.wormwise.app.wormwise',
                        maxNativeZoom: 18,
                        errorTileCallback: (_, _, _) => _onError(),
                      ),
                      if (!widget.compact && widget.boundary.length >= 3)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: widget.boundary,
                              color: const Color(0x2419C85A),
                              borderColor: const Color(0xAA8DFF63),
                              borderStrokeWidth: 8,
                            ),
                            Polygon(
                              points: widget.boundary,
                              color: Colors.transparent,
                              borderColor: const Color(0xFF064D2B),
                              borderStrokeWidth: 3.5,
                              pattern: StrokePattern.dashed(
                                segments: const [10, 7],
                              ),
                            ),
                          ],
                        ),
                      if (!widget.compact)
                        PolylineLayer(
                          polylines: [
                            for (var i = 1; i < ordered.length; i++)
                              if (ordered[i] == ordered[i - 1] + 1)
                                Polyline(
                                  points: [
                                    widget.stations[ordered[i - 1]]!,
                                    widget.stations[ordered[i]]!,
                                  ],
                                  color: const Color(0xFF064D2B),
                                  strokeWidth: 4,
                                  borderColor: Colors.white,
                                  borderStrokeWidth: 2,
                                ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (!widget.compact)
                            for (var i = 1; i < ordered.length; i++)
                              if (ordered[i] == ordered[i - 1] + 1)
                                Marker(
                                  point: _midpoint(
                                    widget.stations[ordered[i - 1]]!,
                                    widget.stations[ordered[i]]!,
                                  ),
                                  width: 30,
                                  height: 30,
                                  child: Transform.rotate(
                                    angle: _screenAngle(
                                      widget.stations[ordered[i - 1]]!,
                                      widget.stations[ordered[i]]!,
                                    ),
                                    child: const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Color(0xFF064D2B),
                                      size: 27,
                                      shadows: [
                                        Shadow(
                                          color: Colors.white,
                                          blurRadius: 4,
                                        ),
                                        Shadow(
                                          color: Colors.white,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          for (final n in ordered)
                            Marker(
                              point: widget.stations[n]!,
                              width: 34,
                              height: 44,
                              alignment: Alignment.topCenter,
                              child: Semantics(
                                label: 'Station $n',
                                child: CustomPaint(
                                  painter: _StationPinPainter(
                                    widget.reviewed.contains(n),
                                  ),
                                  child: Align(
                                    alignment: const Alignment(0, -0.35),
                                    child: AppText(
                                      '$n',
                                      textScaler: TextScaler.noScaling,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (!widget.compact)
                    const Positioned(
                      top: 12,
                      right: 12,
                      child: CircleAvatar(
                        backgroundColor: Color(0xCC17362B),
                        child: Icon(Icons.navigation, color: Colors.white),
                      ),
                    ),
                  Positioned(
                    bottom: 3,
                    right: 3,
                    child: Container(
                      color: Colors.white.withValues(alpha: .85),
                      padding: const EdgeInsets.all(2),
                      child: Text(
                        widget.compact
                            ? 'Esri'
                            : 'Esri World Imagery · Esri and contributors',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

LatLng _midpoint(LatLng first, LatLng second) => LatLng(
  (first.latitude + second.latitude) / 2,
  (first.longitude + second.longitude) / 2,
);

double _screenAngle(LatLng first, LatLng second) => math.atan2(
  -(second.latitude - first.latitude),
  second.longitude - first.longitude,
);

class _StationPinPainter extends CustomPainter {
  const _StationPinPainter(this.reviewed);
  final bool reviewed;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height - 2)
      ..cubicTo(
        size.width * .33,
        size.height * .72,
        2,
        size.height * .53,
        2,
        size.width / 2,
      )
      ..arcToPoint(
        Offset(size.width - 2, size.width / 2),
        radius: Radius.circular(size.width / 2 - 2),
      )
      ..cubicTo(
        size.width - 2,
        size.height * .53,
        size.width * .67,
        size.height * .72,
        size.width / 2,
        size.height - 2,
      )
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(
      path,
      Paint()
        ..color = reviewed ? const Color(0xFF16812D) : const Color(0xFF50636B),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_StationPinPainter oldDelegate) =>
      reviewed != oldDelegate.reviewed;
}

