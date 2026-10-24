# First-half reliability fixes — 2026-10-24

Implemented scope:
- Preserve source captures through verified temporary file writes and database
  registration. Failed decoding, filesystem writes or registration retain the source.
  A refresh failure after commit does not remove registered evidence files.
- Register replacement evidence transactionally before discarding the previous
  accepted photo. Failed retakes retain the old accepted evidence.
- Give the composite CV service explicit, idempotent shutdown; wait for in-flight
  work and close owned interpreters/workers. Assessment and Advisor screens close
  services they create. Injected services/models remain the caller's responsibility.
  Partially initialized native interpreters are closed on initialization failure.
- Missing classifier/detector files throw rather than producing healthy results.
  The composite returns screening-unavailable. Invalid/missing probabilities and
  unsupported binary labels cannot count as available negative screens. Advisor
  explanations distinguish unavailable processing from a damage conclusion.
- Default assessment/Advisor inference uses a persistent, owned background isolate.
  Preprocessing, classifier, highlighting and species inference run there. Asset
  buffers are transferred from the root isolate; optional model assets load only
  when highlighting is enabled. One active request is allowed, with no backlog.
  Startup/request timeouts, worker failure handling and shutdown prevent stranded
  callers. Settings changes recreate the worker when necessary. Stale results
  are rejected before writing photo checkpoints to a changed/disposed workflow.

No database schema change or migration is needed. Existing unavailable statuses,
JSON result contracts, evidence states and transactional registration are retained.
Historical results are not rewritten. Completion validators, startup recovery,
backup retention/manifests, broad UI refactoring and release signing are unchanged.

Validation:
- 41 focused tests passed; one native integration check skipped by default.
- Tests include DB failure/retry, failed retakes, corrupt input, blocked destinations,
  post-commit refresh failure, shutdown ownership, concurrent-request rejection,
  responsive caller during worker CPU work, worker crash/error/timeout, production
  worker missing-file serialization, persisted denominators and Advisor wording.
- Application library plus changed/new tests analyzed: 0 errors, 29 warnings and
  97 informational diagnostics (the existing application baseline).
- Changed Dart files formatted; git diff --check passed.
- Earlier stale pipeline assertions were updated to the existing damage-screening
  contract: optional overlays do not assert evaluator-confirmed infestation.

Native verification limit:
The explicit real-model smoke test was attempted and could not load
libtensorflowlite_c-win.dll in the local Flutter Windows test engine. It failed
before loading a model, so it does not establish native inference parity or device
performance. The opt-in test remains available:

flutter test --no-pub --dart-define=WORMWISE_NATIVE_MODEL_TEST=true test/services/faw_native_worker_test.dart

Run it in an environment with the required platform TFLite runtime installed.
Physical-device capture and native-model performance remain unverified. Full
application startup/interruption recovery belongs to the approved second half;
this increment addresses save failure preservation, not a new durable intake queue.
