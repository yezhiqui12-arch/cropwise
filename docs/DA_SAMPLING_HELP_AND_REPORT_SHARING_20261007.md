# DA sampling help and expert report sharing

Implemented 7 October 2026 following the user's audit corrections.

## Sampling workload and Help

Block preparation receives `locationsPerBlock` and `plantsPerLocation` from the active workflow. Its plant count is required blocks × locations per block × plants per location. A new DA assessment therefore shows 20 plants for one block and 40 for two. Area limits and block sizing remain in `AssessmentAreaPolicy`.

General Help now describes DA guided scouting, 20 dispersed plant locations per block, up to three views of the same plant, explicit batch grouping, natural-enemy confirmation and block review. English and Filipino route questions and the 20-plant percentage example were updated. This replaces obsolete Help instructions; it does not remove the entire Help feature or rewrite historical assessment records.

## Dashboard filter

The Field Reports filter is now labeled **Damage screening**. Its options show percentage ranges without calling them infestation or treatment levels. For DA reports the underlying rate remains model damage screening. Finalized Davis and sampled-infestation results remain separate measures; expert finalization does not change the model screening percentage into an expert metric.

## Expert report submission

The Send to an expert dialog retains farmer name, optional message and Send. It no longer exposes per-report location or photo checkboxes. The submission call supplies `shareLocation: true` and `shareEvidence: true`; the existing service uploads evidence and stores both flags on newly created cases. A short English/Filipino note explains the included results, photos and field location.

Help's submission and sharing articles were aligned. Advisor/AI privacy settings were not changed. There is no background submission triggered by completing sampling; inclusion is automatic when the farmer sends the report. Agreement/onboarding wording can be added in the later agreement work requested by the user.

## Existing reports and verification

Previously submitted cases retain their original sharing flags. The service's existing-case branch remains idempotent and does not rewrite those flags. A historical case with location sharing off can therefore still encounter the previously identified monitoring RPC omission; the new submission flow prevents that combination for new cases but is not a retroactive data repair.

No database migration was added or applied. No tests, build, analyzer, runtime/UI interaction or deployment were performed. Verification consisted of reading the edited callers and declarations, searching for removed references/obsolete Help strings, and checking whitespace in the tracked screen edits.
