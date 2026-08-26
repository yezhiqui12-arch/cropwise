import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/main.dart';

void main() {
  testWidgets('Field editing updates field name and crop cycle attributes', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();

    // 1. Create a new field
    await tester.tap(find.byKey(const Key('home_add_first_field_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_field_fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('field_name_input')),
      'Original Field Name',
    );
    await tester.enterText(find.byKey(const Key('field_area_input')), '2.50');

    await tester.tap(find.byKey(const Key('save_field_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('finish_boundary_setup_button')));
    await tester.pumpAndSettle();

    expect(find.text('Original Field Name'), findsWidgets);

    // 2. Open Field Details Screen and tap edit button
    final field = await database.select(database.fields).getSingle();
    await tester.tap(find.byKey(ValueKey('field_card_${field.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Field Details'), findsOneWidget);
    expect(find.byKey(const Key('edit_field_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_field_button')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Maize Field'), findsOneWidget);
    expect(find.text('Original Field Name'), findsOneWidget);

    // 3. Edit field name and area
    await tester.enterText(
      find.byKey(const Key('field_name_input')),
      'Updated Field Name',
    );
    await tester.enterText(find.byKey(const Key('field_area_input')), '3.75');

    await tester.tap(find.byKey(const Key('save_field_button')));
    await tester.pumpAndSettle();

    // Verify update in details
    expect(find.text('Updated Field Name'), findsWidgets);

    final updatedField = await database.select(database.fields).getSingle();
    expect(updatedField.name, 'Updated Field Name');

    final updatedBoundary =
        await (database.select(database.fieldBoundaryVersions)..where(
              (row) => row.id.equals(updatedField.activeBoundaryVersionId!),
            ))
            .getSingle();
    expect(updatedBoundary.areaHectares, 3.75);
    expect(updatedBoundary.versionNumber, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Long-press field card shows actions sheet with edit action', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home_add_first_field_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_field_fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('field_name_input')),
      'Long Press Test Field',
    );
    await tester.enterText(find.byKey(const Key('field_area_input')), '1.50');

    await tester.tap(find.byKey(const Key('save_field_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('finish_boundary_setup_button')));
    await tester.pumpAndSettle();

    final field = await database.select(database.fields).getSingle();
    final cardFinder = find.byKey(ValueKey('field_card_${field.id}'));

    await tester.longPress(cardFinder);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit_field_details_action')), findsOneWidget);
    expect(find.byKey(const Key('delete_field_action')), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_field_details_action')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Maize Field'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Satellite map toggle switches between ArcGIS Imagery and OSM', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();

    // Create field and go to boundary editor
    await tester.tap(find.byKey(const Key('home_add_first_field_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_field_fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('field_name_input')),
      'Satellite Test Field',
    );
    await tester.enterText(find.byKey(const Key('field_area_input')), '1.00');

    await tester.tap(find.byKey(const Key('save_field_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('choose_manual_boundary_method')));
    await tester.pumpAndSettle();

    expect(find.text('Draw Field Boundary'), findsOneWidget);

    // Verify satellite toggle button exists and default is satellite (ArcGIS)
    final toggleBtn = find.byKey(const Key('toggle_satellite_view_button'));
    expect(toggleBtn, findsOneWidget);

    var tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(
      tileLayer.urlTemplate,
      contains('ArcGIS/rest/services/World_Imagery'),
    );
    expect(tileLayer.maxNativeZoom, 17);

    // Toggle to street map
    await tester.tap(toggleBtn);
    await tester.pumpAndSettle();

    tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(tileLayer.urlTemplate, contains('openstreetmap.org'));

    // Toggle back to satellite
    await tester.tap(toggleBtn);
    await tester.pumpAndSettle();

    tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(
      tileLayer.urlTemplate,
      contains('ArcGIS/rest/services/World_Imagery'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
