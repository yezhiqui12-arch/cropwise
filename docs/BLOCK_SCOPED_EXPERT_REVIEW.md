# Block-scoped expert review — 6 October 2026

## Result

The source fix uses `(case_id, block_run_id, sampling point, plant position)` for expert ratings. Evidence uses the same assessment/block/point/plant identity. A DA sampling point is one plant, so Block 1 Plant 7 and Block 2 Plant 7 now remain separate in upload, expert selection, photo strips, published ratings, mobile assessment results, and dashboard monitoring. GPS is not part of the identity.

This is implemented and tested locally. The remote database migration, dashboard publication and installation of the updated mobile build have not been performed in this task.

## Storage and scoring

Migration `supabase/migrations/202610060001_block_scoped_expert_severity.sql` adds `block_run_id` and `block_sequence` to shared evidence and expert ratings. The ratings primary key becomes `(case_id, plant_key)`, with a generated key containing block, point and plant. This permits repeated display numbers in different blocks without permitting two ratings for one plant in one block.

The dashboard saves through `save_expert_plant_severity_v3`, passing the block UUID. The server verifies assignment, expert role, open case, shared evidence, valid 0–9 grade, existing matching photo, and unchanged freshness requirements. Old scoring RPCs resolve a block only when the point/plant has one possible identity; they reject ambiguous selections instead of overwriting a grade.

Finalization counts distinct block/point/plant identities. Three photographs of one plant remain one reviewed plant. Every photo-linked plant needs a scored or insufficient-evidence outcome. Grade zero contributes to the denominator; insufficient evidence does not. The global mean is the sum of all scored Davis grades divided by the number scored, not an unweighted average of block means. The summary saves block-scoped point statistics, per-block means, a global mean and grade histogram, with `identity_version = 2`. Mean severity remains a 0–9 score. No damaged-hectare calculation was added.

Published grades and evidence identities remain locked. The summary notification is emitted once. Permissions for grading and reading shared evidence remain in place.

## Existing data and automatic repair

The migration fills block IDs in unfinished reviews only when saved station/snapshot information identifies one possible block. It does not copy a colliding old grade into multiple blocks or change a finalized grade.

Normal mobile cloud sync also repairs already-shared, unfinished evidence. It matches the original photo ID to the local station and block run, then calls `sync_evidence_block_identity`. This works even when a restored phone has not downloaded the image file yet. It does not upload a new image, resend a case, alter consent, or rerun a model. Photos with complete identity metadata are skipped. Finalized reviews are skipped. The same repair runs when an existing submission is retried.

A uniquely linked draft grade can gain block metadata without changing its judgment. An ambiguous old draft is retained unassigned; the expert must grade each newly distinguished plant separately before finalization. Historical finalized collisions cannot be reconstructed automatically. Their original rows remain preserved, and an ambiguous association does not become a field mean. Legacy single-block reviews remain readable and reviewable.

If the original local photo/station records are unavailable, the app cannot invent their block assignment. The source photo identity must be recovered before that unfinished review can be finalized.

## Changed components

Mobile:

- `lib/services/cloud/expert_case_submission_service.dart`: uploads block metadata; repairs submitted evidence without changing consent or media.
- `lib/services/cloud/wormwise_cloud_sync_service.dart`: runs metadata repair during normal cloud sync.
- `lib/services/cloud/expert_review_service.dart`: matches photos and ratings by full identity; reads block sequence and DA protocol for labels.
- `lib/models/da_assessment_results.dart`: validates unique local matches and computes the zero-inclusive mean across blocks.
- `lib/services/cloud/expert_damage_monitoring.dart`: retains the new summary/block metadata.
- `lib/screens/expert_severity_review_screen.dart`: shows mean Davis and block/plant labels.
- `lib/screens/assess/da_assessment_results_section.dart`: fixes filter wrapping at large text sizes.

Dashboard:

- `plant-identity.js`: shared identity, selection parsing and block labels.
- `review.js`: block-scoped queue, selection, photos, scoring, report cards and evidence navigation.
- `assessment-results.js`: matches the correct block's photos and scores, validates the whole finalized payload.
- `live-dashboard.js`: matches point statistics using both block ID and point number; accepts modern block-scoped field summaries.
- `index.html`: refreshes module cache versions.

Computer-vision models, inference, classification thresholds and LLM/advice generation were not changed.

## Activation order

1. On the existing shared Supabase project, confirm the earlier expert-rating, finalization and freshness migrations are installed, especially `202610010004_expert_damage_freshness.sql`.
2. Apply `202610060001_block_scoped_expert_severity.sql` once. Identical copies are present in the mobile and dashboard migration directories; both refer to the same shared database, so do not apply it twice. The migration is transactional and requests a PostgREST schema reload.
3. Publish the dashboard source and install the rebuilt mobile app. The dashboard requires the v3 RPC; the mobile repair requires the new columns/RPC. These are source changes, not a handset installation performed by this task.
4. Open/sync the owning account on the original or restored phone. For unfinished cases with old photos, let normal sync finish, then refresh the dashboard case. Check the block labels and independently score any previously ambiguous plants.
5. Verify a two-block assessment with Block 1 Plant 7 = 3 and Block 2 Plant 7 = 8. Each selection must open its own photos and retain its own score after refresh. Finalize only after every photo-linked plant is reviewed.

Single-block deployments can keep older mobile clients for existing unambiguous reviews, but multi-block scoring requires the updated dashboard and migrated server. Older clients cannot safely edit repeated plant numbers; the server rejects that operation.

## Local verification

- Focused Flutter model, results UI, metadata repair, cloud sync and account-readiness regressions: 32 tests passed.
- Dashboard results, actual scoring-handler selection, monitoring adapter and identity tests, plus real PostgreSQL migration/scoring tests: 45 tests passed, none skipped in the verification run.
- PostgreSQL tests used an isolated in-memory PGlite runtime, not the deployed database. They ran the real prior migrations and the new migration, with unique and ambiguous draft data and a historical finalized review already present.
- The PostgreSQL checks cover 40 plants across two blocks; repeated Plant 7 grades 3 and 8; extra photos counted once; zero and insufficient outcomes; global and block means; authorization; incomplete finalization; blocked legacy overwrites; draft backfill; no copying ambiguous old grades; finalization locks; one notification; and legacy single-block scoring.
- The mobile metadata test uses mocked Supabase HTTP requests and confirms the exact original block UUID is sent, complete photos and finalized cases are skipped, and no Storage upload occurs.
- Focused Dart analysis found no errors or warnings; remaining informational style notices are recorded separately from test success. No physical-device or live-server verification is claimed.

Run the dashboard PostgreSQL test with `WORMWISE_PGLITE_MODULE` pointing to the local `@electric-sql/pglite/dist/index.js` module, then run `node --test tests/block-identity-migration.test.mjs tests/assessment-results.test.mjs tests/dashboard-integration.test.mjs tests/plant-identity.test.mjs tests/review-block-selection.test.mjs`. Without that optional runtime, the PostgreSQL test explicitly skips rather than claiming a server test.

Pre-change source copies are in `C:/Users/marka/Documents/Codex/2026-10-02/an/outputs/block-identity-before`. Database rollback after storing block-specific scores needs a deliberate data migration; restoring source files alone does not undo the new database key.
