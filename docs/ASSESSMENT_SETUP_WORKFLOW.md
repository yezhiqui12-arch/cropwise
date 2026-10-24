# Database-backed assessment setup

## Purpose

Assessment setup creates or resumes a local SQLite-backed record and enters the
current DA sampling workflow only after its preconditions pass.

## Preconditions

- A maize field and crop cycle are selected.
- The field has a confirmed approximate outline.
- Required sampling blocks are defined.
- The evaluator and definite crop growth-stage group are recorded.
- Field-entry treatment and re-entry safety information is complete.

The outline is a scouting aid, not a legal or survey-grade boundary.

## New-assessment sequence

1. Confirm the selected field and crop cycle.
2. Record the evaluator and crop growth-stage group.
3. Confirm the field and required sampling-block outlines.
4. Retrieve recent precipitation context when available, otherwise use the
   explicit manual fallback.
5. Complete the treatment/re-entry safety gate.
6. Save the assessment, safety state, audit entry, and outbox entry.
7. Generate 20 dispersed plant suggestions for each block.
8. Enter active sampling when field entry is allowed.

Weather is context and does not prove that entry is safe. WormWise never
invents a re-entry interval; the product label, farm record, or authorized
guidance remains authoritative.

## Sampling behavior

The app uses protocol `wormwise-da-scattered-20-v1`. Each block requires 20
numbered plant locations and one plant per location. Suggestions remain inside
the confirmed block, respect the edge margin and obstacles, and may be adjusted
with a saved reason. The evaluator chooses a safe path between suggestions.

## Resume behavior

Draft, safety-blocked, and in-progress records remain on the phone. Restarting
the app preserves answers, timestamps, evidence, locations, notes, screening
results, and sampling progress. Resume rechecks the current safety and protocol
requirements before continuing.
