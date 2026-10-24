import 'dart:async';
import 'dart:isolate';

/// One owned worker, one active request, and no unbounded queue of photos.
/// Messages are data only; native interpreters never cross isolate boundaries.
class ManagedInferenceWorker {
  ManagedInferenceWorker({
    required this.entryPoint,
    required this.initialData,
    this.timeout = const Duration(minutes: 2),
  });

  final void Function(List<Object?>) entryPoint;
  final Future<Object?> Function() initialData;
  final Duration timeout;
  Isolate? _isolate;
  ReceivePort? _events;
  StreamSubscription<dynamic>? _subscription;
  Completer<Object?>? _response;
  SendPort? _commands;
  Future<Object?>? _active;
  Future<void>? _closing;
  bool _closed = false;
  bool _failed = false;

  Future<void> _start() async {
    if (_commands != null) return;
    final data = await initialData().timeout(timeout);
    final events = _events = ReceivePort();
    final ready = Completer<SendPort>();
    // Install error listeners before spawning so early failures cannot strand
    // startup or an inference Future.
    _subscription = events.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is Map && message.containsKey('result')) {
        final response = _response;
        if (response != null && !response.isCompleted) {
          response.complete(message['result']);
        }
      } else {
        final error = StateError(
          message is Map ? '${message['error']}' : 'Inference worker exited.',
        );
        _failed = true;
        if (!ready.isCompleted) ready.completeError(error);
        final response = _response;
        if (response != null && !response.isCompleted) {
          response.completeError(error);
        }
      }
    });
    final startup = ready.future.timeout(timeout);
    // Observe startup immediately, even if spawning itself fails.
    unawaited(
      startup.then<void>((_) {}, onError: (Object _, StackTrace stack) {}),
    );
    _isolate = await Isolate.spawn(
      entryPoint,
      <Object?>[events.sendPort, data],
      onError: events.sendPort,
      onExit: events.sendPort,
      errorsAreFatal: true,
    );
    _commands = await startup;
  }

  Future<Object?> run(Object? request) {
    if (_closed || _failed) {
      return Future.error(StateError('Inference worker is closed.'));
    }
    if (_active != null) {
      return Future.error(
        StateError('Screening is still running. Please wait.'),
      );
    }
    final operation = _run(request);
    _active = operation;
    return operation;
  }

  Future<Object?> _run(Object? request) async {
    try {
      await _start();
      final response = _response = Completer<Object?>();
      final result = response.future.timeout(timeout);
      _commands!.send(request);
      return await result;
    } catch (_) {
      _failed = true;
      await _release();
      rethrow;
    } finally {
      _response = null;
      _active = null;
    }
  }

  Future<void> close() {
    _closed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      await _active;
    } catch (_) {
      // Failed inference has already been delivered to its caller.
    }
    if (_commands != null && !_failed) {
      final response = _response = Completer<Object?>();
      final stopped = response.future.timeout(timeout);
      _commands!.send(null);
      try {
        await stopped;
      } catch (_) {
        // Force-stop a worker that cannot acknowledge shutdown.
      }
    }
    await _release();
  }

  Future<void> _release() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    await _subscription?.cancel();
    _subscription = null;
    _events?.close();
    _events = null;
  }
}
