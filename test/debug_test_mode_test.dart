import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/main.dart';
import 'package:wormwise/providers/app_data_mode.dart';
import 'package:wormwise/screens/main_navigation_screen.dart';
import 'package:wormwise/screens/debug_test_mode_shell.dart';
import 'package:wormwise/screens/station1/station1_workflow_screen.dart';
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
    'app-bar Back exits to Scan while system Back moves within station',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await tester.pumpWidget(
        MaterialApp(home: DebugTestModeShell(database: database)),
      );
      await _pumpUntil(
        tester,
        find.byKey(const Key('resume_assessment_from_scan_button')),
      );
      await tester.tap(
        find.byKey(const Key('resume_assessment_from_scan_button')),
      );
      await _pumpUntil(
        tester,
        find.byKey(
          const Key('complete_current_test_station_persistent_button'),
        ),
      );

      await tester.tap(
        find.byKey(
          const Key('complete_current_test_station_persistent_button'),
        ),
      );
      await _pumpUntil(tester, find.text('Continue to Station 2'));
      expect(find.text('Continue to Station 2'), findsWidgets);

      _invokePhoneBack(tester);
      await _pumpUntil(tester, find.text('Station Evidence Review'));
      expect(find.text('Station Evidence Review'), findsOneWidget);
      expect(find.byType(Station1WorkflowScreen), findsOneWidget);

      final plantOne = find.byKey(const Key('review_position_1'));
      await tester.tap(plantOne);
      await _pumpUntil(
        tester,
        find.byKey(const Key('manual_confirmation_header')),
      );
      expect(
        find.byKey(const Key('manual_confirmation_header')),
        findsOneWidget,
      );

      _invokePhoneBack(tester);
      await _pumpUntil(tester, find.text('Return to Station Review?'));
      expect(find.text('Return to Station Review?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('keep_editing_plant_button')));
      await tester.pump();
      expect(
        find.byKey(const Key('manual_confirmation_header')),
        findsOneWidget,
      );

      _invokePhoneBack(tester);
      await _pumpUntil(tester, find.text('Return to Station Review?'));
      await tester.tap(find.byKey(const Key('discard_plant_edits_button')));
      await _pumpUntil(tester, find.text('Station Evidence Review'));
      expect(find.text('Station Evidence Review'), findsOneWidget);
      expect(find.byType(Station1WorkflowScreen), findsOneWidget);

      await _pumpUntil(tester, plantOne);
      await tester.tap(plantOne);
      await _pumpUntil(
        tester,
        find.byKey(const Key('manual_confirmation_header')),
      );
      await tester.tap(find.byKey(const Key('station_workflow_back_button')));
      await _pumpUntil(tester, find.text('Return to Scan?'));
      expect(find.text('Return to Scan?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stay_on_plant_button')));
      await tester.pump();
      expect(
        find.byKey(const Key('manual_confirmation_header')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('station_workflow_back_button')));
      await _pumpUntil(tester, find.text('Return to Scan?'));
      await tester.tap(find.byKey(const Key('leave_plant_for_scan_button')));
      await _pumpUntilAbsent(tester, find.byType(Station1WorkflowScreen));
      expect(find.byType(Station1WorkflowScreen), findsNothing);
      expect(find.text('Scan · TEST DATA'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}

void _invokePhoneBack(WidgetTester tester) {
  final scope = tester.widget<PopScope<void>>(
    find.descendant(
      of: find.byType(Station1WorkflowScreen),
      matching: find.byWidgetPredicate((widget) => widget is PopScope<void>),
    ),
  );
  scope.onPopInvokedWithResult!(false, null);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maximumPumps = 100,
}) async {
  for (var pump = 0; pump < maximumPumps; pump++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the expected widget.');
}

Future<void> _pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  int maximumPumps = 100,
}) async {
  for (var pump = 0; pump < maximumPumps; pump++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for the widget to disappear.');
}

Future<void> _closeApp(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await database.close();
  await tester.pump(const Duration(milliseconds: 1));
}
