import 'dart:convert';
import 'dart:io';

class ArcGisPlaceMatch {
  const ArcGisPlaceMatch({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.score,
  });

  final double latitude;
  final double longitude;
  final String label;
  final double score;
}

/// Resolves a user-selected administrative place for temporary map framing.
/// Results are not stored as field GPS measurements or property coordinates.
class ArcGisPlaceGeocoder {
  const ArcGisPlaceGeocoder();

  Future<ArcGisPlaceMatch?> locate({
    required String barangay,
    required String municipality,
    required String province,
  }) async {
    final query = [
      'Barangay $barangay',
      municipality,
      province,
      'Philippines',
    ].where((part) => part.trim().isNotEmpty).join(', ');
    final uri = Uri.https(
      'geocode.arcgis.com',
      '/arcgis/rest/services/World/GeocodeServer/findAddressCandidates',
      {
        'SingleLine': query,
        'f': 'json',
        'outSR': '4326',
        'outFields': 'Match_addr,Addr_type,City,Region,Country',
        'countryCode': 'PHL',
        'maxLocations': '1',
        'forStorage': 'false',
      },
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'WormWise/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final candidate = candidates.first;
      if (candidate is! Map<String, dynamic>) return null;
      final location = candidate['location'];
      if (location is! Map<String, dynamic>) return null;
      final x = location['x'];
      final y = location['y'];
      final score = candidate['score'];
      if (x is! num || y is! num || score is! num || score < 65) return null;
      if (!x.isFinite ||
          !y.isFinite ||
          !score.isFinite ||
          x < -180 ||
          x > 180 ||
          y < -85.05112878 ||
          y > 85.05112878) {
        return null;
      }
      return ArcGisPlaceMatch(
        latitude: y.toDouble(),
        longitude: x.toDouble(),
        label: (candidate['address'] ?? query).toString(),
        score: score.toDouble(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
