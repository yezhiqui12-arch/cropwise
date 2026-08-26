# Current implementation status

Last repository audit: 2026-08-26

This is an engineering-status snapshot, not a scientific validation claim.
`ASSESSMENT_PROTOCOL.md` governs protocol requirements.

## Implemented

### Application shell and fields

- Five-tab Home, Assess, Scan, Map, and Bot structure.
- Scan owns active assessment guidance.
- Offline field registration and selected-field persistence.
- Field details and name editing.
- Recently Deleted recovery for 30 days, followed by evidence-file removal and
  audited local deletion.
- Versioned approximate field-outline editor.
- Online Esri World Imagery reference in the field overview/outline editor,
  with an OpenStreetMap alternative.
- Defensive confirmed-outline gate before new assessment setup or Station 1.

### Setup and safety

- Database-backed assessment setup and resume.
- Evaluator and definite stage selection for new records.
- App-selected W or ladder route policy based on stage.
- Recent 48-hour precipitation retrieval through Open-Meteo, cached locally for
  three hours, with a concise manual fallback when retrieval fails.
- Treatment/re-entry safety gate and safety-blocked state.
- Unsupported-stage setup remains a draft before station/plant creation.

### Scan route guidance

- App-generated five-station W and ladder route documents.
- Locally stored boundary, route, station, obstacle, and progress overlays.
- Current phone location, reported accuracy, approximate direction, and
  straight-line distance.
- Evaluator-confirmed arrival; arrival is not inferred automatically.
- Target adjustment with a required reason and audit record.
- Completed station locations and route progress survive recalculation/restart.
- Esri World Imagery online background matching the Map tab, with permanent
  attribution.
- Deterministic illustrated-field fallback when tiles are unavailable.

### V3-V12 workflow

- Five stations, ten consecutive plant positions per station.
- Station location and context handling.
- Camera-first capture with one plant overview, conditional close-up, and
  documented manual fallback.
- Private canonical evidence images, thumbnails, checksum, preview/zoom,
  retake/removal, and restart reconciliation.
- Compact Station Evidence Review with evaluator-confirmed structured
  observations.
- Atomic per-plant saving, station review, block completion, and restart resume.

### VE-V2 workflow

- Five-station progression using the same overall Scan hierarchy.
- Consecutive planting-position records and ten living-seedling records with an
  explicit physical-seedling link where applicable.
- Stage-specific establishment, cutting/injury, evidence, and evaluator review.
- Camera-first evidence architecture with conditional views and documented
  fallback; healthy positions do not require unnecessary photographs.
- Atomic persistence, station review, completion validation, and restart resume.

### Development support

- Debug-only test shortcuts backed by a separate test-data database and a
  permanent TEST DATA indicator.
- Migration, transaction, evidence association, restart, large-text, route,
  camera, and stage-gating tests.
- QA-A on-device image-quality service and controlled tests for integrity,
  source/canonical dimensions, orientation, upscaling, blur, darkness, and
  highlight metrics.

QA-A is service-level work only. It has no farmer-facing warning UI or database
migration and makes no statement about pests, framing recognition, or evidence
sufficiency.

## Temporarily gated

| Stage | Current behavior |
| --- | --- |
| VT-R2 | Setup remains a saved draft; no station or plant workflow starts |
| R3-R6 | Setup remains a saved draft; no station or plant workflow starts |

Legacy records also pass through a defensive session-level stage gate.

## Not implemented

- Validated computer-vision pest detection or automated scientific findings.
- QA-B farmer-facing technical-quality warnings.
- VT-R2 reproductive assessment.
- R3-R6 ear/kernel assessment.
- General assessment results or treatment recommendations.
- Remote synchronization or upload.
- Production satellite-imagery service or supplied licensed field-imagery set.
- AI/LLM advisory, expert-review workflow, or institutional certification.

## Current external dependencies and limitations

- The direct Esri World Imagery reference still needs production
  review for provider terms, authentication, attribution, availability, and
  expected usage; it is not an offline imagery package.
- Open-Meteo recent precipitation needs usable field coordinates and internet
  access. It is weather context, not an observation of mud, irrigation, or
  field-entry safety.
- Accepted evidence is stored on the phone. Device loss or deletion can lose
  evidence because no remote backup/sync service exists.
- Route guidance and outlines are approximate and require evaluator judgment in
  irregular, concave, obstructed, or unsafe fields.

## Next work must remain separately approved

The next increment should be selected explicitly. Likely candidates are QA-B
camera-quality UI, VT-R2 specification/implementation, R3-R6 specification,
results design after all supported-stage workflows stabilize, or integration of
an approved imagery/dataset source.
