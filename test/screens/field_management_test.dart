import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/main.dart';

void main() {
  test(
    'recently deleted and restore preserve the field and linked workspace',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final repository = FieldRepository(database);
      final created = await repository.createFieldWithBoundaryAndCycle(
        name: 'Archive Test Field',
        geometryGeojson: '{"type":"Polygon","coordinates":[]}',
        areaHectares: 0.8,
        boundarySourceMethod: 'reported_area_only',
        boundaryConfirmationStatus: 'location_pending',
      );

      await repository.setFieldArchived(
        fieldId: created.field.id,
        archived: true,
      );
      final archived = await repository.watchArchivedFieldWorkspaces().first;
      expect(archived.single.field.id, created.field.id);
      expect(await repository.watchFieldWorkspaces().first, isEmpty);

      await repository.setFieldArchived(
        fieldId: created.field.id,
        archived: false,
      );
      final restored = await repository.watchFieldWorkspaces().first;
      expect(restored.single.field.id, created.field.id);
      expect(await database.select(database.cropCycles).get(), hasLength(1));
      expect(
        await database.select(database.fieldBoundaryVersions).get(),
        hasLength(1),
      );

      await database.close();
    },
  );

  testWidgets('field card opens details and delete requires confirmation', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = FieldRepository(database);
    final created = await repository.createFieldWithBoundaryAndCycle(
      name: 'Managed Field',
      geometryGeojson: '{"type":"Polygon","coordinates":[]}',
      areaHectares: 1.2,
      boundarySourceMethod: 'reported_area_only',
      boundaryConfirmationStatus: 'location_pending',
    );
    await repository.savePreferredFieldId(created.field.id);

    await tester.pumpWidget(WormWiseApp(database: database));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Change Field'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change Field'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('field_card_${created.field.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Field Details'), findsOneWidget);
    expect(find.text('1.20 ha'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_field_button')));
    await tester.pumpAndSettle();
    expect(find.text('Edit Maize Field'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('field_name_input')),
      'Renamed Field',
    );
    await tester.tap(find.byKey(const Key('save_field_button')));
    await tester.pumpAndSettle();
    expect(find.text('Renamed Field'), findsWidgets);
    expect(
      (await database.select(database.fields).getSingle()).name,
      'Renamed Field',
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('delete_field_button')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('delete_field_button')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this field?'), findsOneWidget);
    expect(find.textContaining('Recently Deleted for 30 days'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      (await database.select(database.fields).getSingle()).isArchived,
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });
}
