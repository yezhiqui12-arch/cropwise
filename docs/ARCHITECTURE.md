# WormWise architecture

## Runtime shape

WormWise is an offline-first Flutter application. `lib/main.dart` initializes
the optional Supabase boundary, opens one `AppDatabase`, restores local account
state and language settings, and creates `WormWiseDataScope`.

The primary dependency direction is:

```text
screens and widgets
  -> workflow and workspace providers
  -> repositories and domain services
  -> Drift database and private evidence files
```

Home, Assess, Map, and Guide remain alive in the main navigation shell. Active
sampling is a route-local session opened from field context, Home, or Assess.

## Current sampling model

New assessments use `wormwise-da-scattered-20-v1`. Each sampling block has 20
dispersed numbered plant locations and one selected plant per location. The
workflow persists suggested map anchors separately from recorded phone
coordinates. There is no generated connecting route; the evaluator chooses a
safe path through the suggestions.

The existing local sampling-location tables and repository relationships are
retained as internal storage. User-facing DA screens consistently describe
Plant 1 through Plant 20.

## Major boundaries

- `lib/screens`, `lib/widgets`, `lib/theme`: presentation and navigation.
- `lib/providers`: selected-field state, history state, Advisor state, and the
  active sampling workflow.
- `lib/data/local`: Drift schema, migrations, generated queries, and stable
  database codes.
- `lib/data/repositories`: persistence and query boundaries.
- `lib/data/services`: atomic saves, validation, and metric calculation.
- `lib/services`: maps, geometry, location, weather, evidence, CV, cloud, and
  Advisor integrations.

## Evidence and computer vision

Accepted media is normalized, checksummed, thumbnailed, and stored privately.
Database and filesystem operations use staged states and reconciliation because
they cannot share a transaction.

Model results are suggestions with confidence, boxes, model identity, and
evidence association. Evaluator observations and expert findings are separate
facts and are never silently replaced by inference output.

## Cloud boundary

The app can operate locally without Supabase configuration. Configured builds
support identity, account backup, data synchronization, expert-case submission,
private evidence sharing, and reviewer messaging. Database RLS, storage
policies, and guarded RPCs are the authorization boundary.

Gemini traffic goes through the authenticated `gemini-advisor` Supabase Edge
Function. The provider credential exists only in the function environment.
The mobile build contains a Supabase URL and publishable key, not a Gemini
credential.

## Source-of-truth order

1. `lib/services/scouting_sampling_protocol.dart` for current sampling identity
   and dimensions.
2. `lib/data/local/app_database.dart` for local schema and upgrades.
3. Repositories, services, and providers for runtime behavior.
4. `ASSESSMENT_PROTOCOL.md` and feature documentation for explanation.

Generated Drift code must be changed only through code generation after an
approved schema change.
