import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/services/polygon_calculator.dart';

void main() {
  const validField = [
    LatLng(17.7900, 121.4780),
    LatLng(17.7900, 121.4790),
    LatLng(17.7910, 121.4790),
    LatLng(17.7910, 121.4780),
  ];

  test('calculates useful metrics for a valid field polygon', () {
    final validation = PolygonCalculator.validate(validField);

    expect(validation.isValid, isTrue);
    expect(PolygonCalculator.calculateHectares(validField), greaterThan(1));
    expect(
      PolygonCalculator.calculatePerimeterMeters(validField),
      greaterThan(400),
    );
  });

  test('rejects a boundary whose edges cross', () {
    const crossedField = [
      LatLng(17.7900, 121.4780),
      LatLng(17.7910, 121.4790),
      LatLng(17.7900, 121.4790),
      LatLng(17.7910, 121.4780),
    ];

    final validation = PolygonCalculator.validate(crossedField);

    expect(validation.isValid, isFalse);
    expect(
      validation.issues,
      contains('The boundary crosses itself. Move or remove a point.'),
    );
  });

  test('untangles four corners tapped in a crossing order', () {
    const crossedField = [
      LatLng(17.7900, 121.4780), // lower left
      LatLng(17.7910, 121.4780), // upper left
      LatLng(17.7900, 121.4790), // lower right
      LatLng(17.7910, 121.4790), // upper right
    ];

    final order = PolygonCalculator.untangledOrder(crossedField);
    final corrected = [for (final index in order) crossedField[index]];

    expect(order, isNot(orderedEquals([0, 1, 2, 3])));
    expect(PolygonCalculator.validate(corrected).isValid, isTrue);
  });

  test(
    'does not force an already simple concave field into a convex shape',
    () {
      const concaveField = [
        LatLng(17.7900, 121.4780),
        LatLng(17.7910, 121.4780),
        LatLng(17.7905, 121.4785),
        LatLng(17.7910, 121.4790),
        LatLng(17.7900, 121.4790),
      ];

      expect(
        PolygonCalculator.untangledOrder(concaveField),
        orderedEquals([0, 1, 2, 3, 4]),
      );
    },
  );

  test('writes a closed GeoJSON ring and reads it without duplicating it', () {
    final encoded = PolygonCalculator.toGeoJson(validField);
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final ring = (decoded['coordinates'] as List).first as List;

    expect(ring.length, validField.length + 1);
    expect(ring.first, ring.last);
    expect(PolygonCalculator.fromGeoJson(encoded), validField);
  });
}
