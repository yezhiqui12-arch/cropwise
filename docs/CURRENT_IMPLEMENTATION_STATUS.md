# Current implementation status

This is an engineering snapshot, not a scientific-validation claim.

## Implemented

- Home, Assess, Map, and Guide application structure.
- Offline field registration, selected-field persistence, approximate outline
  editing, crop-cycle context, and recently deleted recovery.
- Database-backed assessment setup and resume.
- Recent precipitation lookup with an offline/manual fallback.
- Treatment and re-entry safety gating.
- `wormwise-da-scattered-20-v1` sampling with 20 dispersed plants per confirmed
  block and one plant per numbered location.
- Interior point generation, edge-margin and obstacle checks, point adjustment,
  saved progress, phone-location capture, and interruption recovery.
- Stage-aware observations for all selectable maize growth-stage groups.
- Up to three evidence photographs per sampled plant, private canonical files,
  thumbnails, checksums, review, removal, and reconciliation.
- On-device damage screening and optional pest-species suggestions, stored with
  evidence and model provenance.
- Atomic plant saves, block validation, assessment completion, and
  formula-versioned results.
- Assessment history, result details, plant drill-down, maps, evidence state,
  PDF exports, and targeted resume or repair.
- Optional Supabase identity, account recovery/backup, synchronization, expert
  case submission, evidence upload, reviewer messaging, notifications, and
  finalized expert findings.
- Offline Guide content, local Advisor retrieval, saved-record context, local
  chat history, and on-device photo analysis.
- Gemini open chat through the authenticated `gemini-advisor` Edge Function.
  The provider credential remains server-side.

## Result boundaries

Automatic damage screening, sampled infestation, expert-reviewed damage
incidence, Davis severity, and unavailable evidence are separate measures.
Every rate preserves its numerator and denominator. The app does not convert a
sample into a whole-field diagnosis, infer a treatment threshold, or silently
replace evaluator or expert facts with model output.

## Known operational limits

- Field outlines and suggested sampling points are approximate scouting aids.
- Phone GPS and imagery availability vary by device, environment, and network.
- Cloud behavior depends on the deployed Supabase schema, RLS, storage
  policies, functions, and secrets matching the application version.
- Scientific and field validation remain separate from software correctness.
- Production operations still require deployment monitoring, backup checks,
  privacy review, and device verification.

## Next work

Future increments should be approved separately. Likely areas are deployment
automation, end-to-end schema verification, physical-device QA, scientific
field validation, bidirectional reconciliation, and production expert-service
operations.
