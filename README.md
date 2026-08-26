# WormWise

WormWise is an offline-first Flutter application for structured maize fall
armyworm field assessment. The current pilot is designed for field use in
Piat, Cagayan and keeps assessment records and accepted photographic evidence
on the phone.

The scientific source of truth is [`ASSESSMENT_PROTOCOL.md`](ASSESSMENT_PROTOCOL.md).
Implementation status and product limitations are summarized in
[`docs/CURRENT_IMPLEMENTATION_STATUS.md`](docs/CURRENT_IMPLEMENTATION_STATUS.md).

## Current workflow

The app uses five destinations:

- **Home** — selected field, immediate status, and shortcuts.
- **Assess** — saved assessment records and resume access.
- **Scan** — the authoritative active field workflow.
- **Map** — field and boundary context, without active scouting controls.
- **Bot** — a placeholder for later assistance; it does not currently produce
  scientific diagnoses.

Implemented assessment stages are:

| Growth stage | Current support |
| --- | --- |
| VE, V1, V2 | Five-station establishment/cutting workflow |
| V3-V6, V7-V12 | Five-station vegetative camera-first workflow |
| VT-R2 | Setup may be saved as a draft; workflow unavailable |
| R3-R6 | Setup may be saved as a draft; workflow unavailable |

A confirmed approximate field outline is required before a new assessment can
enter setup or field collection. The outline supports scouting and is not a
legal, cadastral, or survey-grade property boundary.

## Technical profile

- Flutter and Dart
- Drift/SQLite schema version 6
- Private, persistent local evidence storage with checksums and thumbnails
- Esri World Imagery for the current online Map and Scan background
- Deterministic illustrated-field fallback when map tiles are unavailable
- Open-Meteo recent precipitation lookup with an offline/manual fallback
- Debug-only isolated test-data database for field-workflow shortcuts

There is no remote synchronization service, validated pest-detection model,
general results engine, treatment recommendation engine, or production
satellite-imagery feed in the current build. Farmer-facing persistence wording
must therefore remain **Saved on this phone**.

## Development

From the project root:

```text
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

For Drift generation after an approved schema change:

```text
dart run build_runner build --delete-conflicting-outputs
```

Do not edit generated database code directly. Schema changes require a versioned
migration and migration tests.

## Key documentation

- [`docs/ASSESSMENT_SETUP_WORKFLOW.md`](docs/ASSESSMENT_SETUP_WORKFLOW.md)
- [`docs/FIELD_LOCATION_AND_OPTIONAL_BOUNDARY.md`](docs/FIELD_LOCATION_AND_OPTIONAL_BOUNDARY.md)
- [`docs/DATABASE_DATA_MODEL.md`](docs/DATABASE_DATA_MODEL.md)
- [`docs/SCAN_IMAGERY_DEPLOYMENT.md`](docs/SCAN_IMAGERY_DEPLOYMENT.md)
- [`docs/WEATHER_DATA.md`](docs/WEATHER_DATA.md)
