# DA sample bulk import

Implemented 7 October 2026 in the mobile app. This completes multi-plant gallery intake for DA guided scouting. It uses the existing 20-plant sampling block and existing computer-vision pipeline.

## Farmer flow

1. Open **Guided scouting → Import sample photos**. The importer belongs to the current assessment and block; it offers only plant numbers without existing observations or evidence.
2. Choose overview and optional closer photos together in one gallery selection. Each plant supports 1–3 photos. A completely empty 20-plant block permits up to 60 photos. A smaller selection can fill part of the sample; another import can fill the remaining empty plants.
3. Arrange photos before processing. The gallery order is visible. Tap the first photo of each plant to start a group; tap its boundary again to join the preceding group. Shortcuts **1, 2, or 3 per plant** group consecutive photos when that matches the farmer's capture sequence. Mixed-size groups remain editable individually.
4. The first photo in each group is its overview. Open another photo and choose **Use as overview** to switch it. **Move to plant**, long-press dragging, and **Remove photo** correct group assignments. Open a photo to inspect it at full size. Grouping uses explicit farmer confirmation; the app does not claim to recognize which physical plant appears in arbitrary gallery images.
5. Confirm **I checked the plant groups**, then tap **Save and screen** once. Groups are locked during saving so retries retain the same plant identities. The progress card distinguishes photos saved from plants screened. Photos are saved and screened sequentially by plant, rather than running 60 model jobs simultaneously.
6. An unsuccessful plant offers **Retry unfinished plants**. Successfully saved photos and successfully screened plants are skipped. Return to the importer after restarting the app to resume its draft. **Start another import** clears the pending draft; already accepted evidence and plant observations stay in the assessment.
7. Tap **Continue to sample**. Completion of the twentieth plant preserves the existing natural-enemies confirmation before block completion. Cancelling that confirmation leaves the import available. Saved photos and model results remain accessible through the existing plant details and sample review.

## Data and recovery

- Each copied photo gets a stable UUID, retained in evidence metadata. A retry verifies its plant, view and local file before reusing it. A failed screen leaves accepted photos available for retry.
- Pending picker files are copied into app-private documents storage, under `WormWiseBatchImports/<draft UUID>`. Exact duplicate file contents within a selection are excluded. Each copied photo and each processing success is persisted separately.
- Draft JSON uses the existing local `app_preferences` table, scoped by assessment and block. **No new local schema version or Supabase migration is required for this feature.**
- Pending drafts support reopening on the same phone. Their staging files are not a separately implemented cross-device backup facility. Accepted evidence continues through the existing report-submission and sync path.
- Imported photos do not inherit the phone's current GPS or a made-up original capture time. Existing camera capture, recorded sampling locations, completed plants and other blocks are preserved.
- Draft cleanup only removes its own generated staging directory after validating the resolved path; accepted evidence is stored separately.
- Selecting/importing photos saves locally. It does not automatically send a report or finalize expert ratings.

## Source files

- `lib/models/da_batch_import.dart`: group boundaries, overview switching, movement, shortcuts, validation and serialization.
- `lib/services/da_batch_import_store.dart`: private file copies, content deduplication, local draft storage and scoped cleanup.
- `lib/screens/scan/da_batch_import_screen.dart`: one-selection gallery, grouping grid, plant preview, progress and retries.
- `lib/providers/five_station_workflow_provider.dart`: available plant lookup, stable evidence saves, existing CV invocation and plant completion.
- `lib/services/evidence_capture_coordinator.dart`: optional stable media identifier; existing callers retain their normal ID generation.
- `lib/screens/scan/guided_plant_walk_step.dart` and `lib/screens/station1/station1_workflow_screen.dart`: bulk entry point, existing single-plant import and block review transition.

Computer-vision models, thresholds, inference logic, prompts, LLM/advisor logic and Davis calculations were not edited in this change. The legacy station importer remains separate.

## Verification

All 25 focused tests passed across eight suites on 7 October 2026. Static analysis of the changed integration and test files reported no errors or warnings; style information messages remain.

Focused tests cover mixed groups, shortcuts, switching the overview, moving/removing photos, locked assignments, duplicate files, block isolation, durable copies, retry IDs, preserving 19 existing plants while completing Plant 20, model-result persistence, natural-enemies confirmation, guided-map details and 60 photos processed as 20 plants. The importer is rendered with real fonts and photos at normal text size and on a 320-pixel-wide screen with 200% text scaling.

A broader run also found four assertions in the existing `test/services/two_stage_faw_cv_service_test.dart` that conflict with the current screening contract. They expect old `negative`, `uncertain`, `old_damage_only` or confirmed-infestation outputs where the existing service returns damage-screen statuses. These source models and older tests were not changed to make that run pass. A complete passing repository suite is not claimed.

Physical-phone validation remains: native gallery selection order/limits, permission cancellation, memory use with 60 large real photos, process termination during copying/saving/screening, block navigation and eventual cloud report submission. Widget renders and simulated inference tests do not establish hardware performance. This change has not been installed on a phone by this implementation run.
