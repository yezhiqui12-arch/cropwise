# Performance changes — 25 October 2026

## Startup

Prepared capture journals still replay before the account UI opens. Startup
reconciliation now selects only assessments with unfinished or missing evidence
states, using a partial index. Ready historical photographs are no longer all
inspected on every launch. The existing scouting workflow reconciles an
assessment when that session opens. The read-only history repository remains
read-only. External loss of a ready historical file may therefore be detected
later than before, when that assessment's evidence is accessed/reconciled.

## Account backups

Snapshot fingerprints, JSON compression, and fallback file checksums run in
background isolates on native platforms. Full recovery snapshots and their
completeness flags are preserved; this is not an incremental-backup redesign.
An in-memory cache holds up to 512 thumbnail checksums, scoped by account/path
and invalidated by file size/mtime or a fresh-verification request. Original
evidence checksums and upload read-back verification remain in place. Account
identity is rechecked after isolate work and before publishing a snapshot.

## Inference

The native inference worker decodes and orients each photograph once and shares
that request-scoped image between the classifier and optional detector. It
releases references after each request and during shutdown. Model files,
thresholds, resizing algorithms, and output interpretation are unchanged.
Interpreter execution still needs validation on representative Android hardware.

## Database

Schema version 9 adds five indexes without rebuilding tables or deleting records.
Both new databases and upgrades create the indexes. Unique constraints already
cover several station/block parent keys, so those indexes are not duplicated.
Migration tests retain an existing assessment and verify evidence query plans.

## Images

Root image assets are listed explicitly in pubspec.yaml. Four unreferenced
illustrations are kept in source but excluded from packaging:
boundary_layers_accent.png, boundary_satellite_method.png,
boundary_walk_method.png, profile_field_header.png. New root-level images must
be added to the asset list explicitly. Growth-stage and action-image directories
remain bundled.

Twelve PNG IDAT streams were recompressed losslessly. Decompressed image data,
dimensions, transparency, and other PNG chunks are unchanged. This saved 2.52
MiB across source images; savings overlap with the excluded illustrations.
AI model files were not changed.

## Validation scope

Targeted coverage includes snapshot payload compatibility, pending startup
selection, v8-to-v9 migration and query plans, evidence storage/recovery, account
backup/recovery, assessment history, photo GPS persistence, and AI pipeline and
lifecycle behavior. Physical-device frame times, cold-start timings, battery,
and peak RAM remain to be measured. Whole-project analysis has older test/API
errors outside this change; analysis of the changed production code is clean.
