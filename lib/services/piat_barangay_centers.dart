import 'package:latlong2/latlong.dart' show LatLng;

/// Approximate map framing from the dashboard's indicative Piat barangay layer.
/// These references are available offline and are never stored as field GPS.
class PiatBarangayCenters {
  static const fallback = LatLng(17.7905, 121.4781);

  static const _centers = <String, LatLng>{
    'apayao': LatLng(17.851325, 121.506694),
    'aquib': LatLng(17.820092, 121.470564),
    'baung': LatLng(17.820252, 121.503699),
    'calaoagan': LatLng(17.856309, 121.509304),
    'catarauan': LatLng(17.766054, 121.592204),
    'dugayung': LatLng(17.828946, 121.479204),
    'gumarueng': LatLng(17.792023, 121.477409),
    'macapil': LatLng(17.790204, 121.452319),
    'maguilling': LatLng(17.786513, 121.523364),
    'minanga': LatLng(17.846555, 121.493494),
    'poblacioni': LatLng(17.801478, 121.488409),
    'poblacionii': LatLng(17.804388, 121.478509),
    'santabarbara': LatLng(17.768434, 121.494124),
    'santodomingo': LatLng(17.752865, 121.516149),
    'sicatna': LatLng(17.857754, 121.491829),
    'villarey': LatLng(17.835345, 121.510519),
    'villareysangaspar': LatLng(17.835345, 121.510519),
    'villareyno': LatLng(17.740746, 121.544604),
    'warat': LatLng(17.726381, 121.574618),
  };

  static LatLng? forName(String? barangay) {
    if (barangay == null) return null;
    final name = barangay.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    return _centers[name];
  }
}
