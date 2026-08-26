# Database-backed assessment setup

## Purpose

Assessment setup creates or resumes a real local SQLite record. Scan owns the
active field workflow; Home and Assess may only deep-link into that same saved
workflow.

## Preconditions

- A maize field and crop cycle are selected.
- The field has a confirmed approximate outline.
- The outline is a scouting aid, not a legal or survey-grade boundary.
- If the outline is missing, the app shows **Complete field outline** and keeps
  any existing draft data.

The repository also enforces the outline requirement so an older Home or Assess
route cannot bypass it.

## New-assessment sequence

1. Confirm the selected field.
2. Record the evaluator's name.
3. Confirm one maize growth stage for this assessment.
4. Derive the assessment mode and route pattern from that stage.
5. Retrieve recent precipitation automatically when field coordinates and an
   internet connection are available. If retrieval fails, show the concise
   manual rain fallback; weather is context, not proof that the field is safe.
6. Complete the field-entry treatment-safety gate.
7. Save the assessment, safety check, audit entry, and local outbox entry in
   SQLite.
8. Enter Scan only when the selected stage is implemented and field entry is
   allowed.

The app selects and generates the W or ladder pattern. Station targets may be
adjusted with a reason when necessary. The route remains approximate guidance,
not turn-by-turn navigation, proof that the sampling procedure was followed, or
validated station-placement geometry.

## Stage-support gate

| Selected stage | Setup outcome |
| --- | --- |
| VE, V1, V2 | May become `in_progress` and open the VE-V2 workflow |
| V3-V6, V7-V12 | May become `in_progress` and open the vegetative workflow |
| VT-R2 | Remains `draft`; workflow unavailable |
| R3-R6 | Remains `draft`; workflow unavailable |

Newly gated stages do not create plant, station, or route-progress records. A
session-level defensive gate remains for legacy records.

## Field-entry safety outcomes

- `no_recent_treatment` permits field entry.
- `safe_interval_completed` permits entry only after the evaluator records the
  source used and confirms that the required interval was verified.
- `blocked_rei_active` saves the assessment as safety-blocked.
- `cannot_confirm` saves the assessment as safety-blocked.

WormWise does not invent a re-entry interval. The product label, farm treatment
record, or authorized agricultural guidance must be checked.

## Resume behavior

Draft, safety-blocked, and in-progress records remain on the phone. Restarting
the app does not classify every session as an interruption and does not erase
answers, timestamps, evidence, or route progress. Farmer-facing wording is
**Resume assessment**.

## Current implementation boundary

The setup and resume flow is connected to the implemented VE-V2 and V3-V12
five-station workflows. It does not implement VT-R2, R3-R6, results,
recommendations, AI findings, remote synchronization, or satellite imagery.
