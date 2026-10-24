# DA guided scouting: implementation and verification

Implemented 6 October 2026 in the mobile app. This change covers the approved Guided Walk interface and the switch to DA's 20-plant sampling guidance. It does not implement all panel recommendations or redesign the dashboard.

## User flow

1. Start a new assessment and confirm the existing field outline, evaluator, growth stage, conditions, safety, and required block outlines.
2. The app generates 20 suggested plant locations throughout each sampling block and numbers untouched suggestions in a shorter walking order. The map highlights the active plant and upcoming plants; sampled plants use green numbered pins, with no checkmarks. The header shows the current plant (for example, Plant 7 shows `7 of 20`), with saved-count information retained in its accessibility label. The expand icon replaces `View all`; it collapses the plant panel to a bottom strip while keeping the field/hectare/block header visible. Pull the strip upward or tap its handle to restore the details. A separate fit-field icon recenters the outline.
3. Walk to the suggested point and select a nearby actual plant. Inspect the upper 3–4 leaves where present. Early seedling stages instead show guidance for the available newest leaves and stem base. There is no inspected-leaf selector and no repeated “Keep at least 3 m” message on this screen; generated and adjusted suggestions still enforce the margin in geometry.
4. Tap `I'm at the plant`. Phone location is recorded through the existing location service when available. Manual arrival remains possible without GPS. Cached or older-than-30-second fixes do not produce a live distance on the walk screen.
5. Capture an overview and optionally continue with closer views, up to three photos of the same plant. The existing continuous camera session remains open between shots. The user can also import up to the remaining number of photo slots for this plant.
6. Review the saved evidence and automatic screening. `Review / notes` allows natural-enemy counts, uncertainty, and other field observations to be recorded without changing the screening result or assigning a final diagnosis.
7. Tap `Save and next plant`. At Plant 20, review the sample and complete the block using the existing completion controls. The DA capture audit omits unreported leaf counts; it does not default to three leaves. The inspection guidance remains visible in the expanded panel. Expert confirmation remains separate and pending.
8. Resume after interruption through the existing resume and safety checks. Saved photos, location, field notes, and completed sampling locations remain available. Any previously reported leaf counts are preserved. Expanded-map state is preserved while progressing between plants in the same block.

## Pin interaction and model access revision

- Every individual DA pin is tappable. Its read-only sheet shows plant number, sampled/in-progress/not-sampled status, screening result/confidence, recorded plant/photo location where available, photos and field notes. Photos open in the existing viewer with saved model overlays. An untouched point shows No photos yet; a failed load offers Retry.
- Opening another plant's pin does not select it for capture, change the current plant, or rewrite its observation. The provider reads that location's saved snapshot/evidence. Cached model results must match the current photo checksums; old results are not silently attached to different evidence.
- After capturing the first photo, the expanded current-plant panel has a separate `Model results` button. It runs the existing pipeline if needed and opens the same preview without requiring station/sample review. `Edit field notes` retains the existing inspector and save flow. Model architecture, thresholds, prompts and expert confirmation are unchanged.
- DA maps use one anchor per plant at its planned position. Capture coordinates are retained in plant details. Saving does not move a pin, and duplicate pin/checkmark rendering is removed.
- At distant zoom levels, nearby projected screen positions form bounded groups; no long chain across the whole field is collapsed solely because adjacent plants are close. Group badges have a rounded-square layers icon and a count, distinct from circular plant-number pins. Tapping a group lists its member plants and offers `Zoom to these plants`. Counts refer to sampling pins, never to infestation or extra plants.
- Camera-dependent rendering follows zoom, pan and rotation. At normal scouting zoom all 20 plants remain separate numbered markers; grouping is used only when zoomed out. The field border is thinner, and the phone location is a small blue dot with its existing metre-based accuracy circle.
- The latest interaction checks passed 23 tests across the guided walk, route-map, DA database and pin-details widget suites. After the final badge/recorded-location refinements, the eight database/details checks and all 15 walk/map checks passed. They cover zoomed-out grouping, tapping a group/member, removed checkmarks, direct model access after one photo, saved details/classification/confidence, read-only browsing, resume and the existing legacy map behavior. Both expanded-map and expanded-details widget renders were visually checked. Device gesture/GPS and camera checks remain outstanding.

## Sampling and geometry

- Assessment protocol version: `wormwise-da-scattered-20-v1`.
- Saved pattern: `da_scattered_20`; generation algorithm: `da_manual_scattered_points_walk_v2`.
- The 20 positions approximate the dispersed arrangement illustrated in the supplied DA booklet. The diagram is a schematic, not surveyed coordinates or a prescribed numbered walking route.
- Positions adapt to the saved block's shape and orientation, stay inside the polygon and at least 3 m from its edges, and avoid marked obstacles. The app uses a 2 m separation heuristic between suggested points. This additional separation rule is an app choice.
- Completed map anchors remain at their planned points. Actual capture coordinates remain stored and available in plant details; a GPS fix does not relocate or duplicate the numbered pin.
- Walking order uses nearest-next selection followed by reversal of inefficient sections. It keeps Plant 1 as the starting point and never increases the total straight-line distance over the original ordering. This is a local optimization, not a claim of a globally shortest or navigable path. The same set of scattered positions remains sampled.
- On reopening an earlier DA sampling path, only untouched suggestions after the highest recorded, arrived, completed, or manually adjusted plant can be renumbered. Recorded photos, plant observations, locations and notes retain their identities. The updated path version is saved once; completed assessments are not relabeled.
- The 3 m check measures shortest distance to every polygon edge in a local metre coordinate frame. It is relative to the confirmed saved block outline, including concave edges. Boundary accuracy and phone GPS accuracy determine how well the suggested position matches the real field; the app cannot certify the actual selected plant's ground distance from the edge.
- No connecting route is generated for the DA pattern. Users choose an accessible path between the sampling suggestions.
- An unreachable, unsaved point can be adjusted. Adjustments must stay inside the block, respect the edge margin and obstacles, and remain separated from other points.
- A narrow or unusable outline that cannot accommodate 20 points produces an error rather than silently reducing the sample or placing points outside the field.
- The DA page specifies 20 plants in one hectare. Existing block partitioning still supports up to five hectares, using 20 plants per confirmed block of no more than one hectare. Using 20 plants in a smaller or final fractional block is an app adaptation, not a newly verified DA sampling prescription. The interface shows the actual block area.

## Storage and compatibility

The existing station table is retained as an internal sampling-location container: a DA assessment has 20 locations, with one plant record at each location. The interface calls these Plant 1–20. This avoids a database migration and preserves the existing photo, location, review, audit, and sync relationships.

Counts are selected from the saved assessment protocol. Records are never silently converted between protocol versions. Completion validates all 20 DA locations and exactly one plant at each. Multiple photographs never increase the plant count.

History loading now includes all 20 locations. Plant detail pages use the visible sampling number rather than repeatedly calling every internal position `Plant 1`. Existing broader results and PDF screens still use some station terminology; redesigning those summaries and exports belongs to the subsequent reporting work.

The single-plant importer remains scoped to the active plant. As of 7 October 2026, **Import sample photos** opens a separate multi-plant workspace: choose all overview/closer photos together, explicitly group them into up to 20 plants, then save and screen. Gallery evidence does not receive a fabricated original capture location. See [DA bulk import implementation](DA_BATCH_IMPORT_IMPLEMENTATION.md) for grouping, resumable drafts and verification.

Field notes are saved with an audit/outbox entry. Automatic screening may be rerun without overwriting those notes. It cannot become a farmer-confirmed or expert-confirmed diagnosis through the DA inspector. No Davis score, damaged-hectare estimate, treatment threshold, or barangay prevalence is inferred by this change.

## Main implementation files

- `lib/services/scouting_sampling_protocol.dart`: protocol-specific sampling dimensions.
- `lib/services/scouting_route_generator.dart`: dispersed DA points, edge/obstacle checks, serialization.
- `lib/data/repositories/scouting_workflow_repository.dart`: version-aware sampling snapshots, locations, and reviews.
- `lib/providers/five_station_workflow_provider.dart`: guided plant save, resume, progression, and field notes.
- `lib/screens/scan/guided_plant_walk_step.dart`: map beneath the fixed header, expandable/collapsible draggable plant panel, current-plant indicator, and scrollable actions for small screens and larger text.
- `lib/widgets/offline_scouting_route_map.dart`: camera fitting and attribution account for the overlay, keeping the outline and active pin visible above the plant panel.
- `lib/data/repositories/evidence_capture_repository.dart` and `lib/services/evidence_capture_coordinator.dart`: DA capture may omit the leaf count; legacy capture still requires its reported count.
- `lib/screens/station1/station1_workflow_screen.dart`: camera, import, and inspector integration.
- `lib/data/services/five_station_completion_service.dart`: 20-plant completion checks and pending human confirmation.
- `lib/data/repositories/assessment_history_repository.dart`: all 20 sampling locations in saved results.

## Verification

The latest focused checks passed 24 tests across the four files below. After the final map-camera and compact-strip adjustment, all 12 widget tests were rerun successfully. Analysis of the 11 source/test files touched in this revision has no errors or warnings; style-level information messages remain.

- `test/services/da_scouting_route_test.dart`: 20 unique interior points, independent measurements to the four rectangular edges, margin/separation, concave fields, obstacles, completed-point preservation, shorter walk without moving suggestions, fixed-prefix preservation, JSON round trip, unusable geometry.
- `test/database/da_guided_scouting_test.dart`: 19 plants cannot complete; 20 plants can; pending confirmation; all 20 appear in history; legacy dimensions and required leaf count; photo resume, field-note persistence, unchanged screening, upgrading a saved route without moving the captured plant, omitted unreported leaf counts, and progression for VE, vegetative, reproductive, and late-season stages.
- `test/screens/guided_plant_walk_step_test.dart`: no-GPS arrival, cached-GPS handling, current-plant indicator, removed leaf selector/message, saving without a count, three-photo limit, expanded map with fixed header, pull-up panel, small screens and larger text.
- `test/widgets/scouting_route_map_test.dart`: existing map fallback, attribution, accessibility and legacy progress behavior.

The original implementation's analysis of 24 source/test files also had no errors or warnings. Both current Flutter widget renders (expanded map and expanded details) were visually inspected with real fonts using the offline field illustration. These renders are not physical-phone or satellite-imagery tests.

A broader attempted run could not compile two existing suites (`assessment_history_repository_test.dart` and `camera_phase_a_persistence_test.dart`) because their fixtures dereference a nullable `BoundaryRecord` without checking it. Those fixtures were not changed here. An earlier legacy route-generator run also had a completed-point expectation mismatch. The full suite is therefore not claimed to pass.

## Physical-device checks remaining

Before distributing a build, exercise real GPS permission denial and recovery, camera permission and continuous three-photo capture, gallery cancellation/import, a force-close/resume, point adjustment, a complete 20-plant block, multiple blocks, and cloud submission/expert display. Check satellite-provider behavior on the phone and offline fallback without connectivity. The dashboard and live backend were not changed or deployed in this phase.

## Latest usability revision

- Removed suggested-point and expert-review explanations from the guided walk, pin sheet, help dialog and DA note editor. The details sheet opens with saved status, photo count and screening result/confidence.
- Camera completion and photo import trigger the existing plant screening pipeline. The walk shows the result before Save and next, with a Screen photos retry when no result is available. Photo thumbnails open the plant details. The AI models, thresholds and scoring formulas are unchanged.
- Saved pins keep their map anchors and numbered appearance. Zoomed-out groups still retain every plant in their member list. Fit field collapses the sheet before fitting the boundary above it; My location also collapses the panel and centers the GPS position in the visible map.
- Restored the light camera layout, scrollable portrait preview and green Take photo button. Continuous capture still accepts up to three photos. Camera initialization survives an inactive permission dialog, waits for camera disposal before restarting, and starts GPS permissions after preview initialization. A missing session now offers Start camera instead of an empty black area.
- Regression checks include retained Plant 1 with a noisy GPS fix, inline results before saving, visible-map fitting under the panel, camera permission/lifecycle recovery and continuous capture. Hardware preview remains to be checked on the phone.
- All 33 focused tests passed across guided walk, pin details, map, camera and DA database suites. Analysis of the 11 changed source/test files passed with no errors or warnings; 14 style information messages remain.
