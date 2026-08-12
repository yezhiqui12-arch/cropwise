import 'package:latlong2/latlong.dart' show LatLng;

class ScoutingRouteGenerator {
  static LatLng polygonCenter(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    return LatLng(
      points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
      points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
    );
  }

  static bool pointInsidePolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.isEmpty) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses =
          ((a.latitude > point.latitude) != (b.latitude > point.latitude)) &&
          (point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude);
      if (crosses) inside = !inside;
    }
    return inside;
  }

  static List<LatLng> generateWPattern(
    List<LatLng> boundary, {
    int pointCount = 5,
  }) {
    if (boundary.length < 3) return boundary;
    final minLat = boundary
        .map((p) => p.latitude)
        .reduce((a, b) => a < b ? a : b);
    final maxLat = boundary
        .map((p) => p.latitude)
        .reduce((a, b) => a > b ? a : b);
    final minLng = boundary
        .map((p) => p.longitude)
        .reduce((a, b) => a < b ? a : b);
    final maxLng = boundary
        .map((p) => p.longitude)
        .reduce((a, b) => a > b ? a : b);
    final center = polygonCenter(boundary);

    // Generate W-pattern key points
    final wPoints = [
      LatLng(
        maxLat - (maxLat - minLat) * 0.15,
        minLng + (maxLng - minLng) * 0.15,
      ),
      LatLng(
        minLat + (maxLat - minLat) * 0.15,
        minLng + (maxLng - minLng) * 0.35,
      ),
      center,
      LatLng(
        minLat + (maxLat - minLat) * 0.15,
        minLng + (maxLng - minLng) * 0.65,
      ),
      LatLng(
        maxLat - (maxLat - minLat) * 0.15,
        maxLng - (maxLng - minLng) * 0.15,
      ),
    ];

    return wPoints;
  }
}
