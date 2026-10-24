# WormWise database and data model

## Status

WormWise uses Drift over local SQLite. The executable schema is
`lib/data/local/app_database.dart`; the current schema version is **8**.

## Core relationships

```text
field
  -> boundary versions
  -> crop cycles
  -> assessments
      -> block runs
          -> internal sampling locations
              -> plant observations
                  -> stage-specific observations
                  -> evidence media
                  -> model results
      -> metric results
      -> audit and synchronization records
```

For protocol `wormwise-da-scattered-20-v1`, every required block has 20
numbered sampling locations and one selected plant per location. Existing
internal table names are retained to preserve database relationships and cloud
compatibility; user-facing DA screens describe numbered plants.

## Local authority

Drift records and private evidence files are authoritative during fieldwork.
Plant saves, review state, completion, and metric refresh use transactions where
possible. Evidence files use staged database states and reconciliation because
SQLite and filesystem writes cannot share a transaction.

## Cloud projection

Configured builds synchronize account-scoped field, boundary, assessment,
sampling, result, and expert-case data according to the current services and
deployed RLS policies. Consent controls access to location and evidence.
Dashboard access is authorized by database policies and guarded RPCs, not by
browser labels.

## Schema rules

- Do not edit `app_database.g.dart` directly.
- Increment `schemaVersion` for schema changes.
- Preserve every supported upgrade path in `MigrationStrategy`.
- Keep stable protocol, status, provenance, and sync codes centralized.
- Store formulas with their version, numerator, denominator, unit, timestamp,
  and warnings.
- Do not infer missing results as zero or overwrite human observations with
  model output.
