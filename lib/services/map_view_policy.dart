import 'package:latlong2/latlong.dart' show LatLng;

/// Safe map coordinates without restricting viewing to a municipality.
class MapViewPolicy {
  static const minZoom = 2.0;
  static const maxZoom = 20.0;

  static LatLng initialCenter(LatLng point) {
    if (!point.latitude.isFinite || !point.longitude.isFinite) {
      return const LatLng(0, 0);
    }
    return LatLng(
      point.latitude.clamp(-85.05112878, 85.05112878).toDouble(),
      point.longitude.clamp(-180.0, 180.0).toDouble(),
    );
  }
}
