import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/main.dart';

void main() {
  testWidgets('empty app prompts for the first real field', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Add your first field'), findsOneWidget);
    expect(find.text('Bayani Cornfield'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('creates a field that is ready without a boundary', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home_add_first_field_button')));
    await tester.pumpAndSettle();
    expect(find.text('My Maize Fields'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_field_fab')));
    await tester.pumpAndSettle();
    expect(find.text('Add Maize Field'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('field_name_input')),
      'Test Maize Field',
    );
    await tester.enterText(find.byKey(const Key('field_area_input')), '1.25');

    final saveButton = find.byKey(const Key('save_field_button'));
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Field Boundary'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finish_boundary_setup_button')));
    await tester.pumpAndSettle();

    expect(find.text('Test Maize Field'), findsWidgets);
    expect(find.text('Boundary not added'), findsOneWidget);

    await tester.tap(find.text('Test Maize Field'));
    await tester.pumpAndSettle();

    expect(find.text('Test Maize Field'), findsWidgets);
    expect(find.text('REPORTED AREA'), findsOneWidget);
    expect(find.text('1.25 ha'), findsOneWidget);
    expect(find.text('Bayani Cornfield'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
