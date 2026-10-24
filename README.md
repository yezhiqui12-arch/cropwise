# WormWise

WormWise is an offline-first Flutter application for structured maize fall
armyworm field assessment in Piat, Cagayan. Local Drift/SQLite records and
private evidence files remain authoritative during fieldwork. Optional
Supabase services provide identity, account backup, expert review, messaging,
and AI access.

## Current assessment workflow

New assessments use protocol `wormwise-da-scattered-20-v1`.

- Each confirmed sampling block contains 20 dispersed plant locations.
- Each location represents one selected plant.
- Suggested locations stay inside the confirmed block, respect the configured
  edge margin and obstacles, and may be adjusted with a recorded reason.
- The app does not generate or require a connecting walking route. The
  evaluator chooses a safe and accessible path between suggestions.
- Up to three photographs may be associated with one sampled plant.
- On-device model output remains a screening suggestion. It does not silently
  become an evaluator observation, expert finding, Davis score, diagnosis, or
  treatment decision.
- Completion validates the required blocks and all 20 plant locations in each
  block before publishing the assessment result.

The four primary destinations are Home, Assess, Map, and Guide. Active
fieldwork opens in a route-local assessment session from the selected field,
Home, or Assess.

## Technical profile

- Flutter and Dart
- Drift/SQLite schema version 8
- Provider-based application and workflow state
- Private local evidence storage with checksums and thumbnails
- On-device TFLite screening and pest-species suggestions
- Approximate field outlines and dispersed sampling-point generation
- Open-Meteo precipitation context with an offline/manual fallback
- Optional Supabase identity, backup, synchronization, expert review, and
  messaging
- Gemini requests through the authenticated `gemini-advisor` Supabase Edge
  Function

## Gemini configuration

The mobile app never accepts or stores a Gemini provider credential. It sends
authenticated requests to the `gemini-advisor` Edge Function. Store
`GEMINI_API_KEY` only as an Edge Function secret. Flutter builds contain only
the Supabase URL and publishable key.

```sh
supabase secrets set GEMINI_API_KEY=your_key
supabase functions deploy gemini-advisor
```

## Scientific boundaries

WormWise reports sampled observations with their actual denominators. Damage
screening, current sampled infestation, expert-reviewed damage incidence, and
Davis severity are separate measures. The application does not extrapolate a
sample into a whole-field diagnosis, prescribe pesticide use, or claim an
independently validated detector.

Approximate field outlines and suggested plant locations support scouting;
they are not cadastral, survey-grade, or turn-by-turn navigation products.

## Development

Typical validation commands, when explicitly requested, are:

```text
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Do not edit `lib/data/local/app_database.g.dart` directly. Database changes
must update the Drift schema version, preserve upgrade paths, regenerate the
generated file, and include migration coverage.

## Key documentation

- `ASSESSMENT_PROTOCOL.md`
- `docs/ARCHITECTURE.md`
- `docs/CURRENT_IMPLEMENTATION_STATUS.md`
- `docs/ASSESSMENT_SETUP_WORKFLOW.md`
- `docs/DATABASE_DATA_MODEL.md`
- `docs/DA_GUIDED_SCOUTING_IMPLEMENTATION.md`
- `docs/GEMINI_MODEL_POLICY.md`
- `docs/SUPABASE_SETUP.md`

## Reproducible release

Use Flutter 3.44.1, as recorded in .flutter-version and pinned in CI. See docs/REPRODUCIBLE_RELEASE.md for source, configuration, backend deployment, and signing prerequisites.
