import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/main.dart';

void main() {
  testWidgets('Selecting or typing maize variety in RawAutocomplete', (
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
      'Test Maize Field',
    );
    await tester.enterText(find.byKey(const Key('field_area_input')), '1.25');

    final varietyField = find.byKey(const Key('field_variety_input'));
    for (
      var attempt = 0;
      attempt < 6 && varietyField.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(varietyField, findsOneWidget);

    await tester.enterText(varietyField, 'My Custom Corn Variety');
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const Key('save_field_button'));
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Field Boundary'), findsOneWidget);
    expect(find.text('Choose how to add the boundary'), findsOneWidget);
    expect(find.byKey(const Key('boundary_map_tap_area')), findsNothing);

    await tester.tap(find.byKey(const Key('choose_walk_boundary_method')));
    await tester.pumpAndSettle();
    expect(find.text('Walk Field Boundary'), findsOneWidget);
    expect(find.byKey(const Key('start_walk_boundary_button')), findsOneWidget);
    expect(
      find.byKey(const Key('add_gps_boundary_point_button')),
      findsNothing,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Choose how to add the boundary'), findsOneWidget);

    await tester.tap(find.byKey(const Key('choose_manual_boundary_method')));
    await tester.pumpAndSettle();
    expect(find.text('Draw Field Boundary'), findsOneWidget);
    expect(find.byKey(const Key('start_walk_boundary_button')), findsNothing);
    final map = find.byKey(const Key('boundary_map_tap_area'));
    expect(map, findsOneWidget);
    final mapRect = tester.getRect(map);
    await tester.tapAt(mapRect.center + const Offset(-70, 20));
    await tester.pump();
    await tester.tapAt(mapRect.center + const Offset(70, 20));
    await tester.pump();
    await tester.tapAt(mapRect.center + const Offset(0, 90));
    await tester.pump();
    final pointCount = find.descendant(
      of: find.byKey(const Key('boundary_point_count')),
      matching: find.text('3'),
    );
    expect(pointCount, findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Choose how to add the boundary'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finish_boundary_setup_button')));
    await tester.pumpAndSettle();

    expect(find.text('Test Maize Field'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_top_header')), findsOneWidget);
    expect(find.byKey(const Key('home_menu_button')), findsOneWidget);
    expect(find.byKey(const Key('field_conditions_card')), findsOneWidget);
    expect(find.text('30°C'), findsNothing);
    expect(find.textContaining('Bayani Cornfield'), findsNothing);
    expect(find.textContaining('Juan'), findsNothing);
    expect(find.text('Test Maize Field is your active field.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bottom_nav_map')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_top_header')), findsNothing);
    expect(find.byKey(const Key('home_menu_button')), findsNothing);
    expect(find.byKey(const Key('field_map_overview')), findsOneWidget);
    expect(find.byKey(const Key('boundary_map_tap_area')), findsNothing);
    expect(find.byKey(const Key('manage_boundary_button')), findsOneWidget);
    expect(find.text('Add boundary'), findsOneWidget);

    await tester.tap(find.byKey(const Key('manage_boundary_button')));
    await tester.pumpAndSettle();
    expect(find.text('Manage Field Boundary'), findsOneWidget);
    expect(find.text('Choose how to add the boundary'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
