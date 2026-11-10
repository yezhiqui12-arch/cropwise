import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/startup/app_startup_gate.dart';
import 'package:wormwise/screens/startup_logo_screen.dart';

void main() {
  testWidgets('logo precedes loading without a leaf indicator', (tester) async {
    final pending = Completer<Object>();
    var started = false;
    await tester.pumpWidget(
      AppStartupGate<Object>(
        initialize: (_) {
          started = true;
          return pending.future;
        },
        release: (_) async {},
        builder: (_, _) => const MaterialApp(home: Text('Ready')),
      ),
    );
    expect(find.byKey(const Key('launch_logo')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(started, isFalse);
    tester
        .widget<StartupLogoScreen>(find.byType(StartupLogoScreen))
        .onFinished();
    await tester.pump();
    expect(find.byKey(const Key('launch_logo')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(started, isTrue);
    expect(find.byIcon(Icons.eco_outlined), findsNothing);
    expect(find.text('Cropwise'), findsNothing);
    pending.complete(Object());
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'startup failure offers retry and mounts only the prepared result',
    (tester) async {
      var attempts = 0;
      var releases = 0;
      await tester.pumpWidget(
        AppStartupGate<Object>(
          initialize: (report) async {
            attempts++;
            report('Opening saved records');
            if (attempts == 1) throw StateError('database unavailable');
            return Object();
          },
          release: (_) async => releases++,
          builder: (_, resources) =>
              const MaterialApp(home: Text('Prepared account')),
        ),
      );
      tester
          .widget<StartupLogoScreen>(find.byType(StartupLogoScreen))
          .onFinished();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('startup_retry')), findsOneWidget);
      expect(find.text('Prepared account'), findsNothing);
      await tester.tap(find.byKey(const Key('startup_retry')));
      await tester.pumpAndSettle();
      expect(find.text('Prepared account'), findsOneWidget);
      expect(attempts, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(releases, 1);
    },
  );
  testWidgets('resources completing after gate removal are released', (
    tester,
  ) async {
    final pending = Completer<Object>();
    var releases = 0;
    await tester.pumpWidget(
      AppStartupGate<Object>(
        initialize: (_) => pending.future,
        release: (_) async => releases++,
        builder: (_, resources) => const SizedBox(),
      ),
    );
    tester
        .widget<StartupLogoScreen>(find.byType(StartupLogoScreen))
        .onFinished();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(Object());
    await tester.pump();
    expect(releases, 1);
  });
}
