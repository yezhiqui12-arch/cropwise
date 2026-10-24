# Backup manifests and retention

Deploy supabase/migrations/202610240001_backup_manifests_retention.sql before
shipping this client against Supabase. It permits application/json in the existing
private backup bucket and adds authenticated owner-only deletion of snapshot paths.
It cannot delete evidence objects, manifests, or another user's objects. Existing
read/insert/update owner policies remain unchanged. This migration was prepared,
not applied to a live Supabase project; live RLS behavior is not verified here.
There is no local Drift schema change (version remains 8).

Each device publishes:
- <owner>/devices/<device>/snapshot-<timestamp>-<nonce>.json.gz
- <owner>/devices/<device>/manifest.json

The client uploads and verifies a snapshot by checksum before updating and reading
back its manifest. It keeps the newest three indexed copies and, when necessary,
one older complete fallback. Old legacy history is pruned only after a complete
verified replacement exists, retaining three legacy copies for this device. Older
unindexed objects get a one-day grace period. Cleanup rechecks the account and
manifest before deleting, and never considers evidence objects or other devices.
A cleanup failure leaves the verified backup usable and records maintenance status.
Cleanup retries on a subsequent changed-snapshot publication.

Recovery paginates legacy root objects and the much smaller device directories.
Valid manifests avoid scanning each device's full history. Missing/malformed
manifests can fall back to the device directory; legacy snapshots remain candidates.
Every imported snapshot still passes the existing owner/schema/graph validation.
An inaccessible manifest is not treated as an empty one. Publishing refuses to
replace malformed manifests; preserve/recover their snapshots before repairing
such an index. Device IDs are installation-specific and should not be cloned.

Validation covers retention, complete fallback preservation, checksum mismatch,
failed publications, account changes, legacy recovery, orphan discovery, malformed
and cross-account pointers, and cleanup failure using an in-memory object store.
The account-recovery integration test also exercises uploads/read-back through a
local HTTP server. No live snapshot was uploaded or deleted during this work.
