# Database-backed assessment setup

## Purpose

The Home assessment action must create or resume a real local SQLite record. It
must not use the previous demonstration counters as evidence of fieldwork.

## New-assessment sequence

1. Confirm the active maize field and its reported area.
2. Record the name of the farmer, technician, or other person conducting the
   assessment. This person is an evaluator for the record, not automatically a
   government or municipal expert.
3. Select the best maize growth-stage estimate and mark it uncertain when
   necessary.
4. Derive the applicable assessment mode from the stage.
5. Recommend W scouting for VE-V6 and ladder scouting for the taller V7-R6
   groups. Allow a different selection, but require the reason.
6. Save the preferred guided-assessment language and optional field-condition
   note.
7. Complete the field-entry safety gate.
8. Create the assessment, safety-check, audit, and sync-outbox records locally.
9. Start the assessment only when safety is allowed.

## Field-entry safety outcomes

- `no_recent_treatment` permits the assessment to start.
- `safe_interval_completed` permits it only after the evaluator records the
  source used and confirms that the required interval was verified.
- `blocked_rei_active` saves the draft as safety-blocked.
- `cannot_confirm` saves the draft as safety-blocked.

WormWise does not invent or calculate a safe re-entry time from memory. The
product label, farm treatment record, or authorized agricultural guidance must
be checked. Unknown information means no field entry.

## Resume behavior

The app watches the selected crop cycle for an unfinished assessment. A saved
draft or safety-blocked record opens the safety review. An in-progress record
opens the assessment overview. Restarting the app therefore does not discard
the setup.

## Current boundary of implementation

This change implements the persisted setup, safety gate, and resume state. The
five-station guided scouting screens, station GPS, ten-plant observation forms,
photo evidence, severity calculations, recommendations, validation, and final
reports remain subsequent implementation stages.
