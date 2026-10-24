import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/cloud/automatic_sync_scheduler.dart';

void main() {
  test(
    'scoped submission waits for background and other submissions',
    () async {
      final background = Completer<bool>();
      final first = Completer<void>();
      final order = <String>[];
      final scheduler = AutomaticSyncScheduler(() => background.future);
      final running = scheduler.runNow();
      final one = scheduler.runExclusive(() async {
        order.add('first');
        await first.future;
      });
      final two = scheduler.runExclusive(() async => order.add('second'));
      expect(order, isEmpty);
      background.complete(true);
      await running;
      await Future<void>.delayed(Duration.zero);
      expect(order, ['first']);
      first.complete();
      await one;
      await two;
      expect(order, ['first', 'second']);
      scheduler.dispose();
    },
  );

  test(
    'failed scoped submission releases the queue and preserves error',
    () async {
      final scheduler = AutomaticSyncScheduler(() async => true);
      scheduler.setOnline(false);
      await expectLater(
        scheduler.runExclusive<void>(() async => throw StateError('denied')),
        throwsStateError,
      );
      expect(await scheduler.runExclusive(() async => 'next'), 'next');
      scheduler.dispose();
    },
  );

  test('manual backup bypasses a paused reachability probe', () async {
    var attempts = 0;
    final scheduler = AutomaticSyncScheduler(() async {
      attempts++;
      return true;
    });
    scheduler.setOnline(false);
    await scheduler.runManual(() {});
    expect(attempts, 1);
    scheduler.dispose();
  });
  test('manual backup waits then starts a fresh attempt', () async {
    final first = Completer<bool>();
    var attempts = 0;
    final scheduler = AutomaticSyncScheduler(
      () => ++attempts == 1 ? first.future : Future.value(true),
    );
    final running = scheduler.runNow();
    var prepared = false;
    final manual = scheduler.runManual(() => prepared = true);
    expect(prepared, isFalse);
    first.complete(true);
    await running;
    await manual;
    expect(attempts, 2);
    expect(prepared, isTrue);
    scheduler.dispose();
  });

  testWidgets('reconnection uploads waiting work without another edit', (
    tester,
  ) async {
    var attempts = 0;
    final scheduler = AutomaticSyncScheduler(() async {
      attempts++;
      return true;
    });
    scheduler.setOnline(false);
    scheduler.request();
    await tester.pump(const Duration(seconds: 30));
    expect(attempts, 0);
    scheduler.setOnline(true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(attempts, 1);
    scheduler.dispose();
  });

  testWidgets('failures back off and local changes do not bypass retry', (
    tester,
  ) async {
    var attempts = 0;
    final scheduler = AutomaticSyncScheduler(() async => ++attempts >= 3);
    await scheduler.runNow();
    scheduler.request();
    await tester.pump(const Duration(seconds: 4));
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, 2);
    await tester.pump(const Duration(seconds: 9));
    expect(attempts, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, 3);
    await tester.pump(const Duration(minutes: 10));
    expect(attempts, 3);
    scheduler.dispose();
  });

  testWidgets('multiple requests during upload produce one follow-up', (
    tester,
  ) async {
    var attempts = 0;
    final first = Completer<bool>();
    final scheduler = AutomaticSyncScheduler(() {
      attempts++;
      return attempts == 1 ? first.future : Future.value(true);
    });
    final running = scheduler.runNow();
    scheduler.request(immediate: true);
    scheduler.request();
    expect(attempts, 1);
    first.complete(true);
    await running;
    await tester.pump(const Duration(milliseconds: 800));
    expect(attempts, 2);
    scheduler.dispose();
  });

  testWidgets('offline pauses retries and reconnect resumes immediately', (
    tester,
  ) async {
    var attempts = 0;
    final scheduler = AutomaticSyncScheduler(() async {
      attempts++;
      return false;
    });
    await scheduler.runNow();
    scheduler.setOnline(false);
    await tester.pump(const Duration(minutes: 10));
    expect(attempts, 1);
    scheduler.setOnline(true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(attempts, 2);
    scheduler.dispose();
  });

  testWidgets(
    'dispose during failed upload does not schedule another attempt',
    (tester) async {
      var attempts = 0;
      final upload = Completer<bool>();
      final scheduler = AutomaticSyncScheduler(() {
        attempts++;
        return upload.future;
      });
      final running = scheduler.runNow();
      scheduler.dispose();
      upload.complete(false);
      await running;
      await tester.pump(const Duration(minutes: 10));
      expect(attempts, 1);
    },
  );
}
