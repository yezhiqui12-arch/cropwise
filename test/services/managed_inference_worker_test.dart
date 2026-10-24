import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:wormwise/services/computer_vision/faw_inference_worker.dart';
import 'package:wormwise/models/automatic_screening.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/computer_vision/managed_inference_worker.dart';

void _worker(List<Object?> bootstrap) async {
  final replies = bootstrap[0] as SendPort;
  final port = ReceivePort();
  var count = 0;
  replies.send(port.sendPort);
  await for (final dynamic request in port) {
    if (request == null) {
      port.close();
      replies.send({'result': null});
      return;
    }
    if (request == 'crash') Isolate.exit();
    if (request == 'hang') continue;
    if (request == 'error') {
      replies.send({'error': 'inference failed'});
      continue;
    }
    if (request == 'slow') {
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < 150) {
        // Deliberately synchronous CPU work on the worker isolate.
      }
    }
    replies.send({'result': ++count});
  }
}

void _startupCrash(List<Object?> bootstrap) => Isolate.exit();

void main() {
  ManagedInferenceWorker create({void Function(List<Object?>)? entry}) =>
      ManagedInferenceWorker(
        entryPoint: entry ?? _worker,
        initialData: () async => null,
        timeout: const Duration(seconds: 3),
      );

  test('reuses the worker and keeps the calling isolate responsive', () async {
    final worker = create();
    addTearDown(worker.close);
    expect(await worker.run('first'), 1);
    var ticked = false;
    final timer = Timer(const Duration(milliseconds: 20), () => ticked = true);
    addTearDown(timer.cancel);
    expect(await worker.run('slow'), 2);
    expect(ticked, isTrue);
    expect(await worker.run('last'), 3);
  });

  test(
    'rejects concurrent requests and drains active work before close',
    () async {
      final worker = create();
      final active = worker.run('slow');
      await expectLater(worker.run('overflow'), throwsStateError);
      final closed = worker.close();
      await expectLater(worker.run('after close'), throwsStateError);
      expect(await active, 1);
      await closed;
      await worker.close();
    },
  );

  test('worker failure and unexpected exit complete callers', () async {
    for (final request in ['error', 'crash']) {
      final worker = create();
      await expectLater(worker.run(request), throwsStateError);
      await worker.close();
    }
  });

  test('startup failure completes callers and shutdown', () async {
    final worker = create(entry: _startupCrash);
    await expectLater(worker.run('first'), throwsStateError);
    await worker.close();
  });

  test('asset loading failure is retryable with a new worker', () async {
    final worker = ManagedInferenceWorker(
      entryPoint: _worker,
      initialData: () async => throw StateError('assets missing'),
    );
    await expectLater(worker.run('first'), throwsStateError);
    await worker.close();
    final retry = create();
    expect(await retry.run('first'), 1);
    await retry.close();
  });
  test('unresponsive asset loading times out and still closes', () async {
    final worker = ManagedInferenceWorker(
      entryPoint: _worker,
      initialData: () => Completer<Object?>().future,
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(worker.run('first'), throwsA(isA<TimeoutException>()));
    await worker.close();
  });

  test('unresponsive inference times out and releases its worker', () async {
    final worker = ManagedInferenceWorker(
      entryPoint: _worker,
      initialData: () async => null,
      timeout: const Duration(milliseconds: 300),
    );
    await expectLater(worker.run('hang'), throwsA(isA<TimeoutException>()));
    await worker.close();
  });
  test(
    'production worker returns unavailable for missing evidence without plugins',
    () async {
      final worker = ManagedInferenceWorker(
        entryPoint: fawInferenceWorkerMain,
        initialData: () async => [
          TransferableTypedData.fromList([Uint8List(0)]),
        ],
      );
      addTearDown(worker.close);
      final json =
          await worker.run({
                'path': 'missing-evidence-photo',
                'highlighting': false,
                'threshold': .5,
              })
              as Map;
      expect(
        json['suggestedPlantStatus'],
        AutomaticScreening.unavailableStatus,
      );
      expect(json['classificationLabel'], isNull);
    },
  );
}
