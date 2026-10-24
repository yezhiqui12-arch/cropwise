# DA monitoring PDF and guided observations

Implemented 7 October 2026 in the mobile application. This is an adapted printable version of the DA booklet's **Porma 1. Pagsubaybay sa Harabas**, using the user's requested presence checkboxes. It is not a claim that the app reproduces every DA paper reporting requirement.

## Farmer workflow

1. Complete the guided 20-plant walk in a sampling block.
2. Before saving Plant 20 and entering sample review, confirm **Likas na mga kaaway**. Select predators, pathogens and/or parasitoids, or select None observed or Cannot identify. Skip records Not recorded, rather than reporting absence. The answer belongs to that block. Resuming a completed sample without an answer also prompts before completing the block.
3. Optional correction: tap a plant pin, then **Correct observations**. Eggs, larvae, pupae and damage can each use Automatic, Present or Not present. Save explicitly; Reset followed by Save removes overrides. This does not change the active scouting plant, original model outputs, Davis scores or AI advice.
4. From assessment results, choose **Export PDF**. Select L1–L12 for the monitoring week, review prefilled farmer/collector details, and optionally expand Field and planting details. Create PDF opens the platform share/save flow.

## Form fields

| Data | Source / input |
| --- | --- |
| Assessment date, field name, block number and hectares | Saved assessment and sampling block |
| Region, province, municipality, barangay, field ID | Prefilled where available; optional editable export details |
| Farmer / representative, collector | Field owner and assessment evaluator where available; editable |
| Land tenure, topography, soil texture | Optional export details |
| Previous crop, adjacent crop | Optional export details |
| Planting pattern, date, variety, spacing | Crop-cycle data where available; editable |
| Planting material source, corn type, fertilizer application, remarks | Optional export details |
| Latitude / longitude | Optional field coordinates checkbox; saved boundary centroid |
| Monitoring week L1–L12 | Farmer chooses the week; defaults to L1 |
| Plant rows 1–20, Itlog / Larba / Pupa / Pinsala | Saved current model findings plus explicit optional farmer observations |
| Growth stage | Saved assessment stage |
| Rainfall | Saved assessment weather context, previous 48 hours |
| Natural enemies | Block confirmation |

Shared field/planting details are reused within the same crop cycle. Week, collector and remarks remain assessment-specific. Missing details print as blank lines; no invented values are inserted.

## Checkbox rules

- Egg presence: any saved detector box with class ID 3.
- Larva presence: any saved detector box with class ID 2.
- No egg/larva detection counts as a negative only if the detector completed. Disabled, skipped, failed or missing detection remains unassessed.
- Damage: the saved classifier label FAW damage / No FAW damage. **Pinsala records presence, not Davis severity.**
- Pupa: unassessed automatically because the current detector has no pupa class; an optional farmer observation can fill it.
- Several photos still produce one plant row. The entries indicate presence, not numbers of individual eggs or larvae.
- X in a box means present/detected; empty box means not present/not detected; dash means not assessed. An asterisk identifies an optional farmer override.
- Kabuuan shows positive plants / assessed plants separately for each column. Missing results do not count as negatives.

The export uses the saved model-reader eligibility rules. Results from changed/deleted evidence are not silently reused. Corrections use assessment ID + block run ID + plant number and a media ID/checksum signature; changing photos invalidates the old correction. No expert finalization is needed for this observational form.

## Rainfall

Read `open_meteo_precipitation_last_48h_mm` from the assessment's saved weather context. A finite nonnegative amount gives May ulan for >0 mm or Walang ulan for 0 mm. Print the saved period end and source. If unavailable, use a saved farmer rain/wet-field answer where present; otherwise print Not recorded. Historical export does not request today's weather, infer weather from model results, or assign unsupported rainfall intensity categories from the booklet's abbreviated codes.

## Storage and compatibility

`DaMonitoringRepository` uses existing SQLite app preferences:

- `da_monitoring_v1_<assessmentId>`: form details, per-block enemies and per-plant corrections.
- `da_field_profile_v1_<cropCycleId>`: reusable export field details.

Assessment updates are transactional and audit recorded. Existing private account snapshot backup includes these preferences; changes trigger its normal scheduler. This does not add relational dashboard columns or publish corrections as finalized expert ratings. No live database migration is needed for this mobile feature.

DA protocol assessments route Export PDF to the new service. Existing legacy assessments retain their former report exporter. Models, inference thresholds, sampling geometry, LLM prompts and finalized expert severity logic remain unchanged.

## Printable scope

The current assessment exports one 20-plant table per sampling block. Normal-length field information fits one A4 page per block; longer entries can continue onto another page. Fonts are embedded and bundled, so PDF generation works offline and supports Filipino names.

This export records the selected monitoring week/date. It does not combine twelve different visits into the booklet's full L1–L12 history matrix or claim that Plant 7 from different visits is physically the same plant. A combined longitudinal form would require an explicit cross-visit plant identity policy.

## Validation

All 40 focused tests passed across the monitoring models, PDF generation, monitoring controls, Plant 20 screen transition, actual plant overview, assessment results models/screens, guided-scouting database workflow and saved-weather service. They cover detector presence/unavailable mapping, rainfall snapshot parsing, block-specific correction identity, changed-photo invalidation, natural-enemy selection and persistence, optional correction controls, export details and existing scouting/results regressions. Focused source analysis reported no errors or warnings, with 18 style information messages. The generated two-block sample is marked EXAMPLE DATA. PDF pages and widget renders were visually inspected, including natural-enemy controls at 200% text.

Source changes and automated/render checks do not verify camera behavior, native sharing or installed-device navigation on a physical phone.
