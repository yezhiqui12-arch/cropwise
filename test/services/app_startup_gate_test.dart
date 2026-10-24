import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/startup/app_startup_gate.dart';

void main() {
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
    await tester.pumpWidget(const SizedBox());
    pending.complete(Object());
    await tester.pump();
    expect(releases, 1);
  });
}
