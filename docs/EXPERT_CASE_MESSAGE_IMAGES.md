# Follow-up photos in expert case conversations

Implemented on 2026-10-01 in the mobile app and `wormwisedashboard`.

## User experience

- Mobile Expert Review: attach from camera, gallery, or saved assessment photos.
- Dashboard Messages: Attach photos or toggle Request evidence. Describe the
  view needed and optionally identify a station and plant. Sending a request
  atomically sets the case to Needs information.
- Preview selected photos, remove them, add individual captions and optional
  station/plant labels, and zoom before sending. Each message supports up to five
  photos; the input/server limit is 10 MB per photo. Images are resized to a
  maximum 2048-pixel edge and re-encoded as JPEG without camera metadata.
- Received images show their purpose, caption and station/plant association.
  Tap an image to reload its private URL and enlarge it. Mobile supports pinch
  zoom. The dashboard uses its existing photo lightbox.
- Farmers can tap Reply with evidence on a structured request. The draft remains
  linked to that request. Request links are checked to belong to the same case.
- Field evidence and expert reference images are labelled separately by the
  server based on the authenticated sender, not trusted client labels.

Follow-up photos belong to the case conversation. They do not create another
assessment, overwrite the submitted assessment, recompute CV metrics, or revise
finalized severity scores. The existing expert review/finalization workflow
retains its own rules; this feature does not add a severity revision mechanism.

## Reliability and access

The message UUID and payload are saved locally before upload. Mobile stores its
draft metadata in secure storage and copies images into app-private evidence
storage; original assessment photos are not removed. Dashboard drafts and JPEG
blobs are stored in IndexedDB under the signed-in user and case. Draft writes
are serialized to avoid overwriting newer edits with older saves.

Once sending begins, the payload is held fixed. A failed send offers Retry send
or Discard draft. Retry first checks for the same message ID, resumes immutable
object uploads and calls an idempotent RPC. Discard checks delivery before
removing unpublished uploads. A published message and its images are retained.
Uploads show per-photo progress; this is not byte-level upload telemetry.

The private `case-message-images` bucket accepts JPEG, PNG and WebP only. Object
paths are `<case>/<sender>/<message>/<attachment>.jpg`. Only the uploader can
read a staged upload. Published photos are accessible to the case owner, assigned
expert and admins. No public URLs are stored; short-lived signed URLs are used.
The RPC verifies case access, open status, object existence, type and size,
caption limits, photo associations and request links before publishing the message.
Structured requests and attachment paths cannot bypass the RPC via direct insert.
Existing plain-text clients remain compatible. New text-only messages fall back
to the legacy insert only if the RPC is unavailable during deployment.

## Activate on the shared server

Apply **once** to the shared Supabase project:

`supabase/migrations/202610010004_case_message_attachments.sql`

An identical copy is provided in `wormwisedashboard/supabase/migrations` for the
dashboard deployment workflow. It is the same migration, not two separate updates.
It adds message attachment/request fields, the private bucket, storage/RLS rules,
and `send_case_message`. Apply existing prerequisite migrations first.

Then rebuild the mobile app and deploy/reload the dashboard files (index.html,
review.js, case-message-images.js and case-message-images.css). The index includes
an updated script version to avoid cached code. No service-role key belongs in
either client. Live deployment was not performed in this implementation turn.

## Verification

- Changed Dart files: static analysis clean. Dashboard JavaScript: syntax clean.
- Three focused mobile checks: persistent draft identity/request/photo metadata,
  staging and original-photo preservation, discard, camera-metadata removal, and
  oversized-photo rejection.
- Migration executed against an isolated embedded PostgreSQL fixture. Checked
  unpublished image privacy, assigned expert/admin access, unassigned reviewer
  rejection, direct-insert bypass rejection, idempotent retries, request status
  and same-case reply linking, published-image deletion protection and closure.
- Dashboard composer inspected in a local sample preview. No real expert
  messages, uploads to Supabase, paid AI calls, or full test suite were used.

Browser storage clearing or app-data removal removes unsent local drafts. Large
photo collections increase server storage use. Unpublished abandoned uploads
can be deleted by their sender; a future server retention job should remove only
objects unreferenced by published messages, respecting an agreed draft retention
window. No recurring cleanup job was installed by this change.
