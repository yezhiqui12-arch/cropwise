# Computer vision in expert review

Implemented October 1, 2026 in the mobile app and dashboard.

## Review queue

The dashboard's **Review priority** sort brings forward manual earlier-review
requests, then open pending/claimed cases waiting at least 48 hours (oldest
first). Remaining pending/claimed cases are grouped by measurement type,
growth stage, metric code and formula version. Within each group, fully usable
samples come first and are ordered by descending rate. Partial samples are
ordered by coverage before rate; unknown planned counts are ordered by sample
size before rate. Missing or uncertain measurement cohorts use submission time.
Cases awaiting information, cases with advice sent, and closed cases follow
active review work, unless an open case has a manual earlier-review request.

The 48-hour rule is an administrative queue policy, not an agricultural threshold.
The queue distinguishes **screen-positive** from **sampled infestation** and
shows numerator, denominator, planned count and the ordering reason. Rates are
not compared across growth stages or measurement types. Full sample coverage
does not establish that a field estimate or a model prediction is correct.

Admins and assigned experts can add/remove an earlier-review request. A request
requires a reason of at most 300 characters. The database records who made it
and when; closed cases cannot be changed. Saved sort preferences are preserved.

## Image-specific model evidence

Each newly analyzed photo stores its own result in a local preference keyed by
evidence ID, with its SHA-256 checksum and analysis time. Bounding boxes retain
normalized coordinates and model identity; local filesystem paths are removed.
These preferences are included in the existing account backup.

When the farmer first submits a case with photo consent, the app attaches this
metadata to the corresponding private `evidence_files.cv_analysis`. It requires
an exact evidence ID/checksum match. It does not rerun inference during upload.
Location consent is independent: the queue RPC returns only measurements and
sampling counts, and the evidence metadata has no GPS or sampling route.

The expert viewer enables optional highlights only when image-specific metadata
confirms that the second model completed (`detector_used: true` and
`classifierStage: overlay_complete`). The overlay follows the image's rendered
bounds in comparison and Davis-guide views. Experts can hide the suggestions.
Confidence labels describe model output, not confirmed pest identification.

If the model was off, skipped, unavailable, or returned no usable boxes, the
viewer explains that state and offers no suggestions to evaluate. Legacy
submissions without per-photo metadata continue to show the original photos.
Their merged plant boxes are never placed on an arbitrary photo. Existing
submissions are not retroactively changed; cached legacy plant results are not
automatically reprocessed to create overlays.

## Expert feedback

Assigned experts may save **supported**, **not supported**, or **uncertain** for
each photo with saved detector suggestions. Feedback is stored in
`expert_cv_feedback` with reviewer and timestamp. It does not change plant
observations, screening counts, Davis ratings, or treatment advice. Finalizing
the severity review locks this feedback along with the review. Feedback provides
a record for later model evaluation; it is not automatic model retraining.

## Database installation

After the existing dashboard severity migrations, apply the mobile repository's
`supabase/migrations/202610010002_review_priority_and_cv_evidence.sql`. It adds
the evidence metadata column, priority fields, restricted queue-summary RPC,
feedback table/RLS and validated save RPCs. This migration was applied to the
linked Supabase project and recorded in its migration history on October 1.

Validation used focused Dart analysis, JavaScript syntax checks, and small
deterministic checks for ranking and photo identity. No Flutter build or full
test suite was run.
