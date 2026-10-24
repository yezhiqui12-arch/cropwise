import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/screens/offline_field_map_screen.dart';
import 'package:wormwise/services/offline_field_map_store.dart';

class _SavedMapStore extends OfflineFieldMapStore {
  OfflineFieldMap? map = OfflineFieldMap(
    const OfflineMapArea(17.78, 121.46, 17.80, 121.48),
    DateTime.utc(2026, 9, 27),
    const [],
    1200,
  );
  @override
  Future<OfflineFieldMap?> load(String boundaryId, List<LatLng> points) async =>
      map;
  @override
  Future<void> remove(String boundaryId) async {
    map = null;
  }
}

void main() {
  testWidgets('saved map renders without tile requests and can be removed', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO fields (id, name) VALUES ('field-1', 'Test field')",
    );
    await db.customStatement(
      '''INSERT INTO field_boundary_versions
      (id,field_id,version_number,geometry_geojson,source_method,area_hectares,centroid_latitude,centroid_longitude)
      VALUES ('boundary-1','field-1',1,'{}','reported_area_only',1,17.79,121.47)''',
    );
    final workspace = FieldWorkspaceRecord(
      field: (await db.select(db.fields).get()).single,
      boundary: (await db.select(db.fieldBoundaryVersions).get()).single,
    );
    await tester.pumpWidget(
      Provider<AppDatabase>.value(
        value: db,
        child: MaterialApp(
          home: OfflineFieldMapScreen(
            workspace: workspace,
            store: _SavedMapStore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Available offline'), findsOneWidget);
    expect(find.byType(TileLayer), findsNothing);
    expect(find.textContaining('could not be loaded'), findsNothing);
    await tester.tap(find.text('Remove download'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nearby map not downloaded'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });
}
