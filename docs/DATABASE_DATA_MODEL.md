# WormWise database and data model

## Status

WormWise uses Drift over local SQLite. The executable schema is
`lib/data/local/app_database.dart`; the current schema version is **6**. This
document describes what is implemented and separates it from the longer-term
protocol model.

`ASSESSMENT_PROTOCOL.md` remains the scientific source of truth. The existence
of a column does not by itself authorize a scientific derivation or
classification rule.

## Implemented tables

The schema currently contains:

- `people`
- `fields`
- `field_boundary_versions`
- `crop_cycles`
- `field_blocks`
- `interventions`
- `intervention_inputs`
- `intervention_areas`
- `assessments`
- `safety_checks`
- `assessment_block_runs`
- `stations`
- `planting_unit_observations`
- `plant_observations`
- `ve_v2_station_inspections`
- `vegetative_observations`
- `reproductive_observations`
- `ear_observations`
- `evidence_capture_sessions`
- `evidence_media`
- `metric_results`
- `sync_outbox`
- `audit_logs`
- `app_preferences`

Some tables reserve a stable structure for later protocol stages. Their
presence does not mean the related workflow, calculation, result, or service is
implemented.

## Implemented assessment scope

| Area | Persistence status |
| --- | --- |
| Field and versioned approximate outline | Implemented |
| Assessment setup and treatment-safety checks | Implemented |
| Five-station hierarchy and route progress | Implemented for current pilot rules |
| VE-V2 planting positions and linked living seedlings | Implemented |
| V3-V12 raw plant and vegetative observations | Implemented |
| Evidence capture sessions and media | Implemented |
| Station/block completion validation | Implemented for VE-V2 and V3-V12 |
| VT-R2 and R3-R6 persistence structures | Reserved; workflows unavailable |
| Metric/result generation | Not approved as a general results feature |
| Remote synchronization | Not implemented |
| AI inference or expert-review records | Not implemented |

## Core modelling rules

1. Use phone-generated UUID text identifiers for offline creation.
2. Store raw evaluator observations before classifications or calculated
   projections.
3. Never overwrite raw observations with a future automated suggestion or
   expert decision.
4. Keep stage-specific observations and denominators separate.
5. Preserve possible non-FAW evidence, uncertainty, old damage, and mixed
   observation combinations.
6. Do not infer scientific meaning from similarly named database fields unless
   the protocol explicitly defines the mapping.
7. Save each plant or planting-position change atomically with its audit/outbox
   record.
8. Version field outlines, evidence policies, protocols, and future formulas.
9. Use soft deletion and audited tombstones where linked history must remain
   explainable.

## Assessment hierarchy

```text
field
└── crop cycle
    └── assessment
        └── assessment block run
            └── station (1-5)
                ├── planting-unit observations (VE-V2)
                ├── plant observations (positions 1-10)
                │   └── stage-specific observations
                └── evidence capture sessions/media
```

The block, station, and plant identifiers—not screen state—provide evidence
association. Block and station creation is idempotent so reopening a workflow
does not create duplicates.

## VE-V2 relationship

VE-V2 keeps planting-unit and living-seedling records separate because they use
different denominators. When both records describe the same physical seedling,
`plant_observations.source_planting_unit_observation_id` links them. The link
allows reuse of physical context without copying or silently deriving
biological answers.

## V3-V12 observation semantics

`plant_observations` stores common raw/evaluator facts, including assessability,
old damage, possible non-FAW evidence, uncertainty, natural-enemy quick status,
and evaluator-confirmed plant status. `vegetative_observations` stores the
stage-specific raw fields such as fresh windowpanes, scraping, cutting or
tearing, frass, whorl-feeding signs, larva information, and nullable egg-mass
visibility.

`current_faw_evidence` is not species confirmation. Scraping, cutting or
tearing, fresh frass, and general whorl-feeding signs must not independently
create that value unless an approved protocol rule explicitly supports it.

## Evidence storage

Accepted evidence uses private persistent app storage. The pilot treats the
orientation-normalized image, limited to a 2048-pixel longest edge, as the
canonical WormWise evidence image. It preserves a checksum and has a separate
thumbnail. The unrestricted camera-source image is not automatically retained.

Capture sessions and media use staged/ready states because SQLite and the
filesystem cannot be committed atomically together. Reconciliation repairs or
marks incomplete states without attaching an image to a different plant.

Deliberate deletion removes the accepted file and retains an audited metadata
tombstone/checksum where appropriate; it must not secretly preserve the image.

## Migration history

- **v2** — app preferences.
- **v3** — possible non-FAW and uncertainty flags and nullable egg-mass field.
- **v4** — capture sessions and evidence lifecycle metadata.
- **v5** — VE-V2 station/planting-position persistence and the explicit link
  from a living-plant record to its source planting-unit record.
- **v6** — capture-session linkage needed by the current VE-V2 workflow.

Every future schema change requires an additive migration where possible,
rollback/error tests for its transaction boundaries, and preservation tests for
nullable fields and older records.

## Persisted facts versus derived UI state

Persisted facts include assessment status, safety outcome, station completion,
plant/position records, evidence lifecycle state, timestamps, route documents,
and audit entries.

The following are derived view states and must not be collapsed into the
assessment-status column:

- resume assessment
- interrupted presentation state
- plant in progress
- station review
- local save failure

There is no remote synchronization service. Although `sync_state` and
`sync_outbox` support local mutation bookkeeping and a future boundary, the UI
must not tell farmers that synchronization is pending.

## Planned, not implemented

The conceptual protocol model may later require dedicated tables for detailed
diagnostic findings, detailed natural-enemy observations, product-registry
snapshots, AI inferences, expert reviews, comparisons, comparison events, and
reports. None of those should be treated as current schema or silently added to
an unrelated increment.

Likewise, the current `reproductive_observations`, `ear_observations`, and
`metric_results` tables do not authorize VT-R2, R3-R6, or result UI before their
separate specifications are approved.

## Privacy and deletion

- Keep personally identifying information separate from observation data.
- Avoid people and identifying documents in evidence images.
- Keep checksums to detect missing or changed evidence.
- A field moved to Recently Deleted is restorable for 30 days.
- After the retention period, stored evidence files are removed and local rows
  are marked deleted; minimal tombstone/audit metadata is retained.
- Debug test data uses the separate `wormwise_debug_test_data` database and
  cannot be entered from release builds.
