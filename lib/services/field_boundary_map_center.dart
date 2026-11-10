import 'package:latlong2/latlong.dart';

import 'piat_barangay_centers.dart';
import 'polygon_calculator.dart';

/// Camera framing only: these coordinates must never become field GPS data.
LatLng fieldBoundaryMapCenter({
  required String? barangay,
  List<LatLng> outline = const [],
  LatLng? initialCenter,
  LatLng? entrance,
}) {
  if (outline.isNotEmpty) return PolygonCalculator.calculateCenter(outline);
  final barangayCenter = PiatBarangayCenters.forName(barangay);
  if (barangayCenter != null) return barangayCenter;
  for (final candidate in [initialCenter, entrance]) {
    if (candidate != null && PolygonCalculator.isValidCoordinate(candidate)) {
      return candidate;
    }
  }
  return PiatBarangayCenters.fallback;
}
