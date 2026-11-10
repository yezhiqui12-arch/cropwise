import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/services/field_boundary_map_center.dart';
import 'package:wormwise/services/piat_barangay_centers.dart';
import 'package:wormwise/services/polygon_calculator.dart';

void main() {
  test(
    'new boundary uses selected barangay ahead of entrance and route center',
    () {
      expect(
        fieldBoundaryMapCenter(
          barangay: 'Warat',
          entrance: const LatLng(17.79, 121.48),
          initialCenter: const LatLng(17.8, 121.5),
        ),
        PiatBarangayCenters.forName('Warat'),
      );
    },
  );

  test('reopened boundary uses saved outline', () {
    const outline = [
      LatLng(17.8, 121.5),
      LatLng(17.81, 121.5),
      LatLng(17.8, 121.51),
    ];
    expect(
      fieldBoundaryMapCenter(barangay: 'Warat', outline: outline),
      PolygonCalculator.calculateCenter(outline),
    );
  });

  test(
    'unknown barangay uses resolved location then entrance then fallback',
    () {
      const location = LatLng(17.8, 121.5);
      expect(
        fieldBoundaryMapCenter(barangay: 'Unknown', initialCenter: location),
        location,
      );
      expect(
        fieldBoundaryMapCenter(barangay: null, entrance: location),
        location,
      );
      expect(
        fieldBoundaryMapCenter(barangay: null),
        PiatBarangayCenters.fallback,
      );
    },
  );
}
