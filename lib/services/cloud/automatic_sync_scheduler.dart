import 'dart:async';

/// Coalesces local edits and retries failures without concurrent uploads.
class AutomaticSyncScheduler {
  AutomaticSyncScheduler(this.attempt);

  final Future<bool> Function() attempt;
  Timer? _timer;
  Future<void>? _running;
  bool _pending = false;
  bool _paused = false;
  bool _disposed = false;
  int _failures = 0;

  void request({bool immediate = false}) {
    if (_disposed || _paused) return;
    if (_running != null) {
      _pending = true;
      return;
    }
    // Local edits must not bypass a failed upload's backoff.
    if (_failures > 0 && _timer != null && !immediate) return;
    _timer?.cancel();
    _timer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 800),
      () => unawaited(runNow()),
    );
  }

  void setOnline(bool online) {
    _paused = !online;
    if (!online) {
      _timer?.cancel();
      _timer = null;
    } else {
      request(immediate: true);
    }
  }

  /// Serializes a scoped upload with background work and other scoped uploads.
  Future<T> runExclusive<T>(Future<T> Function() operation) async {
    while (_running != null) {
      await _running;
    }
    if (_disposed) throw StateError('Cloud synchronization has stopped.');
    _timer?.cancel();
    _timer = null;
    final completion = Completer<void>();
    _running = completion.future;
    try {
      return await operation();
    } finally {
      _running = null;
      completion.complete();
      final pending = _pending;
      _pending = false;
      if (!_disposed && (pending || _failures > 0)) request();
    }
  }

  /// Manual retries wait for existing work and bypass reachability probes.
  Future<void> runManual(void Function() beforeAttempt) async {
    final running = _running;
    if (running != null) await running;
    if (_disposed) return;
    beforeAttempt();
    await runNow(ignorePause: true);
  }

  Future<void> runNow({bool ignorePause = false}) {
    if (_disposed || (_paused && !ignorePause)) return Future<void>.value();
    final running = _running;
    if (running != null) {
      _pending = true;
      return running;
    }
    _timer?.cancel();
    _timer = null;
    final completion = Completer<void>();
    _running = completion.future;
    unawaited(_run(completion));
    return completion.future;
  }

  Future<void> _run(Completer<void> completion) async {
    var success = false;
    try {
      success = await attempt();
    } catch (_) {
      // The service reports the error; retain retry even for unexpected errors.
    } finally {
      _running = null;
      final pending = _pending;
      _pending = false;
      if (!_disposed) {
        if (success) {
          _failures = 0;
          if (pending) request();
        } else {
          _failures = (_failures + 1).clamp(1, 7);
          if (!_paused) {
            final seconds = (5 * (1 << (_failures - 1))).clamp(5, 300);
            _timer = Timer(
              Duration(seconds: seconds),
              () => unawaited(runNow()),
            );
          }
        }
      }
      completion.complete();
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
