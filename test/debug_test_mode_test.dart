import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/main.dart';
import 'package:wormwise/providers/app_data_mode.dart';
import 'package:wormwise/screens/main_navigation_screen.dart';
import 'package:wormwise/screens/debug_test_mode_shell.dart';
import 'package:wormwise/services/debug_test_data_service.dart';
import 'package:wormwise/widgets/wormwise_data_scope.dart';

void main() {
  test('release build gate rejects test entry and shortcuts', () {
    const production = AppDataMode.production(debugFeaturesEnabled: true);
    const testData = AppDataMode(isTestMode: true, debugFeaturesEnabled: true);

    expect(production.canEnterTestModeForBuild(debugBuild: false), isFalse);
    expect(testData.testShortcutsAvailableForBuild(debugBuild: false), isFalse);
    expect(
      production.testShortcutsAvailableForBuild(debugBuild: false),
      isFalse,
    );
  });

  test(
    'synthetic records and clearing remain isolated from farmer data',
    () async {
      final testDatabase = AppDatabase(NativeDatabase.memory());
      final evidenceRoot = await Directory.systemTemp.createTemp(
        'wormwise_test_data_',
      );
      await File(
        '${evidenceRoot.path}${Platform.pathSeparator}evidence.jpg',
      ).writeAsString('synthetic');
      final service = DebugTestDataService(testDatabase);

      await service.ensureTestAssessment();

      expect(
        await testDatabase.select(testDatabase.assessments).get(),
        hasLength(1),
      );
      expect(
        (await testDatabase.select(testDatabase.fields).getSingle()).name,
        startsWith('[TEST DATA]'),
      );
      await service.clear(evidenceRoot: evidenceRoot);

      expect(
        await testDatabase.select(testDatabase.assessments).get(),
        isEmpty,
      );
      expect(await testDatabase.select(testDatabase.auditLogs).get(), isEmpty);
      expect(await evidenceRoot.exists(), isFalse);
      await testDatabase.close();

      final farmerDatabase = AppDatabase(NativeDatabase.memory());
      expect(
        await farmerDatabase.select(farmerDatabase.assessments).get(),
        isEmpty,
      );
      await farmerDatabase.close();
    },
  );

  testWidgets('production configuration cannot open test mode', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      WormWiseApp(database: database, debugFeaturesEnabled: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom_nav_scan')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_test_mode_button')), findsNothing);
    expect(
      find.byKey(const Key('persistent_test_station_bypass')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('permanent_test_data_indicator')),
      findsNothing,
    );

    await _closeApp(tester, database);
  });

  testWidgets('isolated mode keeps a permanent TEST DATA indicator', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    var clearRequested = false;
    var exitRequested = false;
    await tester.pumpWidget(
      WormWiseDataScope(
        database: database,
        disposeDatabase: false,
        dataMode: const AppDataMode(
          isTestMode: true,
          debugFeaturesEnabled: true,
        ),
        child: MaterialApp(
          home: MainNavigationScreen(
            initialIndex: 2,
            onClearTestMode: () async => clearRequested = true,
            onExitTestMode: () => exitRequested = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('permanent_test_data_indicator')),
      findsOneWidget,
    );
    expect(find.textContaining('TEST DATA'), findsWidgets);
    expect(find.byKey(const Key('open_test_mode_button')), findsNothing);

    await tester.tap(find.byKey(const Key('clear_test_mode_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('exit_test_mode_button')));
    expect(clearRequested, isTrue);
    expect(exitRequested, isTrue);

    await _closeApp(tester, database);
  });

  testWidgets(
    'resuming from TEST DATA Scan keeps the isolated route and bypass controls',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await tester.pumpWidget(
        MaterialApp(home: DebugTestModeShell(database: database)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scan · TEST DATA'), findsOneWidget);
      expect(
        find.byKey(const Key('permanent_test_data_indicator')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('resume_assessment_from_scan_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('persistent_test_station_bypass')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('complete_all_test_stations_persistent_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('complete_current_test_station_persistent_button'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('test_station_shortcuts_button')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'station Back returns to review and never jumps directly to Scan',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await tester.pumpWidget(
        MaterialApp(home: DebugTestModeShell(database: database)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('resume_assessment_from_scan_button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const Key('complete_current_test_station_persistent_button'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue to Station 2'), findsWidgets);

      await tester.tap(find.byKey(const Key('station_workflow_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Station Evidence Review'), findsOneWidget);
      expect(find.text('Scan · TEST DATA'), findsNothing);

      final editPlant = find.byKey(const Key('edit_plant_1_button'));
      await tester.scrollUntilVisible(
        editPlant,
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(editPlant);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('manual_confirmation_header')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('station_workflow_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Return to Station Review?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('keep_editing_plant_button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('manual_confirmation_header')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('station_workflow_back_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discard_plant_edits_button')));
      await tester.pumpAndSettle();
      expect(find.text('Station Evidence Review'), findsOneWidget);
      expect(find.text('Scan · TEST DATA'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}

Future<void> _closeApp(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await database.close();
  await tester.pump(const Duration(milliseconds: 1));
}
