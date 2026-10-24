# Guided plant evidence requests

For the current DA protocol, selecting “Cannot assess from these photos” on the dashboard opens a request dialog for that block and sampled plant. The expert chooses a reason, requested photo views, and editable instructions. Sending saves the insufficient-evidence outcome and request together. Planned plants without photos also appear in the review queue.

The farmer replies from the app. The block and plant are inherited from the request and cannot be changed in Photo details. The farmer must confirm that the photos show the same sampled plant. Known photos from another plant are rejected. Supabase validates the request, case, sampling block, and plant and links the replacement files to the evidence queue. New evidence invalidates the old rating while keeping its note.

The request moves through awaiting photos, photos received, and reassessment complete. Photos alone do not resolve it. A usable expert rating with a known freshness result resolves a received request; finalization is blocked while any plant request remains outstanding. If replacement photos are still unusable, the expert can request clearer photos again, reusing the plant request and appending a follow-up message.

Automatic photo quality screening is disabled in the mobile app for capture, gallery imports, and evidence replies. Photos are not screened for blur, darkness, resolution, or glare, and there is no quality confirmation popup. Image decoding and upload size limits still apply. The expert decides whether evidence supports a rating.

Photo source, reported capture time when available, server receipt time, historical quality warnings, and farmer confirmation are preserved. New mobile photos do not generate automatic quality warnings. Gallery capture time remains unknown. These records support review but cannot independently prove plant identity or its condition on the original assessment date. Old records are not assigned invented capture or receipt times.

## Deployment and verification

Migration: `202610110004_guided_evidence_requests.sql` in both repositories. Applied to the existing Supabase project, including the renewal function and server receipt timestamp default. The phone app must be rebuilt/reinstalled to use the new flow; the dashboard must serve the updated source.

Focused verification: five Flutter message-service tests, six dashboard request/plant-plan tests, changed-file Dart analysis with no errors or warnings, and 17 live database checks in a rolled-back transaction. The dashboard popup was checked through a synthetic local preview. No real farmer messages were sent, and no complete app/dashboard test suite or physical phone verification was performed.
