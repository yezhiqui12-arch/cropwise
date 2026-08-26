import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/services/field_imagery_provider.dart';
import 'package:wormwise/services/scouting_route_generator.dart';
import 'package:wormwise/theme/app_colors.dart';
import 'package:wormwise/widgets/offline_scouting_route_map.dart';

void main() {
  const boundary = [
    LatLng(17.0000, 121.0000),
    LatLng(17.0000, 121.0100),
    LatLng(17.0100, 121.0100),
    LatLng(17.0100, 121.0000),
  ];

  testWidgets('provider failure automatically shows attributed offline view', (
    tester,
  ) async {
    final plan = _plan();
    await tester.pumpWidget(
      _app(
        plan: plan,
        imageryProvider: _ThrowingProvider(),
        boundary: boundary,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Online map unavailable · Offline field view'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Offline illustrated field view'),
      findsOneWidget,
    );
    for (var station = 1; station <= 5; station++) {
      expect(find.byKey(Key('route_station_marker_$station')), findsOneWidget);
    }
    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    for (final target in plan.targets) {
      final marker = markerLayer.markers.singleWhere(
        (item) =>
            item.child.key ==
            Key('route_station_marker_${target.stationNumber}'),
      );
      expect(marker.point, target.location);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('packaged imagery displays its permanent attribution', (
    tester,
  ) async {
    final provider = _FixedProvider(
      FieldImagerySource.packaged(
        kind: FieldImageryKind.approvedHighResolutionPackage,
        displayName: 'DA licensed Piat imagery',
        attribution: 'Department of Agriculture · Licence DA-2026-1',
        licenseReference: 'DA-2026-1',
        resolutionLabel: '0.5 m supplied imagery',
        imageProvider: const AssetImage(
          'assets/images/growth_stages/maize_young_vegetative.jpg',
        ),
        imageBounds: const FieldImageryBounds(
          west: 120.999,
          south: 16.999,
          east: 121.011,
          north: 17.011,
        ),
      ),
    );

    await tester.pumpWidget(
      _app(plan: _plan(), imageryProvider: provider, boundary: boundary),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('DA licensed Piat imagery'), findsOneWidget);
    expect(find.textContaining('Department of Agriculture'), findsOneWidget);
    expect(
      find.text('Online map unavailable · Offline field view'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('map overlays remain usable at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: OfflineScoutingRouteMap(
              boundary: boundary,
              plan: _plan(),
              activeStation: 2,
              completedStationLocations: const {1: LatLng(17.002, 121.002)},
              imageryProvider: _ThrowingProvider(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('offline_scouting_route_map')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed station remains checked without recorded GPS', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfflineScoutingRouteMap(
            boundary: boundary,
            plan: _plan(),
            activeStation: 3,
            completedStationNumbers: const {1, 2},
            imageryProvider: _ThrowingProvider(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    for (final station in [1, 2]) {
      final marker = find.byKey(Key('route_station_marker_$station'));
      expect(marker, findsOneWidget);
      expect(
        find.descendant(of: marker, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
      );
    }
    final active = find.byKey(const Key('route_station_marker_3'));
    expect(
      find.descendant(of: active, matching: find.byIcon(Icons.flag_rounded)),
      findsOneWidget,
    );
  });

  test('route progress uses color and a distinct status icon', () {
    const completed = ScoutingRouteSegment(
      points: [LatLng(17, 121), LatLng(17.001, 121.001)],
      kind: 'ladder_branch_return',
      drawable: true,
      stationNumber: 1,
    );
    const active = ScoutingRouteSegment(
      points: [LatLng(17.001, 121.001), LatLng(17.002, 121.002)],
      kind: 'ladder_spine_approach',
      drawable: true,
      stationNumber: 2,
    );
    const invalid = ScoutingRouteSegment(
      points: [LatLng(17.002, 121.002), LatLng(17.003, 121.003)],
      kind: 'suggested_orientation_only',
      drawable: false,
      stationNumber: 3,
    );
    const future = ScoutingRouteSegment(
      points: [LatLng(17.003, 121.003), LatLng(17.004, 121.004)],
      kind: 'ladder_spine_approach',
      drawable: true,
      stationNumber: 4,
    );

    final completedState = routeProgressStateFor(
      segment: completed,
      activeStation: 2,
      completedStations: {1},
    );
    final activeState = routeProgressStateFor(
      segment: active,
      activeStation: 2,
      completedStations: {1},
    );
    final invalidState = routeProgressStateFor(
      segment: invalid,
      activeStation: 2,
      completedStations: {1},
    );
    final futureState = routeProgressStateFor(
      segment: future,
      activeStation: 2,
      completedStations: {1},
    );

    expect(completedState, RouteProgressState.completed);
    expect(routeProgressColor(completedState), AppColors.primary);
    expect(routeProgressIcon(completedState), Icons.check_circle);
    expect(activeState, RouteProgressState.active);
    expect(routeProgressColor(activeState), const Color(0xFFF57C00));
    expect(routeProgressIcon(activeState), Icons.arrow_circle_right);
    expect(invalidState, RouteProgressState.invalid);
    expect(routeProgressColor(invalidState), const Color(0xFFB3261E));
    expect(routeProgressIcon(invalidState), Icons.warning);
    expect(futureState, RouteProgressState.future);
    expect(routeProgressColor(futureState), const Color(0xFF60727A));
    expect(routeProgressIcon(futureState), Icons.more_horiz);
  });
}

Widget _app({
  required ScoutingRoutePlan plan,
  required FieldImageryProvider imageryProvider,
  required List<LatLng> boundary,
}) => MaterialApp(
  home: Scaffold(
    body: OfflineScoutingRouteMap(
      boundary: boundary,
      plan: plan,
      activeStation: 2,
      completedStationLocations: const {1: LatLng(17.002, 121.002)},
      imageryProvider: imageryProvider,
    ),
  ),
);

ScoutingRoutePlan _plan() => ScoutingRouteGenerator.generate(
  draft: ScoutingRoutePlan(
    assessmentId: 'assessment-1',
    blockRunId: 'run-1',
    blockId: 'block-1',
    boundaryVersionId: 'boundary-1',
    pattern: DatabaseCodes.patternLadder,
    status: ScoutingRouteStatus.draft,
    preparation: const RoutePreparationData(
      entrance: LatLng(17.0002, 121.0002),
      obstaclesReviewed: true,
    ),
    updatedAt: DateTime.utc(2026, 8, 14),
  ),
  boundary: const [
    LatLng(17.0000, 121.0000),
    LatLng(17.0000, 121.0100),
    LatLng(17.0100, 121.0100),
    LatLng(17.0100, 121.0000),
  ],
  completedStations: const {1: LatLng(17.002, 121.002)},
);

class _ThrowingProvider implements FieldImageryProvider {
  @override
  Future<FieldImagerySource?> resolve(FieldImageryRequest request) {
    throw StateError('Offline in test');
  }
}

class _FixedProvider implements FieldImageryProvider {
  const _FixedProvider(this.source);

  final FieldImagerySource source;

  @override
  Future<FieldImagerySource?> resolve(FieldImageryRequest request) async =>
      source;
}
